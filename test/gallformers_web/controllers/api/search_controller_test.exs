defmodule GallformersWeb.API.SearchControllerTest do
  @moduledoc """
  API tests for search endpoint. Galls, hosts and taxa come from the new
  back-end (`803b` Task 11) in the response shape the endpoint always had;
  taxon IDs are the new taxon IDs.
  """
  use GallformersWeb.ConnCase

  import OpenApiSpex.TestAssertions

  defp search(conn, query) do
    conn = get(conn, ~p"/api/v2/search?#{%{q: query}}")
    assert_operation_response(conn, "GallformersWeb.API.SearchController.search")
    json_response(conn, 200)
  end

  describe "GET /api/v2/search response shapes" do
    test "a gall keeps its fields", %{conn: conn} do
      gall =
        conn
        |> search("Andricus quercuscalifornicus")
        |> Map.fetch!("galls")
        |> Enum.find(&(&1["id"] == 100))

      assert Map.keys(gall) |> Enum.sort() ==
               ~w(aliases id match_score name type undescribed)

      assert %{"name" => "Andricus quercuscalifornicus", "type" => "gall"} = gall
      assert "Oak Apple Gall Wasp" in gall["aliases"]
    end

    test "a host keeps its fields; a synonym finds it", %{conn: conn} do
      assert [host] = search(conn, "Lithocarpus")["hosts"]

      assert Map.keys(host) |> Enum.sort() ==
               ~w(aliases genus_placeholder id match_score name type)

      assert %{
               "id" => 10,
               "name" => "Notholithocarpus densiflorus",
               "type" => "host",
               "genus_placeholder" => false,
               "aliases" => ["Lithocarpus densiflorus", "tanoak"]
             } = host
    end

    test "a taxon keeps its fields, with the new taxon ID", %{conn: conn} do
      tribe = search(conn, "Cynipini")["taxonomy"] |> Enum.find(&(&1["name"] == "Cynipini"))

      assert Map.keys(tribe) |> Enum.sort() ==
               ~w(description id match_score name parent_name parent_rank parent_type rank type)

      assert %{
               "type" => "intermediate",
               "rank" => "Tribe",
               "parent_name" => "Cynipinae",
               "parent_type" => "intermediate",
               "parent_rank" => "Subfamily"
             } = tribe

      assert tribe["id"] == hd(Gallformers.Taxa.get_by_name("Cynipini", :tribe)).id
    end
  end

  describe "GET /api/v2/search" do
    test "returns search results with all categories", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/search?q=oak")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "galls") == true
      assert Map.has_key?(response, "hosts") == true
      assert Map.has_key?(response, "glossary") == true
      assert Map.has_key?(response, "sources") == true
      assert Map.has_key?(response, "taxonomy") == true
      assert Map.has_key?(response, "places") == true
    end

    test "returns empty results for empty query", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/search?q=")

      response = json_response(conn, 200)
      assert response["galls"] == []
      assert response["hosts"] == []
      assert response["glossary"] == []
      assert response["sources"] == []
    end

    test "returns empty results without query parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/search")

      response = json_response(conn, 200)
      assert response["galls"] == []
      assert response["hosts"] == []
    end

    test "returns matching galls", %{conn: conn} do
      # Search for a term likely to match galls
      conn = get(conn, ~p"/api/v2/search?q=andricus")

      response = json_response(conn, 200)
      assert is_list(response["galls"])
    end

    test "returns matching hosts", %{conn: conn} do
      # Search for a term likely to match hosts
      conn = get(conn, ~p"/api/v2/search?q=quercus")

      response = json_response(conn, 200)
      assert is_list(response["hosts"])
    end

    test "gall results have type field", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/search?q=oak")

      response = json_response(conn, 200)

      if length(response["galls"]) > 0 do
        gall = hd(response["galls"])
        assert gall["type"] == "gall"
      end
    end

    test "host results have type field", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/search?q=oak")

      response = json_response(conn, 200)

      if length(response["hosts"]) > 0 do
        host = hd(response["hosts"])
        assert host["type"] == "host"
      end
    end

    test "search is case-insensitive", %{conn: conn} do
      conn_lower = get(conn, ~p"/api/v2/search?q=oak")
      conn_upper = get(conn, ~p"/api/v2/search?q=OAK")

      response_lower = json_response(conn_lower, 200)
      response_upper = json_response(conn_upper, 200)

      # Should return same results (or at least same count)
      assert length(response_lower["hosts"]) == length(response_upper["hosts"])
    end

    test "returns correct content type", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/search?q=test")

      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    end

    test "handles special characters in query", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/search?q=test%20query")

      # Should not error
      assert conn.status == 200
      assert is_map(json_response(conn, 200))
    end
  end
end
