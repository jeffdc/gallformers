defmodule GallformersWeb.Admin.GallLive.Index do
  @moduledoc """
  The Gall page's search (matter a856, Task 7): Galls found as the global
  search finds them (`Gallformers.Catalog.search_galls/2` — the name shown,
  aliases, the Inducer's names), a page at a time, each linking to its Gall
  page (`GallformersWeb.Admin.GallLive.Edit`). The query is kept in the URL
  (`?q=`). Galls arrive with imports: there is no "new" and no delete.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Galls")
     |> assign(:page_size, @page_size)
     |> assign(:page, 1)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    query = params["q"] || ""

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:page, 1)
     |> assign(:results, Catalog.search_galls(query))}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/galls?#{[q: query]}", replace: true)}
  end

  def handle_event("page", %{"page" => page}, socket) do
    page = page |> max(1) |> min(total_pages(length(socket.assigns.results)))
    {:noreply, assign(socket, :page, page)}
  end

  defp total_pages(total), do: max(1, ceil(total / @page_size))

  defp page_of(results, page),
    do: results |> Enum.drop((page - 1) * @page_size) |> Enum.take(@page_size)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :total, length(assigns.results))

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Galls">
      <div class="space-y-6">
        <p class="text-sm text-gray-600">
          Galls arrive with imports. Find one here to edit its editorial fields, its name, its
          images, its Gallformers note and its range exclusions.
        </p>

        <div class="max-w-xl">
          <form id="gall-search-form" phx-change="search" phx-submit="search">
            <.search_input
              id="gall-search"
              name="query"
              value={@query}
              placeholder="Search galls by name, alias or inducer..."
              phx-debounce="300"
            />
          </form>
        </div>

        <div class="bg-white shadow rounded-lg overflow-hidden">
          <table id="galls-table" class="gf-table gf-table-dark">
            <thead>
              <tr>
                <th>Name</th>
                <th>Also known as</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={gall <- page_of(@results, @page)} id={"gall-#{gall.id}"}>
                <td>
                  <.link
                    navigate={~p"/admin/galls/#{gall.id}"}
                    class="hover:underline font-medium italic"
                  >
                    {gall.name}
                  </.link>
                </td>
                <td class="text-gray-500">{Enum.join(gall.aliases, ", ")}</td>
                <td>
                  <.badge :if={gall.undescribed} variant="warning">Undescribed</.badge>
                </td>
              </tr>
              <tr :if={@results == []}>
                <td colspan="3" class="px-6 py-8 text-center text-gray-500">
                  {if String.trim(@query) == "",
                    do: "Search for a gall to edit.",
                    else: "No galls found. Try a different search term."}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.pagination
          :if={total_pages(@total) > 1}
          page={@page}
          total_pages={total_pages(@total)}
          total_items={@total}
          page_size={@page_size}
          on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
        />
        <p :if={@total > 0 and total_pages(@total) <= 1} class="text-sm text-gray-500">
          Showing {@total} galls
        </p>
      </div>
    </Layouts.admin>
    """
  end
end
