defmodule GallformersWeb.Admin.HostLive.Index do
  @moduledoc """
  Admin page for listing and searching host species.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Plants
  alias Gallformers.Species

  @page_size 50

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    if connected?(socket) do
      Plants.subscribe()
      Species.subscribe()
    end

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Hosts")
      |> assign(:search_query, "")
      |> assign(:current_page, 1)
      |> assign(:page_size, @page_size)
      |> load_hosts()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Hosts")
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:current_page, 1)
     |> load_hosts()}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    page = max(1, min(page, total_pages(socket)))
    {:noreply, socket |> assign(:current_page, page) |> load_hosts()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Species.get_species(String.to_integer(id)) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:info, "Host already deleted")
         |> load_hosts()}

      species ->
        case Species.delete_species(species) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Host deleted successfully")
             |> load_hosts()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete host")}
        end
    end
  end

  @impl true
  def handle_info({event, _}, socket)
      when event in [:host_created, :host_updated, :species_deleted] do
    {:noreply, load_hosts(socket)}
  end

  defp load_hosts(socket) do
    %{search_query: query, current_page: page, page_size: page_size} = socket.assigns
    offset = (page - 1) * page_size

    case query do
      "" ->
        socket
        |> assign(:total_count, Plants.count_hosts())
        |> assign(:hosts, Plants.list_hosts_paginated(page_size, offset))

      query ->
        results = Plants.search_hosts(query, 500, include_placeholders: true)

        socket
        |> assign(:total_count, length(results))
        |> assign(:hosts, Enum.drop(results, offset) |> Enum.take(page_size))
    end
  end

  defp total_pages(socket) do
    max(1, ceil(socket.assigns.total_count / socket.assigns.page_size))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Hosts">
      <div class="space-y-6">
        <%!-- Header with search and new button --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div class="flex-1 max-w-xl">
            <form phx-change="search" phx-submit="search" id="host-search-form">
              <.search_input
                id="host-search"
                name="query"
                value={@search_query}
                placeholder="Search hosts by name..."
                phx-debounce="300"
              />
            </form>
          </div>
          <.link navigate={~p"/admin/hosts/new"} class="gf-btn gf-btn-primary">
            New Host
          </.link>
        </div>

        <%!-- Host list table --%>
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <table class="gf-table gf-table-dark gf-table-compact">
            <thead>
              <tr>
                <th>Name</th>
                <th class="text-center w-32">Data Complete</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={host <- @hosts}>
                <td>
                  <.link
                    navigate={~p"/admin/hosts/#{host.id}"}
                    class="hover:underline font-medium"
                  >
                    <.taxon_name name={host.name} />
                  </.link>
                </td>
                <td class="text-center">
                  <%= if host.datacomplete in [true, 1] do %>
                    <span class="text-green-600">
                      <.icon name="ph-check" class="size-5 inline-block" />
                    </span>
                  <% else %>
                    <span class="text-red-500">
                      <.icon name="ph-x" class="size-5 inline-block" />
                    </span>
                  <% end %>
                </td>
                <td class="text-right">
                  <.table_actions>
                    <.action_button
                      icon="ph-pencil-simple"
                      label="Edit"
                      navigate={~p"/admin/hosts/#{host.id}"}
                      variant="primary"
                    />
                    <.action_button
                      icon="ph-image"
                      label="Edit Images"
                      navigate={~p"/admin/images?species_id=#{host.id}"}
                    />
                    <.action_button
                      icon="gf-source"
                      label="Map Sources"
                      navigate={~p"/admin/species-sources/find?species_id=#{host.id}"}
                    />
                    <.action_button
                      icon="ph-arrow-square-out"
                      label="View"
                      navigate={~p"/host/#{host.id}"}
                    />
                    <.action_button
                      icon="ph-trash"
                      label="Delete"
                      variant="danger"
                      phx-click="delete"
                      phx-value-id={host.id}
                      confirm="Are you sure? This will delete the host and all its gall associations."
                    />
                  </.table_actions>
                </td>
              </tr>
              <tr :if={@hosts == []}>
                <td colspan="3" class="px-6 py-8 text-center text-gray-500">
                  No hosts found. Try a different search term.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%= if ceil(@total_count / @page_size) > 1 do %>
          <.pagination
            page={@current_page}
            total_pages={ceil(@total_count / @page_size)}
            total_items={@total_count}
            page_size={@page_size}
            on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
          />
        <% else %>
          <p class="text-sm text-gray-500">
            Showing {@total_count} hosts
          </p>
        <% end %>
      </div>
    </Layouts.admin>
    """
  end
end
