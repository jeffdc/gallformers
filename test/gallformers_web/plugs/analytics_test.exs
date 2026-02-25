defmodule GallformersWeb.Plugs.AnalyticsTest do
  @moduledoc """
  Tests for the Analytics plug.
  """
  use GallformersWeb.ConnCase

  describe "Analytics plug" do
    test "stores analytics data in session for LiveView use", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", "Mozilla/5.0 (iPhone) Safari/604.1")
        |> put_req_header("fly-client-ip", "192.168.1.1")
        |> get("/")

      # Should have analytics data in session
      assert get_session(conn, :analytics_browser) == "Safari (iOS)"
      assert get_session(conn, :analytics_device_type) == "mobile"
      assert get_session(conn, :analytics_visitor_hash) != nil
      assert is_binary(get_session(conn, :analytics_visitor_hash))

      # Should store IP, UA, and hash date for LiveView hash regeneration
      assert get_session(conn, :analytics_ip) == "192.168.1.1"
      assert get_session(conn, :analytics_user_agent) == "Mozilla/5.0 (iPhone) Safari/604.1"
      assert get_session(conn, :analytics_hash_date) == Date.utc_today() |> Date.to_iso8601()
    end

    test "stores nil browser when user agent is nil", %{conn: conn} do
      conn =
        conn
        |> put_req_header("fly-client-ip", "192.168.1.1")
        |> get("/")

      # Should store nil for browser/device when UA is missing
      assert get_session(conn, :analytics_browser) == nil
      assert get_session(conn, :analytics_device_type) == nil
      assert get_session(conn, :analytics_visitor_hash) != nil
    end

    test "stores analytics data even for paths that won't be tracked", %{conn: conn} do
      # Even excluded paths get analytics data in session (for subsequent LiveView navs)
      # The tracking decision is made when track_page_view is called, not in the plug
      conn =
        conn
        |> put_req_header("user-agent", "Mozilla/5.0 Chrome/120.0")
        |> put_req_header("fly-client-ip", "192.168.1.1")
        |> get("/")

      # Session data should be present
      assert get_session(conn, :analytics_browser) == "Chrome"
      assert get_session(conn, :analytics_visitor_hash) != nil
    end
  end
end
