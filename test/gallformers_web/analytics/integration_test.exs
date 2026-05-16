defmodule GallformersWeb.Analytics.IntegrationTest do
  @moduledoc """
  End-to-end tests for analytics page-view tracking across realistic request
  flows: initial GET, in-page push_patch, live_redirect between LiveViews, and
  404s on unrouted paths.

  These tests cover the boundary between the HTTP request path (Analytics plug)
  and the LiveView WebSocket lifecycle (TrackPageView on_mount hook), which the
  existing unit tests do not exercise together.
  """
  use GallformersWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Gallformers.Analytics.PageView
  alias Gallformers.Repo

  defp tracked_paths do
    Repo.all(from pv in PageView, order_by: pv.id, select: pv.path)
  end

  defp browser_conn do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("user-agent", "Mozilla/5.0 Firefox/120")
    |> Plug.Conn.put_req_header("fly-client-ip", "192.168.1.1")
  end

  describe "live_redirect between LiveViews" do
    test "records a page view when <.link navigate> moves to another LV" do
      conn = browser_conn()

      {:ok, view, _html} = live(conn, "/")

      assert tracked_paths() == ["/"],
             "initial GET should be tracked once by the Analytics plug"

      {:ok, _view, _html} = live_redirect(view, to: "/galls")

      assert tracked_paths() == ["/", "/galls"],
             "live_redirect to /galls should record a page view, but the hook skipped it"
    end
  end

  describe "push_patch within a LiveView" do
    test "does not record a duplicate page view when the path is unchanged" do
      conn = browser_conn()

      {:ok, view, _html} = live(conn, "/glossary")
      assert tracked_paths() == ["/glossary"]

      render_patch(view, "/glossary?term=gall")

      assert tracked_paths() == ["/glossary"],
             "push_patch to the same path should not record another page view"
    end
  end
end
