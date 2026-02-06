defmodule GallformersWeb.API.GallControllerTest do
  @moduledoc """
  API tests for gall endpoints.
  """
  use GallformersWeb.ConnCase

  alias Gallformers.Galls
  alias Gallformers.Species

  describe "GET /api/v2/galls" do
    test "returns list of galls", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls")

      assert json_response(conn, 200)
      response = json_response(conn, 200)
      assert Map.has_key?(response, "data")
      assert Map.has_key?(response, "total")
      assert is_list(response["data"])
    end

    test "returns galls with expected fields", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls?limit=5")

      response = json_response(conn, 200)

      if length(response["data"]) > 0 do
        gall = hd(response["data"])
        assert Map.has_key?(gall, "id")
        assert Map.has_key?(gall, "name")
      end
    end

    test "respects limit parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls?limit=3")

      response = json_response(conn, 200)
      assert length(response["data"]) <= 3
    end

    test "respects offset parameter", %{conn: conn} do
      conn1 = get(conn, ~p"/api/v2/galls?limit=5&offset=0")
      conn2 = get(conn, ~p"/api/v2/galls?limit=5&offset=5")

      response1 = json_response(conn1, 200)
      response2 = json_response(conn2, 200)

      # Results should be different (unless not enough data)
      if length(response1["data"]) > 0 and length(response2["data"]) > 0 do
        ids1 = Enum.map(response1["data"], & &1["id"])
        ids2 = Enum.map(response2["data"], & &1["id"])
        # Should have no overlap
        assert MapSet.disjoint?(MapSet.new(ids1), MapSet.new(ids2))
      end
    end

    test "search with q parameter", %{conn: conn} do
      # Search for a common term
      conn = get(conn, ~p"/api/v2/galls?q=oak")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "data")
      assert is_list(response["data"])
    end

    test "returns correct content type", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls")

      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    end
  end

  describe "GET /api/v2/galls/:id" do
    test "returns gall details for valid ID", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        conn = get(conn, ~p"/api/v2/galls/#{gall.id}")

        response = json_response(conn, 200)
        assert response["id"] == gall.id
        assert response["name"] == gall.name
      end
    end

    test "returns full gall details with related data", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        conn = get(conn, ~p"/api/v2/galls/#{gall.id}")

        response = json_response(conn, 200)
        # Should have filter fields
        assert Map.has_key?(response, "colors")
        assert Map.has_key?(response, "shapes")
        assert Map.has_key?(response, "textures")
        assert Map.has_key?(response, "hosts")
      end
    end

    test "returns 404 for non-existent ID", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls/999999999")

      assert json_response(conn, 404)
      response = json_response(conn, 404)
      assert Map.has_key?(response, "error")
    end

    test "returns 400 for invalid ID format", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls/invalid")

      assert json_response(conn, 400)
      response = json_response(conn, 400)
      assert Map.has_key?(response, "error")
    end
  end

  describe "GET /api/v2/galls/:id/images" do
    test "returns images for gall", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        conn = get(conn, ~p"/api/v2/galls/#{gall.id}/images")

        response = json_response(conn, 200)
        assert is_list(response)
      end
    end

    test "images have expected fields", %{conn: conn} do
      galls = Galls.list_galls()

      # Find a gall with images
      gall_with_images =
        Enum.find(galls, fn g ->
          length(Species.get_images_for_species(g.id)) > 0
        end)

      if gall_with_images do
        conn = get(conn, ~p"/api/v2/galls/#{gall_with_images.id}/images")

        response = json_response(conn, 200)
        image = hd(response)
        assert Map.has_key?(image, "id")
        assert Map.has_key?(image, "path")
        assert Map.has_key?(image, "url")
      end
    end

    test "returns 400 for invalid ID", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls/invalid/images")

      assert json_response(conn, 400)
    end
  end

  describe "GET /api/v2/galls/:id/sources" do
    test "returns sources for gall", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        conn = get(conn, ~p"/api/v2/galls/#{gall.id}/sources")

        response = json_response(conn, 200)
        assert is_list(response)
      end
    end

    test "sources have expected fields", %{conn: conn} do
      galls = Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)
        conn = get(conn, ~p"/api/v2/galls/#{gall.id}/sources")

        response = json_response(conn, 200)

        if length(response) > 0 do
          source = hd(response)
          assert Map.has_key?(source, "id")
          assert Map.has_key?(source, "title")
        end
      end
    end

    test "returns 400 for invalid ID", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls/invalid/sources")

      assert json_response(conn, 400)
    end

    test "returns 404 for non-existent gall", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls/999999999/sources")

      assert json_response(conn, 404)
    end
  end
end
