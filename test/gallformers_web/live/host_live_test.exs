defmodule GallformersWeb.HostLiveTest do
  @moduledoc """
  LiveView tests for the Host page, which reads `Gallformers.Taxa.host_page/1`
  and `Gallformers.Catalog.list_galls_for_hosts/1`.

  Uses the converted seeds (`priv/repo/test_seeds.sql`): plant 10
  Notholithocarpus densiflorus (genus Notholithocarpus, family Fagaceae) is
  the Host of Galls 300–304, with a common name, a synonym, an image and a
  native (US-CA) and introduced (RO-B) range; it is data-complete and
  common. Plant 11 was a genus
  placeholder ("Notholithocarpus spp"), which is no taxon now: its URL
  redirects to the genus page.
  """
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest

  # The page's visible text: a name's italic and upright parts are separate
  # elements, so assert on text rather than raw HTML.
  defp page_text(html), do: html |> LazyHTML.from_document() |> LazyHTML.text()

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_actor: 0]

  alias Gallformers.Taxa

  describe "Host page rendering" do
    test "renders the host's accepted name as its title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/host/10")

      assert has_element?(view, "h1", "Notholithocarpus densiflorus")
      assert page_title(view) =~ "Notholithocarpus densiflorus"
    end

    test "shows the host's taxonomy as a breadcrumb", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/host/10")

      assert has_element?(view, "a[href='/family/Fagaceae']")
      assert has_element?(view, "a[href='/genus/Notholithocarpus']")
    end

    test "shows its common names and synonyms", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/host/10")

      assert has_element?(view, "header dd", "tanoak")
      assert has_element?(view, "#host-names", "Lithocarpus densiflorus")
    end

    test "lists the Galls on the host by name", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/host/10")

      assert has_element?(view, "#host-galls-section [data-part=count]", "5")

      for id <- 300..304 do
        assert has_element?(view, "a[href='/gall/#{id}']")
      end

      text = page_text(html)
      undescribed = :binary.match(text, "Andricus n-densiflorus-seed-gall") |> elem(0)
      agamic = :binary.match(text, "Neuroterus seedatorius (australis) (agamic)") |> elem(0)
      assert undescribed < agamic
    end

    test "the Galls are photos only: no table view", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/host/10")

      assert has_element?(view, "#host-galls-section .gf-photo-grid")
      refute has_element?(view, "[phx-click=galls_view]")
    end

    test "shows the host's image and range map with the introduced range", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/host/10")

      assert has_element?(view, "#host-images img[alt]")
      assert html =~ "Seed Photographer"
      assert has_element?(view, "#host-range-map")
      assert html =~ "Introduced range"
    end

    test "shows the data-complete badge and the abundance", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/host/10")

      assert html =~ "All galls known to occur on this plant have been added"
      assert has_element?(view, "header", ~r/Abundance\s*common/)
    end

    test "an incomplete host without an abundance shows no Abundance line", %{conn: conn} do
      plant = plant_fixture()
      {:ok, _view, html} = live(conn, ~p"/host/#{plant.id}")

      assert html =~ "In progress"
      assert html =~ "We are still working on this plant"
      refute html =~ "Abundance:"
    end

    test "shows the name's authority upright after the italic name, a synonym's too",
         %{conn: conn} do
      plant = plant_fixture(name: "Quercus auctoria", authorship: "(L.) Sm.")
      {:ok, _} = Taxa.add_synonym(test_actor(), plant, "Quercus veteria", authorship: "Mill.")

      {:ok, view, _html} = live(conn, ~p"/host/#{plant.id}")

      assert has_element?(view, "h1 .taxon-name", "Quercus auctoria")
      assert has_element?(view, "h1 [data-part=authorship]:not(.taxon-name)", "(L.) Sm.")
      assert page_title(view) =~ "Quercus auctoria"
      refute page_title(view) =~ "Sm."

      assert has_element?(view, "#host-names .taxon-name", "Quercus veteria")
      assert has_element?(view, "#host-names [data-part=authorship]", "Mill.")
    end

    test "a name with no authority shows none", %{conn: conn} do
      plant = plant_fixture(name: "Quercus sineauctoria")
      {:ok, view, _html} = live(conn, ~p"/host/#{plant.id}")

      refute has_element?(view, "h1 [data-part=authorship]")
    end

    test "has no Sources block", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/host/10")

      refute html =~ "Further Information"
      refute html =~ "No further information available"
    end

    test "a host with no Galls says so", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/host/1")

      assert html =~ "Quercus alba"
      assert html =~ "No galls recorded on this plant yet."
    end
  end

  describe "the design system's Host page" do
    test "offers to identify a gall on the plant", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/host/10")

      assert has_element?(
               view,
               ~s{a[href="/id?h=Notholithocarpus+densiflorus"]},
               "Identify a gall on Notholithocarpus densiflorus"
             )
    end

    test "points to the Galls recorded on its genus as a whole", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/host/10")

      # Gall 304's Host is the genus Notholithocarpus itself.
      assert has_element?(view, "#on-genus a[href='/genus/Notholithocarpus']")
      assert has_element?(view, "#on-genus", "recorded on")
    end

    test "Enlarge opens the large range map", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/host/10")

      view |> element("button", "Enlarge") |> render_click()
      assert has_element?(view, "#range-dialog #host-range-map-large")
    end
  end

  describe "admin links" do
    test "an admin's Gall and image links go to the new admin screens", %{conn: conn} do
      {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
      {:ok, view, _html} = live(admin_conn, ~p"/host/10")

      for id <- 300..304 do
        # A Gall's range exclusions are edited in Edit mode on its page.
        assert has_element?(view, "a[href='/gall/#{id}?edit']")
      end

      assert has_element?(view, "#host-images a[href='/admin/taxonomy/10#images']")
      refute has_element?(view, "a[href^='/admin/gallhost']")
      refute has_element?(view, "a[href^='/admin/images']")
    end

    test "a visitor gets none", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/host/10")

      refute has_element?(view, "a[href^='/admin']")
    end
  end

  describe "Not found" do
    test "an ID that isn't a number is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/host/invalid") end
    end

    test "a missing ID, a Gall and a higher plant taxon are 404s", %{conn: conn} do
      genus = Taxa.get_by_legacy_id(:taxonomy, 41)

      for id <- [999_999_999, 300, genus.id] do
        assert_error_sent 404, fn -> get(conn, ~p"/host/#{id}") end
      end
    end
  end

  describe "old genus placeholder URLs" do
    # A placeholder ("Quercus spp", the seeds' plant 11) became no taxon; the
    # data migration maps its species ID to its genus. An ID of its own here,
    # so the test does not depend on how recently the seeds were converted.
    test "redirect (301) to the genus page", %{conn: conn} do
      genus = plant_fixture(rank: :genus, name: "Fixturplaceholdera")
      {:ok, _} = Taxa.add_legacy_id(test_actor(), genus, :genus_placeholder, 990_011, "spp")

      conn = get(conn, "/host/990011")

      assert redirected_to(conn, 301) == "/genus/Fixturplaceholdera"
    end

    test "a merged plant's old ID redirects (301) to the plant it became", %{conn: conn} do
      survivor = plant_fixture(name: "Fixturquercus mergedi")
      {:ok, _} = Taxa.add_taxon_redirect(test_actor(), 990_012, survivor.id)

      assert redirected_to(get(conn, "/host/990012"), 301) == "/host/#{survivor.id}"
    end

    test "live navigation to a merged plant's old ID goes to the plant it became", %{conn: conn} do
      survivor = plant_fixture(name: "Fixturquercus mergedii")
      {:ok, _} = Taxa.add_taxon_redirect(test_actor(), 990_013, survivor.id)

      {:ok, view, _html} = live(conn, ~p"/host/1")
      to = "/host/#{survivor.id}"
      assert {:error, {:live_redirect, %{to: ^to}}} = live_redirect(view, to: "/host/990013")
    end

    test "a plant's own page is not redirected", %{conn: conn} do
      conn = get(conn, "/host/1")

      assert html_response(conn, 200) =~ "Quercus alba"
    end
  end
end
