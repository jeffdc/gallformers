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
      |> assign(:delete_gall, nil)
      |> assign(:delete_confirmation, "")
      |> load_galls()

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
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:current_page, 1)
     |> load_galls()}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    page = max(1, min(page, total_pages(socket)))
    {:noreply, socket |> assign(:current_page, page) |> load_galls()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Species.get_species(String.to_integer(id)) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:info, "Gall already deleted")
         |> load_galls()}

      gall ->
        {:noreply,
         socket
         |> assign(:delete_gall, gall)
         |> assign(:delete_confirmation, "")}
    end
  end

  @impl true
  def handle_event("update_delete_confirmation", %{"value" => value}, socket) do
    {:noreply, assign(socket, :delete_confirmation, value)}
  end

  @impl true
  def handle_event("confirm_delete", %{"confirmation" => confirmation}, socket) do
    selected_gall = socket.assigns.delete_gall

    case selected_gall && Species.get_species(selected_gall.id) do
      nil ->
        {:noreply,
         socket
         |> assign(:delete_gall, nil)
         |> assign(:delete_confirmation, "")
         |> put_flash(:info, "Gall already deleted")
         |> load_galls()}

      gall when confirmation != gall.name ->
        {:noreply, put_flash(socket, :error, "Name does not match. Type the exact gall name.")}

      gall ->
        case Species.delete_species(gall) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:delete_gall, nil)
             |> assign(:delete_confirmation, "")
             |> put_flash(:info, "Gall deleted successfully")
             |> load_galls()}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to delete gall")}
        end
    end
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:delete_gall, nil)
     |> assign(:delete_confirmation, "")}
  end

  @impl true
  def handle_info({event, _species}, socket)
      when event in [:species_created, :species_updated, :species_deleted] do
    {:noreply, load_galls(socket)}
  end

  defp load_galls(socket) do
    %{search_query: query, current_page: page, page_size: page_size} = socket.assigns
    offset = (page - 1) * page_size

    case query do
      "" ->
        socket
        |> assign(:total_count, Galls.count_galls())
        |> assign(:gall_list, Galls.list_galls_paginated(page_size, offset))

      query ->
        results =
          Species.search_species(query, 500)
          |> Enum.filter(&(&1.taxoncode == "gall"))

        socket
        |> assign(:total_count, length(results))
        |> assign(:gall_list, Enum.drop(results, offset) |> Enum.take(page_size))
    end
  end

  defp total_pages(socket) do
    max(1, ceil(socket.assigns.total_count / socket.assigns.page_size))
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
              <tr :for={gall <- @gall_list}>
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
            Showing {@total_count} galls
          </p>
        <% end %>
        <.dangerous_delete_modal
          :if={@delete_gall}
          show
          item_type="gall"
          item_name={@delete_gall.name}
          consequences={[
            "All uploaded images will be deleted from storage.",
            "Host, source, taxonomy, range, alias, and trait records associated with this gall will be removed."
          ]}
          confirmation_value={@delete_confirmation}
        />
      </div>
    </Layouts.admin>
    """
  end
end
