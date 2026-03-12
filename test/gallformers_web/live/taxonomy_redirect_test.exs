defmodule GallformersWeb.TaxonomyRedirectTest do
  @moduledoc """
  Tests for backwards-compatible redirects from old ID-based taxonomy URLs
  to new name-based URLs.

  Old URLs like /family/30, /genus/33, /section/5 need to 301-redirect
  to /family/Cynipidae, /genus/Andricus, etc.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "family ID redirect" do
    test "redirects /family/:id to /family/:name", %{conn: conn} do
      # Cynipidae has id=30 in test seeds
      {:error, {:live_redirect, %{to: to}}} = live(conn, "/family/30")

      assert to == "/family/Cynipidae"
    end

    test "name-based URL loads normally (no redirect loop)", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/family/Cynipidae")

      assert html =~ "Cynipidae"
    end

    test "invalid numeric ID shows not found", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/family/99999")

      assert html =~ "not found" or html =~ "Not Found"
    end
  end

  describe "genus ID redirect" do
    test "redirects /genus/:id to /genus/:name", %{conn: conn} do
      # Andricus has id=33 in test seeds
      {:error, {:live_redirect, %{to: to}}} = live(conn, "/genus/33")

      assert to == "/genus/Andricus"
    end

    test "name-based URL loads normally (no redirect loop)", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/Andricus")

      assert html =~ "Andricus"
    end

    test "invalid numeric ID shows not found", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/99999")

      assert html =~ "not found" or html =~ "Not Found"
    end
  end

  describe "section ID redirect" do
    # No section in test seeds with a known ID, so we test the not-found path
    test "invalid numeric section ID shows not found", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/section/99999")

      assert html =~ "not found" or html =~ "Not Found"
    end
  end

  describe "old /taxonomy/:id redirect for intermediates" do
    test "redirects /taxonomy/31 to /subfamily/Cynipinae", %{conn: conn} do
      # Cynipinae is id=31, rank=Subfamily in test seeds
      conn = get(conn, "/taxonomy/31")
      assert redirected_to(conn, 301) == "/subfamily/Cynipinae"
    end

    test "redirects /taxonomy/32 to /tribe/Cynipini", %{conn: conn} do
      # Cynipini is id=32, rank=Tribe in test seeds
      conn = get(conn, "/taxonomy/32")
      assert redirected_to(conn, 301) == "/tribe/Cynipini"
    end

    test "redirects /taxonomy/:id for family to /family/:name", %{conn: conn} do
      # Cynipidae is id=30, type=family
      conn = get(conn, "/taxonomy/30")
      assert redirected_to(conn, 301) == "/family/Cynipidae"
    end

    test "redirects /taxonomy/:id for genus to /genus/:name", %{conn: conn} do
      # Andricus is id=33, type=genus
      conn = get(conn, "/taxonomy/33")
      assert redirected_to(conn, 301) == "/genus/Andricus"
    end

    test "returns 404 for nonexistent /taxonomy/:id", %{conn: conn} do
      conn = get(conn, "/taxonomy/99999")
      assert conn.status == 404
    end
  end
end
