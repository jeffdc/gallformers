defmodule GallformersWeb.FamilyLive do
  @moduledoc """
  LiveView for the public family page.

  Displays a family (`Gallformers.Taxa.get_by_name/2`) with its direct
  children (genera and intermediate ranks) in a sortable, filterable table
  with the Galls whose Inducer is under each and the host plants in each,
  and the Galls placed at the family itself (undescribed Galls whose
  Inducer is the family). Data through `GallformersWeb.RankPage`.
  """
  use GallformersWeb, :live_view

  alias GallformersWeb.RankPage
  alias GallformersWeb.RankPageComponents
  alias GallformersWeb.TaxonomyURL

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    case RankPage.lookup(name, :family) do
      {:redirect, path} -> {:ok, push_navigate(socket, to: path, replace: true)}
      {:ok, []} -> {:ok, assign_not_found(socket, "Family not found")}
      {:ok, [family | _]} -> {:ok, load_family(socket, family.id, name)}
    end
  end

  defp load_family(socket, id, name) do
    children = RankPage.children(id)
    galls = RankPage.galls_of_inducers([id])

    assign(socket,
      page_title: name,
      page_description: "#{name} - A taxonomic family documented on Gallformers.",
      page_url: TaxonomyURL.public_path(%{rank: :family, name: name}),
      page_image: nil,
      page_json_ld: nil,
      page_noindex: false,
      taxonomy: %{id: id, name: name, description: RankPage.description(id)},
      children: children,
      filtered_children: children,
      total_children_count: length(children),
      galls: galls,
      search_query: "",
      sort_by: :name,
      sort_dir: :asc,
      error: nil
    )
  end

  defp assign_not_found(socket, error) do
    assign(socket,
      page_title: "Not Found",
      page_description: "The requested taxonomic family was not found on Gallformers.",
      page_url: nil,
      page_image: nil,
      page_json_ld: nil,
      page_noindex: true,
      taxonomy: nil,
      children: [],
      filtered_children: [],
      total_children_count: 0,
      galls: [],
      search_query: "",
      sort_by: :name,
      sort_dir: :asc,
      error: error
    )
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     assign(socket,
       search_query: query,
       filtered_children: RankPage.filter_children(socket.assigns.children, query)
     )}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket)
      when column in ["name", "type", "gall_count", "host_count"] do
    {sort_by, sort_dir} =
      RankPage.toggle_sort(
        socket.assigns.sort_by,
        socket.assigns.sort_dir,
        String.to_existing_atom(column)
      )

    {:noreply, assign(socket, sort_by: sort_by, sort_dir: sort_dir)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-7xl">
        <%= if @error do %>
          <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">{@error}</div>
        <% else %>
          <%= if @taxonomy do %>
            <%!-- Header --%>
            <div class="mb-6">
              <div class="flex items-center gap-2 mb-2">
                <h1 class="text-2xl font-bold text-gf-maroon">
                  <span class="text-lg font-normal text-gray-600">Family:</span>
                  {@taxonomy.name}
                </h1>
                <RankPageComponents.admin_edit_link
                  current_user={@current_user}
                  taxon_id={@taxonomy.id}
                />
              </div>
              <p
                :if={@taxonomy.description not in [nil, ""]}
                class="text-gray-600"
              >
                {@taxonomy.description}
              </p>
            </div>

            <%!-- Children list --%>
            <div class="mt-6">
              <%= if @total_children_count > 0 do %>
                <h2 class="text-lg font-semibold text-gray-800 mb-3">
                  Children ({@total_children_count})
                </h2>

                <%!-- Search box --%>
                <div class="mb-4 max-w-md">
                  <form phx-change="search" phx-submit="search" id="family-search-form">
                    <.search_input
                      id="family-search"
                      name="query"
                      value={@search_query}
                      placeholder="Filter by name, type, or description..."
                      phx-debounce="300"
                    />
                  </form>
                </div>

                <%= if Enum.empty?(@filtered_children) do %>
                  <div class="bg-gray-50 rounded-lg p-8 text-center text-gray-600">
                    <p>No children found matching "{@search_query}"</p>
                  </div>
                <% else %>
                  <div class="bg-white rounded border border-gray-200 overflow-hidden">
                    <table class="gf-table">
                      <thead>
                        <tr>
                          <th class="sortable" phx-click="sort" phx-value-column="name">
                            Name
                            <span :if={@sort_by == :name} class="ml-1">
                              {if @sort_dir == :asc, do: "↑", else: "↓"}
                            </span>
                          </th>
                          <th
                            class="sortable text-center"
                            phx-click="sort"
                            phx-value-column="type"
                          >
                            Type
                            <span :if={@sort_by == :type} class="ml-1">
                              {if @sort_dir == :asc, do: "↑", else: "↓"}
                            </span>
                          </th>
                          <th
                            class="sortable text-center"
                            phx-click="sort"
                            phx-value-column="gall_count"
                          >
                            Galls
                            <span :if={@sort_by == :gall_count} class="ml-1">
                              {if @sort_dir == :asc, do: "↑", else: "↓"}
                            </span>
                          </th>
                          <th
                            class="sortable text-center"
                            phx-click="sort"
                            phx-value-column="host_count"
                          >
                            Hosts
                            <span :if={@sort_by == :host_count} class="ml-1">
                              {if @sort_dir == :asc, do: "↑", else: "↓"}
                            </span>
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={
                          child <- RankPage.sort_children(@filtered_children, @sort_by, @sort_dir)
                        }>
                          <td>
                            <.link
                              :if={child.url}
                              href={child.url}
                              class="hover:underline font-medium"
                            >
                              <.taxon_name name={child.name} rank={child.rank} />
                            </.link>
                            <.taxon_name :if={!child.url} name={child.name} rank={child.rank} />
                            <span
                              :if={child.description not in [nil, ""]}
                              class="text-gray-500 text-sm ml-1"
                            >
                              ({child.description})
                            </span>
                          </td>
                          <td class="text-center">
                            <span class="text-sm text-gray-600">{child.rank}</span>
                          </td>
                          <td class="text-center text-gray-600">{child.gall_count}</td>
                          <td class="text-center text-gray-600">{child.host_count}</td>
                        </tr>
                      </tbody>
                    </table>
                  </div>

                  <%!-- Filter status message --%>
                  <div class="mt-4 text-sm text-gray-500">
                    <%= if @search_query != "" do %>
                      Filtering {length(@filtered_children)} of {@total_children_count} children
                    <% else %>
                      Showing {length(@filtered_children)} children
                    <% end %>
                  </div>
                <% end %>
              <% else %>
                <p class="text-gray-500 italic">No children found.</p>
              <% end %>
            </div>

            <%!-- Galls placed at the family itself --%>
            <div :if={@galls != []} class="mt-6">
              <h2 class="text-lg font-semibold text-gray-800 mb-3">
                Galls placed in this family ({length(@galls)})
              </h2>
              <RankPageComponents.species_table
                id="family-galls"
                rows={@galls}
                url_prefix="/gall/"
                name_header="Gall"
                count_header="Number of Hosts"
              />
            </div>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
