defmodule GallformersWeb.ExploreLive do
  @moduledoc """
  LiveView for exploring galls and hosts by taxonomic hierarchy.

  Provides three browse tabs:
  - Galls: All described gall species organized by Family → Genus → Species
  - Undescribed: Undescribed gall species
  - Hosts: Host plant species organized by Family → Genus → Species

  Uses an expandable tree UI for navigation with smart expand on search.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Galls
  alias Gallformers.Plants
  alias GallformersWeb.TreeComponents

  @tabs ~w(galls undescribed hosts)

  # Smart expand thresholds
  @max_families_to_auto_expand 3
  @max_children_per_node 5

  @impl true
  def mount(_params, _session, socket) do
    # Load all tree data on mount
    galls_tree = Galls.get_galls_tree()
    undescribed_tree = Galls.get_undescribed_tree()
    hosts_tree = Plants.get_hosts_tree()

    {:ok,
     assign(socket,
       page_title: "Explore",
       page_description:
         "Explore the Gallformers database - browse galls and host plants organized by taxonomic family, genus, and species.",
       page_url: "/explore",
       page_image: nil,
       page_json_ld: nil,
       tabs: @tabs,
       active_tab: "galls",
       search_query: "",
       galls_tree: galls_tree,
       undescribed_tree: undescribed_tree,
       hosts_tree: hosts_tree,
       galls_expanded: MapSet.new(),
       undescribed_expanded: MapSet.new(),
       hosts_expanded: MapSet.new(),
       galls_filtered: galls_tree,
       undescribed_filtered: undescribed_tree,
       hosts_filtered: hosts_tree
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = params["tab"]
    active_tab = if tab in @tabs, do: tab, else: socket.assigns.active_tab
    {:noreply, assign(socket, active_tab: active_tab)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply, push_patch(socket, to: ~p"/explore?tab=#{tab}")}
  end

  @impl true
  def handle_event("switch_tab", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_node", %{"key" => key}, socket) do
    expanded_key = expanded_key_for_tab(socket.assigns.active_tab)
    current_expanded = Map.get(socket.assigns, expanded_key, MapSet.new())

    new_expanded =
      if MapSet.member?(current_expanded, key) do
        MapSet.delete(current_expanded, key)
      else
        MapSet.put(current_expanded, key)
      end

    {:noreply, assign(socket, [{expanded_key, new_expanded}])}
  end

  @impl true
  def handle_event("expand_all", _params, socket) do
    tab = socket.assigns.active_tab
    tree = filtered_tree_for_tab(socket.assigns, tab)
    all_keys = collect_branch_keys(tree)
    expanded_key = expanded_key_for_tab(tab)

    {:noreply, assign(socket, [{expanded_key, MapSet.new(all_keys)}])}
  end

  @impl true
  def handle_event("collapse_all", _params, socket) do
    expanded_key = expanded_key_for_tab(socket.assigns.active_tab)
    {:noreply, assign(socket, [{expanded_key, MapSet.new()}])}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    tab = socket.assigns.active_tab
    tree = tree_for_tab(socket.assigns, tab)
    filtered = filter_tree(tree, query)

    # Smart expand logic with two thresholds
    new_expanded =
      if String.trim(query) != "" do
        matching_families = count_families_with_matches(filtered)

        if matching_families <= @max_families_to_auto_expand do
          # Auto-expand, but respect per-node limit
          filtered
          |> collect_branch_keys_with_limit(@max_children_per_node)
          |> MapSet.new()
        else
          # Too many families match - keep current expansion
          Map.get(socket.assigns, expanded_key_for_tab(tab), MapSet.new())
        end
      else
        # Empty search - keep current expansion
        Map.get(socket.assigns, expanded_key_for_tab(tab), MapSet.new())
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(filtered_key_for_tab(tab), filtered)
     |> assign(expanded_key_for_tab(tab), new_expanded)}
  end

  defp expanded_key_for_tab("galls"), do: :galls_expanded
  defp expanded_key_for_tab("undescribed"), do: :undescribed_expanded
  defp expanded_key_for_tab("hosts"), do: :hosts_expanded

  defp filtered_key_for_tab("galls"), do: :galls_filtered
  defp filtered_key_for_tab("undescribed"), do: :undescribed_filtered
  defp filtered_key_for_tab("hosts"), do: :hosts_filtered

  defp tree_for_tab(assigns, "galls"), do: assigns.galls_tree
  defp tree_for_tab(assigns, "undescribed"), do: assigns.undescribed_tree
  defp tree_for_tab(assigns, "hosts"), do: assigns.hosts_tree

  defp filtered_tree_for_tab(assigns, "galls"), do: assigns.galls_filtered
  defp filtered_tree_for_tab(assigns, "undescribed"), do: assigns.undescribed_filtered
  defp filtered_tree_for_tab(assigns, "hosts"), do: assigns.hosts_filtered

  defp expanded_for_tab(assigns, "galls"), do: assigns.galls_expanded
  defp expanded_for_tab(assigns, "undescribed"), do: assigns.undescribed_expanded
  defp expanded_for_tab(assigns, "hosts"), do: assigns.hosts_expanded

  defp collect_branch_keys(nodes) do
    Enum.flat_map(nodes, fn node ->
      if Map.has_key?(node, :nodes) and node.nodes != [] do
        [node.key | collect_branch_keys(node.nodes)]
      else
        []
      end
    end)
  end

  # Collects branch keys but only if the node has <= max_children children
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

  # Counts how many families (top-level nodes) have matches in the filtered tree
  defp count_families_with_matches(nodes), do: length(nodes)

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

  defp tab_label("galls"), do: "Galls"
  defp tab_label("undescribed"), do: "Undescribed"
  defp tab_label("hosts"), do: "Hosts"

  defp tab_count(assigns, "galls"), do: count_species(assigns.galls_tree)
  defp tab_count(assigns, "undescribed"), do: count_species(assigns.undescribed_tree)
  defp tab_count(assigns, "hosts"), do: count_species(assigns.hosts_tree)

  defp count_species(tree) do
    Enum.reduce(tree, 0, fn family, acc ->
      acc +
        Enum.reduce(family.nodes, 0, fn genus, acc2 ->
          acc2 + length(genus.nodes)
        end)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="explore-container">
        <p class="text-lg text-gray-600 mb-6">
          Browse galls and host plants organized by taxonomic family. Click on families and genera
          to expand and see species.
        </p>

        <%!-- Tabs --%>
        <div class="border-b border-gray-200 mb-4">
          <nav class="-mb-px flex space-x-8" aria-label="Tabs">
            <button
              :for={tab <- @tabs}
              phx-click="switch_tab"
              phx-value-tab={tab}
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-lg",
                if(@active_tab == tab,
                  do: "border-gf-maroon text-gf-maroon",
                  else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
                )
              ]}
              aria-current={if @active_tab == tab, do: "page", else: false}
            >
              {tab_label(tab)}
              <span class={[
                "ml-2 py-0.5 px-2 rounded-full text-xs",
                if(@active_tab == tab,
                  do: "bg-gf-maroon text-white",
                  else: "bg-gray-100 text-gray-600"
                )
              ]}>
                {tab_count(assigns, tab)}
              </span>
            </button>
          </nav>
        </div>

        <%!-- Tree browser --%>
        <TreeComponents.tree_browser
          id={"explore-#{@active_tab}"}
          nodes={filtered_tree_for_tab(assigns, @active_tab)}
          expanded={expanded_for_tab(assigns, @active_tab)}
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
