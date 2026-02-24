defmodule GallformersWeb.PlacesLive do
  @moduledoc """
  LiveView for browsing places by geographic hierarchy.

  Displays the place hierarchy (Continent -> Country -> Subdivision)
  in an expandable tree with search.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Places
  alias GallformersWeb.TreeComponents

  @max_families_to_auto_expand 3
  @max_children_per_node 5

  @impl true
  def mount(_params, _session, socket) do
    places_tree = Places.get_places_tree()

    {:ok,
     assign(socket,
       page_title: "Places",
       page_description:
         "Browse geographic places in the Gallformers database - continents, countries, and subdivisions worldwide.",
       page_url: "/places",
       page_image: nil,
       page_json_ld: nil,
       places_tree: places_tree,
       places_filtered: places_tree,
       places_expanded: MapSet.new(),
       search_query: ""
     )}
  end

  @impl true
  def handle_event("toggle_node", %{"key" => key}, socket) do
    expanded = socket.assigns.places_expanded

    new_expanded =
      if MapSet.member?(expanded, key) do
        MapSet.delete(expanded, key)
      else
        MapSet.put(expanded, key)
      end

    {:noreply, assign(socket, places_expanded: new_expanded)}
  end

  @impl true
  def handle_event("expand_all", _params, socket) do
    all_keys = collect_branch_keys(socket.assigns.places_filtered)
    {:noreply, assign(socket, places_expanded: MapSet.new(all_keys))}
  end

  @impl true
  def handle_event("collapse_all", _params, socket) do
    {:noreply, assign(socket, places_expanded: MapSet.new())}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    filtered = filter_tree(socket.assigns.places_tree, query)

    new_expanded =
      if String.trim(query) != "" do
        matching_top = length(filtered)

        if matching_top <= @max_families_to_auto_expand do
          filtered
          |> collect_branch_keys_with_limit(@max_children_per_node)
          |> MapSet.new()
        else
          socket.assigns.places_expanded
        end
      else
        socket.assigns.places_expanded
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:places_filtered, filtered)
     |> assign(:places_expanded, new_expanded)}
  end

  # Tree helpers (same pattern as ExploreLive)

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
      <div id="places-container">
        <p class="text-lg text-gray-600 mb-6">
          Browse geographic places worldwide. Click on continents, countries,
          and subdivisions to explore.
        </p>

        <TreeComponents.tree_browser
          id="places-tree"
          nodes={@places_filtered}
          expanded={@places_expanded}
          search_query={@search_query}
          show_search={true}
          show_controls={true}
          on_toggle="toggle_node"
          on_expand_all="expand_all"
          on_collapse_all="collapse_all"
          on_search="search"
        />
      </div>
    </Layouts.app>
    """
  end
end
