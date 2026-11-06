defmodule GallformersWeb.Admin.ArticleLive.FormTest do
  @moduledoc """
  The article edit page (`/admin/articles/:id`, design system matter bc0d),
  on the admin edit page pattern: crumb, title, status and View on site in
  the header; the form; Preview; the image browser with its insert and
  delete-image dialogs; Delete in the rail's danger panel. (Typed-title
  delete: `delete_test.exs`; Preview's prose: `preview_test.exs`; the
  content image manager: `form_content_images_test.exs`.)

  In tests S3 is off: image lists come back empty and deletes succeed.
  Not async: admin access reads the site settings (persistent_term).
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Articles

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn)

    {:ok, article} =
      Articles.create_article(%{
        title: "Oak apples in winter",
        author: "Ada Fixture",
        content: "Some **text**."
      })

    %{conn: conn, article: article}
  end

  describe "the header" do
    test "an article: crumb, title, status and its page on the site", %{
      conn: conn,
      article: article
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/articles/#{article.id}")

      assert has_element?(
               view,
               "nav[aria-label=Breadcrumb] a[href='/admin/articles']",
               "Articles"
             )

      assert has_element?(view, "h1", "Oak apples in winter")
      assert has_element?(view, "[data-part=chips]", "Draft")
      assert has_element?(view, "a[href='/articles/#{article.slug}']", "Preview on site")
    end

    test "a new article: its title, no Delete", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/articles/new")

      assert has_element?(view, "h1", "New article")
      refute has_element?(view, "#danger")
    end
  end

  describe "the form" do
    test "save a change", %{conn: conn, article: article} do
      {:ok, view, _html} = live(conn, ~p"/admin/articles/#{article.id}")

      view
      |> form("#article-form", article: %{title: "Oak apples in spring"})
      |> render_submit()

      assert Articles.get_article!(article.id).title == "Oak apples in spring"
    end

    test "Preview, then back to the Markdown", %{conn: conn, article: article} do
      {:ok, view, _html} = live(conn, ~p"/admin/articles/#{article.id}")

      view |> element("button[phx-click=switch_tab][phx-value-tab=preview]") |> render_click()
      refute has_element?(view, "#article-form")

      view |> element("button[phx-click=switch_tab][phx-value-tab=edit]") |> render_click()
      assert has_element?(view, "#article-form")
    end

    test "Delete is in the rail's danger panel", %{conn: conn, article: article} do
      {:ok, view, _html} = live(conn, ~p"/admin/articles/#{article.id}")

      view |> element("#danger button", "Delete…") |> render_click()

      assert has_element?(view, "#dangerous-delete-modal", article.title)
    end
  end

  describe "the image browser" do
    test "Browse images shows the article's images, and closes", %{conn: conn, article: article} do
      {:ok, view, _html} = live(conn, ~p"/admin/articles/#{article.id}")

      view |> element("button[phx-click=open_image_browser]") |> render_click()

      assert has_element?(view, "#image-browser h2", "Article images")
      assert has_element?(view, "#image-browser [data-part=empty]")
      refute has_element?(view, "#article-form")

      view |> element("#image-browser button[phx-click=close_image_browser]") |> render_click()
      assert has_element?(view, "#article-form")
    end

    test "an image chosen to insert: its dialog asks for alt text, then inserts", %{
      conn: conn,
      article: article
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/articles/#{article.id}")
      view |> element("button[phx-click=open_image_browser]") |> render_click()

      render_click(view, "select_image", %{"url" => "https://img.test/a.jpg", "name" => "a.jpg"})

      assert has_element?(view, "#insert-image [role=dialog]")
      assert has_element?(view, "#insert-image img[src='https://img.test/a.jpg']")

      view
      |> form("#image-insert-form", %{"alt_text" => "An oak apple", "size_preset" => "medium"})
      |> render_submit()

      assert_push_event(view, "insert_image_markdown", %{markdown: markdown})
      assert markdown =~ "An oak apple"
      refute has_element?(view, "#insert-image")
    end

    test "an image to delete: its dialog names the articles using it", %{
      conn: conn,
      article: article
    } do
      {:ok, _} =
        Articles.update_article(article, %{content: "![x](https://img.test/a.jpg)"})

      {:ok, view, _html} = live(conn, ~p"/admin/articles/#{article.id}")
      view |> element("button[phx-click=open_image_browser]") |> render_click()

      render_click(view, "confirm_delete_image", %{
        "url" => "https://img.test/a.jpg",
        "path" => "articles/#{article.id}/a.jpg",
        "name" => "a.jpg"
      })

      assert has_element?(view, "#delete-image [role=dialog]")
      assert has_element?(view, "#delete-image li", "Oak apples in winter")

      view |> element("#delete-image button", "Delete anyway") |> render_click()
      refute has_element?(view, "#delete-image")
    end
  end
end
