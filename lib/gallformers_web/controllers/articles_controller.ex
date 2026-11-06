defmodule GallformersWeb.ArticlesController do
  use GallformersWeb, :controller

  alias Gallformers.Accounts
  alias Gallformers.Articles
  alias Gallformers.Keys

  def index(conn, params) do
    selected_tag = params["tag"]
    current_user = conn.assigns.current_user
    is_admin = Accounts.admin?(current_user)
    tags = Articles.list_tags(published_only: true)

    articles =
      if selected_tag do
        Articles.list_articles(published_only: true, tag: selected_tag)
      else
        Articles.list_published_articles()
      end

    # The newest article is featured on the unfiltered list.
    {featured, articles} =
      case {selected_tag, articles} do
        {nil, [first | rest]} -> {first, rest}
        _ -> {nil, articles}
      end

    conn
    |> assign(:page_title, "Articles")
    |> assign(
      :page_description,
      "Gallformers Articles - in-depth articles on gall biology, identification guides, and scientific literature."
    )
    |> assign(:page_url, "/articles")
    |> assign(:tags, tags)
    |> assign(:selected_tag, selected_tag)
    |> assign(:featured, featured)
    |> assign(:articles, articles)
    |> assign(:key_count, length(Keys.list_keys()))
    |> assign(:is_admin, is_admin)
    |> render(:index)
  end
end
