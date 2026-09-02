defmodule GallformersWeb.Admin.ArticleLive.Index do
  @moduledoc """
  Admin page for listing and managing reference articles.
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
      |> assign(:delete_article, nil)
      |> assign(:delete_confirmation, "")

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
  def handle_event("delete", %{"id" => id}, socket) do
    article = Articles.get_article!(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:delete_article, article)
     |> assign(:delete_confirmation, "")}
  end

  @impl true
  def handle_event("update_delete_confirmation", %{"value" => value}, socket) do
    {:noreply, assign(socket, :delete_confirmation, value)}
  end

  @impl true
  def handle_event("confirm_delete", %{"confirmation" => confirmation}, socket) do
    selected_article = socket.assigns.delete_article

    case selected_article && Articles.get_article(selected_article.id) do
      nil ->
        {:noreply,
         socket
         |> assign(:delete_article, nil)
         |> assign(:delete_confirmation, "")
         |> put_flash(:info, "Article already deleted")
         |> reload_articles()}

      article when confirmation != article.title ->
        {:noreply,
         put_flash(socket, :error, "Title does not match. Type the exact article title.")}

      article ->
        case Articles.delete_article(article) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:delete_article, nil)
             |> assign(:delete_confirmation, "")
             |> put_flash(:info, "Article deleted.")
             |> reload_articles()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete article.")}
        end
    end
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:delete_article, nil)
     |> assign(:delete_confirmation, "")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Articles">
      <div class="space-y-6">
        <%!-- Header with filters and new button --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div class="flex flex-1 gap-3 max-w-2xl">
            <form phx-change="search" phx-submit="search" id="article-search-form" class="flex-1">
              <.search_input
                id="article-search"
                name="query"
                value={@search_query}
                placeholder="Filter by title or author..."
                phx-debounce="300"
              />
            </form>
            <form phx-change="filter_tag" id="article-tag-filter" class="w-48">
              <.input
                type="select"
                name="tag"
                prompt="All Tags"
                options={Enum.map(@all_tags, &{&1, &1})}
                value={@tag_filter}
              />
            </form>
            <form phx-change="filter_status" id="article-status-filter" class="w-40">
              <.input
                type="select"
                name="status"
                prompt="All Status"
                options={[{"Published", "published"}, {"Draft", "draft"}]}
                value={@status_filter}
              />
            </form>
          </div>
          <.link navigate={~p"/admin/articles/new"} class="gf-btn gf-btn-primary">
            New Article
          </.link>
        </div>

        <%!-- Articles Table --%>
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <%= if @filtered_articles == [] do %>
            <div class="p-8 text-center text-gray-500">
              <.icon name="ph-article" class="h-12 w-12 mx-auto text-gray-300 mb-4" />
              <%= if @articles == [] do %>
                <p>No articles yet. Create your first article to get started.</p>
              <% else %>
                <p>No articles match your filters. Try a different search term or tag.</p>
              <% end %>
            </div>
          <% else %>
            <table class="gf-table gf-table-dark gf-table-compact">
              <thead>
                <tr>
                  <th>Title</th>
                  <th>Author</th>
                  <th>Status</th>
                  <th>Tags</th>
                  <th>Updated</th>
                  <th class="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={article <- @filtered_articles}>
                  <td>
                    <.link
                      navigate={~p"/admin/articles/#{article.id}"}
                      class="font-medium hover:underline"
                    >
                      {article.title}
                    </.link>
                  </td>
                  <td class="text-gray-600">{article.author}</td>
                  <td>
                    <%= if article.is_published do %>
                      <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800">
                        Published
                      </span>
                    <% else %>
                      <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800">
                        Draft
                      </span>
                    <% end %>
                  </td>
                  <td class="text-gray-600 text-sm">
                    <%= if article.tags != [] do %>
                      {Enum.join(article.tags, ", ")}
                    <% else %>
                      <span class="text-gray-400">-</span>
                    <% end %>
                  </td>
                  <td class="text-gray-600 text-sm">{format_date(article.updated_at, :short)}</td>
                  <td class="text-right">
                    <.table_actions>
                      <.action_button
                        icon="ph-pencil-simple"
                        label="Edit"
                        variant="primary"
                        navigate={~p"/admin/articles/#{article.id}"}
                      />
                      <.action_button
                        icon="ph-arrow-square-out"
                        label={if article.is_published, do: "View", else: "Preview"}
                        href={~p"/articles/#{article.slug}"}
                        target="_blank"
                      />
                      <.action_button
                        icon="ph-trash"
                        label="Delete"
                        variant="danger"
                        phx-click="delete"
                        phx-value-id={article.id}
                      />
                    </.table_actions>
                  </td>
                </tr>
              </tbody>
            </table>
          <% end %>
        </div>

        <p class="text-sm text-gray-500">
          Showing {length(@filtered_articles)} of {length(@articles)} article{if length(@articles) !=
                                                                                   1,
                                                                                 do: "s",
                                                                                 else: ""}
        </p>
      </div>

      <.dangerous_delete_modal
        :if={@delete_article}
        show
        item_type="article"
        item_name={@delete_article.title}
        consequences={[
          "The article content, publication state, and tags will be permanently deleted.",
          "All images owned by this article will be deleted from storage."
        ]}
        confirmation_value={@delete_confirmation}
      />
    </Layouts.admin>
    """
  end

  defp reload_articles(socket) do
    socket
    |> assign(:articles, Articles.list_articles())
    |> assign(:all_tags, Articles.list_all_tags())
    |> apply_filters()
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
