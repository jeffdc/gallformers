defmodule GallformersWeb.HostsBrowseLive do
  @moduledoc """
  Browse host plants: the plant families (`Gallformers.Taxa.plant_tree/0`)
  as `family_card`s, the most galled first, counting the distinct Galls on
  each family and genus (`Gallformers.Catalog.host_gall_counts/0`).

  The cards are the browse tree: a card opens to its genera and a genus to
  its plants (`toggle_node`, `expand_all`, `collapse_all`), and the name
  filter keeps what matches with smart expand (`GallformersWeb.BrowseHelpers`).
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.Taxa
  alias GallformersWeb.BrowseHelpers

  @impl true
  def mount(_params, _session, socket) do
    tree = Taxa.plant_tree()

    {:ok,
     socket
     |> assign(
       page_title: "Hosts",
       page_description: "Browse host plant species organized by family and genus.",
       page_url: "/hosts",
       page_image: nil,
       page_json_ld: nil,
       search_query: "",
       tree: tree,
       counts: Catalog.host_gall_counts(),
       expanded: MapSet.new()
     )
     |> show_tree(tree)}
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

    {:noreply,
     socket
     |> assign(search_query: query, expanded: expanded)
     |> show_tree(filtered)}
  end

  defp show_tree(socket, filtered) do
    cards = BrowseHelpers.family_cards(filtered, {:taxa, socket.assigns.counts})
    assign(socket, filtered: filtered, cards: cards)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="hosts-browse-container" class="flex flex-col gap-section">
        <.page_header>
          <:title>Browse galls</:title>
          <:description>
            Galls by the plants they grow on: {format_number(length(@tree))} host plant families, the most galled first.
          </:description>
        </.page_header>

        <.tab_nav label="Browse by" class="-mt-4">
          <:tab
            :for={{label, path} <- BrowseHelpers.browse_tabs()}
            navigate={path}
            current={path == "/hosts"}
          >
            {label}
          </:tab>
        </.tab_nav>

        <div class="flex flex-wrap items-center gap-x-6 gap-y-3">
          <form
            id="hosts-browse-search-form"
            phx-change="search"
            phx-submit="search"
            class="w-full sm:w-80"
          >
            <.search_field
              id="hosts-browse-search"
              name="query"
              value={@search_query}
              label="Filter by name"
              placeholder="Filter by name…"
            />
          </form>
          <div class="flex gap-2 sm:ml-auto">
            <.button variant="ghost" size="sm" phx-click="expand_all">Show all plants</.button>
            <.button variant="ghost" size="sm" phx-click="collapse_all">Collapse all</.button>
          </div>
        </div>

        <p :if={@cards == []} class="text-ui text-muted">
          {if @search_query != "", do: "No matching items found.", else: "No items found."}
        </p>

        <div :if={@cards != []} class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          <.family_card
            :for={card <- @cards}
            card={card}
            expanded={@expanded}
            on_toggle="toggle_node"
            icon="gf-host"
            leaves="plants"
          />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
