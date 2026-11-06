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

  # The page's visible text: a name's italic and upright parts are separate
  # elements, so assert on text rather than raw HTML.
  defp page_text(html), do: html |> LazyHTML.from_document() |> LazyHTML.text()

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
      {:ok, view, _html} = live(conn, "/genus/Andricus")

      assert has_element?(view, "#genus-galls-section h2", "Galls")
      assert has_element?(view, "#genus-galls-section [data-part=count]", "4")
      refute has_element?(view, "#genus-hosts-section")

      for id <- [200, 300, 301, 304] do
        assert has_element?(view, ~s{a[href="/gall/#{id}"]})
      end

      view |> element("button[phx-click=galls_view][phx-value-view=table]") |> render_click()

      assert has_element?(view, "tbody tr", ~r/Andricus seedii \(agamic\)\s+seed oak apple\s+1/)

      assert has_element?(
               view,
               "tbody tr",
               ~r/Andricus n-densiflorus-seed-gall\s+Undescribed\s+2/
             )
    end

    test "filters the list by name or common name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/genus/Andricus")

      html = view |> element("#genus-search-form") |> render_change(%{"query" => "oak apple"})

      assert page_text(html) =~ "Andricus seedii (agamic)"
      refute page_text(html) =~ "Andricus crystallinus"
    end

    test "an unknown genus name is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, "/genus/Nonexistent") end
    end

    test "an old numeric URL redirects through the crosswalk", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/genus/Andricus"}}} = live(conn, "/genus/33")
    end
  end

  describe "a host genus" do
    test "lists its plants with gall counts, and the Galls on the genus as a whole", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/genus/Notholithocarpus")

      assert has_element?(view, "#genus-hosts-section h2", "Species")
      assert has_element?(view, "#genus-hosts-section [data-part=count]", "1")
      assert has_element?(view, ~s{a[href="/host/10"]})
      assert has_element?(view, "tbody tr", ~r/Notholithocarpus densiflorus\s+tanoak\s+5/)

      assert has_element?(view, "#galls-on-taxon", "Andricus")
      assert has_element?(view, ~s{#galls-on-taxon a[href="/gall/304"]})
      refute has_element?(view, "#genus-galls-section")

      assert has_element?(
               view,
               ~s{a[href="/id?g=Notholithocarpus"]},
               "Identify a gall on Notholithocarpus"
             )
    end

    test "shows its common name, migrated from the old taxonomy description", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/genus/Notholithocarpus")

      assert has_element?(view, "header dd", "Tanoaks")
    end
  end

  describe "related genera" do
    test "the Host genus facet narrows the Galls", %{conn: conn} do
      fixture = create_mapping_fixture()
      other_host = plant_fixture(name: "LiveMappingOtherHost", rank: :genus)

      extra =
        for i <- 1..6 do
          gall = gall_fixture(name: "LiveMappingGallGenus unrelatus extra #{i}")
          relate!("inducer_of", fixture.unrelated_inducer, gall)
          relate!("host_of", other_host, gall)
          gall
        end

      :ok =
        Catalog.refresh_gall_index(
          [fixture.associated_gall.id, fixture.unrelated_gall.id] ++ Enum.map(extra, & &1.id)
        )

      {:ok, view, _html} = live(conn, "/genus/#{fixture.gall_genus_name}")

      assert has_element?(view, "#genus-galls-facets", fixture.host_genus_name)

      html =
        view
        |> element("#genus-galls-facets")
        |> render_change(%{"host" => [fixture.host_genus_name]})

      assert page_text(html) =~ fixture.associated_gall.name
      refute page_text(html) =~ fixture.unrelated_gall.name
      assert has_element?(view, "#genus-galls-section [data-part=count]", "1 of 8")

      view |> element("button[phx-click=galls_clear]") |> render_click()
      assert has_element?(view, "#genus-galls-section [data-part=count]", "8")
    end

    test "the Gallformer genera on its plants filter the plants", %{conn: conn} do
      fixture = create_mapping_fixture()

      {:ok, view, _html} = live(conn, "/genus/#{fixture.host_genus_name}")

      assert has_element?(view, "button[phx-click=plants_filter]", fixture.gall_genus_name)

      html =
        view
        |> element("button[phx-click=plants_filter][phx-value-id='#{fixture.gall_genus.id}']")
        |> render_click()

      assert page_text(html) =~ fixture.associated_host_name
      refute page_text(html) =~ fixture.unrelated_host_name

      assert has_element?(
               view,
               "button[phx-click=plants_filter][phx-value-id='#{fixture.gall_genus.id}'][aria-pressed=true]"
             )

      html =
        view
        |> element("button[phx-click=plants_filter][phx-value-id=all]")
        |> render_click()

      assert page_text(html) =~ fixture.unrelated_host_name
    end
  end

  test "a genus with both Galls and host plants lists both", %{conn: conn} do
    family = plant_fixture(name: "Bothfixturaceae", rank: :family)
    genus = plant_fixture(name: "Bothfixtura", rank: :genus, parent: family)
    mistletoe = plant_fixture(name: "Bothfixtura leucarpa", parent: genus)
    gall = gall_fixture(name: "Bothfixtura leucarpa witches broom")
    relate!("inducer_of", mistletoe, gall)

    :ok = Catalog.refresh_gall_index([gall.id])
    {:ok, view, _html} = live(conn, "/genus/Bothfixtura")

    assert has_element?(view, "#genus-galls-section [data-part=count]", "1")
    assert has_element?(view, "#genus-hosts-section [data-part=count]", "1")
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
      {:ok, view, html} = live(conn, "/genus/Twinfixta?family=Twinfixtaceae")

      assert has_element?(view, "#genus-hosts-section [data-part=count]", "1")
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
      unrelated_inducer: unrelated_inducer,
      associated_host_name: "LiveMappingHostGenus associata",
      unrelated_host_name: "LiveMappingHostGenus unrelata"
    }
  end
end
