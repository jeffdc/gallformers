defmodule GallformersWeb.SectionLiveTest do
  @moduledoc """
  Tests for the public section page (a plant genus's section), which reads
  `Gallformers.Taxa` (`get_by_name/2`, `lineage/1`, `list_plants_under/1`)
  and `Gallformers.Catalog.count_galls_for_hosts/1`.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_actor: 0]

  alias Gallformers.Catalog
  alias Gallformers.Taxa

  defp section_fixture do
    family = plant_fixture(name: "Sectionfixturaceae", rank: :family)
    genus = plant_fixture(name: "Sectionfixtura", rank: :genus, parent: family)
    section = plant_fixture(name: "Sectionfixtlobatae", rank: :section, parent: genus)
    {:ok, _} = Taxa.add_common_name(test_actor(), section, "red fixture oaks")
    rubra = plant_fixture(name: "Sectionfixtura rubra", parent: section)
    {:ok, _} = Taxa.add_common_name(test_actor(), rubra, "northern fixture oak")
    velutina = plant_fixture(name: "Sectionfixtura velutina", parent: section)

    gall = gall_fixture()

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: rubra.id, object_gall_id: gall.id},
        confirm(source_fixture("Weld", "1959"))
      )

    %{section: section, rubra: rubra, velutina: velutina}
  end

  test "renders the section with its common names and breadcrumb", %{conn: conn} do
    section_fixture()

    {:ok, view, html} = live(conn, "/section/Sectionfixtlobatae")

    assert html =~ "Section Sectionfixtlobatae (red fixture oaks)"
    assert page_title(view) =~ "Section Sectionfixtlobatae"
    assert has_element?(view, ~s{a[href="/family/Sectionfixturaceae"]})
    assert has_element?(view, ~s{a[href="/genus/Sectionfixtura"]})
  end

  test "lists its plants with common names and gall counts", %{conn: conn} do
    %{rubra: rubra, velutina: velutina} = section_fixture()

    {:ok, view, html} = live(conn, "/section/Sectionfixtlobatae")

    assert html =~ "Species (2)"
    assert has_element?(view, ~s{a[href="/host/#{rubra.id}"]})
    assert has_element?(view, ~s{a[href="/host/#{velutina.id}"]})
    assert has_element?(view, "tbody tr", ~r/Sectionfixtura rubra\s+northern fixture oak\s+1/)
    assert has_element?(view, "tbody tr", ~r/Sectionfixtura velutina\s+0/)
  end

  test "filters its plants by name or common name", %{conn: conn} do
    section_fixture()

    {:ok, view, _html} = live(conn, "/section/Sectionfixtlobatae")

    html = view |> element("#section-search-form") |> render_change(%{"query" => "northern"})

    assert html =~ "Sectionfixtura rubra"
    refute html =~ "Sectionfixtura velutina"
  end

  test "returns not found for a nonexistent section", %{conn: conn} do
    {:ok, view, html} = live(conn, "/section/Nonexistent")

    assert html =~ "Section not found"
    assert page_title(view) =~ "Not Found"
  end
end
