defmodule GallformersWeb.Admin.GallLive.IndexTest do
  @moduledoc """
  The Gall page's search (matter a856, Task 7): `/admin/galls` finds Galls
  as the global search does (`Gallformers.Catalog.search_galls/2`), a page
  at a time, each linking to its Gall page. Galls arrive with imports: there
  is no "new".
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import GallformersWeb.AdminLiveHelpers

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Gail Galls")
    %{conn: conn}
  end

  test "asks for a search before listing anything", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/galls")

    assert has_element?(view, "#gall-search-form")
    refute has_element?(view, "#galls-table tbody tr[id^='gall-']")
    refute has_element?(view, "a[href='/admin/galls/new']")
  end

  test "finds Galls by name and links each to its Gall page", %{conn: conn} do
    gall = gall_fixture(name: "Zyzzyxa searchable gall")
    other = gall_fixture(name: "Unrelated gall")

    {:ok, view, _html} = live(conn, ~p"/admin/galls")
    view |> form("#gall-search-form", %{query: "zyzzyxa"}) |> render_change()

    assert has_element?(view, "#gall-#{gall.id} a[href='/admin/galls/#{gall.id}']")
    refute has_element?(view, "#gall-#{other.id}")
  end

  test "marks an undescribed Gall", %{conn: conn} do
    gall = gall_fixture(name: "Zyzzyxb undescribed gall")

    {:ok, view, _html} = live(conn, ~p"/admin/galls")
    view |> form("#gall-search-form", %{query: "zyzzyxb"}) |> render_change()

    assert has_element?(view, "#gall-#{gall.id}", "Undescribed")
  end

  test "pages through the results", %{conn: conn} do
    prefix = "Zyzzyxpaged#{System.unique_integer([:positive])}"

    for n <- 1..26,
        do: gall_fixture(name: "#{prefix} #{String.pad_leading("#{n}", 2, "0")}")

    {:ok, view, _html} = live(conn, ~p"/admin/galls")
    view |> form("#gall-search-form", %{query: prefix}) |> render_change()

    assert has_element?(view, "#galls-table", "#{prefix} 01")
    refute has_element?(view, "#galls-table", "#{prefix} 26")

    view |> element("nav[aria-label='Pagination'] button", "Next") |> render_click()

    assert has_element?(view, "#galls-table", "#{prefix} 26")
    refute has_element?(view, "#galls-table", "#{prefix} 01")
  end

  test "keeps the search in the URL", %{conn: conn} do
    gall = gall_fixture(name: "Zyzzyxc linked gall")

    {:ok, view, _html} = live(conn, ~p"/admin/galls?q=zyzzyxc")

    assert has_element?(view, "#gall-#{gall.id}")
  end
end
