defmodule GallformersWeb.GallLiveTest do
  @moduledoc """
  LiveView tests for the Gall detail page, which reads
  `Gallformers.Catalog.gall_page/1`.

  Uses the converted seeds (`priv/repo/test_seeds.sql`): Galls 300/301 are
  an agamic/sexgen pair of Andricus seedii (300 has an image, a Gallformers
  note, a default citation of Source 59, a common name and a synonym; 301's
  default Source is its note), 304 an undescribed Andricus gall with a
  Gallformers Code, a former label, a code and a genus Host, 102 a Gall with
  no Hosts; plant 10 is the Host of 300–304.
  """
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.Catalog
  alias Gallformers.DataCase

  describe "Gall page rendering" do
    test "renders the Gall's name, its generation split off", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/300")

      assert html =~ "Andricus seedii"
      assert html =~ "agamic"
    end

    test "shows error for invalid ID format", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/invalid")

      assert html =~ "Invalid gall ID"
    end

    test "shows not found for a missing ID and for an ID that is not a Gall", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/999999999")
      assert html =~ "Gall not found"

      {:ok, _view, html} = live(conn, ~p"/gall/10")
      assert html =~ "Gall not found"
    end

    test "an old ID excluded as a non-gall redirects (301) to the gall-lookalikes Article",
         %{conn: conn} do
      {:ok, 1} =
        Catalog.insert_non_gall_redirects(DataCase.test_actor(), [
          %{species_id: 990_250, name: "Fixturella lookalike"}
        ])

      conn = get(conn, "/gall/990250")

      assert redirected_to(conn, 301) == "/articles/gall-lookalikes"
    end

    test "shows the Inducer's taxonomy as a breadcrumb", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "a[href='/family/Cynipidae']")
      assert has_element?(view, "a[href='/subfamily/Cynipinae']")
      assert has_element?(view, "a[href='/tribe/Cynipini']")
      assert has_element?(view, "a[href='/genus/Andricus']")
      assert html =~ "Tribe:"
    end

    test "shows Traits and abundance", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert view |> element("div", ~r/Detachable:\s*Detachable/) |> has_element?()
      assert view |> element("div", ~r/Abundance:\s*common/) |> has_element?()
      assert render(view) =~ "Location:"
    end

    test "displays completion status badge", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/300")
      assert html =~ "Complete"

      {:ok, _view, html} = live(conn, ~p"/gall/301")
      assert html =~ "In Progress"
    end

    test "shows common names and the Inducer's synonyms", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/300")

      assert html =~ "Common Name(s):"
      assert html =~ "seed oak apple"
      assert html =~ "Synonymy (1)"
      assert html =~ "Callirhytis seedii"
    end

    test "shows former labels and codes in the names table, not as common names",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/gall/304")

      refute html =~ "Common Name(s):"
      assert html =~ "Synonymy (2)"
      assert has_element?(view, "tr", ~r/Andricus q-seed-old-label\s*former label/)
      assert has_element?(view, "tr", ~r/q-seed-code\s*code/)
    end

    test "lists the other generation as a related Gall", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/gall/300")

      assert html =~ "Related Galls (1)"
      assert has_element?(view, "a[href='/gall/301']")
    end
  end

  describe "the admin link" do
    test "an admin gets a link to the Gall page in admin; a visitor does not", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")
      refute has_element?(view, "a[href='/admin/galls/300']")

      {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
      {:ok, view, _html} = live(admin_conn, ~p"/gall/300")
      assert has_element?(view, "a[href='/admin/galls/300']")
    end

    test "an admin's image edit link goes to the Gall page's images", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")
      refute has_element?(view, "a[href='/admin/galls/300#images']")

      {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
      {:ok, view, _html} = live(admin_conn, ~p"/gall/300")
      assert has_element?(view, "#gall-images a[href='/admin/galls/300#images']")
    end

    test "a Gall with no images offers an admin to add them on the Gall page", %{conn: conn} do
      gall = Gallformers.CatalogFixtures.gall_fixture()
      {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
      {:ok, view, _html} = live(admin_conn, ~p"/gall/#{gall.id}")

      assert has_element?(view, "a[href='/admin/galls/#{gall.id}#images']", "Add images")
    end

    test "no admin link goes to a deleted old screen", %{conn: conn} do
      {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
      {:ok, view, _html} = live(admin_conn, ~p"/gall/300")

      refute has_element?(view, "a[href^='/admin/gallhost']")
      refute has_element?(view, "a[href^='/admin/images']")
    end
  end

  describe "undescribed Galls" do
    test "show the undescribed notice, the Code and its iNaturalist link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/304")

      assert html =~ "The inducer of this gall is unknown or undescribed."
      assert html =~ "iNaturalist"
      assert html =~ "n-densiflorus-seed-gall"
    end

    test "a described Gall shows no undescribed notice", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/300")

      refute html =~ "unknown or undescribed"
    end
  end

  describe "Page title and SEO" do
    test "sets page title to the Gall's name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert page_title(view) =~ "Andricus seedii (agamic)"
    end

    test "sets page title for not found", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/999999999")

      assert page_title(view) =~ "Not Found"
    end

    test "describes the Gall from its Traits", %{conn: conn} do
      html = conn |> get(~p"/gall/300") |> html_response(200)

      assert html =~ "Andricus seedii (agamic) - A gall. Detachable."
    end
  end

  describe "Host links" do
    test "a species-rank Host links to its host page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "a[href='/host/10']", "Notholithocarpus densiflorus")
    end

    test "a genus Host links to its genus page, marked genus-level", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/304")

      assert has_element?(view, "a[href='/genus/Notholithocarpus']", "(genus-level)")
      assert has_element?(view, "a[href='/host/10']")
    end
  end

  describe "Range map" do
    test "shows the Hosts' range with its disclaimer", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "#gall-range-map")
      assert html =~ "Not an occurrence map"
      assert html =~ "has not been documented throughout this area"
    end

    test "a Gall with no Host range data has no map", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/gall/102")

      refute has_element?(view, "#gall-range-map")
      assert html =~ "Range unknown"
    end
  end

  describe "Sources" do
    test "the default citation and the Gallformers note link to their Source pages",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/gall/300")

      assert html =~ "Further Information (2)"
      assert has_element?(view, "a[href='/source/59']", "Cynipid galls of the seed slope")
      assert has_element?(view, "a[href='/source/58']", "Gallformers ID Notes")
      assert html =~ "seed citation"
      assert html =~ "Our ID Notes may contain important tips"
    end

    test "Show notes opens the Gallformers note", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      view |> element("button", "Show notes") |> render_click()

      assert has_element?(view, "#source-detail-modal")
      assert render(view) =~ "The seed note"
    end

    test "a Gall with none says so", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/302")

      assert html =~ "No further information available"
    end
  end

  describe "Source deep-linking via ?source= param" do
    setup do
      source =
        Gallformers.Repo.insert!(%Gallformers.Sources.Source{
          title: "Test Source for Deep Link",
          author: "Test Author",
          pubyear: "2024",
          link: "https://example.com",
          citation: "Test citation",
          license: "Public Domain"
        })

      {:ok, 1} =
        Catalog.insert_legacy_citations(DataCase.test_actor(), [
          %{
            gall_id: 100,
            source_id: source.id,
            description: "Deep link test description",
            useasdefault: false
          }
        ])

      %{source: source}
    end

    test "opens a legacy citation when ?source= matches", %{conn: conn, source: source} do
      {:ok, view, _html} = live(conn, "/gall/100?source=#{source.id}")

      assert has_element?(view, "#source-detail-modal")
      assert render(view) =~ "Deep link test description"
    end

    test "opens the Gallformers note when ?source= is its Source", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/gall/300?source=58")

      assert has_element?(view, "#source-detail-modal")
      assert render(view) =~ "The seed note"
    end

    test "ignores invalid source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/gall/100?source=invalid")

      refute has_element?(view, "#source-detail-modal")
    end

    test "ignores non-existent source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/gall/100?source=999999")

      refute has_element?(view, "#source-detail-modal")
    end

    test "page loads normally without source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/gall/100")

      refute has_element?(view, "#source-detail-modal")
    end
  end

  describe "Image display" do
    test "displays the Gall's image with its credit", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "#gall-images img[alt]")
      assert html =~ "Seed Photographer"
    end

    test "shows no gallery when the Gall has no images", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/301")

      refute has_element?(view, "#gall-images")
    end
  end
end
