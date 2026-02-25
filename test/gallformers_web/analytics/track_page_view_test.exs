defmodule GallformersWeb.Analytics.TrackPageViewTest do
  @moduledoc """
  Tests for the TrackPageView on_mount hook.
  """
  use GallformersWeb.ConnCase

  alias GallformersWeb.Analytics.TrackPageView

  describe "on_mount/4" do
    test "assigns analytics data from session to socket", %{conn: conn} do
      # Simulate session data set by Analytics plug
      conn =
        conn
        |> init_test_session(%{
          analytics_browser: "Firefox",
          analytics_device_type: "desktop",
          analytics_visitor_hash: "test123456789abc",
          analytics_ip: "192.168.1.1",
          analytics_user_agent: "Mozilla/5.0 Firefox",
          analytics_hash_date: Date.utc_today() |> Date.to_iso8601()
        })

      {:cont, socket} =
        TrackPageView.on_mount(:default, %{}, get_session(conn), %Phoenix.LiveView.Socket{})

      assert socket.assigns.analytics_browser == "Firefox"
      assert socket.assigns.analytics_device_type == "desktop"
      assert socket.assigns.analytics_visitor_hash == "test123456789abc"
      assert socket.assigns.analytics_ip == "192.168.1.1"
      assert socket.assigns.analytics_user_agent == "Mozilla/5.0 Firefox"
      assert socket.assigns.analytics_hash_date == Date.utc_today() |> Date.to_iso8601()
    end

    test "assigns nil when session data is missing", %{conn: conn} do
      conn = conn |> init_test_session(%{})

      {:cont, socket} =
        TrackPageView.on_mount(:default, %{}, get_session(conn), %Phoenix.LiveView.Socket{})

      assert socket.assigns.analytics_browser == nil
      assert socket.assigns.analytics_device_type == nil
      assert socket.assigns.analytics_visitor_hash == nil
      assert socket.assigns.analytics_ip == nil
      assert socket.assigns.analytics_user_agent == nil
      assert socket.assigns.analytics_hash_date == nil
    end
  end
end
