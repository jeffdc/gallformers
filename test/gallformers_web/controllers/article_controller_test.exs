defmodule GallformersWeb.ArticleControllerTest do
  use GallformersWeb.ConnCase

  alias Gallformers.Articles

  @valid_attrs %{
    title: "Test Article",
    slug: "test-article",
    content: "Some **markdown** content here.",
    author: "Test Author",
    is_published: true
  }

  defp create_article(attrs \\ %{}) do
    {:ok, article} = Articles.create_article(Map.merge(@valid_attrs, attrs))
    article
  end

  test "GET /articles/:slug renders a published article", %{conn: conn} do
    article = create_article()

    conn = get(conn, ~p"/articles/#{article.slug}")

    assert html_response(conn, 200) =~ "Test Article"
    assert html_response(conn, 200) =~ "Test Author"
  end

  test "GET /articles/:slug sets page metadata", %{conn: conn} do
    article = create_article()

    conn = get(conn, ~p"/articles/#{article.slug}")

    assert conn.assigns.page_title == "Test Article"
    assert conn.assigns.page_url == "/articles/test-article"
  end

  test "GET /articles/:slug returns 404 for nonexistent slug", %{conn: conn} do
    conn = get(conn, ~p"/articles/nonexistent-slug")

    assert html_response(conn, 404)
  end

  test "GET /articles/:slug returns 404 for unpublished article", %{conn: conn} do
    create_article(%{slug: "draft-article", is_published: false})

    conn = get(conn, ~p"/articles/draft-article")

    assert html_response(conn, 404)
  end
end
