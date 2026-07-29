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
      host_genus = create_host_mapping()

      unrelated_gall =
        Repo.insert!(%Species{
          name: "Andricus testunrelated",
          taxoncode: "gall",
          abundance_id: 1
        })

      {:ok, _} = Taxonomy.link_species_to_taxonomy(unrelated_gall.id, 33)

      {:ok, view, html} = live(conn, "/genus/Andricus")

      assert html =~ "Host genera used by this genus"
      assert html =~ "Show filters"
      refute has_element?(view, "#related-genera-filters")

      view
      |> element("button[phx-click='toggle_related_genera']")
      |> render_click()

      assert has_element?(view, "#related-genera-filters")
      assert render(view) =~ "TestHostGenus"

      view
      |> element("button[phx-click='filter_related_genus'][phx-value-id='#{host_genus.id}']")
      |> render_click()

      filtered_html = render(view)
      assert filtered_html =~ "Andricus crystallinus"
      refute filtered_html =~ "Andricus testunrelated"
    end

    test "lists gall genera associated with a host genus" do
      host_genus = create_host_mapping()

      assert [
               %{
                 id: 33,
                 name: "Andricus",
                 focal_species_count: 1,
                 focal_species_ids: [1]
               }
             ] = Taxonomy.list_associated_genera(host_genus.id, "plant")
    end
  end

  defp create_host_mapping do
    {:ok, family} =
      Taxonomy.create_taxonomy(%{
        name: "TestHostFamily",
        description: "Plant",
        type: "family"
      })

    {:ok, host_genus} =
      Taxonomy.create_taxonomy(%{
        name: "TestHostGenus",
        type: "genus",
        parent_id: family.id
      })

    {:ok, _} = Taxonomy.link_species_to_taxonomy(1, host_genus.id)
    {:ok, _} = Galls.create_gall_host(%{gall_species_id: 200, host_species_id: 1})

    host_genus
  end
end
