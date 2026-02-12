defmodule GallformersWeb.Admin.PlaceLive.Index do
  @moduledoc """
  Admin page for listing and managing geographic places.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Places

  @page_size 50

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    if connected?(socket), do: Places.subscribe()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Places")
      |> assign(:search_query, "")
      |> assign(:current_page, 1)
      |> assign(:page_size, @page_size)
      |> load_places()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Places")
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:current_page, 1)
      |> load_places()

    {:noreply, socket}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    page = max(1, min(page, total_pages(socket.assigns.places, socket.assigns.page_size)))
    {:noreply, assign(socket, current_page: page)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    place = Places.get_place!(String.to_integer(id))

    case Places.delete_place(place) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Place deleted successfully")
         |> load_places()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete place")}
    end
  end

  @impl true
  def handle_info({event, _place}, socket)
      when event in [:place_created, :place_updated, :place_deleted] do
    {:noreply, load_places(socket)}
  end

  defp load_places(socket) do
    places =
      case socket.assigns.search_query do
        "" -> Places.list_all_places()
        query -> Places.search_places(query, 500)
      end

    assign(socket, :places, places)
  end

  defp paginated(list, current_page, page_size) do
    list
    |> Enum.drop((current_page - 1) * page_size)
    |> Enum.take(page_size)
  end

  defp total_pages(list, page_size) do
    max(1, ceil(length(list) / page_size))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Places">
      <div class="space-y-6">
        <%!-- Header with search and new button --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div class="flex-1 max-w-xl">
            <form phx-change="search" phx-submit="search" id="place-search-form">
              <.search_input
                id="place-search"
                name="query"
                value={@search_query}
                placeholder="Search places..."
                phx-debounce="300"
              />
            </form>
          </div>
          <.link navigate={~p"/admin/places/new"} class="gf-btn gf-btn-primary">
            New Place
          </.link>
        </div>

        <%!-- Place list table --%>
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <table class="gf-table gf-table-dark">
            <thead>
              <tr>
                <th>Name</th>
                <th>Code</th>
                <th>Type</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={place <- paginated(@places, @current_page, @page_size)}>
                <td>
                  <.link
                    navigate={~p"/admin/places/#{place.id}"}
                    class="hover:underline font-medium"
                  >
                    {place.name}
                  </.link>
                </td>
                <td>
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                    {place.code}
                  </span>
                </td>
                <td class="text-gray-500">
                  {place.type}
                </td>
                <td class="text-right">
                  <.table_actions>
                    <.action_button
                      icon="ph-pencil-simple"
                      label="Edit"
                      navigate={~p"/admin/places/#{place.id}"}
                      variant="primary"
                    />
                    <.action_button
                      icon="ph-arrow-square-out"
                      label="View"
                      href={~p"/place/#{place.id}"}
                      target="_blank"
                    />
                    <.action_button
                      icon="ph-trash"
                      label="Delete"
                      variant="danger"
                      phx-click="delete"
                      phx-value-id={place.id}
                      confirm="Are you sure? This will remove all species range associations for this place."
                    />
                  </.table_actions>
                </td>
              </tr>
              <tr :if={@places == []}>
                <td colspan="4" class="px-6 py-8 text-center text-gray-500">
                  No places found. Try a different search term.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%= if total_pages(@places, @page_size) > 1 do %>
          <.pagination
            page={@current_page}
            total_pages={total_pages(@places, @page_size)}
            total_items={length(@places)}
            page_size={@page_size}
            on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
          />
        <% else %>
          <p class="text-sm text-gray-500">
            Showing {length(@places)} places
          </p>
        <% end %>
      </div>
    </Layouts.admin>
    """
  end
end
