defmodule GallformersWeb.ArticleLive do
  @moduledoc """
  LiveView for individual article pages.

  Displays a single article with rendered markdown content, metadata,
  and related articles (by shared tags).
  """
  use GallformersWeb, :live_view

  alias Gallformers.Articles
  alias Gallformers.Markdown

  alias Gallformers.Accounts

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    current_user = socket.assigns.current_user
    is_admin = Accounts.admin?(current_user)

    case Articles.get_article_by_slug(slug) do
      nil ->
        {:ok,
         assign(socket,
           page_title: "Article Not Found",
           page_description: "The requested article was not found.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           article: nil,
           related_articles: [],
           error: "Article not found"
         )}

      article ->
        # Show draft articles to admins only
        if article.is_published or is_admin do
          load_article(socket, article, is_admin)
        else
          {:ok,
           assign(socket,
             page_title: "Article Not Found",
             page_description: "The requested article was not found.",
             page_url: nil,
             page_image: nil,
             page_json_ld: nil,
             page_noindex: true,
             article: nil,
             related_articles: [],
             error: "Article not found"
           )}
        end
    end
  end

  defp load_article(socket, article, is_admin) do
    # Find related articles (same tags, excluding self) - single query
    related_articles = Articles.list_related_articles(article, limit: 5)

    # Render markdown content
    rendered_content = Markdown.render!(article.content)

    # Draft articles should not be indexed by search engines
    noindex = not article.is_published

    # Use description if available, otherwise generate from content
    page_description =
      if article.description && article.description != "" do
        article.description
      else
        content_description(article.content)
      end

    {:ok,
     assign(socket,
       page_title: article.title,
       page_description: page_description,
       page_url: "/articles/#{article.slug}",
       page_image: nil,
       page_json_ld: article_json_ld(article),
       page_noindex: noindex,
       article: article,
       rendered_content: rendered_content,
       related_articles: related_articles,
       is_draft_preview: not article.is_published and is_admin,
       is_admin: is_admin,
       error: nil
     )}
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
    # Use published_at if available, otherwise fall back to inserted_at
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

  # Returns the date to display (published_at if available, otherwise inserted_at)
  defp display_date(article) do
    article.published_at || article.inserted_at
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-4xl">
        <%= if @error do %>
          <div class="bg-gray-50 rounded-lg p-8 text-center">
            <div class="mb-4">
              <svg
                class="w-16 h-16 mx-auto text-gray-400"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M12 12h.01M12 12h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
            </div>
            <h1 class="text-2xl font-bold text-gray-700 mb-2">Article Not Found</h1>
            <p class="text-gray-600 mb-4">{@error}</p>
            <.link href={~p"/articles"} class="hover:underline">
              Browse all articles
            </.link>
          </div>
        <% else %>
          <%!-- Draft preview banner --%>
          <div
            :if={@is_draft_preview}
            class="mb-6 px-4 py-3 bg-yellow-100 border border-yellow-300 rounded-lg"
          >
            <div class="flex items-center gap-2 text-yellow-800">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                />
              </svg>
              <span class="font-medium">Draft Preview</span>
              <span class="text-sm">
                — This article is not published and only visible to administrators.
              </span>
            </div>
          </div>

          <%!-- Back link --%>
          <div class="mb-6">
            <.link
              href={~p"/articles"}
              class="hover:underline inline-flex items-center gap-1"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 19l-7-7 7-7"
                />
              </svg>
              Back to Articles
            </.link>
          </div>

          <%!-- Article header --%>
          <header class="mb-8">
            <h1 class="text-3xl font-bold text-gf-maroon mb-4">
              <span class="inline-flex items-center gap-3">
                {@article.title}
                <.link
                  :if={@is_admin}
                  navigate={~p"/admin/articles/#{@article.id}"}
                  class="text-gray-400 hover:text-gf-maroon"
                  title="Edit in admin"
                >
                  <.icon name="ph-pencil-simple" class="h-5 w-5" />
                </.link>
              </span>
            </h1>
            <div class="flex flex-wrap items-center gap-4 text-gray-600">
              <span>By {@article.author}</span>
              <span>•</span>
              <span>{format_date(display_date(@article))}</span>
              <span :if={@article.updated_at != @article.inserted_at} class="text-sm text-gray-500">
                (Updated {format_date(@article.updated_at)})
              </span>
            </div>
            <div :if={@article.tags != []} class="flex flex-wrap gap-2 mt-4">
              <.link
                :for={tag <- @article.tags}
                href={~p"/articles?tag=#{tag}"}
                class="px-3 py-1 bg-gray-100 text-gray-700 text-sm rounded-full hover:bg-gray-200 transition-colors"
              >
                {tag}
              </.link>
            </div>
          </header>

          <%!-- Article content --%>
          <article class="prose prose-lg max-w-none">
            {Phoenix.HTML.raw(@rendered_content)}
          </article>

          <%!-- Related articles --%>
          <aside :if={@related_articles != []} class="mt-12 pt-8 border-t border-gray-200">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">Related Articles</h2>
            <div class="space-y-4">
              <.link
                :for={related <- @related_articles}
                navigate={~p"/articles/#{related.slug}"}
                class="block p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
              >
                <h3 class="font-medium hover:underline">{related.title}</h3>
                <p class="text-sm text-gray-500 mt-1">By {related.author}</p>
              </.link>
            </div>
          </aside>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
