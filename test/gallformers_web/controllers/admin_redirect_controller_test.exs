defmodule GallformersWeb.AdminRedirectControllerTest do
  @moduledoc """
  The URLs of the deleted old-domain admin screens (matter a856, Task 11):
  those with a sensible new screen redirect to it; the rest are not found.
  """
  use GallformersWeb.ConnCase, async: true

  alias Gallformers.CatalogFixtures
  alias GallformersWeb.AdminLiveHelpers

  setup %{conn: conn} do
    {conn, _user} = AdminLiveHelpers.log_in_admin(conn)
    %{conn: conn}
  end

  defp assert_moved(conn, path, to) do
    conn = get(conn, path)
    assert conn.status == 301, "#{path} answered #{conn.status}"
    assert redirected_to(conn, 301) == to
  end

  describe "the Host and Section screens" do
    test "go to the taxonomy admin (plant IDs are taxon IDs)", %{conn: conn} do
      assert_moved(conn, "/admin/hosts", "/admin/taxonomy")
      assert_moved(conn, "/admin/hosts/new", "/admin/taxonomy/new")
      assert_moved(conn, "/admin/hosts/10", "/admin/taxonomy/10")
      assert_moved(conn, "/admin/section", "/admin/taxonomy")
      assert_moved(conn, "/admin/section/new", "/admin/taxonomy")
      assert_moved(conn, "/admin/section/42", "/admin/taxonomy")
    end
  end

  describe "the Species–Source screens" do
    test "go to the Source editor", %{conn: conn} do
      assert_moved(conn, "/admin/species-sources/add", "/admin/sources")
      assert_moved(conn, "/admin/species-sources/find", "/admin/sources")
    end
  end

  describe "the gall–host screen" do
    test "goes to the Gall page of its Gall", %{conn: conn} do
      assert_moved(conn, "/admin/gallhost?id=300", "/admin/galls/300")
    end

    test "with no Gall, goes to the Gall search", %{conn: conn} do
      assert_moved(conn, "/admin/gallhost", "/admin/galls")
      assert_moved(conn, "/admin/gallhost?id=abc", "/admin/galls")
    end
  end

  describe "the image admin" do
    test "goes to the images of the Gall page for a Gall", %{conn: conn} do
      gall = CatalogFixtures.gall_fixture()
      assert_moved(conn, "/admin/images?species_id=#{gall.id}", "/admin/galls/#{gall.id}#images")
    end

    test "goes to the images of the taxon page for a taxon", %{conn: conn} do
      plant = CatalogFixtures.plant_fixture()

      assert_moved(
        conn,
        "/admin/images?species_id=#{plant.id}",
        "/admin/taxonomy/#{plant.id}#images"
      )
    end

    test "is not found for no or an unknown species", %{conn: conn} do
      assert conn |> get("/admin/images") |> response(404)
      assert conn |> get("/admin/images?species_id=999999999") |> response(404)
      assert conn |> get("/admin/images?species_id=abc") |> response(404)
    end
  end

  describe "the other old screens" do
    test "are not found", %{conn: conn} do
      for path <- ~w(/admin/gall-range /admin/image-audit /admin/filter-terms
                     /admin/filter-terms/new /admin/filter-terms/1 /admin/reclassify) do
        assert conn |> get(path) |> response(404), "#{path} was found"
      end
    end
  end

  describe "who is redirected" do
    test "an anonymous visitor is sent to log in first" do
      conn = get(build_conn(), "/admin/hosts")
      assert redirected_to(conn) == "/auth/auth0"
    end
  end
end
