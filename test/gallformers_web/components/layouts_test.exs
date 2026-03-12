defmodule GallformersWeb.LayoutsTest do
  @moduledoc """
  Tests for layout components.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GallformersWeb.Layouts

  describe "site_header" do
    test "renders Browse dropdown with galls, hosts, and places links" do
      html = render_component(&Layouts.site_header/1, %{})

      # The Browse dropdown label should be present
      assert html =~ "Browse"

      # Each link should be present with correct href
      assert html =~ ~s(href="/galls")
      assert html =~ "Galls"
      assert html =~ ~s(href="/hosts")
      assert html =~ "Hosts"
      assert html =~ ~s(href="/places")
      assert html =~ "Places"
    end

    test "does not render the old Explore link" do
      html = render_component(&Layouts.site_header/1, %{})

      refute html =~ ~s(href="/explore")
      refute html =~ "Explore"
    end

    test "Browse dropdown appears in both desktop and mobile nav" do
      html = render_component(&Layouts.site_header/1, %{})

      # Desktop: browse-menu dropdown (mirrors resources-menu pattern)
      assert html =~ "browse-menu"

      # Mobile: Browse section label
      assert html =~ "Browse"
    end

    test "still renders Identify link" do
      html = render_component(&Layouts.site_header/1, %{})

      assert html =~ ~s(href="/id")
      assert html =~ "Identify"
    end

    test "still renders Resources dropdown" do
      html = render_component(&Layouts.site_header/1, %{})

      assert html =~ "Resources"
      assert html =~ "resources-menu"
    end
  end

  describe "maintenance banner" do
    setup do
      cache_key = {Gallformers.SiteSettings, :cache}
      previous = :persistent_term.get(cache_key, %{})
      :persistent_term.put(cache_key, %{})
      on_exit(fn -> :persistent_term.put(cache_key, previous) end)
      :ok
    end

    test "shows maintenance banner when enabled", %{conn: conn} do
      Gallformers.SiteSettings.set("banner_enabled", true)
      Gallformers.SiteSettings.set("banner_text", "Scheduled maintenance tonight")

      conn = get(conn, "/")
      html = html_response(conn, 200)
      assert html =~ "maintenance-banner"
      assert html =~ "Scheduled maintenance tonight"
    end

    test "does not show maintenance banner when disabled", %{conn: conn} do
      conn = get(conn, "/")
      html = html_response(conn, 200)
      refute html =~ "maintenance-banner"
    end

    test "does not show maintenance banner when explicitly set to false", %{conn: conn} do
      Gallformers.SiteSettings.set("banner_enabled", false)

      conn = get(conn, "/")
      html = html_response(conn, 200)
      refute html =~ "maintenance-banner"
    end
  end
end
