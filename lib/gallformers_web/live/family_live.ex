defmodule GallformersWeb.FamilyLive do
  @moduledoc """
  LiveView for the taxonomic family listing page.

  Displays a family with its genera and species in an expandable tree view.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.Family
  alias GallformersWeb.TreeComponents

  # Smart expand thresholds (same as Explore page)
  @max_children_per_node 5

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {family_id, ""} ->
        load_family(socket, family_id)

      _ ->
        {:ok,
         assign(socket,
           page_title: "Family Not Found",
           page_description: "The requested taxonomic family was not found on Gallformers.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           family: nil,
           error: "Invalid family ID"
         )}
    end
  end

  defp load_family(socket, family_id) do
    case Taxonomy.get_family(family_id) do
      nil ->
        {:ok,
         assign(socket,
           page_title: "Family Not Found",
           page_description: "The requested taxonomic family was not found on Gallformers.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           family: nil,
           error: "Family not found"
         )}

      %Family{} = family ->
        # Get genera under this family
        genera = Taxonomy.get_children(family_id)

        # Build tree data
        tree_data = build_tree_data(genera)

        {:ok,
         assign(socket,
           page_title: family.name,
           page_description:
             "#{family.name} - A taxonomic family documented on Gallformers with genera and species.",
           page_url: "/family/#{family_id}",
           page_image: nil,
           page_json_ld: nil,
           page_noindex: false,
           family: family,
           tree_data: tree_data,
           filtered_tree: tree_data,
           expanded_keys: MapSet.new(),
           search_query: "",
           error: nil
         )}
    end
  end

  defp build_tree_data(genera) do
    # Batch fetch all species IDs for all genera (1 query instead of N)
    genus_ids = Enum.map(genera, & &1.id)
    species_ids_map = Taxonomy.get_species_ids_for_genera(genus_ids)

    # Batch fetch all species info (1 query)
    all_species_ids = species_ids_map |> Map.values() |> List.flatten() |> Enum.uniq()
    all_species = get_species_info(all_species_ids)
    species_map = Enum.into(all_species, %{}, fn s -> {s.id, s} end)

    Enum.map(genera, fn genus ->
      species_ids = Map.get(species_ids_map, genus.id, [])

      species =
        species_ids
        |> Enum.map(&Map.get(species_map, &1))
        |> Enum.reject(&is_nil/1)

      %{
        key: "g-#{genus.id}",
        label: format_label(genus.name, genus.description),
        name: genus.name,
        rank: "genus",
        url: "/genus/#{genus.id}",
        nodes:
          Enum.map(species, fn s ->
            %{
              key: "s-#{s.id}",
              label: s.name,
              url: s.url
            }
          end)
      }
    end)
  end

  defp get_species_info(species_ids) do
    Gallformers.Species.list_species_by_ids(species_ids)
    |> Enum.map(fn s ->
      url = if s.taxoncode == "gall", do: "/gall/#{s.id}", else: "/host/#{s.id}"
      Map.put(s, :url, url)
    end)
  end

  defp format_label(name, nil), do: name
  defp format_label(name, ""), do: name
  defp format_label(name, description), do: "#{name} (#{description})"

  @impl true
  def handle_event("toggle_node", %{"key" => key}, socket) do
    expanded_keys = socket.assigns.expanded_keys

    new_expanded =
      if MapSet.member?(expanded_keys, key) do
        MapSet.delete(expanded_keys, key)
      else
        MapSet.put(expanded_keys, key)
      end

    {:noreply, assign(socket, expanded_keys: new_expanded)}
  end

  @impl true
  def handle_event("expand_all", _params, socket) do
    all_keys = collect_branch_keys(socket.assigns.filtered_tree)
    {:noreply, assign(socket, expanded_keys: MapSet.new(all_keys))}
  end

  @impl true
  def handle_event("collapse_all", _params, socket) do
    {:noreply, assign(socket, expanded_keys: MapSet.new())}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    filtered = filter_tree(socket.assigns.tree_data, query)

    # Smart expand logic with two thresholds
    new_expanded =
      if String.trim(query) != "" do
        # For family page, we're always at 1 "family" (the genera list)
        # So we use the per-node threshold
        filtered
        |> collect_branch_keys_with_limit(@max_children_per_node)
        |> MapSet.new()
      else
        # Empty search - keep current expansion
        socket.assigns.expanded_keys
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:filtered_tree, filtered)
     |> assign(:expanded_keys, new_expanded)}
  end

  defp collect_branch_keys(nodes) do
    Enum.flat_map(nodes, fn node ->
      if Map.has_key?(node, :nodes) and node.nodes != [] do
        [node.key | collect_branch_keys(node.nodes)]
      else
        []
      end
    end)
  end

  defp collect_branch_keys_with_limit(nodes, max_children) do
    Enum.flat_map(nodes, &collect_node_keys_with_limit(&1, max_children))
  end

  defp collect_node_keys_with_limit(%{nodes: children} = node, max_children)
       when is_list(children) and children != [] do
    child_keys = collect_branch_keys_with_limit(children, max_children)

    if length(children) <= max_children do
      [node.key | child_keys]
    else
      child_keys
    end
  end

  defp collect_node_keys_with_limit(_node, _max_children), do: []

  defp filter_tree(nodes, ""), do: nodes

  defp filter_tree(nodes, query) do
    query_lower = String.downcase(query)

    nodes
    |> Enum.map(&filter_node(&1, query, query_lower))
    |> Enum.reject(&is_nil/1)
  end

  defp filter_node(node, query, query_lower) do
    if branch_node?(node) do
      filter_branch_node(node, query, query_lower)
    else
      if label_matches?(node.label, query_lower), do: node, else: nil
    end
  end

  defp filter_branch_node(node, query, query_lower) do
    filtered_children = filter_tree(node.nodes, query)

    if filtered_children != [] or label_matches?(node.label, query_lower) do
      %{node | nodes: filtered_children}
    else
      nil
    end
  end

  defp branch_node?(node), do: Map.has_key?(node, :nodes) and node.nodes != []

  defp label_matches?(label, query_lower),
    do: String.contains?(String.downcase(label), query_lower)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-7xl">
        <%= if @error do %>
          <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">{@error}</div>
        <% else %>
          <%= if @family do %>
            <%!-- Header --%>
            <div class="mb-6">
              <div class="flex items-center gap-2">
                <h1 class="text-2xl font-bold text-gf-maroon">
                  {@family.name}
                  <span :if={@family.description} class="text-lg font-normal text-gray-600">
                    - {@family.description}
                  </span>
                </h1>
                <.link
                  :if={@current_user}
                  href={~p"/admin/taxonomy/#{@family.id}"}
                  class="text-gray-400 hover:text-gf-maroon"
                  title="Edit in admin"
                >
                  <.icon name="ph-pencil-simple" class="h-5 w-5" />
                </.link>
              </div>
            </div>

            <%!-- Tree browser --%>
            <%= if length(@tree_data) > 0 do %>
              <TreeComponents.tree_browser
                id="family-tree"
                nodes={@filtered_tree}
                expanded={@expanded_keys}
                search_query={@search_query}
                show_search={true}
                show_controls={true}
                on_toggle="toggle_node"
                on_expand_all="expand_all"
                on_collapse_all="collapse_all"
                on_search="search"
              />
            <% else %>
              <div class="bg-white rounded-lg border border-gray-200 p-4">
                <p class="text-gray-500 italic">No genera or species found for this family.</p>
              </div>
            <% end %>
          <% else %>
            <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
              Family not found
            </div>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
