defmodule GallformersWeb.Admin.ArticleLive.DeleteTest do
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Articles
  alias Gallformers.Articles.Article
  alias Gallformers.Repo

  defp setup_admin_session(conn) do
    user = %Auth0User{
      id: "test-admin-id",
      email: "admin@test.com",
      name: "Test Admin",
      nickname: nil,
      picture: nil,
      roles: ["admin"]
    }

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, user)
    |> put_session(:db_display_name, "Test User")
  end

  defp create_article! do
    {:ok, article} =
      Articles.create_article(%{
        title: "Destructive delete article",
        author: "Test Author",
        content: "Irreplaceable article content"
      })

    article
  end

  setup %{conn: conn} do
    {:ok, conn: setup_admin_session(conn)}
  end

  test "edit view requires the exact article title before deletion", %{conn: conn} do
    article = create_article!()
    {:ok, view, _html} = live(conn, ~p"/admin/articles/#{article.id}")

    render_click(view, "delete")

    assert has_element?(view, "#dangerous-delete-modal", article.title)
    assert Repo.get(Article, article.id) != nil

    html = render_submit(view, "confirm_delete", %{"confirmation" => "wrong title"})

    assert html =~ "Title does not match"
    assert Repo.get(Article, article.id) != nil

    render_submit(view, "confirm_delete", %{"confirmation" => article.title})

    assert_redirect(view, "/admin/articles")
    refute Repo.get(Article, article.id)
  end

  test "index view requires the exact article title before deletion", %{conn: conn} do
    article = create_article!()
    {:ok, view, _html} = live(conn, ~p"/admin/articles")

    render_click(view, "delete", %{"id" => Integer.to_string(article.id)})

    assert has_element?(view, "#dangerous-delete-modal", article.title)
    assert Repo.get(Article, article.id) != nil

    html = render_submit(view, "confirm_delete", %{"confirmation" => "wrong title"})

    assert html =~ "Title does not match"
    assert Repo.get(Article, article.id) != nil

    render_submit(view, "confirm_delete", %{"confirmation" => article.title})

    refute Repo.get(Article, article.id)
  end

  test "index handles an article deleted while its confirmation is open", %{conn: conn} do
    article = create_article!()
    {:ok, view, _html} = live(conn, ~p"/admin/articles")

    render_click(view, "delete", %{"id" => Integer.to_string(article.id)})
    Articles.delete_article(article)

    html = render_submit(view, "confirm_delete", %{"confirmation" => article.title})

    assert html =~ "Article already deleted"
    refute has_element?(view, "#dangerous-delete-modal")
  end
end
