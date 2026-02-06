defmodule GallformersWeb.API.HostControllerTest do
  @moduledoc """
  API tests for host endpoints.
  """
  use GallformersWeb.ConnCase

  alias Gallformers.{Plants, Species}

  describe "GET /api/v2/hosts" do
    test "returns list of hosts", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts")

      assert json_response(conn, 200)
      response = json_response(conn, 200)
      assert Map.has_key?(response, "data")
      assert Map.has_key?(response, "total")
      assert is_list(response["data"])
    end

    test "returns hosts with expected fields", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts?limit=5")

      response = json_response(conn, 200)

      if length(response["data"]) > 0 do
        host = hd(response["data"])
        assert Map.has_key?(host, "id")
        assert Map.has_key?(host, "name")
        assert Map.has_key?(host, "taxoncode")
      end
    end

    test "respects limit parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts?limit=3")

      response = json_response(conn, 200)
      assert length(response["data"]) <= 3
    end

    test "respects offset parameter", %{conn: conn} do
      conn1 = get(conn, ~p"/api/v2/hosts?limit=5&offset=0")
      conn2 = get(conn, ~p"/api/v2/hosts?limit=5&offset=5")

      response1 = json_response(conn1, 200)
      response2 = json_response(conn2, 200)

      if length(response1["data"]) > 0 and length(response2["data"]) > 0 do
        ids1 = Enum.map(response1["data"], & &1["id"])
        ids2 = Enum.map(response2["data"], & &1["id"])
        assert MapSet.disjoint?(MapSet.new(ids1), MapSet.new(ids2))
      end
    end

    test "search with q parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts?q=quercus")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "data")
      assert is_list(response["data"])
    end

    test "returns correct content type", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts")

      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    end
  end

  describe "GET /api/v2/hosts/:id" do
    test "returns host details for valid ID", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)
        conn = get(conn, ~p"/api/v2/hosts/#{host.id}")

        response = json_response(conn, 200)
        assert response["id"] == host.id
        assert response["name"] == host.name
      end
    end

    test "returns 404 for non-existent ID", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts/999999999")

      assert json_response(conn, 404)
      response = json_response(conn, 404)
      assert Map.has_key?(response, "error")
    end

    test "returns 400 for invalid ID format", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts/invalid")

      assert json_response(conn, 400)
      response = json_response(conn, 400)
      assert Map.has_key?(response, "error")
    end

    test "returns host with gall count", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)
        conn = get(conn, ~p"/api/v2/hosts/#{host.id}")

        response = json_response(conn, 200)
        # Should include galls or gall_count
        assert Map.has_key?(response, "galls") or Map.has_key?(response, "gall_count")
      end
    end
  end

  describe "GET /api/v2/hosts/:id/images" do
    test "returns images for host", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)
        conn = get(conn, ~p"/api/v2/hosts/#{host.id}/images")

        response = json_response(conn, 200)
        assert is_list(response)
      end
    end

    test "images have expected fields", %{conn: conn} do
      hosts = Plants.list_hosts()

      host_with_images =
        Enum.find(hosts, fn h ->
          length(Species.get_images_for_species(h.id)) > 0
        end)

      if host_with_images do
        conn = get(conn, ~p"/api/v2/hosts/#{host_with_images.id}/images")

        response = json_response(conn, 200)
        image = hd(response)
        assert Map.has_key?(image, "id")
        assert Map.has_key?(image, "path")
        assert Map.has_key?(image, "url")
      end
    end

    test "returns 400 for invalid ID", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts/invalid/images")

      assert json_response(conn, 400)
    end

    test "returns 404 for non-existent host", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts/999999999/images")

      assert json_response(conn, 404)
    end
  end

  describe "GET /api/v2/hosts/:id/galls" do
    test "returns galls for host", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)
        conn = get(conn, ~p"/api/v2/hosts/#{host.id}/galls")

        response = json_response(conn, 200)
        assert is_list(response)
      end
    end

    test "galls have expected fields", %{conn: conn} do
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)
        conn = get(conn, ~p"/api/v2/hosts/#{host.id}/galls")

        response = json_response(conn, 200)

        if length(response) > 0 do
          gall = hd(response)
          assert Map.has_key?(gall, "id")
          assert Map.has_key?(gall, "name")
          assert Map.has_key?(gall, "undescribed")
          assert Map.has_key?(gall, "datacomplete")
        end
      end
    end

    test "returns 400 for invalid ID", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts/invalid/galls")

      assert json_response(conn, 400)
    end

    test "returns 404 for non-existent host", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/hosts/999999999/galls")

      assert json_response(conn, 404)
    end
  end
end
