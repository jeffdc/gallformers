defmodule GallformersWeb.SectionLive do
  @moduledoc """
  LiveView for the taxonomic section listing page.

  Displays a section (a subdivision within genus for certain plant genera)
  with its list of species.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Species
  alias Gallformers.Taxonomy

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {section_id, ""} ->
        load_section(socket, section_id)

      _ ->
        {:ok,
         assign(socket,
           page_title: "Section Not Found",
           page_description: "The requested taxonomic section was not found on Gallformers.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           lineage: nil,
           error: "Invalid section ID"
         )}
    end
  end

  defp load_section(socket, section_id) do
    case Taxonomy.get_section_lineage(section_id) do
      {:ok, lineage} ->
        # Get enriched species for this section
        species =
          Taxonomy.get_species_for_section(section_id)
          |> Species.enrich_with_common_names_and_counts()

        {:ok,
         assign(socket,
           page_title: "Section #{lineage.section.name}",
           page_description:
             "#{lineage.section.name} - A taxonomic section documented on Gallformers with #{length(species)} species.",
           page_url: "/section/#{section_id}",
           page_image: nil,
           page_json_ld: nil,
           page_noindex: false,
           lineage: lineage,
           species: species,
           search_query: "",
           sort_by: :name,
           sort_dir: :asc,
           filtered_species: species,
           total_species_count: length(species),
           error: nil
         )}

      {:error, :not_found} ->
        {:ok,
         assign(socket,
           page_title: "Section Not Found",
           page_description: "The requested taxonomic section was not found on Gallformers.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           lineage: nil,
           error: "Section not found"
         )}
    end
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
     socket
     |> assign(:search_query, query)
     |> filter_species()}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket)
      when column in ["name", "common_name", "count"] do
    column_atom = String.to_atom(column)

    {new_sort_by, new_sort_dir} =
      if socket.assigns.sort_by == column_atom do
        new_dir = if socket.assigns.sort_dir == :asc, do: :desc, else: :asc
        {column_atom, new_dir}
      else
        {column_atom, :asc}
      end

    {:noreply, assign(socket, sort_by: new_sort_by, sort_dir: new_sort_dir)}
  end

  defp filter_species(socket) do
    query = String.downcase(socket.assigns.search_query)

    filtered =
      if query == "" do
        socket.assigns.species
      else
        Enum.filter(socket.assigns.species, fn s ->
          String.contains?(String.downcase(s.name), query) ||
            (s.common_name && String.contains?(String.downcase(s.common_name), query))
        end)
      end

    assign(socket, :filtered_species, filtered)
  end

  defp sorted_species(species, sort_by, sort_dir) do
    sorted =
      Enum.sort_by(species, fn s ->
        case sort_by do
          :name -> String.downcase(s.name || "")
          :common_name -> String.downcase(s.common_name || "zzz")
          :count -> s.count
          _ -> String.downcase(s.name || "")
        end
      end)

    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-7xl">
        <%= if @error do %>
          <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">{@error}</div>
        <% else %>
          <%= if @lineage do %>
            <%!-- Header --%>
            <div class="mb-6">
              <div class="flex items-center justify-between mb-2">
                <div class="flex items-center gap-2">
                  <h1 class="text-2xl font-bold text-gf-maroon">
                    Section {format_full_name(@lineage.section.name, @lineage.section.description)}
                  </h1>
                  <.link
                    :if={@current_user}
                    href={~p"/admin/section/#{@lineage.section.id}"}
                    class="text-gray-400 hover:text-gf-maroon"
                    title="Edit in admin"
                  >
                    <.icon name="ph-pencil-simple" class="h-5 w-5" />
                  </.link>
                </div>
              </div>

              <%!-- Parent breadcrumbs --%>
              <div class="text-gray-700 flex items-center gap-1">
                <%= if @lineage.family do %>
                  <span class="font-semibold">Family:</span>
                  <.link href={"/family/#{@lineage.family.id}"} class="hover:underline">
                    <.taxon_name name={@lineage.family.name} rank="family" />
                  </.link>
                  <span :if={@lineage.family.description} class="text-gray-600">
                    ({@lineage.family.description})
                  </span>
                  <span class="text-gray-400 mx-1">/</span>
                <% end %>
                <span class="font-semibold">Genus:</span>
                <.link href={"/genus/#{@lineage.genus.id}"} class="hover:underline">
                  <.taxon_name name={@lineage.genus.name} rank="genus" />
                </.link>
                <span :if={@lineage.genus.description} class="text-gray-600">
                  ({@lineage.genus.description})
                </span>
              </div>
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
                  <div class="bg-white rounded border border-gray-200 overflow-hidden">
                    <table class="gf-table">
                      <thead>
                        <tr>
                          <th class="sortable" phx-click="sort" phx-value-column="name">
                            Species Name
                            <span :if={@sort_by == :name} class="ml-1">
                              {if @sort_dir == :asc, do: "↑", else: "↓"}
                            </span>
                          </th>
                          <th class="sortable" phx-click="sort" phx-value-column="common_name">
                            Common Name
                            <span :if={@sort_by == :common_name} class="ml-1">
                              {if @sort_dir == :asc, do: "↑", else: "↓"}
                            </span>
                          </th>
                          <th class="sortable" phx-click="sort" phx-value-column="count">
                            Number of Galls
                            <span :if={@sort_by == :count} class="ml-1">
                              {if @sort_dir == :asc, do: "↑", else: "↓"}
                            </span>
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={species <- sorted_species(@filtered_species, @sort_by, @sort_dir)}>
                          <td>
                            <%!-- Sections are for hosts (plants) --%>
                            <.link href={"/host/#{species.id}"} class="hover:underline">
                              <.taxon_name name={species.name} />
                            </.link>
                          </td>
                          <td>{species.common_name}</td>
                          <td class="text-gray-600">
                            {species.count}
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>

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
          <% else %>
            <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
              Section not found.
            </div>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
