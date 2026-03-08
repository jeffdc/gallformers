defmodule GallformersWeb.ArticleController do
  @moduledoc """
  Controller for individual article pages.

  Displays a single article with rendered markdown content, metadata,
  and related articles (by shared tags).
  """
  use GallformersWeb, :controller

  alias Gallformers.Accounts
  alias Gallformers.Articles
  alias Gallformers.Markdown

  def show(conn, %{"slug" => slug}) do
    current_user = conn.assigns.current_user
    is_admin = Accounts.admin?(current_user)

    with %{} = article <- Articles.get_article_by_slug(slug),
         true <- article.is_published or is_admin do
      render_article(conn, article, is_admin)
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> put_view(GallformersWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  defp render_article(conn, article, is_admin) do
    related_articles = Articles.list_related_articles(article, limit: 5)
    rendered_content = Markdown.render!(article.content)
    noindex = not article.is_published

    page_description =
      if article.description in [nil, ""] do
        content_description(article.content)
      else
        article.description
      end

    conn
    |> assign(:page_title, article.title)
    |> assign(:page_description, page_description)
    |> assign(:page_url, "/articles/#{article.slug}")
    |> assign(:page_json_ld, article_json_ld(article))
    |> assign(:page_noindex, noindex)
    |> assign(:article, article)
    |> assign(:rendered_content, rendered_content)
    |> assign(:related_articles, related_articles)
    |> assign(:is_draft_preview, not article.is_published and is_admin)
    |> assign(:is_admin, is_admin)
    |> render(:show)
  end

  defp content_description(content) when is_binary(content) do
    content
    |> String.replace(~r/[#*_`\[\]()]/, "")
    |> String.slice(0, 160)
    |> String.trim()
    |> then(fn desc ->
      if String.length(content) > 160, do: desc <> "...", else: desc
    end)
  end

  defp content_description(_), do: "Reference article on Gallformers"

  defp article_json_ld(article) do
    date_published =
      if article.published_at do
        DateTime.to_iso8601(article.published_at)
      else
        NaiveDateTime.to_iso8601(article.inserted_at)
      end

    json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "Article",
      "headline" => article.title,
      "author" => %{
        "@type" => "Person",
        "name" => article.author
      },
      "datePublished" => date_published,
      "dateModified" => NaiveDateTime.to_iso8601(article.updated_at),
      "publisher" => %{
        "@type" => "Organization",
        "name" => "Gallformers",
        "url" => "https://gallformers.org"
      }
    }

    Jason.encode!(json_ld)
  end
end
