defmodule GallformersWeb.Admin.SourceLive.Index do
  @moduledoc """
  Admin page for listing and searching scientific sources/references.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Sources

  @page_size 50
  @valid_sort_columns ~w(title author pubyear datacomplete)

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    if connected?(socket), do: Sources.subscribe()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Sources")
      |> assign(:search_query, "")
      |> assign(:current_page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:sort_by, :title)
      |> assign(:sort_dir, :asc)
      |> load_sources()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Sources")
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:current_page, 1)
      |> load_sources()

    {:noreply, socket}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    page = max(1, min(page, total_pages(socket.assigns.sources, socket.assigns.page_size)))
    {:noreply, assign(socket, current_page: page)}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket) when column in @valid_sort_columns do
    column_atom = String.to_atom(column)

    {new_sort_by, new_sort_dir} =
      if socket.assigns.sort_by == column_atom do
        new_dir = if socket.assigns.sort_dir == :asc, do: :desc, else: :asc
        {column_atom, new_dir}
      else
        {column_atom, :asc}
      end

    {:noreply, assign(socket, sort_by: new_sort_by, sort_dir: new_sort_dir, current_page: 1)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    source = Sources.get_source!(String.to_integer(id))

    case Sources.delete_source(source) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Source deleted successfully")
         |> load_sources()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete source")}
    end
  end

  @impl true
  def handle_info({event, _source}, socket)
      when event in [:source_created, :source_updated, :source_deleted] do
    {:noreply, load_sources(socket)}
  end

  defp load_sources(socket) do
    sources =
      case socket.assigns.search_query do
        "" -> Sources.list_sources()
        query -> Sources.search_sources(query)
      end

    assign(socket, :sources, sources)
  end

  defp paginated_sources(sources, current_page, page_size, sort_by, sort_dir) do
    sources
    |> sorted_sources(sort_by, sort_dir)
    |> Enum.drop((current_page - 1) * page_size)
    |> Enum.take(page_size)
  end

  defp total_pages(list, page_size) do
    max(1, ceil(length(list) / page_size))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Sources">
      <div class="space-y-6">
        <%!-- Header with search and new button --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div class="flex-1 max-w-xl">
            <form phx-change="search" phx-submit="search" id="source-search-form">
              <.search_input
                id="source-search"
                name="query"
                value={@search_query}
                placeholder="Search sources by title or author..."
                phx-debounce="300"
              />
            </form>
          </div>
          <.link navigate={~p"/admin/sources/new"} class="gf-btn gf-btn-primary">
            New Source
          </.link>
        </div>

        <%!-- Source list table --%>
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <table class="gf-table gf-table-dark">
            <thead>
              <tr>
                <th class="sortable" phx-click="sort" phx-value-column="title">
                  Title
                  <span :if={@sort_by == :title} class="ml-1">
                    {if @sort_dir == :asc, do: "↑", else: "↓"}
                  </span>
                </th>
                <th class="sortable" phx-click="sort" phx-value-column="author">
                  Author
                  <span :if={@sort_by == :author} class="ml-1">
                    {if @sort_dir == :asc, do: "↑", else: "↓"}
                  </span>
                </th>
                <th class="sortable" phx-click="sort" phx-value-column="pubyear">
                  Year
                  <span :if={@sort_by == :pubyear} class="ml-1">
                    {if @sort_dir == :asc, do: "↑", else: "↓"}
                  </span>
                </th>
                <th class="sortable" phx-click="sort" phx-value-column="datacomplete">
                  Complete
                  <span :if={@sort_by == :datacomplete} class="ml-1">
                    {if @sort_dir == :asc, do: "↑", else: "↓"}
                  </span>
                </th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={
                source <-
                  paginated_sources(@sources, @current_page, @page_size, @sort_by, @sort_dir)
              }>
                <td>
                  <.link
                    navigate={~p"/admin/sources/#{source.id}"}
                    class="hover:underline font-medium"
                  >
                    {truncate(source.title, 60)}
                  </.link>
                </td>
                <td class="text-gray-500">
                  {truncate(source.author, 30)}
                </td>
                <td class="text-gray-500">
                  {source.pubyear}
                </td>
                <td>
                  <%= if source.datacomplete do %>
                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                      Yes
                    </span>
                  <% else %>
                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                      No
                    </span>
                  <% end %>
                </td>
                <td class="text-right">
                  <.table_actions>
                    <.action_button
                      icon="ph-pencil-simple"
                      label="Edit"
                      navigate={~p"/admin/sources/#{source.id}"}
                      variant="primary"
                    />
                    <.action_button
                      icon="ph-dna"
                      label="Map Species"
                      navigate={~p"/admin/species-sources/add?source_id=#{source.id}"}
                      variant="primary"
                    />
                    <.action_button
                      icon="ph-arrow-square-out"
                      label="View"
                      navigate={~p"/source/#{source.id}"}
                    />
                    <.action_button
                      icon="ph-trash"
                      label="Delete"
                      variant="danger"
                      phx-click="delete"
                      phx-value-id={source.id}
                      confirm="Are you sure? This will remove all species associations."
                    />
                  </.table_actions>
                </td>
              </tr>
              <tr :if={@sources == []}>
                <td colspan="5" class="px-6 py-8 text-center text-gray-500">
                  No sources found. Try a different search term.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%= if total_pages(@sources, @page_size) > 1 do %>
          <.pagination
            page={@current_page}
            total_pages={total_pages(@sources, @page_size)}
            total_items={length(@sources)}
            page_size={@page_size}
            on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
          />
        <% else %>
          <p class="text-sm text-gray-500">
            Showing {length(@sources)} sources
          </p>
        <% end %>
      </div>
    </Layouts.admin>
    """
  end

  defp sorted_sources(sources, sort_by, sort_dir) do
    sorted = Enum.sort_by(sources, &sort_key(&1, sort_by))
    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp sort_key(source, :title), do: normalize_for_sort(strip_leading_quotes(source.title))
  defp sort_key(source, :author), do: normalize_for_sort(source.author)
  defp sort_key(source, :pubyear), do: normalize_for_sort(source.pubyear)
  defp sort_key(source, :datacomplete), do: normalize_for_sort(source.datacomplete)
  defp sort_key(source, _), do: normalize_for_sort(strip_leading_quotes(source.title))

  defp normalize_for_sort(value) when is_binary(value), do: String.downcase(value)
  defp normalize_for_sort(true), do: 1
  defp normalize_for_sort(false), do: 0
  defp normalize_for_sort(nil), do: ""
  defp normalize_for_sort(value), do: value

  # Strip leading quotes and apostrophes for sorting purposes
  defp strip_leading_quotes(nil), do: ""
  defp strip_leading_quotes(str), do: String.replace(str, ~r/^["']+/, "")

  defp truncate(nil, _), do: ""

  defp truncate(string, max_length) do
    if String.length(string) > max_length do
      String.slice(string, 0, max_length) <> "..."
    else
      string
    end
  end
end
