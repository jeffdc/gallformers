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

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_actor: 0]

  alias Gallformers.Taxa

  describe "Host page rendering" do
    test "renders the host's accepted name as its title", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/host/10")

      assert html =~ "Notholithocarpus densiflorus"
      assert page_title(view) =~ "Notholithocarpus densiflorus"
    end

    test "shows the host's taxonomy as a breadcrumb", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/host/10")

      assert has_element?(view, "a[href='/family/Fagaceae']")
      assert has_element?(view, "a[href='/genus/Notholithocarpus']")
    end

    test "shows its common names and synonyms", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/host/10")

      assert html =~ "Common Name(s):"
      assert html =~ "tanoak"
      assert html =~ "Synonymy (1)"
      assert html =~ "Lithocarpus densiflorus"
    end

    test "lists the Galls on the host by name", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/host/10")

      assert html =~ "Associated Galls (5)"

      for id <- 300..304 do
        assert has_element?(view, "a[href='/gall/#{id}']")
      end

      undescribed = :binary.match(html, "Andricus n-densiflorus-seed-gall") |> elem(0)
      agamic = :binary.match(html, "Neuroterus seedatorius (australis) (agamic)") |> elem(0)
      assert undescribed < agamic
    end

    test "shows the host's image and range map with the introduced range", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/host/10")

      assert has_element?(view, "#host-images img[alt]")
      assert html =~ "Seed Photographer"
      assert has_element?(view, "#host-range-map")
      assert html =~ "Introduced range"
    end

    test "shows the data-complete badge and the abundance", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/host/10")

      assert html =~ "All galls known to occur on this plant have been added"
      assert html =~ "<strong>Abundance:</strong> common"
    end

    test "an incomplete host without an abundance shows no Abundance line", %{conn: conn} do
      plant = plant_fixture()
      {:ok, _view, html} = live(conn, ~p"/host/#{plant.id}")

      assert html =~ "In Progress"
      assert html =~ "We are still working on this species"
      refute html =~ "Abundance:"
    end

    test "has no Sources block", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/host/10")

      refute html =~ "Further Information"
      refute html =~ "No further information available"
    end

    test "a host with no Galls says so", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/host/1")

      assert html =~ "Quercus alba"
      assert html =~ "No galls recorded for this host."
    end
  end

  describe "Not found" do
    test "shows error for invalid ID format", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/host/invalid")

      assert html =~ "Invalid host ID"
    end

    test "for a missing ID, a Gall and a higher plant taxon", %{conn: conn} do
      genus = Taxa.get_by_legacy_id(:taxonomy, 41)

      for id <- [999_999_999, 300, genus.id] do
        {:ok, view, html} = live(conn, ~p"/host/#{id}")

        assert html =~ "Host not found", "host #{id}"
        assert page_title(view) =~ "Not Found"
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

    test "a plant's own page is not redirected", %{conn: conn} do
      conn = get(conn, "/host/1")

      assert html_response(conn, 200) =~ "Quercus alba"
    end
  end
end
