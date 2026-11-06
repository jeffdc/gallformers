defmodule GallformersWeb.Admin.ArticleLive.Index do
  @moduledoc """
  The articles admin list (design system matter bc0d, the admin list
  pattern): every article with its status, tags and public page, filtered
  by title or author, tag and status. Deleting is on the edit page.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Articles

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]
    articles = Articles.list_articles()
    all_tags = Articles.list_all_tags()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Articles")
      |> assign(:articles, articles)
      |> assign(:filtered_articles, articles)
      |> assign(:search_query, "")
      |> assign(:tag_filter, "")
      |> assign(:status_filter, "")
      |> assign(:all_tags, all_tags)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Articles")
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:search_query, query) |> apply_filters()}
  end

  @impl true
  def handle_event("filter_tag", %{"tag" => tag}, socket) do
    {:noreply, socket |> assign(:tag_filter, tag) |> apply_filters()}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:status_filter, status) |> apply_filters()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:title>Articles</:title>
          <:meta label="Articles">{length(@articles)}</:meta>
          <:description>
            Long-form pages on galls and gall study, listed on the site's Articles page once published.
          </:description>
          <:action>
            <.button navigate={~p"/admin/articles/new"} variant="primary" icon="ph-plus">
              New article
            </.button>
          </:action>
        </.page_header>

        <div class="flex flex-wrap items-end gap-3">
          <form
            id="article-search-form"
            phx-change="search"
            phx-submit="search"
            class="w-80 max-w-full"
          >
            <.search_field
              id="article-search"
              name="query"
              value={@search_query}
              label="Filter the articles"
              placeholder="Title or author"
            />
          </form>
          <.filter_select
            id="article-tag-filter"
            name="tag"
            label="Tag"
            prompt="Every tag"
            value={@tag_filter}
            options={Enum.map(@all_tags, &{&1, &1})}
            class="w-48"
            phx-change="filter_tag"
          />
          <.filter_select
            id="article-status-filter"
            name="status"
            label="Status"
            prompt="Any status"
            value={@status_filter}
            options={[{"Published", "published"}, {"Draft", "draft"}]}
            class="w-40"
            phx-change="filter_status"
          />
          <span class="pb-2 text-meta text-muted">
            {length(@filtered_articles)} of {length(@articles)}
          </span>
        </div>

        <.data_table
          id="articles"
          rows={@filtered_articles}
          row_id={&"articles-#{&1.id}"}
          compact
        >
          <:col :let={article} label="Title" grow>
            <.link navigate={~p"/admin/articles/#{article.id}"} class="font-semibold">
              {article.title}
            </.link>
          </:col>
          <:col :let={article} label="Author" hide_below={:md}>
            <span class="text-ink-2">{article.author}</span>
          </:col>
          <:col :let={article} label="Status">
            <span data-status>
              <.chip :if={article.is_published} variant={:ok} size="sm">Published</.chip>
              <.chip :if={!article.is_published} variant={:warn} size="sm">Draft</.chip>
            </span>
          </:col>
          <:col :let={article} label="Tags" hide_below={:lg}>
            <span class="text-meta text-muted">{Enum.join(article.tags, ", ")}</span>
          </:col>
          <:col :let={article} label="Updated" hide_below={:md}>
            <span class="text-meta text-muted">{format_date(article.updated_at, :short)}</span>
          </:col>
          <:col :let={article} label="On the site">
            <.link href={~p"/articles/#{article.slug}"} target="_blank">
              {if article.is_published, do: "View", else: "Preview"} ↗
            </.link>
          </:col>
          <:empty>
            {if @articles == [],
              do: "No articles yet. Start one with New article.",
              else: "No articles match these filters."}
          </:empty>
        </.data_table>
      </div>
    </Layouts.admin>
    """
  end

  defp apply_filters(socket) do
    articles = socket.assigns.articles
    search_query = socket.assigns.search_query
    tag_filter = socket.assigns.tag_filter
    status_filter = socket.assigns.status_filter

    filtered =
      articles
      |> filter_by_search(search_query)
      |> filter_by_tag(tag_filter)
      |> filter_by_status(status_filter)

    assign(socket, :filtered_articles, filtered)
  end

  defp filter_by_search(articles, ""), do: articles

  defp filter_by_search(articles, query) do
    query_lower = String.downcase(query)

    Enum.filter(articles, fn article ->
      String.contains?(String.downcase(article.title || ""), query_lower) ||
        String.contains?(String.downcase(article.author || ""), query_lower)
    end)
  end

  defp filter_by_tag(articles, ""), do: articles

  defp filter_by_tag(articles, tag) do
    Enum.filter(articles, fn article ->
      tag in (article.tags || [])
    end)
  end

  defp filter_by_status(articles, ""), do: articles

  defp filter_by_status(articles, "published") do
    Enum.filter(articles, fn article -> article.is_published end)
  end

  defp filter_by_status(articles, "draft") do
    Enum.filter(articles, fn article -> not article.is_published end)
  end
end
