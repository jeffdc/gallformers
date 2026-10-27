defmodule GallformersWeb.HostsBrowseLive do
  @moduledoc """
  Browse host plants organized by Family > Genus > plant
  (`Gallformers.Taxa.plant_tree/0`).

  Uses a tree UI with search filtering and smart expand.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Taxa
  alias GallformersWeb.BrowseHelpers
  alias GallformersWeb.TreeComponents

  @impl true
  def mount(_params, _session, socket) do
    tree = Taxa.plant_tree()

    {:ok,
     assign(socket,
       page_title: "Hosts",
       page_description: "Browse host plant species organized by family and genus.",
       page_url: "/hosts",
       page_image: nil,
       page_json_ld: nil,
       search_query: "",
       tree: tree,
       filtered: tree,
       expanded: MapSet.new()
     )}
  end

  @impl true
  def handle_event("toggle_node", %{"key" => key}, socket) do
    expanded = BrowseHelpers.toggle_set(socket.assigns.expanded, key)
    {:noreply, assign(socket, expanded: expanded)}
  end

  @impl true
  def handle_event("expand_all", _params, socket) do
    all_keys = BrowseHelpers.collect_branch_keys(socket.assigns.filtered)
    {:noreply, assign(socket, expanded: MapSet.new(all_keys))}
  end

  @impl true
  def handle_event("collapse_all", _params, socket) do
    {:noreply, assign(socket, expanded: MapSet.new())}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    filtered = BrowseHelpers.filter_tree(socket.assigns.tree, query)
    expanded = BrowseHelpers.smart_expand(filtered, query, socket.assigns.expanded)

    {:noreply, assign(socket, search_query: query, filtered: filtered, expanded: expanded)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="hosts-browse-container">
        <p class="text-lg text-gray-600 mb-6">
          Browse host plant species by family and genus.
        </p>

        <TreeComponents.tree_browser
          id="hosts-browse"
          nodes={@filtered}
          expanded={@expanded}
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
