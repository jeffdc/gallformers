defmodule GallformersWeb.PlaceLive do
  @moduledoc """
  LiveView for the geographic place detail page.

  Displays a place (state/province) with its list of host plants.
  """
  use GallformersWeb, :live_view

  alias Phoenix.LiveView.JS

  @page_size 25
  @valid_sort_columns ~w(name aliases)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {place_id, ""} ->
        load_place(socket, place_id)

      _ ->
        {:ok,
         assign(socket,
           page_title: "Place Not Found",
           page_description: "The requested geographic location was not found on Gallformers.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           place: nil,
           error: "Invalid place ID"
         )}
    end
  end

  defp load_place(socket, place_id) do
    case Gallformers.Places.get_place(place_id) do
      nil ->
        {:ok,
         assign(socket,
           page_title: "Place Not Found",
           page_description: "The requested geographic location was not found on Gallformers.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           place: nil,
           error: "Place not found"
         )}

      place ->
        # Get parent place via place_hierarchy join table
        parent = Gallformers.Places.get_parent_place(place_id)

        # Get hosts for this place
        hosts = Gallformers.Ranges.get_hosts_for_place(place_id)

        {:ok,
         assign(socket,
           page_title: place.name,
           page_description:
             "#{place.name} - Host plants found in this geographic location on Gallformers.",
           page_url: "/place/#{place_id}",
           page_image: nil,
           page_json_ld: nil,
           page_noindex: false,
           place: place,
           parent: parent,
           hosts: hosts,
           search_query: "",
           current_page: 1,
           page_size: @page_size,
           sort_by: :name,
           sort_dir: :asc,
           error: nil
         )}
    end
  end

  defp format_parent_info(place, parent) do
    if parent do
      article = if parent.name == "United States", do: "the ", else: ""
      "a #{place.type} of #{article}#{parent.name}"
    else
      ""
    end
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, search_query: query, current_page: 1)}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    filtered = filtered_hosts(socket.assigns.hosts, socket.assigns.search_query)
    page = max(1, min(page, total_pages(filtered, socket.assigns.page_size)))
    {:noreply, assign(socket, current_page: page)}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket) when column in @valid_sort_columns do
    column_atom = String.to_existing_atom(column)

    {new_sort_by, new_sort_dir} =
      if socket.assigns.sort_by == column_atom do
        new_dir = if socket.assigns.sort_dir == :asc, do: :desc, else: :asc
        {column_atom, new_dir}
      else
        {column_atom, :asc}
      end

    {:noreply,
     socket
     |> assign(:sort_by, new_sort_by)
     |> assign(:sort_dir, new_sort_dir)
     |> assign(:current_page, 1)}
  end

  defp filtered_hosts(hosts, ""), do: hosts

  defp filtered_hosts(hosts, query) do
    query_down = String.downcase(query)

    Enum.filter(hosts, fn host ->
      name_matches = String.contains?(String.downcase(host.name), query_down)
      aliases_match = host.aliases && String.contains?(String.downcase(host.aliases), query_down)
      name_matches or aliases_match
    end)
  end

  defp paginated_hosts(hosts, current_page, page_size, sort_by, sort_dir) do
    hosts
    |> sorted_hosts(sort_by, sort_dir)
    |> Enum.drop((current_page - 1) * page_size)
    |> Enum.take(page_size)
  end

  defp sorted_hosts(hosts, sort_by, sort_dir) do
    sorted = Enum.sort_by(hosts, &sort_key(&1, sort_by))
    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp sort_key(host, :name), do: normalize_for_sort(host.name)
  defp sort_key(host, :aliases), do: normalize_for_sort(host.aliases)

  defp normalize_for_sort(nil), do: ""
  defp normalize_for_sort(value) when is_binary(value), do: String.downcase(value)
  defp normalize_for_sort(value), do: value

  defp total_pages(hosts, page_size) do
    max(1, ceil(length(hosts) / page_size))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-7xl">
        <%= if @error do %>
          <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">{@error}</div>
        <% else %>
          <%= if @place do %>
            <%!-- Header --%>
            <div class="mb-6">
              <div class="flex items-center justify-between mb-2">
                <div class="flex items-center gap-2">
                  <h1 class="text-2xl font-bold text-gf-maroon">
                    {@place.name} - {@place.code}
                  </h1>
                  <.link
                    :if={@current_user}
                    href={~p"/admin/places/#{@place.id}"}
                    class="text-gray-400 hover:text-gf-maroon"
                    title="Edit in admin"
                  >
                    <.icon name="ph-pencil-simple" class="h-5 w-5" />
                  </.link>
                </div>
              </div>

              <%!-- Parent info --%>
              <p :if={@parent} class="text-gray-600">
                {format_parent_info(@place, @parent)}
              </p>
            </div>

            <%!-- Hosts list --%>
            <% filtered = filtered_hosts(@hosts, @search_query) %>
            <div class="mt-6">
              <div class="flex items-center justify-between mb-3">
                <h2 class="text-lg font-semibold text-gray-800">
                  Host Plants ({length(filtered)}{if @search_query != "", do: " of #{length(@hosts)}"})
                </h2>
                <form phx-change="search" class="w-64">
                  <.search_input
                    id="host-search"
                    name="query"
                    value={@search_query}
                    placeholder="Filter hosts..."
                    phx-debounce="200"
                  />
                </form>
              </div>
              <%= if length(filtered) > 0 do %>
                <div class="bg-white rounded border border-gray-200 overflow-hidden">
                  <table class="gf-table">
                    <thead>
                      <tr>
                        <th class="sortable cursor-pointer" phx-click="sort" phx-value-column="name">
                          Species Name
                          <span :if={@sort_by == :name} class="ml-1">
                            {if @sort_dir == :asc, do: "↑", else: "↓"}
                          </span>
                        </th>
                        <th
                          class="sortable cursor-pointer"
                          phx-click="sort"
                          phx-value-column="aliases"
                        >
                          Aliases
                          <span :if={@sort_by == :aliases} class="ml-1">
                            {if @sort_dir == :asc, do: "↑", else: "↓"}
                          </span>
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr :for={
                        host <-
                          paginated_hosts(filtered, @current_page, @page_size, @sort_by, @sort_dir)
                      }>
                        <td>
                          <.link
                            href={"/host/#{host.id}"}
                            class="hover:underline"
                          >
                            <em>{host.name}</em>
                          </.link>
                        </td>
                        <td class="text-gray-600">{host.aliases}</td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <.pagination
                  :if={total_pages(filtered, @page_size) > 1}
                  page={@current_page}
                  total_pages={total_pages(filtered, @page_size)}
                  total_items={length(filtered)}
                  page_size={@page_size}
                  on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
                  class="mt-4"
                />
              <% else %>
                <%= if @search_query != "" do %>
                  <p class="text-gray-500 italic">No hosts match "{@search_query}".</p>
                <% else %>
                  <p class="text-gray-500 italic">No host plants found for this location.</p>
                <% end %>
              <% end %>
            </div>
          <% else %>
            <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
              Place not found
            </div>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
