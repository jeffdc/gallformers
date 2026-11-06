defmodule GallformersWeb.Admin.ArticleLive.PreviewTest do
  @moduledoc "The article form's Preview tab: the Markdown rendered as the article page shows it."
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gallformers.Articles

  test "Preview shows the content in prose", %{conn: conn} do
    {:ok, article} =
      Articles.create_article(%{
        title: "Preview piece",
        author: "A. Kranz",
        content: "A **bold** claim."
      })

    {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
    {:ok, view, _html} = live(admin_conn, ~p"/admin/articles/#{article.id}")

    view |> element("button[phx-click=switch_tab][phx-value-tab=preview]") |> render_click()

    assert has_element?(view, ".gf-prose[data-size=sm] strong", "bold")
  end
end
