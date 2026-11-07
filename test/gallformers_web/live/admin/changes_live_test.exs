defmodule GallformersWeb.Admin.ChangesLiveTest do
  @moduledoc """
  The Changes page (`/admin/changes`, matters bc0d, 15db): every curator
  change (`Gallformers.Audit.ChangeLog`), newest first, as `change_entry`s;
  searched (`q`: a Gall, taxon, Source or value), filtered by curator
  (`who`) and kind (`kind`), over a period (`period`: 7d, 30d, all; 30
  days by default).

  Not async: admin access reads the site settings (persistent_term).
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.AuditFixtures
  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1]
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Audit.ChangeLog

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  setup do
    oaky = gall_fixture(%{name: "Andricus oakyi"})
    rosy = gall_fixture(%{name: "Diplolepis rosyi"})

    curator_change("Adam Kranz", "catalog.update_gall_editorial", 60 * 24 * 10, [
      {"galls", "update", %{id: oaky.id, name: oaky.name}}
    ])

    curator_change("Jeff Clark", "catalog.update_name_parts", 5, [
      {"galls", "update", %{id: rosy.id, name: rosy.name}}
    ])

    %{oaky: oaky, rosy: rosy}
  end

  test "the page: every change in the period, newest first", %{conn: conn, rosy: rosy} do
    {:ok, view, _html} = live(conn, ~p"/admin/changes")

    assert has_element?(view, "h1", "Changes")
    assert has_element?(view, "nav[aria-label=Breadcrumb] a[href='/admin']", "Dashboard")
    assert has_element?(view, "#changes li [data-part=summary]", "Jeff Clark")

    assert has_element?(
             view,
             "#changes [data-part=galls] a[href='/gall/#{rosy.id}?edit']",
             "Edit"
           )

    # Adam's change is ten days old: inside the default 30 days.
    assert has_element?(view, "#changes li [data-part=summary]", "Adam Kranz")
  end

  test "the period narrows to the last 7 days", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/changes?period=7d")

    assert has_element?(view, "nav[aria-label=Period] a[aria-current=page]", "7 days")
    assert has_element?(view, "#changes li", "Jeff Clark")
    refute has_element?(view, "#changes li", "Adam Kranz")
  end

  test "by curator", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/changes?who=Adam+Kranz")

    assert has_element?(view, "#changes li", "Adam Kranz")
    refute has_element?(view, "#changes li", "Jeff Clark")
  end

  test "by kind", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/changes?kind=catalog.update_name_parts")

    assert has_element?(view, "#changes li", "changed a Gall's name")
    refute has_element?(view, "#changes li", "Adam Kranz")
  end

  test "a search finds a Gall by name, and the filters patch the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/changes")

    view |> form("#changes-search", %{"q" => "oakyi"}) |> render_change()

    assert_patch(view, ~p"/admin/changes?period=30d&q=oakyi")
    assert has_element?(view, "#changes li", "Adam Kranz")
    refute has_element?(view, "#changes li", "Jeff Clark")
  end

  test "nothing matching says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/changes?q=nothing-like-this")
    assert has_element?(view, "[data-part=title]", "No changes match")
  end

  test "keeps up: changes recorded show without a refresh, the search and filters kept", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/changes?who=Adam+Kranz&q=oakyi&period=7d")
    refute has_element?(view, "#changes li", "Adam Kranz")

    curator_change("Adam Kranz", "catalog.update_gall_editorial", 1, [
      {"galls", "update", %{id: ctx.oaky.id, name: ctx.oaky.name}}
    ])

    curator_change("Adam Kranz", "catalog.update_name_parts", 1, [
      {"galls", "update", %{id: ctx.rosy.id, name: ctx.rosy.name}}
    ])

    ChangeLog.changed()

    assert has_element?(view, "#changes li", "Andricus oakyi")
    refute has_element?(view, "#changes li", "Diplolepis rosyi")
    assert has_element?(view, "#changes-q[value=oakyi]")
    assert has_element?(view, "nav[aria-label=Period] a[aria-current=page]", "7 days")
  end

  test "the sidebar has the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/changes")
    assert has_element?(view, "#admin-nav a[data-nav-href='/admin/changes']", "Changes")
  end
end
