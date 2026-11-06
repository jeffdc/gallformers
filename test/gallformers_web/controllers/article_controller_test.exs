defmodule GallformersWeb.ArticleControllerTest do
  @moduledoc """
  An article (`/articles/:slug`): the page header (author, dates, topics),
  the text in `prose`, related articles, the draft notice and edit link for
  admins.
  """
  use GallformersWeb.ConnCase

  alias Gallformers.Articles

  defp query(html, selector), do: html |> LazyHTML.from_document() |> LazyHTML.query(selector)
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()
  defp count(html, selector), do: html |> query(selector) |> Enum.count()

  defp create_article(attrs \\ %{}) do
    {:ok, article} =
      Articles.create_article(
        Map.merge(
          %{
            title: "Test Article",
            slug: "test-article",
            content: "Some **markdown** content here.",
            author: "Test Author",
            is_published: true
          },
          attrs
        )
      )

    article
  end

  test "renders the article: title, author, topics, and its text in prose", %{conn: conn} do
    article = create_article(%{tags: ["guide", "faq"]})

    html = conn |> get(~p"/articles/#{article.slug}") |> html_response(200)

    assert text(html, "h1") == "Test Article"
    assert text(html, "[data-part=meta]") =~ "Test Author"
    assert count(html, ~s{[data-part=meta] a[href="/articles?tag=guide"]}) == 1
    assert count(html, ~s{nav[aria-label=Breadcrumb] a[href="/articles"]}) == 1
    assert text(html, ~s{.gf-prose[data-size="lg"] strong}) == "markdown"
  end

  test "lists related articles", %{conn: conn} do
    article = create_article(%{tags: ["guide"]})
    create_article(%{slug: "other", title: "Other Guide", tags: ["guide"]})

    html = conn |> get(~p"/articles/#{article.slug}") |> html_response(200)

    assert text(html, ~s{aside a[href="/articles/other"]}) == "Other Guide"
  end

  test "sets page metadata", %{conn: conn} do
    article = create_article()

    conn = get(conn, ~p"/articles/#{article.slug}")

    assert conn.assigns.page_title == "Test Article"
    assert conn.assigns.page_url == "/articles/test-article"
  end

  test "a missing article is a 404", %{conn: conn} do
    assert html_response(get(conn, ~p"/articles/nonexistent-slug"), 404)
  end

  test "an unpublished article is a 404 to visitors", %{conn: conn} do
    create_article(%{slug: "draft-article", is_published: false})
    assert html_response(get(conn, ~p"/articles/draft-article"), 404)
  end

  test "an admin sees an unpublished article as a draft, with an edit link", %{conn: conn} do
    article = create_article(%{slug: "draft-article", is_published: false})
    {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)

    html = admin_conn |> get(~p"/articles/draft-article") |> html_response(200)

    assert text(html, "[role=status], [role=alert]") =~ "Draft"
    assert count(html, ~s{a[href="/admin/articles/#{article.id}"]}) == 1
  end
end
