defmodule GallformersWeb.GlossaryLiveTest do
  @moduledoc """
  The public glossary page (`/glossary`): every term with its definition and
  references, each row anchored by its lowercase word (search results and
  glossary tooltips link to `/glossary#word`).

  Uses the seeds' glossary (abscission, bivalved, cynipid, detachable …).
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Reads the seeds' glossary.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  test "lists every term, each row anchored by its lowercase word", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/glossary")

    assert has_element?(view, "h1", "Glossary")
    assert has_element?(view, "tr#cynipid", "A member of the family Cynipidae")
    assert has_element?(view, "tr#abscission")
    assert page_title(view) =~ "Glossary"
  end

  test "a term's references are numbered links", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/glossary")

    assert has_element?(
             view,
             ~s{tr#cynipid a[href="https://en.wikipedia.org/wiki/Cynipidae"]},
             "1"
           )
  end

  test "a definition links the other terms it uses", %{conn: conn} do
    {:ok, _} =
      Gallformers.Glossaries.create_glossary(%{
        word: "Fixturgall",
        definition: "A gall made by a cynipid.",
        urls: "https://example.org/fixturgall"
      })

    {:ok, view, _html} = live(conn, ~p"/glossary")

    assert view |> element("tr#fixturgall") |> render() =~ ~s(href="/glossary#cynipid")
  end

  test "the filter narrows the terms", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/glossary")

    view |> element("#glossary-search-form") |> render_change(%{"query" => "cynip"})

    assert has_element?(view, "tr#cynipid")
    refute has_element?(view, "tr#abscission")
  end

  test "a filter that matches nothing says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/glossary")

    view |> element("#glossary-search-form") |> render_change(%{"query" => "zzzz-nothing"})

    assert has_element?(view, "[data-part=empty]", "No glossary entries found.")
  end

  test "sorts by word, either way", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/glossary")
    first = fn -> view |> element("tbody tr:first-child") |> render() end

    assert first.() =~ ~s(id="abscission")

    view |> element("button[phx-click=sort][phx-value-field=word]") |> render_click()
    refute first.() =~ ~s(id="abscission")
    assert has_element?(view, "th[aria-sort=descending]", "Word")
  end

  test "a signed-in user gets an edit link for each term; a visitor does not", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/glossary")
    refute has_element?(view, "a[href^='/admin/glossary/']")

    {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
    {:ok, view, _html} = live(admin_conn, ~p"/glossary")
    assert has_element?(view, "tr#cynipid a[href^='/admin/glossary/'][title='Edit']")
  end
end
