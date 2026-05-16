defmodule GallformersWeb.GenusLive do
  @moduledoc """
  LiveView for the taxonomic genus listing page.

  Displays a genus with its parent family and list of species.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Species
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.Lineage
  alias GallformersWeb.TaxonomyURL

  @impl true
  def mount(%{"name" => name} = params, _session, socket) do
    if TaxonomyURL.numeric?(name) do
      redirect_by_id(socket, name)
    else
      case Taxonomy.get_genera_by_name(name) do
        [] ->
          {:ok, assign_genus_not_found(socket, "Genus not found")}

        [%{id: genus_id}] ->
          load_genus(socket, genus_id)

        multiple ->
          resolve_disambiguation(socket, name, params, multiple)
      end
    end
  end

  defp redirect_by_id(socket, id_str) do
    case Taxonomy.get_taxonomy(String.to_integer(id_str)) do
      %{type: "genus"} = taxonomy ->
        {:ok, push_navigate(socket, to: TaxonomyURL.public_path(taxonomy), replace: true)}

      _ ->
        {:ok, assign_genus_not_found(socket, "Genus not found")}
    end
  end

  defp load_genus(socket, genus_id) do
    case Taxonomy.get_genus_lineage(genus_id) do
      {:ok, lineage} ->
        {:ok, assign_genus_data(socket, lineage, genus_id)}

      {:error, :not_found} ->
        {:ok, assign_genus_not_found(socket, "Genus not found")}
    end
  end

  defp assign_genus_not_found(socket, error) do
    assign(socket,
      page_title: "Genus Not Found",
      page_description: "The requested taxonomic genus was not found on Gallformers.",
      page_url: nil,
      page_image: nil,
      page_json_ld: nil,
      page_noindex: true,
      lineage: nil,
      disambiguation: nil,
      error: error
    )
  end

  defp resolve_disambiguation(socket, name, params, genera) do
    case find_genus_by_family_hint(genera, params["family"]) do
      %{id: genus_id} -> load_genus(socket, genus_id)
      nil -> {:ok, assign_disambiguation(socket, name, genera)}
    end
  end

  defp find_genus_by_family_hint(_genera, nil), do: nil

  defp find_genus_by_family_hint(genera, family_name) do
    Enum.find(genera, fn genus ->
      case Taxonomy.get_genus_lineage(genus.id) do
        {:ok, lineage} -> lineage.family.name == family_name
        _ -> false
      end
    end)
  end

  defp assign_disambiguation(socket, name, genera) do
    # Resolve each genus's ancestor family for display context
    options =
      Enum.map(genera, fn genus ->
        case Taxonomy.get_genus_lineage(genus.id) do
          {:ok, lineage} ->
            %{
              genus: genus,
              family_name: lineage.family.name,
              family_description: lineage.family.description,
              species_count: length(Taxonomy.get_species_ids_for_genus(genus.id))
            }

          {:error, _} ->
            %{genus: genus, family_name: "Unknown", family_description: nil, species_count: 0}
        end
      end)

    assign(socket,
      page_title: "Genus #{name} — Disambiguation",
      page_description:
        "Multiple genera named #{name} exist on Gallformers under different families.",
      page_url: nil,
      page_image: nil,
      page_json_ld: nil,
      page_noindex: true,
      lineage: nil,
      disambiguation: options,
      error: nil
    )
  end

  defp assign_genus_data(socket, %Lineage{} = lineage, genus_id) do
    species_ids = Taxonomy.get_species_ids_for_genus(genus_id)

    species =
      if species_ids == [] do
        []
      else
        species_ids
        |> Species.list_species_by_ids()
        |> Species.enrich_with_common_names_and_counts()
      end

    # Don't index empty placeholder genera (no species)
    is_empty_unknown = Taxonomy.placeholder_genus?(lineage) && species == []

    # Determine column header based on species type in this genus
    count_header =
      case species do
        [first | _] ->
          if first.taxoncode == "gall", do: "Number of Hosts", else: "Number of Galls"

        [] ->
          "Count"
      end

    assign(socket,
      page_title: "Genus #{lineage.genus.name}",
      page_description:
        "#{lineage.genus.name} - A taxonomic genus documented on Gallformers with #{length(species)} species.",
      page_url: TaxonomyURL.public_path(%{type: "genus", name: lineage.genus.name}),
      page_image: nil,
      page_json_ld: nil,
      page_noindex: is_empty_unknown,
      lineage: lineage,
      disambiguation: nil,
      species: species,
      search_query: "",
      sort_by: :name,
      sort_dir: :asc,
      filtered_species: species,
      total_species_count: length(species),
      count_header: count_header,
      error: nil
    )
  end

  defp format_with_description(name, description) do
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
          <%= if @disambiguation do %>
            <div class="mb-6">
              <h1 class="text-2xl font-bold text-gf-maroon mb-4">
                Genus <.taxon_name name={hd(@disambiguation).genus.name} rank="genus" />
              </h1>
              <p class="text-gray-600 mb-6">
                This genus name exists under multiple families. Select the one you're looking for:
              </p>
              <div class="grid gap-4 max-w-2xl">
                <.link
                  :for={option <- @disambiguation}
                  navigate={"/genus/#{URI.encode(option.genus.name)}?family=#{URI.encode(option.family_name)}"}
                  class="block p-4 bg-white border border-gray-200 rounded-lg hover:border-gf-maroon hover:bg-gf-cream transition-colors"
                >
                  <div class="font-semibold text-gf-maroon">
                    <.taxon_name name={option.genus.name} rank="genus" />
                    <span class="text-gray-500 font-normal">
                      in Family {option.family_name}
                      <span :if={option.family_description not in [nil, ""]}>
                        ({option.family_description})
                      </span>
                    </span>
                  </div>
                  <div class="text-sm text-gray-500 mt-1">
                    {option.species_count} species
                  </div>
                </.link>
              </div>
            </div>
          <% end %>
          <%= if @lineage do %>
            <%!-- Header --%>
            <div class="mb-6">
              <div class="flex items-center justify-between mb-2">
                <div class="flex items-center gap-2">
                  <h1 class="text-2xl font-bold text-gf-maroon">
                    Genus
                    <.taxon_name
                      name={format_with_description(@lineage.genus.name, @lineage.genus.description)}
                      rank="genus"
                    />
                  </h1>
                  <.link
                    :if={@current_user}
                    href={~p"/admin/taxonomy/#{@lineage.genus.id}"}
                    class="text-gray-400 hover:text-gf-maroon"
                    title="Edit in admin"
                  >
                    <.icon name="ph-pencil-simple" class="h-5 w-5" />
                  </.link>
                </div>
              </div>

              <.taxonomy_breadcrumb
                family={@lineage.family}
                intermediates={@lineage.intermediates}
                show_genus={false}
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
                  <form phx-change="search" phx-submit="search" id="genus-search-form">
                    <.search_input
                      id="genus-search"
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
                          <th
                            class="sortable text-center"
                            phx-click="sort"
                            phx-value-column="common_name"
                          >
                            Common Name
                            <span :if={@sort_by == :common_name} class="ml-1">
                              {if @sort_dir == :asc, do: "↑", else: "↓"}
                            </span>
                          </th>
                          <th class="sortable text-center" phx-click="sort" phx-value-column="count">
                            {@count_header}
                            <span :if={@sort_by == :count} class="ml-1">
                              {if @sort_dir == :asc, do: "↑", else: "↓"}
                            </span>
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={species <- sorted_species(@filtered_species, @sort_by, @sort_dir)}>
                          <td>
                            <.link
                              href={"#{if species.taxoncode == "gall", do: "/gall", else: "/host"}/#{species.id}"}
                              class="hover:underline"
                            >
                              <.taxon_name
                                name={species.name}
                                genus_placeholder={species[:genus_placeholder] == true}
                              />
                            </.link>
                          </td>
                          <td class="text-center">{species.common_name}</td>
                          <td class="text-center text-gray-600">
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
                <p class="text-gray-500 italic">No species found for this genus.</p>
              <% end %>
            </div>
          <% else %>
            <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
              Genus not found.
            </div>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
