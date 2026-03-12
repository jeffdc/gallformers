defmodule GallformersWeb.Admin.ArticleLive.FormContentImagesTest do
  @moduledoc """
  Tests for ContentImageManager integration in the article admin form.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Articles

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

  setup %{conn: conn} do
    {:ok, article} =
      Articles.create_article(%{
        title: "Content Images Test Article",
        content: "Test content",
        author: "tester"
      })

    {:ok, conn: setup_admin_session(conn), article: article}
  end

  describe "content image manager on article edit" do
    test "shows content image manager component", %{conn: conn, article: article} do
      {:ok, view, _html} = live(conn, ~p"/admin/articles/#{article.id}")

      assert has_element?(view, "[data-content-image-manager]")
    end

    test "does not show content image manager on new article", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/articles/new")

      refute has_element?(view, "[data-content-image-manager]")
    end
  end
end
