defmodule GallformersWeb.Plugs.ApiCacheTest do
  @moduledoc """
  Tests for the API cache plug (ETag + Cache-Control headers).
  """
  use GallformersWeb.ConnCase

  describe "Cache-Control headers" do
    test "sets Cache-Control on successful responses", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/stats")

      assert [cache_control] = get_resp_header(conn, "cache-control")
      assert cache_control =~ "public"
      assert cache_control =~ "max-age=3600"
    end

    test "sets ETag on successful responses", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/stats")

      assert [etag] = get_resp_header(conn, "etag")
      assert etag =~ ~r/^"[a-f0-9]{32}"$/
    end

    test "sets no-store on error responses", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls/invalid")

      assert [cache_control] = get_resp_header(conn, "cache-control")
      assert cache_control == "no-store"
    end

    test "returns consistent ETag for same content", %{conn: conn} do
      conn1 = get(conn, ~p"/api/v2/stats")
      conn2 = get(conn, ~p"/api/v2/stats")

      [etag1] = get_resp_header(conn1, "etag")
      [etag2] = get_resp_header(conn2, "etag")
      assert etag1 == etag2
    end
  end

  describe "If-None-Match" do
    test "returns 304 when ETag matches", %{conn: conn} do
      # First request to get the ETag
      conn1 = get(conn, ~p"/api/v2/stats")
      [etag] = get_resp_header(conn1, "etag")

      # Second request with If-None-Match
      conn2 =
        conn
        |> put_req_header("if-none-match", etag)
        |> get(~p"/api/v2/stats")

      assert conn2.status == 304
    end

    test "returns 200 when ETag does not match", %{conn: conn} do
      conn =
        conn
        |> put_req_header("if-none-match", ~s("stale-etag"))
        |> get(~p"/api/v2/stats")

      assert conn.status == 200
    end
  end
end
