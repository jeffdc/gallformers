defmodule GallformersWeb.Admin.SourceLive.Index do
  @moduledoc """
  The Source editor's list (matter a856, Task 10): the Sources by title,
  searched by title or author and paginated, each linking to its editor.
  Sources are created by imports; there is no "new" and no delete.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Sources

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sources")
     |> assign(:query, "")
     |> assign(:page, 1)
     |> assign(:page_size, @page_size)
     |> load_sources()}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(query: query, page: 1) |> load_sources()}
  end

  def handle_event("page", %{"page" => page}, socket) do
    page = page |> max(1) |> min(total_pages(socket.assigns.total, @page_size))
    {:noreply, socket |> assign(:page, page) |> load_sources()}
  end

  defp load_sources(socket) do
    %{entries: sources, total: total} =
      Sources.list_sources_page(
        query: socket.assigns.query,
        page: socket.assigns.page,
        page_size: @page_size
      )

    assign(socket, sources: sources, total: total)
  end

  defp total_pages(total, page_size), do: max(1, ceil(total / page_size))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Sources">
      <div class="space-y-6">
        <p class="text-sm text-gray-600">
          Sources arrive with imports. Here you can correct a Source's details, or mark it
          retracted by a retraction notice (and undo that).
        </p>

        <div class="max-w-xl">
          <form id="source-search-form" phx-change="search" phx-submit="search">
            <.search_input
              id="source-search"
              name="query"
              value={@query}
              placeholder="Search sources by title or author..."
              phx-debounce="300"
            />
          </form>
        </div>

        <div class="bg-white shadow rounded-lg overflow-hidden">
          <table id="sources-table" class="gf-table gf-table-dark">
            <thead>
              <tr>
                <th>Title</th>
                <th>Author</th>
                <th>Year</th>
                <th>Kind</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={source <- @sources} id={"source-#{source.id}"}>
                <td>
                  <.link
                    navigate={~p"/admin/sources/#{source.id}"}
                    class="hover:underline font-medium"
                  >
                    {source.title}
                  </.link>
                </td>
                <td class="text-gray-500">{source.author}</td>
                <td class="text-gray-500">{source.pubyear}</td>
                <td class="text-gray-500">{source.kind}</td>
                <td>
                  <.badge :if={source.retracted_by_id} variant="warning">Retracted</.badge>
                  <.badge :if={!source.retracted_by_id && source.datacomplete} variant="success">
                    Complete
                  </.badge>
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

        <.pagination
          :if={total_pages(@total, @page_size) > 1}
          page={@page}
          total_pages={total_pages(@total, @page_size)}
          total_items={@total}
          page_size={@page_size}
          on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
        />
        <p :if={total_pages(@total, @page_size) <= 1} class="text-sm text-gray-500">
          Showing {@total} sources
        </p>
      </div>
    </Layouts.admin>
    """
  end
end
