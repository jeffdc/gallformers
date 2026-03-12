defmodule GallformersWeb.ExploreRedirectTest do
  @moduledoc """
  Tests for legacy /explore URL redirects.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "/explore redirect" do
    test "redirects /explore to /galls with 301", %{conn: conn} do
      conn = get(conn, ~p"/explore")
      assert redirected_to(conn, 301) == "/galls"
    end

    test "redirects /explore?tab=hosts to /hosts with 301", %{conn: conn} do
      conn = get(conn, "/explore?tab=hosts")
      assert redirected_to(conn, 301) == "/hosts"
    end

    test "redirects /explore?tab=places to /places with 301", %{conn: conn} do
      conn = get(conn, "/explore?tab=places")
      assert redirected_to(conn, 301) == "/places"
    end

    test "redirects /explore?tab=undescribed to /galls with 301", %{conn: conn} do
      conn = get(conn, "/explore?tab=undescribed")
      assert redirected_to(conn, 301) == "/galls"
    end

    test "redirects /explore?tab=galls to /galls with 301", %{conn: conn} do
      conn = get(conn, "/explore?tab=galls")
      assert redirected_to(conn, 301) == "/galls"
    end
  end

  describe "/places legacy redirect" do
    test "redirects /places to the new /places route (not explore)", %{conn: conn} do
      # /places used to redirect to /explore?tab=places, now it should go to /places directly
      # This is handled by the router having a direct live route for /places
      {:ok, _view, html} = live(conn, ~p"/places")
      assert html =~ "North America"
    end
  end
end
