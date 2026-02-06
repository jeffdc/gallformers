defmodule GallformersWeb.API.TaxonomyControllerTest do
  @moduledoc """
  API tests for taxonomy endpoints.
  """
  use GallformersWeb.ConnCase

  describe "GET /api/v2/genera" do
    test "returns paginated list of genera", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/genera")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "data")
      assert Map.has_key?(response, "total")
      assert is_list(response["data"])
    end

    test "genera have expected fields", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/genera?limit=5")

      response = json_response(conn, 200)

      if length(response["data"]) > 0 do
        genus = hd(response["data"])
        assert Map.has_key?(genus, "id")
        assert Map.has_key?(genus, "name")
        assert Map.has_key?(genus, "type")
        assert genus["type"] == "genus"
      end
    end

    test "respects limit parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/genera?limit=3")

      response = json_response(conn, 200)
      assert length(response["data"]) <= 3
    end

    test "respects offset parameter", %{conn: conn} do
      conn1 = get(conn, ~p"/api/v2/genera?limit=5&offset=0")
      conn2 = get(conn, ~p"/api/v2/genera?limit=5&offset=5")

      response1 = json_response(conn1, 200)
      response2 = json_response(conn2, 200)

      if length(response1["data"]) > 0 and length(response2["data"]) > 0 do
        ids1 = Enum.map(response1["data"], & &1["id"])
        ids2 = Enum.map(response2["data"], & &1["id"])
        assert MapSet.disjoint?(MapSet.new(ids1), MapSet.new(ids2))
      end
    end

    test "search with q parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/genera?q=Quer")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "data")
      assert is_list(response["data"])
    end

    test "only returns genus type entries", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/genera")

      response = json_response(conn, 200)

      Enum.each(response["data"], fn entry ->
        assert entry["type"] == "genus"
      end)
    end
  end

  describe "GET /api/v2/families" do
    test "returns list of families", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/families")

      response = json_response(conn, 200)
      assert is_list(response)
    end
  end
end
