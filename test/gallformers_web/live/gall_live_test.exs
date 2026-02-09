defmodule GallformersWeb.GallLiveTest do
  @moduledoc """
  LiveView tests for the gall detail page.
  """
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Gallformers.Galls
  alias Gallformers.Species

  describe "Gall page rendering" do
    test "renders gall details for valid ID", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        {:ok, _view, html} = live(conn, ~p"/gall/#{gall.id}")

        assert html =~ gall.name
      end
    end

    test "shows error for invalid ID format", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/invalid")

      assert html =~ "Invalid gall ID" or html =~ "not found" or html =~ "Gall Not Found"
    end

    test "shows error for non-existent ID", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/999999999")

      assert html =~ "not found" or html =~ "Gall not found"
    end

    test "displays hosts for gall with hosts", %{conn: conn} do
      galls = Galls.list_galls()

      # Find a gall that has hosts
      gall_with_host =
        Enum.find(galls, fn g ->
          length(Gallformers.GallHosts.get_hosts_for_gall(g.id)) > 0
        end)

      if gall_with_host do
        {:ok, _view, html} = live(conn, ~p"/gall/#{gall_with_host.id}")

        assert html =~ "Hosts:" or html =~ "host"
      end
    end

    test "displays morphology fields", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        {:ok, _view, html} = live(conn, ~p"/gall/#{gall.id}")

        # Should display various morphology fields
        assert html =~ "Color" or html =~ "Shape" or html =~ "Texture" or html =~ "Detachable"
      end
    end

    test "displays sources section", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        {:ok, _view, html} = live(conn, ~p"/gall/#{gall.id}")

        # Should display sources section
        assert html =~ "Sources" or html =~ "source" or html =~ "No sources"
      end
    end

    test "displays external links (See Also)", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        {:ok, _view, html} = live(conn, ~p"/gall/#{gall.id}")

        # Should display external reference links
        assert html =~ "See Also" or html =~ "iNaturalist" or html =~ "BugGuide"
      end
    end

    test "displays range map component", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        {:ok, view, _html} = live(conn, ~p"/gall/#{gall.id}")

        # Should have range map element
        assert has_element?(view, "#gall-range-map") or has_element?(view, "[id*='range']")
      end
    end

    test "displays completion status badge", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        {:ok, _view, html} = live(conn, ~p"/gall/#{gall.id}")

        # Should show completion status
        assert html =~ "Complete" or html =~ "In Progress"
      end
    end

    test "displays undescribed indicator for undescribed galls", %{conn: conn} do
      galls = Galls.list_galls()

      # Find an undescribed gall
      undescribed_gall = Enum.find(galls, fn g -> g.undescribed == true end)

      if undescribed_gall do
        {:ok, _view, html} = live(conn, ~p"/gall/#{undescribed_gall.id}")

        assert html =~ "undescribed" or html =~ "unknown"
      end
    end

    test "displays aliases when present", %{conn: conn} do
      galls = Galls.list_galls()

      # Find a gall with aliases
      gall_with_alias =
        Enum.find(galls, fn g ->
          length(Species.get_aliases_for_species(g.id)) > 0
        end)

      if gall_with_alias do
        {:ok, _view, html} = live(conn, ~p"/gall/#{gall_with_alias.id}")

        # Common names are displayed separately from Synonymy
        assert html =~ "Synonymy" or html =~ "Common Name"
      end
    end
  end

  describe "Page title" do
    test "sets page title to gall name", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        {:ok, view, _html} = live(conn, ~p"/gall/#{gall.id}")

        # Check page title
        assert page_title(view) =~ gall.name or page_title(view) =~ "Gallformers"
      end
    end

    test "sets page title for not found", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/999999999")

      assert page_title(view) =~ "Not Found" or page_title(view) =~ "Gallformers"
    end
  end

  describe "Host links" do
    test "host names are clickable links", %{conn: conn} do
      galls = Galls.list_galls()

      gall_with_host =
        Enum.find(galls, fn g ->
          length(Gallformers.GallHosts.get_hosts_for_gall(g.id)) > 0
        end)

      if gall_with_host do
        {:ok, view, _html} = live(conn, ~p"/gall/#{gall_with_host.id}")

        # Should have links to host pages
        assert has_element?(view, "a[href*='/host/']")
      end
    end
  end

  describe "Source links" do
    test "source titles are clickable links", %{conn: conn} do
      galls = Galls.list_galls()

      gall_with_source =
        Enum.find(galls, fn g ->
          length(Gallformers.Sources.get_sources_for_species(g.id)) > 0
        end)

      if gall_with_source do
        {:ok, view, _html} = live(conn, ~p"/gall/#{gall_with_source.id}")

        # Should have links to source pages
        assert has_element?(view, "a[href*='/source/']")
      end
    end
  end

  describe "Source deep-linking via ?source= param" do
    setup do
      # Create a source linked to gall 100 with a description
      source =
        Gallformers.Repo.insert!(%Gallformers.Sources.Source{
          title: "Test Source for Deep Link",
          author: "Test Author",
          pubyear: "2024",
          link: "https://example.com",
          citation: "Test citation",
          license: "Public Domain"
        })

      Gallformers.Repo.insert!(%Gallformers.Species.SpeciesSource{
        species_id: 100,
        source_id: source.id,
        description: "Deep link test description",
        useasdefault: false
      })

      %{source: source}
    end

    test "opens source modal when ?source= param matches", %{conn: conn, source: source} do
      {:ok, view, _html} = live(conn, "/gall/100?source=#{source.id}")

      # The modal should be open with the source's description
      assert has_element?(view, "#source-detail-modal")
      assert render(view) =~ "Deep link test description"
    end

    test "ignores invalid source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/gall/100?source=invalid")

      # Modal should not be open
      refute has_element?(view, "#source-detail-modal")
    end

    test "ignores non-existent source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/gall/100?source=999999")

      # Modal should not be open
      refute has_element?(view, "#source-detail-modal")
    end

    test "page loads normally without source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/gall/100")

      # Modal should not be open
      refute has_element?(view, "#source-detail-modal")
    end
  end

  describe "Image display" do
    test "displays image when available", %{conn: conn} do
      galls = Galls.list_galls()

      gall_with_image =
        Enum.find(galls, fn g ->
          length(Species.get_images_for_species(g.id)) > 0
        end)

      if gall_with_image do
        {:ok, view, _html} = live(conn, ~p"/gall/#{gall_with_image.id}")

        assert has_element?(view, "img[alt]")
      end
    end

    test "shows no image message when none available", %{conn: conn} do
      galls = Galls.list_galls()

      gall_without_image =
        Enum.find(galls, fn g ->
          length(Species.get_images_for_species(g.id)) == 0
        end)

      if gall_without_image do
        {:ok, _view, html} = live(conn, ~p"/gall/#{gall_without_image.id}")

        assert html =~ "No images" or html =~ "available"
      end
    end

    test "displays image credit when available", %{conn: conn} do
      galls = Galls.list_galls()

      gall_with_image =
        Enum.find(galls, fn g ->
          images = Species.get_images_for_species(g.id)
          length(images) > 0 and hd(images).creator != nil
        end)

      if gall_with_image do
        {:ok, _view, html} = live(conn, ~p"/gall/#{gall_with_image.id}")

        assert html =~ "Photo" or html =~ "credit" or html =~ "creator"
      end
    end
  end
end
