defmodule GallformersWeb.Admin.GallLive.EditTest do
  @moduledoc """
  The Gall page in admin (matter a856, Task 7): `/admin/galls/:id` edits a
  Gall's editorial fields (with the `datacomplete` lock and the code's
  uniqueness), its name parts and override, its images (the image
  component), its Gallformers note (each save a new dated version) and its
  range exclusions (saved as a Gallformers statement through the import
  path), all as the signed-in admin.

  Not async: the Gallformers Source is unique, and imports create Sources.
  The audit trail records one actor per database transaction and a test
  runs in one, so the fixtures write as the signed-in admin too.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Ecto.Query, only: [from: 2]
  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_audit_changes: 0, test_actor: 0]
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Facts.RangeFact
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Repo
  alias Gallformers.Sources

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Gail Galls")
    %{conn: conn, gallformers: gallformers_source(), source: source_fixture("Weld", "1959")}
  end

  # A genus and its name.
  defp genus! do
    name = "Zyzzedit#{System.unique_integer([:positive])}"
    {taxon_fixture(rank: :genus, name: name, kingdom: "Animalia"), name}
  end

  defp relate!(gall, type, taxon, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: type, subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source)
      )

    gall
  end

  # A Gall whose current Inducer is a species, its name derived from it.
  defp described_gall(%{source: source}) do
    {genus, genus_name} = genus!()
    name = "#{genus_name} lecta"
    species = taxon_fixture(name: name, parent: genus, kingdom: "Animalia")
    gall = gall_fixture(name: name)
    relate!(gall, "inducer_of", species, source)
  end

  # A described Gall on a Host that grows in California and Alberta.
  defp gall_with_range(ctx) do
    plant = plant_fixture()
    :ok = host_range_fixture(plant, [{"US-CA", "exact"}, {"CA-AB", "exact"}])
    ctx |> described_gall() |> relate!("host_of", plant, ctx.source)
  end

  defp reload(gall), do: Catalog.get_gall!(gall.id)

  describe "the page" do
    test "shows the Gall's name and links to its public page", ctx do
      gall = described_gall(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      assert has_element?(view, "#derived-name", gall.name)
      assert has_element?(view, "a[href='/gall/#{gall.id}']")
      assert has_element?(view, "#gall-images")
    end

    test "an unknown Gall goes back to the search", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/galls"}}} =
               live(conn, ~p"/admin/galls/999999999")
    end
  end

  describe "the editorial fields" do
    test "save the code, abundance and lead Source as the signed-in admin", ctx do
      gall = described_gall(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      view
      |> form("#editorial-form",
        gall: %{
          gallformers_code: " zz-code ",
          abundance_id: "2",
          default_source_id: ctx.source.id
        }
      )
      |> render_submit()

      assert %{gallformers_code: "zz-code", abundance_id: 2, default_source_id: source_id} =
               reload(gall)

      assert source_id == ctx.source.id

      assert [%{transaction: %{meta: %{"actor" => %{"name" => "Gail Galls"}}}} | _] =
               Repo.all(
                 from(c in test_audit_changes(),
                   where: c.table_name == "galls" and c.op == :update,
                   preload: :transaction
                 )
               )
    end

    test "the lead Source is picked from the Gall's own Sources", ctx do
      gall = described_gall(ctx)
      unrelated = source_fixture("Unrelated", "1990")
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      assert has_element?(view, "#gall_default_source_id option[value='#{ctx.source.id}']")
      refute has_element?(view, "#gall_default_source_id option[value='#{unrelated.id}']")
    end

    test "a code another Gall has is shown taken as it is typed, and is not saved", ctx do
      gall_fixture(gallformers_code: "taken-code")
      gall = described_gall(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      html =
        view
        |> form("#editorial-form", gall: %{gallformers_code: "taken-code"})
        |> render_change()

      assert html =~ "already used by another Gall"

      view |> form("#editorial-form", gall: %{gallformers_code: "taken-code"}) |> render_submit()

      assert reload(gall).gallformers_code == nil
    end

    test "datacomplete is locked, with the reason, for a Gall with no Sources", %{conn: conn} do
      gall = gall_fixture(datacomplete: true)
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      assert has_element?(view, "#datacomplete-lock", "no Sources")
      assert has_element?(view, "#editorial-form input[type='checkbox'][disabled]")

      view |> form("#editorial-form", gall: %{abundance_id: "1"}) |> render_submit()

      # A locked Gall stored as complete saves only with it cleared.
      assert %{datacomplete: false, abundance_id: 1} = reload(gall)
    end

    test "datacomplete can be set for a described Gall with Sources", ctx do
      gall = described_gall(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      refute has_element?(view, "#datacomplete-lock")
      view |> form("#editorial-form", gall: %{datacomplete: "true"}) |> render_submit()

      assert reload(gall).datacomplete == true
    end
  end

  describe "the name" do
    test "name parts save and the derived name is shown", ctx do
      gall = described_gall(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      html = view |> form("#name-form", name: %{form_label: "bud"}) |> render_change()
      assert html =~ "#{gall.name} (bud)"

      view |> form("#name-form", name: %{form_label: "bud"}) |> render_submit()

      assert reload(gall).name == "#{gall.name} (bud)"
      assert has_element?(view, "#derived-name", "#{gall.name} (bud)")
    end

    test "the Host qualifier is picked from the plants", ctx do
      gall = described_gall(ctx)
      plant = plant_fixture(name: "Quercus zyzzqualifier")
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      render_hook(view, "search_qualifier", %{"value" => "zyzzqualifier"})
      assert has_element?(view, "#host-qualifier-picker", "Quercus zyzzqualifier")

      render_hook(view, "select_qualifier", %{"id" => "#{plant.id}"})
      view |> form("#name-form", name: %{}) |> render_submit()

      assert %{host_qualifier_taxon_id: plant_id, name: name} = reload(gall)
      assert plant_id == plant.id
      assert name == "#{gall.name} (on Quercus zyzzqualifier)"
    end

    test "an override replaces the name shown", ctx do
      gall = described_gall(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      view |> form("#name-form", name: %{name_override: "Shown otherwise"}) |> render_submit()

      assert reload(gall).name_override == "Shown otherwise"
    end

    test "a name another Gall shows is refused with the collision message", ctx do
      gall = described_gall(ctx)
      gall_fixture(name: "#{gall.name} (bud)")
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      html = view |> form("#name-form", name: %{form_label: "bud"}) |> render_change()
      assert html =~ "already the name of another Gall"

      html = view |> form("#name-form", name: %{form_label: "bud"}) |> render_submit()
      assert html =~ "already the name of another Gall"

      assert reload(gall).name == gall.name
      assert reload(gall).form_label == nil
    end

    test "parts that give no name need an override", %{conn: conn} do
      gall = gall_fixture(name: "Unknown (Unknown) zz-descriptor", descriptor: "zz-descriptor")
      {:ok, view, _html} = live(conn, ~p"/admin/galls/#{gall.id}")

      html = view |> form("#name-form", name: %{descriptor: ""}) |> render_submit()

      assert html =~ "give a name override"
      assert reload(gall).descriptor == "zz-descriptor"
    end
  end

  describe "the Gallformers note" do
    test "each save is a new dated version; earlier versions are listed", ctx do
      gall = described_gall(ctx)
      {:ok, _} = Sources.store_note(test_actor(), ctx.gallformers, gall.id, "Old note.", nil)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      assert has_element?(view, "#note-form textarea", "Old note.")

      view |> form("#note-form", note: %{text: "New note."}) |> render_submit()

      assert [newest, oldest] = Sources.list_gall_notes(gall.id)
      assert newest.version_date == Date.utc_today()
      assert oldest.version_date == nil
      assert has_element?(view, "#note-form textarea", "New note.")
      assert has_element?(view, "#note-version-#{newest.id}", "New note.")
      assert has_element?(view, "#note-version-#{oldest.id}", "Old note.")
    end

    test "an unchanged note stores nothing", ctx do
      gall = described_gall(ctx)
      {:ok, _} = Sources.store_note(test_actor(), ctx.gallformers, gall.id, "Same.", nil)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      html = view |> form("#note-form", note: %{text: "Same."}) |> render_submit()

      assert html =~ "unchanged"
      assert [_one] = Sources.list_gall_notes(gall.id)
    end

    test "a Gall's first note", ctx do
      gall = described_gall(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      view |> form("#note-form", note: %{text: "First."}) |> render_submit()

      assert [%{source_id: source_id}] = Sources.list_gall_notes(gall.id)
      assert source_id == ctx.gallformers.id
    end
  end

  describe "range exclusions" do
    defp excluded_on_map(view) do
      view
      |> element("#exclusions-range-map")
      |> render()
      |> then(&Regex.run(~r/data-excluded-range="([^"]*)"/, &1))
      |> List.last()
      |> String.replace("&quot;", "\"")
      |> Jason.decode!()
    end

    test "excluding a place saves a Gallformers statement that takes it out of the range", ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      render_hook(view, "toggle_region", %{"code" => "US-CA"})
      assert has_element?(view, "#marked-places", "California")

      view
      |> form("#exclusions-form", exclusions: %{statement: "No gall recorded in California."})
      |> render_submit()

      assert has_element?(view, "#exclusions-outcome", "Applied")

      assert [%{adjustment: :exclude, place_code: "US-CA", fact_id: fact_id}] =
               Catalog.list_range_adjustments(gall.id)

      assert [attribution] = Facts.list_attributions(fact_id)
      assert attribution.source_id == ctx.gallformers.id
      assert attribution.stance == :confirm
      assert attribution.statement_text == "No gall recorded in California."
      assert attribution.stated_on == Date.utc_today()

      assert Catalog.display_range(gall.id).in_range == ["CA-AB"]
      assert excluded_on_map(view) == ["US-CA"]
      refute has_element?(view, "#marked-places")
    end

    test "restoring an exclusion withdraws it with a Gallformers denial", ctx do
      gall = gall_with_range(ctx)

      {:ok, _} =
        Catalog.assert_range(
          test_actor(),
          %{gall_id: gall.id, adjustment: :exclude, place_id: place_id("CA")},
          confirm(ctx.source)
        )

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")
      assert excluded_on_map(view) == ["CA-AB"]

      render_hook(view, "toggle_region", %{"code" => "CA-AB"})
      assert has_element?(view, "#marked-places", "Alberta")

      view
      |> form("#exclusions-form", exclusions: %{statement: "Recorded in Alberta after all."})
      |> render_submit()

      assert Catalog.list_range_adjustments(gall.id) == []
      assert Catalog.display_range(gall.id).in_range == ["CA-AB", "US-CA"]

      [fact_id] =
        Repo.all(from(r in RangeFact, where: r.gall_id == ^gall.id, select: r.fact_id))

      stances = for a <- Facts.list_attributions(fact_id), do: {a.source_id, a.stance}
      assert {ctx.gallformers.id, :deny} in stances
      assert {ctx.source.id, :confirm} in stances
    end

    test "a statement is required", ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      render_hook(view, "toggle_region", %{"code" => "US-CA"})

      html =
        view |> form("#exclusions-form", exclusions: %{statement: "  "}) |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert %{total: 0} = Import.list_packages()
    end

    test "with nothing marked or restored there is nothing to save", ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      html =
        view |> form("#exclusions-form", exclusions: %{statement: "Nothing."}) |> render_submit()

      assert html =~ "Nothing to save"
      assert %{total: 0} = Import.list_packages()
    end

    test "a place outside the potential range cannot be marked", ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      render_hook(view, "toggle_region", %{"code" => "MX-JAL"})

      refute has_element?(view, "#marked-places")
    end

    test "a country with subdivisions opens the drill-down", ctx do
      gall = gall_with_range(ctx)
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")
      refute has_element?(view, "input[phx-click='toggle_place'][phx-value-code='US-CA']")

      render_hook(view, "toggle_country", %{"code" => "US"})

      assert has_element?(view, "input[phx-click='toggle_place'][phx-value-code='US-CA']")
      refute has_element?(view, "#marked-places")
    end

    test "a statement that needs a decision awaits review in the queue", ctx do
      plant = plant_fixture()
      :ok = host_range_fixture(plant, [{"US-CA", "exact"}])
      {genus, genus_name} = genus!()

      gall =
        gall_fixture(name: "#{genus_name} zz-undescribed-gall", descriptor: "zz-undescribed-gall")
        |> relate!("inducer_of", genus, ctx.source)
        |> relate!("host_of", plant, ctx.source)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/galls/#{gall.id}")

      render_hook(view, "toggle_region", %{"code" => "US-CA"})

      view
      |> form("#exclusions-form", exclusions: %{statement: "Not in California."})
      |> render_submit()

      assert %{entries: [package]} = Import.list_packages()
      assert package.status == :awaiting_review
      assert has_element?(view, "#exclusions-outcome", "awaits review")

      assert has_element?(
               view,
               "#exclusions-outcome a[href='/admin/queue/packages/#{package.id}']"
             )

      assert Catalog.list_range_adjustments(gall.id) == []
    end
  end
end
