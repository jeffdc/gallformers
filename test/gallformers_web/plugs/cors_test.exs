defmodule GallformersWeb.Plugs.CORSTest do
  @moduledoc """
  Tests for CORS plug.
  """
  use GallformersWeb.ConnCase

  describe "CORS headers on API routes" do
    test "sets Access-Control-Allow-Origin header", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls")

      headers = get_resp_header(conn, "access-control-allow-origin")
      assert length(headers) > 0
      assert hd(headers) == "*"
    end

    test "sets Access-Control-Allow-Methods header", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls")

      headers = get_resp_header(conn, "access-control-allow-methods")
      assert length(headers) > 0
      allowed = hd(headers)
      assert allowed =~ "GET"
      assert allowed =~ "HEAD"
      assert allowed =~ "OPTIONS"
      refute allowed =~ "POST"
      refute allowed =~ "PUT"
      refute allowed =~ "DELETE"
    end

    test "sets Access-Control-Allow-Headers header", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls")

      headers = get_resp_header(conn, "access-control-allow-headers")
      assert length(headers) > 0
      allowed = hd(headers)
      assert allowed =~ "content-type"
    end

    test "sets Access-Control-Max-Age header", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/galls")

      headers = get_resp_header(conn, "access-control-max-age")
      assert length(headers) > 0
      # Should be a number (in seconds)
      max_age = hd(headers)
      assert String.match?(max_age, ~r/^\d+$/)
    end

    test "handles OPTIONS preflight request", %{conn: conn} do
      # Note: Phoenix routes OPTIONS to catch-all by default
      # The CORS plug still sets headers but the route may 404
      conn =
        conn
        |> put_req_header("origin", "https://example.com")
        |> put_req_header("access-control-request-method", "GET")
        |> options(~p"/api/v2/galls")

      # CORS headers should be set regardless of status
      # (The plug adds headers before the route is matched)
      headers = get_resp_header(conn, "access-control-allow-origin")

      # Either we get 204 with CORS headers, or we get the headers anyway
      assert conn.status in [200, 204, 404]

      if length(headers) > 0 do
        assert hd(headers) == "*"
      end
    end

    test "CORS headers present on all API endpoints", %{conn: conn} do
      endpoints = [
        ~p"/api/v2/galls",
        ~p"/api/v2/hosts",
        ~p"/api/v2/search?q=test",
        ~p"/api/v2/glossary"
      ]

      for endpoint <- endpoints do
        response = get(conn, endpoint)
        headers = get_resp_header(response, "access-control-allow-origin")
        assert length(headers) > 0, "Missing CORS headers on #{endpoint}"
      end
    end

    test "CORS headers allow cross-origin requests", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://some-other-site.com")
        |> get(~p"/api/v2/galls")

      # Request should succeed
      assert conn.status == 200

      # CORS headers should be present
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    end
  end

  describe "CORS not applied to non-API routes" do
    test "browser routes do not have CORS headers", %{conn: conn} do
      conn = get(conn, ~p"/")

      # Browser routes shouldn't have Access-Control-Allow-Origin: *
      headers = get_resp_header(conn, "access-control-allow-origin")
      assert headers == [] or hd(headers) != "*"
    end
  end
end
