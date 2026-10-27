defmodule GallformersWeb.Admin.TaxonomyLive.IndexTest do
  @moduledoc """
  The taxonomy admin's list (matter a856, Task 9): search taxa by name,
  synonym or common name; browse the tree from its roots; move selected
  children under another parent (the old "move genera"), logged for
  replay.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Audit.Actor
  alias Gallformers.Import
  alias Gallformers.Taxa

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Ida Index")
    %{conn: conn, actor: Actor.user(user.id, "Ida Index")}
  end

  defp uniq, do: System.unique_integer([:positive])

  describe "searching" do
    test "finds taxa by accepted name, synonym or common name, linking each to its page",
         %{conn: conn, actor: actor} do
      tag = "Zqx#{uniq()}"
      by_name = plant_fixture(name: "#{tag}us alba")
      by_synonym = plant_fixture(name: "Otherplant#{uniq()} rubra")
      {:ok, _} = Taxa.add_synonym(actor, by_synonym, "#{tag}us rubra")
      by_common = taxon_fixture(rank: :genus, name: "Commongenus#{uniq()}", kingdom: "Animalia")
      {:ok, _} = Taxa.add_common_name(actor, by_common, "#{tag} wasps")

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy")
      view |> form("#taxonomy-search-form", %{q: tag}) |> render_change()

      assert_patch(view, ~p"/admin/taxonomy?#{%{q: tag}}")

      for taxon <- [by_name, by_synonym, by_common],
          do: assert(has_element?(view, "#taxa-table a[href='/admin/taxonomy/#{taxon.id}']"))

      assert has_element?(view, "#taxon-#{by_common.id}", "Animalia")
    end
  end

  describe "browsing" do
    test "starts at the roots and walks down by the child counts", %{conn: conn} do
      family = taxon_fixture(rank: :family, name: "Aabrowsidae#{uniq()}", kingdom: "Animalia")
      genus = taxon_fixture(rank: :genus, name: "Browsegenus#{uniq()}", parent: family)
      _species = taxon_fixture(name: "#{Taxa.accepted_name(genus)} alba", parent: genus)

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy")
      assert has_element?(view, "#taxon-#{family.id}", "1")
      refute has_element?(view, "#taxon-#{genus.id}")

      view |> element("#taxon-#{family.id} a[href*='parent=']") |> render_click()
      assert_patch(view, ~p"/admin/taxonomy?#{%{parent: family.id}}")

      assert has_element?(view, "#taxon-#{genus.id}")
      assert has_element?(view, "#browse-trail", Taxa.accepted_name(family))
    end

    test "has the new-taxon and Host range review links", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy")

      assert has_element?(view, "a[href='/admin/taxonomy/new']")
      assert has_element?(view, "a[href='/admin/host-range']")
    end
  end

  describe "moving selected children" do
    test "moves the selected genera under the picked family", %{conn: conn} do
      from = taxon_fixture(rank: :family, name: "Fromidae#{uniq()}", kingdom: "Animalia")
      to = taxon_fixture(rank: :family, name: "Toidae#{uniq()}", kingdom: "Animalia")
      a = taxon_fixture(rank: :genus, name: "Movea#{uniq()}", parent: from)
      b = taxon_fixture(rank: :genus, name: "Moveb#{uniq()}", parent: from)
      c = taxon_fixture(rank: :genus, name: "Movec#{uniq()}", parent: from)

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy?#{%{parent: from.id}}")

      render_click(view, "toggle_select", %{"id" => "#{a.id}"})
      render_click(view, "toggle_select", %{"id" => "#{b.id}"})
      render_click(view, "open_move_modal", %{})
      render_keyup(view, "search_move_target", %{"value" => Taxa.accepted_name(to)})
      render_click(view, "select_move_target", %{"id" => "#{to.id}"})
      html = view |> element("#move-selected") |> render_click()

      assert html =~ "Moved 2 taxa under #{Taxa.accepted_name(to)}"
      assert Taxa.get_taxon!(a.id).parent_id == to.id
      assert Taxa.get_taxon!(b.id).parent_id == to.id
      assert Taxa.get_taxon!(c.id).parent_id == from.id

      assert 2 ==
               Enum.count(Import.list_replay_entries(), &(&1.key["op"] == "place"))
    end

    test "the new parent must rank above the selected taxa", %{conn: conn} do
      from = taxon_fixture(rank: :family, name: "Rankidae#{uniq()}", kingdom: "Animalia")
      genus = taxon_fixture(rank: :genus, name: "Rankgenus#{uniq()}", parent: from)
      sibling = taxon_fixture(rank: :genus, name: "Rankgenus#{uniq()}b", parent: from)

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy?#{%{parent: from.id}}")
      render_click(view, "toggle_select", %{"id" => "#{genus.id}"})
      render_click(view, "open_move_modal", %{})
      render_keyup(view, "search_move_target", %{"value" => Taxa.accepted_name(sibling)})

      results = :sys.get_state(view.pid).socket.assigns.move_results
      refute Enum.any?(results, &(&1.id == sibling.id))
    end
  end
end
