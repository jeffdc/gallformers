defmodule GallformersWeb.GenusLiveTest do
  @moduledoc """
  Tests for the public genus browse page with semantic URLs.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Gallformers.{Galls, Repo, Taxonomy}
  alias Gallformers.Species.Species

  describe "GenusLive with name-based URLs" do
    test "renders genus page by name", %{conn: conn} do
      # Andricus (id=33) is a genus under Cynipini tribe
      {:ok, _view, html} = live(conn, "/genus/Andricus")

      assert html =~ "Andricus"
    end

    test "shows breadcrumb with family name link", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/Andricus")

      assert html =~ "Cynipidae"
      assert html =~ "/family/Cynipidae"
      refute html =~ "/family/30"
    end

    test "shows breadcrumb with intermediate name links", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/Andricus")

      # Should show intermediate breadcrumbs with rank-typed URLs
      assert html =~ "Cynipinae"
      assert html =~ "/subfamily/Cynipinae"
      refute html =~ "/taxonomy/31"
    end

    test "shows species for the genus", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/Andricus")

      # Andricus crystallinus (id=200) is linked to genus Andricus (id=33)
      assert html =~ "Andricus crystallinus"
    end

    test "returns error for nonexistent genus name", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/Nonexistent")

      assert html =~ "not found" or html =~ "Not Found"
    end

    test "shows associated host genera collapsed and filters species when expanded", %{conn: conn} do
      fixture = create_mapping_fixture()

      {:ok, view, html} = live(conn, "/genus/#{fixture.gall_genus.name}")

      assert html =~ "Host genera used by this genus"
      assert html =~ "Show filters"
      refute has_element?(view, "#related-genera-filters")

      view
      |> element("button[phx-click='toggle_related_genera']")
      |> render_click()

      assert has_element?(view, "#related-genera-filters")
      assert render(view) =~ fixture.host_genus.name
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

    test "shows associated gall genera collapsed and filters hosts when expanded", %{conn: conn} do
      fixture = create_mapping_fixture()

      {:ok, view, html} = live(conn, "/genus/#{fixture.host_genus.name}")

      assert html =~ "Gall-former genera found on this host"
      assert html =~ "Show filters"
      refute has_element?(view, "#related-genera-filters")

      view
      |> element("button[phx-click='toggle_related_genera']")
      |> render_click()

      assert has_element?(view, "#related-genera-filters")
      assert render(view) =~ fixture.gall_genus.name
      assert has_element?(view, "button.gf-btn-pill[phx-value-id='all']")

      view
      |> element(
        "button[phx-click='filter_related_genus'][phx-value-id='#{fixture.gall_genus.id}']"
      )
      |> render_click()

      filtered_html = render(view)
      assert filtered_html =~ fixture.associated_host.name
      refute filtered_html =~ fixture.unrelated_host.name
    end
  end

  defp create_mapping_fixture do
    {:ok, gall_family} =
      Taxonomy.create_taxonomy(%{
        name: "LiveMappingGallFamily",
        description: "Wasp",
        type: "family"
      })

    {:ok, host_family} =
      Taxonomy.create_taxonomy(%{
        name: "LiveMappingHostFamily",
        description: "Plant",
        type: "family"
      })

    {:ok, gall_genus} =
      Taxonomy.create_taxonomy(%{
        name: "LiveMappingGallGenus",
        type: "genus",
        parent_id: gall_family.id
      })

    {:ok, host_genus} =
      Taxonomy.create_taxonomy(%{
        name: "LiveMappingHostGenus",
        type: "genus",
        parent_id: host_family.id
      })

    associated_gall =
      Repo.insert!(%Species{name: "LiveMappingGallGenus associated", taxoncode: "gall"})

    unrelated_gall =
      Repo.insert!(%Species{name: "LiveMappingGallGenus unrelated", taxoncode: "gall"})

    associated_host =
      Repo.insert!(%Species{name: "LiveMappingHostGenus associated", taxoncode: "plant"})

    unrelated_host =
      Repo.insert!(%Species{name: "LiveMappingHostGenus unrelated", taxoncode: "plant"})

    for species <- [associated_gall, unrelated_gall] do
      {:ok, _} = Taxonomy.link_species_to_taxonomy(species.id, gall_genus.id)
    end

    for species <- [associated_host, unrelated_host] do
      {:ok, _} = Taxonomy.link_species_to_taxonomy(species.id, host_genus.id)
    end

    {:ok, _} =
      Galls.create_gall_host(%{
        gall_species_id: associated_gall.id,
        host_species_id: associated_host.id
      })

    %{
      gall_genus: gall_genus,
      host_genus: host_genus,
      associated_gall: associated_gall,
      unrelated_gall: unrelated_gall,
      associated_host: associated_host,
      unrelated_host: unrelated_host
    }
  end
end
