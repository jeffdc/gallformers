defmodule GallformersWeb.Admin.TaxonomyLive.NewTest do
  @moduledoc """
  Adding a taxon in the taxonomy admin (matter a856, Task 9): a plant from
  POWO-WCVP (name, family, genus, range, link; the old Host admin's
  duplicate warnings), or a taxon by name, rank and parent — moving some
  of the parent's children under a new rank, and drawing a new plant's
  Host range on the map. Writes are the signed-in admin's and in the
  replay log.
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
  alias Gallformers.Taxa

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Nel New")
    %{conn: conn, actor: Actor.user(user.id, "Nel New")}
  end

  defp uniq, do: System.unique_integer([:positive])
  defp get_assign(view, key), do: :sys.get_state(view.pid).socket.assigns[key]

  defp ops, do: for(e <- Import.list_replay_entries(), do: {e.kind, e.key["op"]})

  defp pick_parent(view, parent) do
    render_keyup(view, "search_parent", %{"value" => Taxa.accepted_name(parent)})
    render_click(view, "select_parent", %{"id" => "#{parent.id}"})
  end

  defp resolve(name) do
    case Taxa.resolve_name(name, kingdom: "Plantae") do
      {:ok, taxon} -> taxon
      _ -> nil
    end
  end

  describe "adding a plant from WCVP" do
    test "searches WCVP, showing loading then results", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      html = render_keyup(view, "search_wcvp", %{"value" => "Zzyzx"})
      assert html =~ "wcvp-search-loading"

      html = render_async(view)
      assert html =~ "Zzyzx wcvponly"
      refute html =~ "wcvp-search-loading"
    end

    test "a short query does not search", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      html = render_keyup(view, "search_wcvp", %{"value" => "Zz"})

      refute html =~ "wcvp-search-loading"
      assert get_assign(view, :wcvp_searching) == false
    end

    test "adds the plant with its family, genus, native range and WCVP link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      html = render_click(view, "select_wcvp", %{"id" => "800"})
      assert html =~ "Loading WCVP data..."

      html = render_async(view)
      assert html =~ "Wcvpseedus rangeus"
      assert html =~ "Seedaceae"
      assert html =~ "WCVP matched 1 native places (+ 1 introduced)."

      view |> element("#add-from-wcvp") |> render_click()

      plant = resolve("Wcvpseedus rangeus")
      assert_redirect(view, "/admin/taxonomy/#{plant.id}")

      assert [%{name: "Seedaceae", rank: :family}, %{name: "Wcvpseedus", rank: :genus} | _] =
               Taxa.lineage(plant)

      assert Wcvp.get_link(plant.id).wcvp_id == "800"

      assert [%{code: "US-CA", distribution_type: "native"}] =
               Ranges.get_places_for_taxon_with_precision(plant.id)

      assert {:plant_added, nil} in ops()
      assert {:taxonomy_edit, "set_host_range"} in ops()
      assert {:taxonomy_edit, "set_wcvp"} in ops()
    end

    test "includes the introduced range when asked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")
      render_click(view, "select_wcvp", %{"id" => "800"})
      render_async(view)

      render_click(view, "toggle_wcvp_introduced", %{})
      view |> element("#add-from-wcvp") |> render_click()

      plant = resolve("Wcvpseedus rangeus")

      assert %{"US-CA" => "native", "CA-AB" => "introduced"} ==
               plant.id
               |> Ranges.get_places_for_taxon_with_precision()
               |> Map.new(&{&1.code, &1.distribution_type})
    end

    test "uses the family and genus that exist", %{conn: conn} do
      family = plant_fixture(rank: :family, name: "Seedaceae")
      genus = plant_fixture(rank: :genus, name: "Wcvpseedus", parent: family)

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")
      render_click(view, "select_wcvp", %{"id" => "800"})
      render_async(view)
      view |> element("#add-from-wcvp") |> render_click()

      assert resolve("Wcvpseedus rangeus").parent_id == genus.id
    end

    test "warns of a plant with the name or the WCVP record already", %{conn: conn, actor: actor} do
      existing = plant_fixture(name: "Wcvptestus alpinus")
      linked = plant_fixture(name: "Linkedplant#{uniq()} alba")
      {:ok, _} = Wcvp.put_link(actor, linked, %{wcvp_id: "700"})

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")
      render_click(view, "select_wcvp", %{"id" => "700"})
      html = render_async(view)

      assert html =~ "Possible duplicate"
      assert has_element?(view, "#wcvp-prefilled a[href='/admin/taxonomy/#{existing.id}']")
      assert has_element?(view, "#wcvp-prefilled a[href='/admin/taxonomy/#{linked.id}']")
      assert html =~ "WCVP record is already linked to"
    end

    test "a record with no range in WCVP is refused", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")
      render_click(view, "select_wcvp", %{"id" => "500"})
      render_async(view)

      html = view |> element("#add-from-wcvp") |> render_click()

      assert html =~ "at least one range entry"
      assert is_nil(resolve("Zzyzx wcvponly"))
    end
  end

  describe "adding a taxon by name" do
    test "creates a genus under its family, logged for replay", %{conn: conn} do
      family = plant_fixture(rank: :family, name: "Newfamaceae#{uniq()}")
      name = "Newgenus#{uniq()}"

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")
      view |> form("#taxon-form", taxon: %{name: name, rank: "genus"}) |> render_change()
      pick_parent(view, family)
      view |> form("#taxon-form", taxon: %{name: name, rank: "genus"}) |> render_submit()

      genus = resolve(name)
      assert_redirect(view, "/admin/taxonomy/#{genus.id}")
      assert genus.parent_id == family.id
      assert genus.kingdom == "Plantae"
      assert {:taxonomy_edit, "create_taxon"} in ops()
    end

    test "below family a parent is required", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      html =
        view
        |> form("#taxon-form", taxon: %{name: "Orphanus", rank: "genus", kingdom: "Animalia"})
        |> render_submit()

      assert html =~ "A genus needs a parent"
    end

    test "a root needs a kingdom", %{conn: conn} do
      name = "Rootidae#{uniq()}"
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      html = view |> form("#taxon-form", taxon: %{name: name, rank: "family"}) |> render_submit()
      assert html =~ "needs a kingdom"

      view
      |> form("#taxon-form", taxon: %{name: name, rank: "family", kingdom: "Animalia"})
      |> render_submit()

      assert {:ok, %{kingdom: "Animalia", parent_id: nil}} = Taxa.resolve_name(name)
    end

    test "warns of a taxon with the name, and refuses one under the same parent", %{conn: conn} do
      family = taxon_fixture(rank: :family, name: "Dupidae#{uniq()}", kingdom: "Animalia")
      name = "Dupgenus#{uniq()}"
      existing = taxon_fixture(rank: :genus, name: name, parent: family)

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")
      html = view |> form("#taxon-form", taxon: %{name: name, rank: "genus"}) |> render_change()

      assert html =~ "Possible duplicate"
      assert has_element?(view, "a[href='/admin/taxonomy/#{existing.id}']")

      pick_parent(view, family)
      html = view |> form("#taxon-form", taxon: %{name: name, rank: "genus"}) |> render_submit()

      assert html =~ "already exists under this parent"
    end

    test "warns of a name that is another taxon's common name", %{conn: conn, actor: actor} do
      plant = plant_fixture(name: "Commonly#{uniq()} alba")
      {:ok, _} = Taxa.add_common_name(actor, plant, "zebra oak#{uniq()}")
      [common] = Taxa.list_common_names(plant)

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")

      html =
        view
        |> form("#taxon-form", taxon: %{name: common.name, rank: "species"})
        |> render_change()

      assert html =~ "common name of"
      assert has_element?(view, "a[href='/admin/taxonomy/#{plant.id}']")
    end

    test "a new tribe takes the picked children of its parent", %{conn: conn} do
      family = taxon_fixture(rank: :family, name: "Tribidae#{uniq()}", kingdom: "Animalia")
      moved = taxon_fixture(rank: :genus, name: "Movedgenus#{uniq()}", parent: family)
      stayed = taxon_fixture(rank: :genus, name: "Stayedgenus#{uniq()}", parent: family)
      name = "Newtribini#{uniq()}"

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")
      view |> form("#taxon-form", taxon: %{name: name, rank: "tribe"}) |> render_change()
      pick_parent(view, family)
      assert has_element?(view, "#children-to-move", Taxa.accepted_name(stayed))

      html = view |> form("#taxon-form", taxon: %{name: name, rank: "tribe"}) |> render_submit()
      assert html =~ "Pick at least one child"

      render_click(view, "toggle_child", %{"id" => "#{moved.id}"})
      view |> form("#taxon-form", taxon: %{name: name, rank: "tribe"}) |> render_submit()

      {:ok, tribe} = Taxa.resolve_name(name)
      assert tribe.parent_id == family.id
      assert Taxa.get_taxon!(moved.id).parent_id == tribe.id
      assert Taxa.get_taxon!(stayed.id).parent_id == family.id
      assert {:taxonomy_edit, "place"} in ops()
    end

    test "a new plant needs a Host range, drawn on the map", %{conn: conn} do
      genus = plant_fixture(rank: :genus, name: "Drawgenus#{uniq()}")
      name = "#{Taxa.accepted_name(genus)} mapped"

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/new")
      view |> form("#taxon-form", taxon: %{name: name, rank: "species"}) |> render_change()
      pick_parent(view, genus)
      assert has_element?(view, "#host-range-map")

      html = view |> form("#taxon-form", taxon: %{name: name, rank: "species"}) |> render_submit()
      assert html =~ "at least one range entry"

      render_click(view, "toggle_region", %{"code" => "US-CA"})
      view |> form("#taxon-form", taxon: %{name: name, rank: "species"}) |> render_submit()

      plant = resolve(name)
      assert plant.parent_id == genus.id

      assert [%{code: "US-CA", distribution_type: "native"}] =
               Ranges.get_places_for_taxon_with_precision(plant.id)

      assert {:plant_added, nil} in ops()
      assert {:taxonomy_edit, "set_host_range"} in ops()
    end
  end
end
