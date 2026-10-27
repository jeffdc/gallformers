defmodule GallformersWeb.SectionLive do
  @moduledoc """
  LiveView for the taxonomic section listing page.

  Displays a section (a subdivision within a genus for certain plant
  genera, `Gallformers.Taxa.get_by_name/2`) with its breadcrumb lineage
  and its plants, each with the number of Galls on it. Data through
  `GallformersWeb.RankPage`.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Taxa
  alias GallformersWeb.LineageBreadcrumb
  alias GallformersWeb.RankPage
  alias GallformersWeb.RankPageComponents
  alias GallformersWeb.TaxonomyURL

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    case RankPage.lookup(name, :section) do
      {:redirect, path} -> {:ok, push_navigate(socket, to: path, replace: true)}
      {:ok, []} -> {:ok, assign_section_not_found(socket)}
      {:ok, [section | _]} -> {:ok, load_section(socket, section.id, name)}
    end
  end

  defp assign_section_not_found(socket) do
    assign(socket,
      page_title: "Section Not Found",
      page_description: "The requested taxonomic section was not found on Gallformers.",
      page_url: nil,
      page_image: nil,
      page_json_ld: nil,
      page_noindex: true,
      section: nil,
      error: "Section not found"
    )
  end

  defp load_section(socket, id, name) do
    species = RankPage.host_rows(id)

    lineage =
      id
      |> Taxa.lineage()
      |> Enum.reject(&(&1.taxon_id == id))
      |> LineageBreadcrumb.from_lineage()

    assign(socket,
      page_title: "Section #{name}",
      page_description:
        "#{name} - A taxonomic section documented on Gallformers with #{length(species)} species.",
      page_url: TaxonomyURL.public_path(%{rank: :section, name: name}),
      page_image: nil,
      page_json_ld: nil,
      page_noindex: false,
      section: %{id: id, name: name, description: RankPage.description(id)},
      lineage: lineage,
      species: species,
      search_query: "",
      sort_by: :name,
      sort_dir: :asc,
      filtered_species: species,
      total_species_count: length(species),
      error: nil
    )
  end

  defp format_full_name(name, description) do
    if description && String.trim(description) != "" do
      "#{name} (#{description})"
    else
      name
    end
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     assign(socket,
       search_query: query,
       filtered_species: RankPage.filter_rows(socket.assigns.species, query)
     )}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket)
      when column in ["name", "common_name", "count"] do
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
          <%!-- Header --%>
          <div class="mb-6">
            <div class="flex items-center justify-between mb-2">
              <div class="flex items-center gap-2">
                <h1 class="text-2xl font-bold text-gf-maroon">
                  Section {format_full_name(@section.name, @section.description)}
                </h1>
                <RankPageComponents.admin_edit_link
                  current_user={@current_user}
                  taxon_id={@section.id}
                />
              </div>
            </div>

            <.taxonomy_breadcrumb
              :if={@lineage}
              family={@lineage.family}
              intermediates={@lineage.intermediates}
              genus={@lineage.genus}
            />
          </div>

          <%!-- Species list --%>
          <div class="mt-6">
            <%= if @total_species_count > 0 do %>
              <h2 class="text-lg font-semibold text-gray-800 mb-3">
                Species ({@total_species_count})
              </h2>

              <%!-- Search box --%>
              <div class="mb-4 max-w-md">
                <form phx-change="search" phx-submit="search" id="section-search-form">
                  <.search_input
                    id="section-search"
                    name="query"
                    value={@search_query}
                    placeholder="Filter by species or common name..."
                    phx-debounce="300"
                  />
                </form>
              </div>

              <%= if Enum.empty?(@filtered_species) do %>
                <div class="bg-gray-50 rounded-lg p-8 text-center text-gray-600">
                  <p>No species found matching "{@search_query}"</p>
                </div>
              <% else %>
                <RankPageComponents.species_table
                  id="section-species"
                  rows={@filtered_species}
                  url_prefix="/host/"
                  count_header="Number of Galls"
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />

                <%!-- Filter status message --%>
                <div class="mt-4 text-sm text-gray-500">
                  <%= if @search_query != "" do %>
                    Filtering {length(@filtered_species)} of {@total_species_count} species
                  <% else %>
                    Showing {length(@filtered_species)} species
                  <% end %>
                </div>
              <% end %>
            <% else %>
              <p class="text-gray-500 italic">No species found for this section.</p>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
