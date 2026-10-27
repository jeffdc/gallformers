defmodule GallformersWeb.GenusLiveTest do
  @moduledoc """
  Tests for the public genus page, which reads `Gallformers.Taxa`
  (`get_by_name/2`, `lineage/1`, `subtree_ids/1`, `list_plants_under/1`)
  and `Gallformers.Catalog` (Galls by Inducer and on the genus as a Host,
  their details, gall counts and the related-genera filters).

  Uses the converted seeds (`priv/repo/test_seeds.sql`) — Andricus (under
  Cynipini, Cynipinae, Cynipidae) with Galls 200, 300, 301 and the
  undescribed 304 linked at the genus; Notholithocarpus with plant 10, the
  genus itself a Host of Gall 304 — and fixtures.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Reading the seeds, converted, is part of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_actor: 0]
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog

  defp relate!(type, taxon, gall) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: type, subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source_fixture("Weld", "1959"))
      )

    :ok
  end

  describe "a gall-former genus" do
    test "renders genus page by name", %{conn: conn} do
      {:ok, view, html} = live(conn, "/genus/Andricus")

      assert html =~ "Andricus"
      assert page_title(view) =~ "Genus Andricus"
    end

    test "shows breadcrumb with family and intermediate name links", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/genus/Andricus")

      assert has_element?(view, ~s{a[href="/family/Cynipidae"]})
      assert has_element?(view, ~s{a[href="/subfamily/Cynipinae"]})
      assert has_element?(view, ~s{a[href="/tribe/Cynipini"]})
    end

    test "lists the Galls of its Inducers, the undescribed one too, with Host counts", %{
      conn: conn
    } do
      {:ok, view, html} = live(conn, "/genus/Andricus")

      assert html =~ "Galls (4)"
      refute html =~ "Hosts ("

      for id <- [200, 300, 301, 304] do
        assert has_element?(view, ~s{a[href="/gall/#{id}"]})
      end

      assert has_element?(view, "tbody tr", ~r/Andricus seedii \(agamic\)\s+seed oak apple\s+1/)
      assert has_element?(view, "tbody tr", ~r/Andricus n-densiflorus-seed-gall\s+2/)
    end

    test "filters the list by name or common name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/genus/Andricus")

      html = view |> element("#genus-search-form") |> render_change(%{"query" => "oak apple"})

      assert html =~ "Andricus seedii (agamic)"
      refute html =~ "Andricus crystallinus"
    end

    test "returns error for nonexistent genus name", %{conn: conn} do
      {:ok, view, html} = live(conn, "/genus/Nonexistent")

      assert html =~ "Genus not found"
      assert page_title(view) =~ "Not Found"
    end

    test "an old numeric URL redirects through the crosswalk", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/genus/Andricus"}}} = live(conn, "/genus/33")
    end
  end

  describe "a host genus" do
    test "lists its plants with gall counts, and the Galls on the genus as a whole", %{
      conn: conn
    } do
      {:ok, view, html} = live(conn, "/genus/Notholithocarpus")

      assert html =~ "Hosts (1)"
      assert has_element?(view, ~s{a[href="/host/10"]})
      assert has_element?(view, "tbody tr", ~r/Notholithocarpus densiflorus\s+tanoak\s+5/)

      assert html =~ "Galls on the genus as a whole (1)"
      assert has_element?(view, ~s{a[href="/gall/304"]})
      refute html =~ "Galls (1)"
    end

    test "shows its common name, migrated from the old taxonomy description", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/Notholithocarpus")

      assert html =~ "Notholithocarpus (Tanoaks)"
    end
  end

  describe "related genera" do
    test "shows associated host genera collapsed and filters Galls when expanded", %{conn: conn} do
      fixture = create_mapping_fixture()

      {:ok, view, html} = live(conn, "/genus/#{fixture.gall_genus_name}")

      assert html =~ "Host genera used by this genus"
      assert html =~ "Show filters"
      refute has_element?(view, "#related-genera-filters-galls")

      view
      |> element("button[phx-click='toggle_related_genera'][phx-value-section='galls']")
      |> render_click()

      assert has_element?(view, "#related-genera-filters-galls")
      assert render(view) =~ fixture.host_genus_name
      assert has_element?(view, "button.gf-btn-pill[phx-value-id='all']")

      view
      |> element(
        "button[phx-click='filter_related_genus'][phx-value-id='#{fixture.host_genus.id}']"
      )
      |> render_click()

      filtered_html = render(view)
      assert filtered_html =~ fixture.associated_gall.name
      refute filtered_html =~ fixture.unrelated_gall.name
    end

    test "shows associated gall-former genera collapsed and filters hosts when expanded", %{
      conn: conn
    } do
      fixture = create_mapping_fixture()

      {:ok, view, html} = live(conn, "/genus/#{fixture.host_genus_name}")

      assert html =~ "Gall-former genera found on this host"
      assert html =~ "Show filters"
      refute has_element?(view, "#related-genera-filters-hosts")

      view
      |> element("button[phx-click='toggle_related_genera'][phx-value-section='hosts']")
      |> render_click()

      assert has_element?(view, "#related-genera-filters-hosts")
      assert render(view) =~ fixture.gall_genus_name

      view
      |> element(
        "button[phx-click='filter_related_genus'][phx-value-id='#{fixture.gall_genus.id}']"
      )
      |> render_click()

      filtered_html = render(view)
      assert filtered_html =~ fixture.associated_host_name
      refute filtered_html =~ fixture.unrelated_host_name
    end
  end

  test "a genus with both Galls and host plants lists both", %{conn: conn} do
    family = plant_fixture(name: "Bothfixturaceae", rank: :family)
    genus = plant_fixture(name: "Bothfixtura", rank: :genus, parent: family)
    mistletoe = plant_fixture(name: "Bothfixtura leucarpa", parent: genus)
    gall = gall_fixture(name: "Bothfixtura leucarpa witches broom")
    relate!("inducer_of", mistletoe, gall)

    {:ok, view, html} = live(conn, "/genus/Bothfixtura")

    assert html =~ "Galls (1)"
    assert html =~ "Hosts (1)"
    assert has_element?(view, ~s{a[href="/gall/#{gall.id}"]})
    assert has_element?(view, ~s{a[href="/host/#{mistletoe.id}"]})
  end

  describe "a genus name used in two kingdoms" do
    setup do
      animals = taxon_fixture(name: "Twinfixtidae", rank: :family, kingdom: "Animalia")
      plants = plant_fixture(name: "Twinfixtaceae", rank: :family)
      animal = taxon_fixture(name: "Twinfixta", rank: :genus, parent: animals)
      plant = plant_fixture(name: "Twinfixta", rank: :genus, parent: plants)
      plant_fixture(name: "Twinfixta alba", parent: plant)

      %{animal: animal, plant: plant}
    end

    test "offers each, with its family", %{conn: conn} do
      {:ok, view, html} = live(conn, "/genus/Twinfixta")

      assert html =~ "This genus name exists under multiple families"
      assert has_element?(view, ~s{a[href="/genus/Twinfixta?family=Twinfixtidae"]})
      assert has_element?(view, ~s{a[href="/genus/Twinfixta?family=Twinfixtaceae"]})
      assert page_title(view) =~ "Disambiguation"
    end

    test "the family hint picks one", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/Twinfixta?family=Twinfixtaceae")

      assert html =~ "Hosts (1)"
      assert html =~ "Twinfixta alba"
    end
  end

  defp create_mapping_fixture do
    gall_family = taxon_fixture(name: "LiveMappingGallFamily", rank: :family, kingdom: "Animalia")
    gall_genus = taxon_fixture(name: "LiveMappingGallGenus", rank: :genus, parent: gall_family)
    host_family = plant_fixture(name: "LiveMappingHostFamily", rank: :family)
    host_genus = plant_fixture(name: "LiveMappingHostGenus", rank: :genus, parent: host_family)

    associated_inducer =
      taxon_fixture(name: "LiveMappingGallGenus associatus", parent: gall_genus)

    unrelated_inducer = taxon_fixture(name: "LiveMappingGallGenus unrelatus", parent: gall_genus)
    associated_gall = gall_fixture(name: "LiveMappingGallGenus associatus gall")
    unrelated_gall = gall_fixture(name: "LiveMappingGallGenus unrelatus gall")
    relate!("inducer_of", associated_inducer, associated_gall)
    relate!("inducer_of", unrelated_inducer, unrelated_gall)

    associated_host = plant_fixture(name: "LiveMappingHostGenus associata", parent: host_genus)
    plant_fixture(name: "LiveMappingHostGenus unrelata", parent: host_genus)
    relate!("host_of", associated_host, associated_gall)

    %{
      gall_genus: gall_genus,
      gall_genus_name: "LiveMappingGallGenus",
      host_genus: host_genus,
      host_genus_name: "LiveMappingHostGenus",
      associated_gall: associated_gall,
      unrelated_gall: unrelated_gall,
      associated_host_name: "LiveMappingHostGenus associata",
      unrelated_host_name: "LiveMappingHostGenus unrelata"
    }
  end
end
