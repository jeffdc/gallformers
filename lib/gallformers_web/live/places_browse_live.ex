defmodule GallformersWeb.PlacesBrowseLive do
  @moduledoc """
  Browse galls by place: the continents, each with how many Galls are known
  there, then the chosen continent's countries in a table, ranked by Galls,
  each with its busiest states or provinces. Counts are known places
  (`Gallformers.Catalog.place_gall_counts/0`: where the Hosts are native,
  or introduced and the Gall is recorded), read once the page connects.

  The places tree (`Gallformers.Places.get_places_tree/0`) keeps its tree
  behaviors: the name filter across every continent with smart expand,
  a country's toggle (`toggle_node`) showing all its states or provinces,
  and `expand_all` / `collapse_all` (`GallformersWeb.BrowseHelpers`).
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.Places
  alias GallformersWeb.BrowseHelpers

  # States or provinces shown in a country's row until it is opened.
  @busiest 5

  @impl true
  def mount(_params, _session, socket) do
    tree = Places.get_places_tree()

    %{counts: counts, everywhere: everywhere} =
      if connected?(socket),
        do: Catalog.place_gall_counts(),
        else: %{counts: %{}, everywhere: 0}

    {:ok,
     assign(socket,
       page_title: "Places",
       page_description:
         "Browse geographic places — continents, countries, and states or provinces.",
       page_url: "/places",
       page_image: nil,
       page_json_ld: nil,
       search_query: "",
       tree: tree,
       filtered: tree,
       counts: counts,
       everywhere: everywhere,
       expanded: MapSet.new(),
       sort: %{field: :count, dir: :desc}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    codes = Enum.map(socket.assigns.tree, &code/1)

    code =
      Enum.find([params["c"], socket.assigns[:continent_code]], &(&1 in codes)) ||
        busiest_continent(socket.assigns)

    {:noreply, socket |> assign(continent_code: code) |> show_rows()}
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
     |> assign(search_query: query, filtered: filtered, expanded: expanded)
     |> show_rows()}
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) when field in ["name", "count"] do
    field = String.to_existing_atom(field)
    %{field: current, dir: dir} = socket.assigns.sort

    dir =
      cond do
        field == current -> if(dir == :asc, do: :desc, else: :asc)
        field == :count -> :desc
        true -> :asc
      end

    {:noreply, socket |> assign(sort: %{field: field, dir: dir}) |> show_rows()}
  end

  # The table's rows: the chosen continent's countries, or with a filter
  # the matching countries of every continent.
  defp show_rows(socket) do
    %{filtered: filtered, search_query: query, continent_code: continent} = socket.assigns
    %{field: field, dir: dir} = socket.assigns.sort

    countries =
      if query == "",
        do: filtered |> Enum.filter(&(code(&1) == continent)) |> Enum.flat_map(&children/1),
        else: Enum.flat_map(filtered, &children/1)

    rows =
      countries
      |> Enum.map(&row(&1, socket.assigns.counts))
      |> Enum.sort_by(&Map.get(&1, field), dir)

    assign(socket, rows: rows)
  end

  defp row(country, counts) do
    places =
      country
      |> children()
      |> Enum.map(&%{name: &1.name, url: &1.url, count: Map.get(counts, code(&1), 0)})
      |> Enum.sort_by(&{-&1.count, &1.name})

    %{
      id: country.key,
      key: country.key,
      name: country.name,
      url: country.url,
      count: Map.get(counts, code(country), 0),
      places: places
    }
  end

  defp busiest_continent(%{tree: tree, counts: counts}) do
    tree |> Enum.max_by(&Map.get(counts, code(&1), 0), fn -> %{key: "p-XN"} end) |> code()
  end

  defp children(node), do: Map.get(node, :nodes, [])
  defp code(%{key: "p-" <> code}), do: code

  @impl true
  def render(assigns) do
    assigns = assign(assigns, busiest: @busiest)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="places-browse-container" class="flex flex-col gap-section">
        <.page_header>
          <:title>Browse galls</:title>
          <:description>
            The galls known in each place: those whose host plants are native there, and
            those recorded there on introduced hosts.
            <span :if={@everywhere > 0}>
              {format_number(@everywhere)} galls with no range data aren't counted.
            </span>
          </:description>
        </.page_header>

        <.tab_nav label="Browse by" class="-mt-4">
          <:tab
            :for={{label, path} <- BrowseHelpers.browse_tabs()}
            navigate={path}
            current={path == "/places"}
          >
            {label}
          </:tab>
        </.tab_nav>

        <nav aria-label="Continents" class="grid grid-cols-2 gap-3 sm:grid-cols-4 2xl:grid-cols-8">
          <.continent_tile
            :for={continent <- Enum.sort_by(@tree, &(-Map.get(@counts, code(&1), 0)))}
            continent={continent}
            count={Map.get(@counts, code(continent))}
            current={@search_query == "" and code(continent) == @continent_code}
          />
        </nav>

        <div class="flex flex-wrap items-center gap-x-6 gap-y-3">
          <form
            id="places-browse-search-form"
            phx-change="search"
            phx-submit="search"
            class="w-full sm:w-80"
          >
            <.search_field
              id="places-browse-search"
              name="query"
              value={@search_query}
              label="Find a country, state or province"
              placeholder="Filter by name…"
            />
          </form>
          <div class="flex gap-2 sm:ml-auto">
            <.button variant="ghost" size="sm" phx-click="expand_all">
              Show all states and provinces
            </.button>
            <.button variant="ghost" size="sm" phx-click="collapse_all">Collapse all</.button>
          </div>
        </div>

        <.section
          title={
            if @search_query == "",
              do: continent_name(@tree, @continent_code),
              else: "Matching places"
          }
          count={"#{length(@rows)} countries"}
        >
          <.data_table id="countries" rows={@rows} row_navigate={& &1.url} sort={@sort}>
            <:col :let={c} label="Country" field={:name} sortable>{c.name}</:col>
            <:col :let={c} label="Galls" field={:count} sortable numeric>
              {format_number(c.count)}
            </:col>
            <:col :let={c} label="States and provinces, busiest first" grow wrap hide_below={:md}>
              <span :if={c.places != []} class="flex flex-wrap gap-x-1.5 text-meta text-ink-2">
                <span
                  :for={{place, i} <- Enum.with_index(shown(c, @expanded))}
                  class="whitespace-nowrap"
                >
                  <.link navigate={place.url}>{place.name}</.link>
                  <span class="tabular-nums text-muted">{format_number(place.count)}</span>{list_separator(
                    i,
                    shown(c, @expanded)
                  )}
                </span>
                <button
                  :if={length(c.places) > @busiest}
                  type="button"
                  phx-click="toggle_node"
                  phx-value-key={c.key}
                  aria-expanded={to_string(MapSet.member?(@expanded, c.key))}
                  class="text-link hover:underline"
                >
                  {if MapSet.member?(@expanded, c.key),
                    do: "Show fewer",
                    else: "#{length(c.places) - @busiest} more"}
                </button>
              </span>
            </:col>
            <:empty>
              {if @search_query != "", do: "No matching items found.", else: "No items found."}
            </:empty>
          </.data_table>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  attr :continent, :map, required: true
  attr :count, :integer, default: nil
  attr :current, :boolean, required: true

  defp continent_tile(assigns) do
    ~H"""
    <.link
      patch={"/places?c=#{code(@continent)}"}
      aria-current={@current && "page"}
      class={[
        "flex flex-col rounded-panel border bg-surface px-3 py-2 hover:no-underline",
        if(@current,
          do: "border-brand ring-1 ring-brand",
          else: "border-line hover:border-line-strong"
        )
      ]}
    >
      <span class="text-ui font-semibold text-ink">{@continent.name}</span>
      <span :if={@count} class="text-meta tabular-nums text-muted">
        {format_number(@count)} galls
      </span>
    </.link>
    """
  end

  # A country's states or provinces shown: the busiest few until opened.
  defp shown(row, expanded) do
    if MapSet.member?(expanded, row.key), do: row.places, else: Enum.take(row.places, @busiest)
  end

  defp continent_name(tree, code) do
    Enum.find_value(tree, "", &(code(&1) == code && &1.name))
  end
end
