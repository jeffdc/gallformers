defmodule GallformersWeb.PaletteLiveTest do
  @moduledoc """
  The command palette (`GallformersWeb.PaletteLive`, a sticky LiveView in
  the root layout): closed until opened (the header's trigger, or `/` or
  `s`, which send it `open`); a search field; the groups of
  `GallformersWeb.Palette`; ↑ ↓ move the selection; Esc or a click outside
  closes it.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GallformersWeb.PaletteLive

  defp palette(conn, user \\ nil) do
    {:ok, view, _html} = live_isolated(conn, PaletteLive, session: %{"current_user" => user})
    view
  end

  test "closed until opened; then the search field and the Go to list" do
    view = palette(build_conn())
    refute has_element?(view, "[role=dialog]")

    render_hook(view, "open", %{})

    assert has_element?(view, "[role=dialog][aria-label='Search Gallformers'] input#palette-q")
    assert has_element?(view, "#palette-results a[href='/id']", "Identify a gall")
    refute has_element?(view, "#palette-results", "Edit this page")
  end

  test "a curator gets their commands", %{conn: conn} do
    curator = %Gallformers.Accounts.Auth0User{
      id: "u1",
      name: "Ada",
      nickname: "ada",
      roles: ["admin"]
    }

    view = palette(conn, curator)
    render_hook(view, "open", %{})

    assert has_element?(view, "#palette-results a[href='/admin/changes']", "Changes")
  end

  test "typing searches; the first row is selected, and the arrows move it", %{conn: conn} do
    view = palette(conn)
    render_hook(view, "open", %{})

    view
    |> form("#palette-form", %{"q" => "glossary-term-that-matches-nothing"})
    |> render_change()

    assert has_element?(view, "#palette-row-0[aria-selected=true]", "See every result")

    render_hook(view, "open", %{})
    view |> form("#palette-form", %{"q" => ""}) |> render_change()
    render_keydown(view, "key", %{"key" => "ArrowDown"})

    assert has_element?(view, "#palette-row-1[aria-selected=true]", "Browse galls")
    assert has_element?(view, "input#palette-q[aria-activedescendant=palette-row-1]")
  end

  test "Esc and close shut it", %{conn: conn} do
    view = palette(conn)

    render_hook(view, "open", %{})
    render_keydown(view, "key", %{"key" => "Escape"})
    refute has_element?(view, "[role=dialog]")

    render_hook(view, "open", %{})
    render_hook(view, "close", %{})
    refute has_element?(view, "[role=dialog]")
  end

  test "opening again starts fresh", %{conn: conn} do
    view = palette(conn)
    render_hook(view, "open", %{})
    view |> form("#palette-form", %{"q" => "quercus"}) |> render_change()
    render_hook(view, "close", %{})

    render_hook(view, "open", %{})
    assert has_element?(view, "input#palette-q[value='']")
    assert has_element?(view, "#palette-results a[href='/id']")
  end
end
