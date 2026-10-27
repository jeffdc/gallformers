defmodule GallformersWeb.Admin.TaxonomyLive.RangeEditorTest do
  @moduledoc """
  The Host range editor on the taxon page (matter a856, decision 4: carried
  over unchanged from the old Host admin). These are the old Host form's
  range tests (`HostLive.Form`, `HostLive.WcvpTest`) on a plant taxon: the
  tri-state map, the country drill-down, refresh from WCVP with the staged
  diff, and Save writing the range by `taxon_id` through
  `Gallformers.Import.record_taxonomy_edit/2` (`:set_host_range`).
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Audit.Actor
  alias Gallformers.Import
  alias Gallformers.Ranges
  alias Gallformers.Ranges.Wcvp
  alias GallformersWeb.Admin.CountryDrillDown
  alias GallformersWeb.Admin.PowoDiffReview

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Rae Ranges")
    %{conn: conn, actor: Actor.user(user.id, "Rae Ranges")}
  end

  # A plant in a genus in a family, with `places` as its Host range.
  defp plant_with_range(name, places) do
    u = System.unique_integer([:positive])
    family = plant_fixture(rank: :family, name: "Rangeaceae#{u}")
    genus = plant_fixture(rank: :genus, name: name |> String.split() |> hd(), parent: family)
    plant = plant_fixture(name: name, parent: genus)
    if places != [], do: host_range_fixture(plant, places)
    plant
  end

  defp alpinus, do: plant_with_range("Rangetest#{uniq()} alpinus", [{"US-CA", "exact"}])

  defp serpyllum,
    do:
      plant_with_range("Rangetest#{uniq()} serpyllum", [
        {"US-CA", "exact"},
        {"BS", "exact", "introduced"}
      ])

  defp uniq, do: System.unique_integer([:positive])

  defp get_assign(view, key), do: :sys.get_state(view.pid).socket.assigns[key]

  defp put_assign(view, key, value) do
    :sys.replace_state(view.pid, fn state -> put_in(state.socket.assigns[key], value) end)
  end

  defp range_codes(plant),
    do: plant.id |> Ranges.get_places_for_taxon_with_precision() |> Map.new(&{&1.code, &1})

  describe "loading" do
    test "builds the range entries from the taxon's rows", %{conn: conn} do
      plant = serpyllum()
      {:ok, view, html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      assert html =~ "host-range-map"
      range_entries = get_assign(view, :range_entries)
      assert range_entries["US-CA"] == %{precision: "exact", distribution_type: "native"}
      assert range_entries["BS"].distribution_type == "introduced"
      assert get_assign(view, :original_range_entries) == range_entries
    end

    test "shows no range editor for a taxon that is no plant", %{conn: conn} do
      genus = taxon_fixture(rank: :genus, name: "Notaplant#{uniq()}", kingdom: "Animalia")
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{genus.id}")

      refute has_element?(view, "#host-range-map")
    end
  end

  describe "the tri-state map" do
    test "a click adds a place as native, then introduced, then removes it", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "toggle_region", %{"code" => "MX-JAL"})

      assert get_assign(view, :range_entries)["MX-JAL"] == %{
               precision: "exact",
               distribution_type: "native"
             }

      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      assert get_assign(view, :range_entries)["MX-JAL"].distribution_type == "introduced"

      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      refute Map.has_key?(get_assign(view, :range_entries), "MX-JAL")

      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      assert get_assign(view, :range_entries)["MX-JAL"].distribution_type == "native"
    end

    test "an existing native place cycles to introduced, then is removed", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "toggle_region", %{"code" => "US-CA"})
      assert get_assign(view, :range_entries)["US-CA"].distribution_type == "introduced"

      render_click(view, "toggle_region", %{"code" => "US-CA"})
      refute Map.has_key?(get_assign(view, :range_entries), "US-CA")
    end

    test "an unknown code is ignored", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "toggle_region", %{"code" => "INVALID-CODE"})

      assert get_assign(view, :range_entries) == get_assign(view, :original_range_entries)
      assert get_assign(view, :form_dirty) == false
    end

    test "a change marks the page dirty", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      html = render_click(view, "request_cancel", %{})

      assert html =~ "Discard"
    end

    test "a leaf country toggles directly", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "toggle_country", %{"code" => "BS"})

      assert get_assign(view, :range_entries)["BS"].distribution_type == "native"
    end
  end

  describe "the country drill-down" do
    test "set_exact_type adds native and removes on second click", %{conn: conn} do
      plant = serpyllum()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      send(view.pid, {CountryDrillDown, {:set_exact_type, "MX-JAL", "native"}})

      assert get_assign(view, :range_entries)["MX-JAL"] == %{
               precision: "exact",
               distribution_type: "native"
             }

      send(view.pid, {CountryDrillDown, {:set_exact_type, "MX-JAL", "native"}})
      refute Map.has_key?(get_assign(view, :range_entries), "MX-JAL")
    end

    test "set_exact_type converts an existing native entry to introduced", %{conn: conn} do
      plant = serpyllum()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      send(view.pid, {CountryDrillDown, {:set_exact_type, "US-CA", "introduced"}})

      assert get_assign(view, :range_entries)["US-CA"].distribution_type == "introduced"
    end

    test "set_all_exact_type marks in bulk and deselect_all_exact clears", %{conn: conn} do
      plant = serpyllum()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      send(view.pid, {CountryDrillDown, {:set_all_exact_type, ["CA-AB", "MX-JAL"], "native"}})
      range_entries = get_assign(view, :range_entries)
      assert range_entries["CA-AB"].distribution_type == "native"
      assert range_entries["MX-JAL"].distribution_type == "native"

      send(view.pid, {CountryDrillDown, {:set_all_exact_type, ["US-CA"], "introduced"}})
      assert get_assign(view, :range_entries)["US-CA"].distribution_type == "introduced"

      send(view.pid, {CountryDrillDown, {:deselect_all_exact, ["CA-AB", "MX-JAL"]}})
      range_entries = get_assign(view, :range_entries)
      refute Map.has_key?(range_entries, "CA-AB")
      refute Map.has_key?(range_entries, "MX-JAL")
    end

    test "select_all_exact adds the missing places as native", %{conn: conn} do
      plant = serpyllum()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      send(view.pid, {CountryDrillDown, {:set_exact_type, "US-CA", "introduced"}})
      send(view.pid, {CountryDrillDown, {:select_all_exact, ["US-CA", "MX-JAL"]}})

      range_entries = get_assign(view, :range_entries)
      assert range_entries["US-CA"].distribution_type == "introduced"
      assert range_entries["MX-JAL"].distribution_type == "native"
    end

    test "an exact native subdivision clears the introduced display under an introduced country",
         %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      send(view.pid, {CountryDrillDown, {:set_country_level, "US", "introduced"}})
      render(view)

      range_entries = get_assign(view, :range_entries)
      assert range_entries["US"].distribution_type == "introduced"
      assert range_entries["US-CA"].distribution_type == "native"
      assert "US-CA" in get_assign(view, :in_range)
      refute "US-CA" in get_assign(view, :introduced_range)
    end

    test "set_country_level false removes the country entry", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      send(view.pid, {CountryDrillDown, {:set_country_level, "US", "native"}})
      send(view.pid, {CountryDrillDown, {:set_country_level, "US", false}})

      refute Map.has_key?(get_assign(view, :range_entries), "US")
    end

    test "replacing a country with its baseline removes its exact subdivisions", %{conn: conn} do
      plant = serpyllum()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      send(view.pid, {CountryDrillDown, {:replace_with_country_baseline, "US", "introduced"}})

      range_entries = get_assign(view, :range_entries)
      assert range_entries["US"] == %{precision: "country", distribution_type: "introduced"}
      refute Map.has_key?(range_entries, "US-CA")
      assert "US-CA" in get_assign(view, :introduced_range)
      assert "US-CA" in get_assign(view, :inherited_range)
    end
  end

  describe "saving" do
    test "Save writes the range by taxon, logged for replay, and reloads it", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      render_click(view, "toggle_region", %{"code" => "MX-JAL"})
      html = render_click(view, "save_range", %{})

      assert html =~ "Range saved"
      codes = range_codes(plant)
      assert codes["US-CA"].distribution_type == "native"
      assert codes["MX-JAL"].distribution_type == "introduced"

      assert get_assign(view, :range_entries) == get_assign(view, :original_range_entries)
      assert get_assign(view, :form_dirty) == false

      assert [entry] =
               for(
                 e <- Import.list_replay_entries(),
                 e.kind == :taxonomy_edit and e.key["op"] == "set_host_range",
                 do: e
               )

      assert Enum.sort(Enum.map(entry.payload["places"], & &1["code"])) == ["MX-JAL", "US-CA"]
    end

    test "Save & Confirm Range saves and marks the range confirmed", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      html = render_click(view, "save_range", %{"confirm" => "true"})

      assert html =~ "Range saved and confirmed"
      assert Wcvp.get_link(plant.id).range_confirmed == true
      assert html =~ "Range confirmed"
    end

    test "Save refuses an empty range", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "toggle_region", %{"code" => "US-CA"})
      render_click(view, "toggle_region", %{"code" => "US-CA"})
      assert get_assign(view, :range_entries) == %{}

      html = render_click(view, "save_range", %{})

      assert html =~ "at least one range entry"
      assert %{"US-CA" => %{distribution_type: "native"}} = range_codes(plant)
    end
  end

  describe "WCVP sync status" do
    test "shows never synced and needs review without a link", %{conn: conn} do
      plant = alpinus()
      {:ok, _view, html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      assert html =~ "Never synced with WCVP"
      assert html =~ "Range needs review"
    end

    test "shows a confirmed range and its sync date", %{conn: conn, actor: actor} do
      plant = alpinus()

      {:ok, _} =
        Wcvp.put_link(actor, plant, %{
          range_confirmed: true,
          wcvp_synced_at: ~U[2025-06-15 14:30:00Z]
        })

      {:ok, _view, html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      assert html =~ "Range confirmed"
      assert html =~ "Jun 15, 2025"
    end
  end

  describe "refresh from WCVP" do
    test "shows loading, then the diff for a plant WCVP matches", %{conn: conn} do
      plant = plant_with_range("Wcvptestus alpinus", [{"US-CA", "exact"}])
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      html = render_click(view, "refresh_from_wcvp", %{})
      assert html =~ "wcvp-refresh-loading"

      html = render_async(view)
      assert html =~ "POWO-WCVP Data Comparison"
      assert get_assign(view, :wcvp_refreshing) == false
      assert get_assign(view, :powo_diff) != nil
    end

    test "uses the plant's WCVP link before its name", %{conn: conn, actor: actor} do
      plant = alpinus()
      {:ok, _} = Wcvp.put_link(actor, plant, %{wcvp_id: "700"})
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "refresh_from_wcvp", %{})
      render_async(view)

      assert get_assign(view, :powo_diff).wcvp_data.plant_name_id == "700"
    end

    test "shows the no-match search, which can be cancelled", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "refresh_from_wcvp", %{})
      html = render_async(view)
      assert html =~ "No exact match found"

      html = render_click(view, "cancel_wcvp_search", %{})
      refute html =~ "No exact match found"
    end

    test "the no-match search finds a record and continues to the diff", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "refresh_from_wcvp", %{})
      render_async(view)
      render_keyup(view, "wcvp_nomatch_search", %{"value" => "Zzyzx"})
      html = render_async(view)
      assert html =~ "Zzyzx wcvponly"

      render_click(view, "select_wcvp_nomatch", %{"id" => "500"})
      render_click(view, "continue_wcvp_search", %{})
      html = render_async(view)

      refute html =~ "No exact match found"
      assert html =~ "POWO-WCVP Data Comparison"
    end

    test "applying the diff stages the range and the WCVP link; Save writes both",
         %{conn: conn} do
      plant = plant_with_range("Wcvptestus alpinus", [{"US-CA", "exact"}])
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "refresh_from_wcvp", %{})
      render_async(view)
      diff = get_assign(view, :powo_diff)

      selections = %{
        add_native: MapSet.new(diff.add_native),
        add_introduced: MapSet.new(diff.add_introduced),
        remove: MapSet.new(diff.remove),
        reclassify_to_introduced: MapSet.new(diff.reclassify_to_introduced),
        reclassify_to_native: MapSet.new(diff.reclassify_to_native)
      }

      send(view.pid, {PowoDiffReview, {:apply, selections}})
      html = render(view)

      assert html =~ "WCVP range data staged"
      assert get_assign(view, :powo_diff) == nil
      assert get_assign(view, :pending_wcvp_link).wcvp_id == "700"
      assert get_assign(view, :form_dirty) == true
      assert is_nil(Wcvp.get_link(plant.id))

      render_click(view, "save_range", %{})

      link = Wcvp.get_link(plant.id)
      assert link.wcvp_id == "700"
      assert link.powo_id == "urn:lsid:ipni.org:names:test700"
      assert %DateTime{} = link.wcvp_synced_at
    end

    test "apply keeps country precision from POWO", %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      diff = %{
        add_native: ["MX"],
        add_introduced: ["CA"],
        remove: [],
        reclassify_to_introduced: [],
        reclassify_to_native: [],
        agree_count: 0,
        has_changes: true,
        powo_precision_by_code: %{"MX" => "country", "CA" => "country"},
        wcvp_data: %{plant_name_id: "manual-test", powo_id: "manual-powo"}
      }

      put_assign(view, :powo_diff, diff)

      selections = %{
        add_native: MapSet.new(["MX"]),
        add_introduced: MapSet.new(["CA"]),
        remove: MapSet.new(),
        reclassify_to_introduced: MapSet.new(),
        reclassify_to_native: MapSet.new()
      }

      send(view.pid, {PowoDiffReview, {:apply, selections}})
      _ = render(view)

      range_entries = get_assign(view, :range_entries)
      assert range_entries["MX"] == %{precision: "country", distribution_type: "native"}
      assert range_entries["CA"] == %{precision: "country", distribution_type: "introduced"}
    end

    test "apply materializes changed country-level leaves before remove and reclassify",
         %{conn: conn} do
      plant = alpinus()
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      put_assign(view, :range_entries, %{
        "FR" => %{precision: "country", distribution_type: "native"}
      })

      leaf = fn ->
        %{
          precision: "exact",
          distribution_type: "native",
          source_code: "FR",
          source_precision: "country"
        }
      end

      diff = %{
        add_native: [],
        add_introduced: [],
        remove: ["FR-01", "FR-02"],
        reclassify_to_introduced: ["FR-06"],
        reclassify_to_native: [],
        agree_count: 0,
        has_changes: true,
        powo_precision_by_code: %{},
        current_leaf_sources_by_code: %{
          "FR-01" => leaf.(),
          "FR-02" => leaf.(),
          "FR-06" => leaf.()
        },
        wcvp_data: %{plant_name_id: "manual-test", powo_id: "manual-powo"}
      }

      put_assign(view, :powo_diff, diff)

      selections = %{
        add_native: MapSet.new(),
        add_introduced: MapSet.new(),
        remove: MapSet.new(["FR-02"]),
        reclassify_to_introduced: MapSet.new(["FR-06"]),
        reclassify_to_native: MapSet.new()
      }

      send(view.pid, {PowoDiffReview, {:apply, selections}})
      _ = render(view)

      range_entries = get_assign(view, :range_entries)
      refute Map.has_key?(range_entries, "FR")
      refute Map.has_key?(range_entries, "FR-01")
      assert range_entries["FR-02"] == %{precision: "exact", distribution_type: "native"}
      assert range_entries["FR-06"] == %{precision: "exact", distribution_type: "introduced"}
    end

    test "cancel dismisses the diff", %{conn: conn} do
      plant = plant_with_range("Wcvptestus alpinus", [{"US-CA", "exact"}])
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      render_click(view, "refresh_from_wcvp", %{})
      render_async(view)
      assert get_assign(view, :powo_diff) != nil

      send(view.pid, {PowoDiffReview, :cancel})
      _ = render(view)

      assert get_assign(view, :powo_diff) == nil
    end
  end
end
