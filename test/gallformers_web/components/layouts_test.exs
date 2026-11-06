defmodule GallformersWeb.LayoutsTest do
  @moduledoc """
  Tests for layout components.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]

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
      :persistent_term.put({Gallformers.SiteSettings, :cache}, %{
        "banner_enabled" => true,
        "banner_text" => "Scheduled maintenance tonight"
      })

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
      :persistent_term.put({Gallformers.SiteSettings, :cache}, %{"banner_enabled" => false})

      conn = get(conn, "/")
      html = html_response(conn, 200)
      refute html =~ "maintenance-banner"
    end
  end

  describe "site_shell (Layouts.app)" do
    defp q(html, selector), do: html |> LazyHTML.from_document() |> LazyHTML.query(selector)

    defp app(user) do
      assigns = %{user: user}

      rendered_to_string(~H"""
      <Layouts.app flash={%{}} current_user={@user}>
        <p id="content">Body</p>
      </Layouts.app>
      """)
    end

    test "the footer sits at the end of the page, not fixed over it" do
      footer = app(nil) |> q("footer")
      assert Enum.count(footer) == 1
      refute footer |> LazyHTML.attribute("class") |> hd() =~ "fixed"
      assert app(nil) =~ ~s(href="/privacy")
    end

    test "a visitor sees Log in in the header" do
      assert app(nil) |> q("header a[href='/auth/auth0']") |> LazyHTML.text() =~ "Log in"
    end

    test "a signed-in user gets a menu with Admin and Log out" do
      user = %Gallformers.Accounts.Auth0User{
        id: "u1",
        name: "Ada",
        nickname: "ada",
        roles: ["admin"]
      }

      html = app(user)
      assert html |> q("header a[href='/admin']") |> Enum.count() >= 1
      assert html |> q("header a[href='/auth/logout']") |> LazyHTML.text() =~ "Log out"
    end

    test "content sits in the page column" do
      assert app(nil) |> q("main .max-w-page #content") |> Enum.count() == 1
    end

    test "the header opens the command palette; it has no search box of its own" do
      html = app(nil)

      assert html |> q("header button[data-palette-trigger]") |> Enum.count() >= 1
      assert html |> q("header button[data-palette-trigger] .gf-kbd") |> LazyHTML.text() =~ "/"
      assert html |> q("header input[type=search]") |> Enum.count() == 0
    end

    test "the header has the theme switch: System, Light and Dark" do
      html = app(nil)

      assert html |> q("header #theme-menu button[aria-label='Theme']") |> Enum.count() == 1

      for choice <- ~w(system light dark) do
        assert html
               |> q("header #theme-menu [role=menuitemradio][data-theme-option=#{choice}]")
               |> Enum.count() == 1
      end
    end
  end

  describe "dark mode" do
    test "the page follows the OS setting unless a theme was chosen: nothing pins it", %{
      conn: conn
    } do
      html = conn |> get("/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert doc |> LazyHTML.query("html") |> Enum.count() == 1
      assert doc |> LazyHTML.query("html[data-theme]") |> Enum.count() == 0

      assert doc |> LazyHTML.query("meta[name=color-scheme]") |> LazyHTML.attribute("content") ==
               ["light dark"]

      # The saved choice is applied in <head>, before the page paints.
      assert doc |> LazyHTML.query("head script#theme-init") |> LazyHTML.text() =~ "gf-theme"
    end

    test "every page carries the command palette", %{conn: conn} do
      html = conn |> get("/about") |> html_response(200)

      assert html
             |> LazyHTML.from_document()
             |> LazyHTML.query("#palette[phx-hook=Palette]")
             |> Enum.count() == 1
    end
  end

  describe "admin_shell (Layouts.admin)" do
    defp admin(attrs) do
      user = %Gallformers.Accounts.Auth0User{
        id: "u1",
        name: "Ada",
        nickname: "ada",
        roles: ["admin"]
      }

      assigns = Map.merge(%{user: user, page_title: nil}, attrs)

      rendered_to_string(~H"""
      <Layouts.admin flash={%{}} current_user={@user} page_title={@page_title}>
        <p id="content">Body</p>
      </Layouts.admin>
      """)
      |> LazyHTML.from_document()
    end

    test "the logo goes to the public site; Admin beside it is a label" do
      html = admin(%{})

      assert html
             |> LazyHTML.query(
               "#admin-sidebar a[aria-label='Gallformers home'][href='/'] img.gf-only-light"
             )
             |> Enum.count() == 1

      assert html
             |> LazyHTML.query(
               "#admin-sidebar a[aria-label='Gallformers home'][href='/'] img.gf-only-dark"
             )
             |> Enum.count() == 1

      refute html |> LazyHTML.query("#admin-sidebar a[href='/admin'] img") |> Enum.any?()
    end

    test "the top bar opens the command palette" do
      assert admin(%{}) |> LazyHTML.query("button[data-palette-trigger]") |> Enum.count() == 1
    end

    test "follows the viewer's theme, with the theme switch in its top bar" do
      assert admin(%{}) |> LazyHTML.query("[data-theme] #content") |> Enum.count() == 0
      assert admin(%{}) |> LazyHTML.query("#theme-menu") |> Enum.count() == 1
    end

    test "sets the Working density for everything inside it" do
      assert admin(%{}) |> LazyHTML.query(".gf-density-working #content") |> Enum.count() == 1
    end

    test "has the sidebar navigation and no site header or footer" do
      html = admin(%{})

      assert html |> LazyHTML.query("#admin-nav a[data-nav-href='/admin/review']") |> Enum.count() ==
               1

      assert html |> LazyHTML.query("footer") |> Enum.count() == 0

      assert html |> LazyHTML.query("#admin-nav a[href='/']") |> LazyHTML.text() =~
               "View public site"
    end

    test "a page title becomes the page's one h1" do
      html = admin(%{page_title: "Sources"})
      assert html |> LazyHTML.query("h1") |> Enum.count() == 1
      assert html |> LazyHTML.query("h1") |> LazyHTML.text() =~ "Sources"
    end
  end
end
