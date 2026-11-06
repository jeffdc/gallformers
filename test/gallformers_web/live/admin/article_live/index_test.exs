defmodule GallformersWeb.Admin.ArticleLive.IndexTest do
  @moduledoc """
  The articles admin list (`/admin/articles`, design system matter bc0d), on
  the admin list pattern: every article linked to its edit page, its status,
  tags and public page; filters by title or author, tag and status; New
  article. Deleting is on the edit page (its danger panel).

  Not async: admin access reads the site settings (persistent_term).
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Articles

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn)

    {:ok, published} =
      Articles.create_article(%{
        title: "Oak apples in winter",
        author: "Ada Fixture",
        content: "Text.",
        tags: ["oaks"],
        is_published: true
      })

    {:ok, draft} =
      Articles.create_article(%{
        title: "Rose galls, a draft",
        author: "Bo Fixture",
        content: "Text.",
        tags: ["roses"]
      })

    %{conn: conn, published: published, draft: draft}
  end

  test "every article, linked to its edit page, with its status and public page", %{
    conn: conn,
    published: published,
    draft: draft
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/articles")

    assert has_element?(view, "h1", "Articles")
    assert has_element?(view, "a[href='/admin/articles/new']", "New article")

    assert has_element?(
             view,
             "#articles a[href='/admin/articles/#{published.id}']",
             "Oak apples in winter"
           )

    assert has_element?(view, "#articles-#{published.id} [data-status]", "Published")
    assert has_element?(view, "#articles-#{draft.id} [data-status]", "Draft")

    assert has_element?(
             view,
             "#articles-#{published.id} a[href='/articles/#{published.slug}']",
             "View"
           )

    assert has_element?(
             view,
             "#articles-#{draft.id} a[href='/articles/#{draft.slug}']",
             "Preview"
           )
  end

  test "no Delete in the list: it is on the edit page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/articles")

    refute has_element?(view, "#articles [phx-click=delete]")
  end

  test "filter by title or author", %{conn: conn, published: published, draft: draft} do
    {:ok, view, _html} = live(conn, ~p"/admin/articles")

    view |> form("#article-search-form", %{"query" => "bo fix"}) |> render_change()

    assert has_element?(view, "#articles-#{draft.id}")
    refute has_element?(view, "#articles-#{published.id}")
  end

  test "filter by tag and by status", %{conn: conn, published: published, draft: draft} do
    {:ok, view, _html} = live(conn, ~p"/admin/articles")

    view |> form("form:has(#article-tag-filter)", %{"tag" => "roses"}) |> render_change()
    assert has_element?(view, "#articles-#{draft.id}")
    refute has_element?(view, "#articles-#{published.id}")

    view |> form("form:has(#article-tag-filter)", %{"tag" => ""}) |> render_change()

    view
    |> form("form:has(#article-status-filter)", %{"status" => "published"})
    |> render_change()

    assert has_element?(view, "#articles-#{published.id}")
    refute has_element?(view, "#articles-#{draft.id}")
  end

  test "nothing matching says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/articles")

    view |> form("#article-search-form", %{"query" => "zzz-nothing"}) |> render_change()

    assert has_element?(view, "#articles[data-part=empty]", "No articles match")
  end
end
