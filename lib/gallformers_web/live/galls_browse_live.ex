defmodule GallformersWeb.GallsBrowseLive do
  @moduledoc """
  Browse all Galls by what causes them: the Inducer families
  (`Gallformers.Catalog.gall_tree/0`) as `family_card`s in their
  plain-language groups (`Gallformers.Catalog.InducerGroups`).

  The cards are the browse tree: a card opens to its genera and a genus to
  its Galls (`toggle_node`, `expand_all`, `collapse_all`), and the name
  filter keeps what matches with smart expand (`GallformersWeb.BrowseHelpers`).
  "Undescribed galls only" switches to `Gallformers.Catalog.undescribed_gall_tree/0`.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.Catalog.InducerGroups
  alias GallformersWeb.BrowseHelpers

  @impl true
  def mount(_params, _session, socket) do
    galls_tree = Catalog.gall_tree()

    {:ok,
     socket
     |> assign(
       page_title: "Galls",
       page_description: "Browse gall-forming species organized by family and genus.",
       page_url: "/galls",
       page_image: nil,
       page_json_ld: nil,
       showing_undescribed: false,
       search_query: "",
       galls_tree: galls_tree,
       undescribed_tree: nil,
       photos: Catalog.gall_photo_urls(),
       expanded: MapSet.new()
     )
     |> show_tree(galls_tree)}
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
    filtered = BrowseHelpers.filter_tree(active_tree(socket.assigns), query)
    expanded = BrowseHelpers.smart_expand(filtered, query, socket.assigns.expanded)

    {:noreply,
     socket
     |> assign(search_query: query, expanded: expanded)
     |> show_tree(filtered)}
  end

  @impl true
  def handle_event("toggle_undescribed", _params, socket) do
    new_showing = !socket.assigns.showing_undescribed

    # Lazy-load undescribed tree on first toggle
    socket =
      if new_showing && is_nil(socket.assigns.undescribed_tree) do
        assign(socket, undescribed_tree: Catalog.undescribed_gall_tree())
      else
        socket
      end

    tree = if new_showing, do: socket.assigns.undescribed_tree, else: socket.assigns.galls_tree
    query = socket.assigns.search_query
    filtered = BrowseHelpers.filter_tree(tree, query)

    expanded =
      if query != "",
        do: BrowseHelpers.smart_expand(filtered, query, MapSet.new()),
        else: MapSet.new()

    {:noreply,
     socket
     |> assign(showing_undescribed: new_showing, expanded: expanded)
     |> show_tree(filtered)}
  end

  defp active_tree(assigns) do
    if assigns.showing_undescribed, do: assigns.undescribed_tree, else: assigns.galls_tree
  end

  # The filtered tree, and its cards in their groups.
  defp show_tree(socket, filtered) do
    groups =
      filtered
      |> BrowseHelpers.family_cards({:leaves, socket.assigns.photos})
      |> InducerGroups.groups()

    total = active_tree(socket.assigns) |> Enum.flat_map(&leaf_keys/1) |> length()
    assign(socket, filtered: filtered, groups: groups, total: total)
  end

  defp leaf_keys(%{nodes: [_ | _] = nodes}), do: Enum.flat_map(nodes, &leaf_keys/1)
  defp leaf_keys(%{key: key}), do: [key]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="galls-browse-container" class="flex flex-col gap-section">
        <.page_header>
          <:title>Browse galls</:title>
          <:description>
            {format_number(@total)} {if @showing_undescribed,
              do: "undescribed galls",
              else: "galls"}, by what causes them.
          </:description>
        </.page_header>

        <.tab_nav label="Browse by" class="-mt-4">
          <:tab
            :for={{label, path} <- BrowseHelpers.browse_tabs()}
            navigate={path}
            current={path == "/galls"}
          >
            {label}
          </:tab>
        </.tab_nav>

        <div class="flex flex-col gap-3">
          <div class="flex flex-wrap items-center gap-x-6 gap-y-3">
            <form
              id="galls-browse-search-form"
              phx-change="search"
              phx-submit="search"
              class="w-full sm:w-80"
            >
              <.search_field
                id="galls-browse-search"
                name="query"
                value={@search_query}
                label="Filter by name"
                placeholder="Filter by name…"
              />
            </form>
            <label
              class="flex items-center gap-2 text-ui text-ink-2"
              data-active-view={if @showing_undescribed, do: "undescribed", else: "described"}
            >
              <input
                type="checkbox"
                class="gf-checkbox"
                checked={@showing_undescribed}
                phx-click="toggle_undescribed"
              /> Undescribed galls only
            </label>
            <div class="flex gap-2 sm:ml-auto">
              <.button variant="ghost" size="sm" phx-click="expand_all">Show all galls</.button>
              <.button variant="ghost" size="sm" phx-click="collapse_all">Collapse all</.button>
            </div>
          </div>

          <nav
            :if={@groups != []}
            aria-label="Groups"
            class="flex flex-wrap gap-x-4 gap-y-1 text-meta"
          >
            <a :for={group <- @groups} href={"#group-#{group.slug}"}>
              {group.name}
              <span class="tabular-nums text-muted">{format_number(group.count)}</span>
            </a>
          </nav>
        </div>

        <p :if={@groups == []} class="text-ui text-muted">
          {if @search_query != "", do: "No matching items found.", else: "No items found."}
        </p>

        <.section
          :for={group <- @groups}
          id={"group-#{group.slug}"}
          title={group.name}
          count={format_number(group.count)}
        >
          <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            <.family_card
              :for={card <- group.families}
              card={card}
              expanded={@expanded}
              on_toggle="toggle_node"
            />
          </div>
        </.section>
      </div>
    </Layouts.app>
    """
  end
end
