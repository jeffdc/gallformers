defmodule GallformersWeb.Admin.GallLive.Index do
  @moduledoc """
  Admin page for listing and searching galls.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Galls
  alias Gallformers.Species

  @page_size 50

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    if connected?(socket), do: Species.subscribe()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Galls")
      |> assign(:search_query, "")
      |> assign(:current_page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:gall_list, list_galls(""))

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Galls")
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    gall_list = list_galls(query)
    {:noreply, assign(socket, gall_list: gall_list, search_query: query, current_page: 1)}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    page = max(1, min(page, total_pages(socket.assigns.gall_list, socket.assigns.page_size)))
    {:noreply, assign(socket, current_page: page)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    species = Species.get_species!(String.to_integer(id))

    case Species.delete_species(species) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gall deleted successfully")
         |> assign(:gall_list, list_galls(socket.assigns.search_query))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete gall")}
    end
  end

  @impl true
  def handle_info({event, _species}, socket)
      when event in [:species_created, :species_updated, :species_deleted] do
    gall_list = list_galls(socket.assigns.search_query)
    {:noreply, assign(socket, gall_list: gall_list)}
  end

  defp list_galls("") do
    Galls.list_galls()
  end

  defp list_galls(query) do
    Species.search_species(query, 500)
    |> Enum.filter(&(&1.taxoncode == "gall"))
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
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Galls">
      <div class="space-y-6">
        <%!-- Header with search and new button --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div class="flex-1 max-w-xl">
            <form phx-change="search" phx-submit="search" id="gall-search-form">
              <.search_input
                id="gall-search"
                name="query"
                value={@search_query}
                placeholder="Filter galls by name or alias..."
                phx-debounce="300"
              />
            </form>
          </div>
          <.link navigate={~p"/admin/galls/new"} class="gf-btn gf-btn-primary">
            New Gall
          </.link>
        </div>

        <%!-- Gall list table --%>
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <table class="gf-table gf-table-dark gf-table-compact">
            <thead>
              <tr>
                <th>Name</th>
                <th class="text-center w-32">Data Complete</th>
                <th class="text-center">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={gall <- paginated(@gall_list, @current_page, @page_size)}>
                <td>
                  <.link
                    navigate={~p"/admin/galls/#{gall.id}"}
                    class="hover:underline font-medium"
                  >
                    <.taxon_name name={gall.name} />
                  </.link>
                </td>
                <td class="text-center">
                  <%= if gall.datacomplete in [true, 1] do %>
                    <span class="text-green-600">
                      <.icon name="ph-check" class="size-5 inline-block" />
                    </span>
                  <% else %>
                    <span class="text-red-500">
                      <.icon name="ph-x" class="size-5 inline-block" />
                    </span>
                  <% end %>
                </td>
                <td class="text-center">
                  <.table_actions>
                    <.action_button
                      icon="ph-pencil-simple"
                      label="Edit"
                      navigate={~p"/admin/galls/#{gall.id}"}
                      variant="primary"
                    />
                    <.action_button
                      icon="ph-image"
                      label="Edit Images"
                      navigate={~p"/admin/images?species_id=#{gall.id}"}
                    />
                    <.action_button
                      icon="gf-host"
                      label="Map Hosts"
                      navigate={~p"/admin/gallhost?id=#{gall.id}"}
                    />
                    <.action_button
                      icon="gf-source"
                      label="Map Sources"
                      navigate={~p"/admin/species-sources/find?species_id=#{gall.id}"}
                    />
                    <.action_button
                      icon="ph-arrow-square-out"
                      label="View"
                      navigate={~p"/gall/#{gall.id}"}
                    />
                    <.action_button
                      icon="ph-trash"
                      label="Delete"
                      variant="danger"
                      phx-click="delete"
                      phx-value-id={gall.id}
                      confirm="Are you sure? This will delete the gall and all its associations."
                    />
                  </.table_actions>
                </td>
              </tr>
              <tr :if={@gall_list == []}>
                <td colspan="3" class="px-6 py-8 text-center text-gray-500">
                  No galls found. Try a different search term.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%= if total_pages(@gall_list, @page_size) > 1 do %>
          <.pagination
            page={@current_page}
            total_pages={total_pages(@gall_list, @page_size)}
            total_items={length(@gall_list)}
            page_size={@page_size}
            on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
          />
        <% else %>
          <p class="text-sm text-gray-500">
            Showing {length(@gall_list)} galls
          </p>
        <% end %>
      </div>
    </Layouts.admin>
    """
  end
end
