defmodule GallformersWeb.SearchLive do
  @moduledoc """
  Global search across all entity types, on the design system (matter bc0d):

  - the query in the URL (`?q=`, push_patch), debounced as it is typed;
  - results of every type (galls, hosts, sources, glossary, taxonomy,
    places) in one `data_table`, by relevance, sortable by type and name,
    50 a page;
  - ↑/↓ (a window keydown) move a highlight, Enter opens the highlighted
    result, a click on a row highlights it;
  - the region filter (`region_scope`), and when a region leaves nothing,
    a way back to all regions.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.Search
  alias GallformersWeb.Live.ContinentScope
  alias GallformersWeb.TaxonomyURL

  @valid_sort_columns ~w(type name relevance)
  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Search",
       page_description:
         "Search the Gallformers database - find galls, host plants, sources, glossary terms, and taxonomic information.",
       page_url: "/globalsearch",
       page_image: nil,
       page_json_ld: nil,
       page_noindex: true,
       query: "",
       results: [],
       total_count: 0,
       current_page: 1,
       page_size: @page_size,
       sort_by: :relevance,
       sort_dir: :asc,
       selected_index: -1,
       type_filter: nil,
       page_results: [],
       total_pages_count: 1,
       shown_count: 0,
       details: %{},
       types: [],
       loading: false,
       default_continent_code: socket.assigns[:continent_code]
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params["q"] || ""

    socket =
      if query != socket.assigns.query do
        perform_search(socket, query)
      else
        socket
      end

    page_title =
      if query == "" do
        "Search"
      else
        "Search Results - '#{query}'"
      end

    types = socket.assigns.results |> Enum.map(& &1.category) |> MapSet.new()
    type = if params["type"] in types, do: params["type"]

    socket =
      if type != socket.assigns.type_filter,
        do: assign(socket, type_filter: type, current_page: 1, selected_index: -1),
        else: socket

    {:noreply, socket |> assign(query: query, page_title: page_title) |> assign_page()}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    # Update URL with the search query, triggering handle_params
    {:noreply, push_patch(socket, to: ~p"/globalsearch?#{%{q: query}}")}
  end

  @impl true
  def handle_event("search_input", %{"q" => query}, socket) do
    # Debounce is handled by phx-debounce on the input
    # This just updates the URL when debounce fires
    {:noreply, push_patch(socket, to: ~p"/globalsearch?#{%{q: query}}")}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    page = max(1, min(page, total_pages(shown(socket.assigns), socket.assigns.page_size)))
    {:noreply, socket |> assign(current_page: page, selected_index: -1) |> assign_page()}
  end

  @impl true
  def handle_event("sort", %{"field" => column}, socket) when column in @valid_sort_columns do
    column_atom = String.to_atom(column)

    {new_sort_by, new_sort_dir} =
      if socket.assigns.sort_by == column_atom do
        new_dir = if socket.assigns.sort_dir == :asc, do: :desc, else: :asc
        {column_atom, new_dir}
      else
        {column_atom, :asc}
      end

    {:noreply,
     socket
     |> assign(sort_by: new_sort_by, sort_dir: new_sort_dir, current_page: 1, selected_index: -1)
     |> assign_page()}
  end

  @impl true
  def handle_event("keydown", %{"key" => "ArrowDown"}, socket) do
    max_index = current_page_count(socket.assigns) - 1
    new_index = min(socket.assigns.selected_index + 1, max_index)
    {:noreply, assign(socket, selected_index: new_index)}
  end

  @impl true
  def handle_event("keydown", %{"key" => "ArrowUp"}, socket) do
    new_index = max(socket.assigns.selected_index - 1, -1)
    {:noreply, assign(socket, selected_index: new_index)}
  end

  @impl true
  def handle_event("keydown", %{"key" => "Enter"}, socket) do
    selected_index = socket.assigns.selected_index

    if selected_index >= 0 do
      case Enum.at(socket.assigns.page_results, selected_index) do
        nil ->
          {:noreply, socket}

        result ->
          {:noreply, push_navigate(socket, to: result_link(result))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_result", %{"index" => index}, socket) do
    index = if is_integer(index), do: index, else: String.to_integer(index)
    {:noreply, assign(socket, selected_index: index)}
  end

  @impl true
  def handle_event("change_region", %{"code" => code}, socket) do
    {continent_code, continent_name} =
      case code do
        "" -> {nil, nil}
        code -> {code, ContinentScope.continent_names()[code]}
      end

    socket =
      socket
      |> assign(continent_code: continent_code, continent_name: continent_name)
      |> perform_search(socket.assigns.query)
      |> assign(type_filter: nil)
      |> assign_page()

    {:noreply, socket}
  end

  defp perform_search(socket, query) do
    trimmed = String.trim(query)

    if trimmed == "" do
      assign(socket,
        results: [],
        total_count: 0,
        current_page: 1,
        selected_index: -1
      )
    else
      grouped = Search.global_search(trimmed, socket.assigns[:continent_code])
      results = flatten_results(grouped)

      assign(socket,
        results: results,
        total_count: length(results),
        current_page: 1,
        selected_index: -1
      )
    end
  end

  defp flatten_results(grouped) do
    galls = Enum.map(grouped.galls, &Map.put(&1, :category, "Gall"))
    hosts = Enum.map(grouped.hosts, &Map.put(&1, :category, "Host"))
    species = Enum.map(grouped.species, &Map.put(&1, :category, "Gallformer"))
    glossary = Enum.map(grouped.glossary, &Map.put(&1, :category, "Glossary"))
    sources = Enum.map(grouped.sources, &Map.put(&1, :category, "Source"))

    taxonomy =
      Enum.map(grouped.taxonomy, fn t ->
        category =
          case t.type do
            "genus" -> "Genus"
            "family" -> "Family"
            "intermediate" -> t.rank || "Taxonomy"
            "section" -> "Section"
            _ -> "Taxonomy"
          end

        Map.put(t, :category, category)
      end)

    places = Enum.map(grouped.places, &Map.put(&1, :category, "Place"))

    galls ++ species ++ hosts ++ glossary ++ sources ++ taxonomy ++ places
  end

  defp sorted_results(results, sort_by, sort_dir) do
    sorted = Enum.sort_by(results, &sort_key(&1, sort_by))
    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp sort_key(result, :type), do: result.category
  defp sort_key(result, :name), do: String.downcase(result.name || "")

  defp sort_key(result, :relevance),
    do: {result.match_score || 2, String.downcase(result.name || "")}

  defp sort_key(result, _), do: String.downcase(result.name || "")

  # The page the table shows, its rows' second lines and the type counts:
  # recomputed when the results, the type, the sort or the page change, not
  # on a keyboard highlight.
  defp assign_page(socket) do
    assigns = socket.assigns
    shown = shown(assigns)

    page_results =
      shown
      |> sorted_results(assigns.sort_by, assigns.sort_dir)
      |> paginated_results(assigns.current_page, assigns.page_size)
      |> Enum.with_index(fn result, index -> Map.put(result, :index, index) end)

    assign(socket,
      page_results: page_results,
      total_pages_count: total_pages(shown, assigns.page_size),
      shown_count: length(shown),
      details: details(page_results),
      types: type_counts(assigns.results)
    )
  end

  # The results the table shows: those of the chosen type, or all.
  defp shown(%{results: results, type_filter: nil}), do: results

  defp shown(%{results: results, type_filter: type}),
    do: Enum.filter(results, &(&1.category == type))

  # The result types present, in the page's order, each with its count.
  @type_order ~w(Gall Gallformer Host Family Subfamily Tribe Subtribe Genus Section Source Glossary Place)
  defp type_counts(results) do
    counts = Enum.frequencies_by(results, & &1.category)

    counts
    |> Map.keys()
    |> Enum.sort_by(&{Enum.find_index(@type_order, fn t -> t == &1 end) || 99, &1})
    |> Enum.map(&{&1, counts[&1]})
  end

  # What each result on the page shows on its second line, read for the
  # page only: a Gall's photo, Hosts and traits; how many Galls are on a
  # plant; a taxon's Galls.
  defp details(page_results) do
    by_type = Enum.group_by(page_results, & &1.type, & &1.id)
    gall_ids = Map.get(by_type, "gall", [])
    host_ids = Map.get(by_type, "host", [])

    taxon_ids =
      Enum.flat_map(~w(species genus family intermediate section), &Map.get(by_type, &1, []))

    %{
      galls: Catalog.gall_search_details(gall_ids),
      galls_on: if(host_ids == [], do: %{}, else: Catalog.count_galls_for_hosts(host_ids)),
      induced: if(taxon_ids == [], do: %{}, else: Catalog.count_galls_under(taxon_ids)),
      taxa_on:
        if(taxon_ids == [],
          do: %{},
          else:
            Catalog.host_gall_counts()
            |> Map.take(taxon_ids)
            |> Map.new(fn {k, v} -> {k, v.count} end)
        )
    }
  end

  defp paginated_results(results, current_page, page_size) do
    results
    |> Enum.drop((current_page - 1) * page_size)
    |> Enum.take(page_size)
  end

  defp total_pages(results, page_size) do
    max(1, ceil(length(results) / page_size))
  end

  defp current_page_count(assigns) do
    total = length(shown(assigns))
    page_start = (assigns.current_page - 1) * assigns.page_size
    max(0, min(assigns.page_size, total - page_start))
  end

  @type_icons %{
    "gall" => "gf-gall",
    "host" => "gf-host",
    "species" => "gf-taxon",
    "glossary" => "gf-entry",
    "source" => "gf-source",
    "genus" => "gf-taxon",
    "family" => "gf-taxon",
    "intermediate" => "gf-taxon",
    "section" => "gf-taxon",
    "place" => "gf-place"
  }

  defp result_link(%{type: "glossary", name: name}), do: ~p"/glossary##{String.downcase(name)}"
  defp result_link(%{type: "place", code: code}), do: "/place/#{code}"
  defp result_link(%{type: "species", id: id}), do: TaxonomyURL.species_path(id)

  defp result_link(%{type: type} = result)
       when type in ~w(genus family intermediate section) do
    TaxonomyURL.public_path(result) || "/"
  end

  defp result_link(%{type: type, id: id}) when type in ~w(gall host source), do: "/#{type}/#{id}"
  defp result_link(_), do: "/"

  defp type_icon(type), do: Map.get(@type_icons, type, "ph-question")

  # A result's second line, or nil.
  defp detail_line(%{type: "gall", id: id}, details) do
    case details.galls[id] do
      nil ->
        nil

      gall ->
        hosts =
          case gall.hosts do
            [] -> nil
            [one] -> "on #{one}"
            [first | rest] -> "on #{first} and #{length(rest)} more"
          end

        [hosts, Enum.join(gall.plant_part, ", "), Enum.join(gall.season, ", ")]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> join_or_nil()
    end
  end

  # A plant's common names are already among its other names, in brackets.
  defp detail_line(%{type: "host", id: id}, details),
    do: galls_text(Map.get(details.galls_on, id, 0))

  defp detail_line(%{type: "species", id: id}, details),
    do: galls_text(Map.get(details.induced, id, 0))

  defp detail_line(%{type: type, id: id} = result, details)
       when type in ~w(genus family intermediate section) do
    count = max(Map.get(details.induced, id, 0), Map.get(details.taxa_on, id, 0))
    [result[:description], galls_text(count)] |> Enum.reject(&(&1 in [nil, ""])) |> join_or_nil()
  end

  defp detail_line(%{type: "glossary"} = result, _details), do: result[:definition]

  defp detail_line(%{type: "place"} = result, _details),
    do: result[:kind] && String.capitalize(result.kind)

  defp detail_line(_result, _details), do: nil

  defp galls_text(0), do: nil
  defp galls_text(1), do: "1 gall"
  defp galls_text(n), do: "#{format_number(n)} galls"

  defp join_or_nil([]), do: nil
  defp join_or_nil(parts), do: Enum.join(parts, " · ")

  defp format_name(%{type: "place"} = result), do: "#{result.name} - #{result.code}"
  defp format_name(%{type: "source"} = result), do: format_source_name(result)

  defp format_name(%{type: type} = result) when type in ~w(genus section intermediate family),
    do: format_taxonomy_with_parent(result, self_type_label(result))

  defp format_name(result), do: result.name

  defp self_type_label(%{type: "intermediate", rank: rank}) when is_binary(rank), do: rank
  defp self_type_label(%{type: type}), do: String.capitalize(type)

  defp format_taxonomy_with_parent(result, type_label) do
    base = "#{type_label} #{result.name}"

    case Map.get(result, :parent_name) do
      nil -> base
      parent -> "#{base} - #{parent_type_label(result)} #{parent}"
    end
  end

  defp parent_type_label(%{parent_type: "intermediate", parent_rank: rank}) when is_binary(rank),
    do: rank

  defp parent_type_label(%{parent_type: type}) when is_binary(type),
    do: String.capitalize(type)

  defp parent_type_label(_), do: ""

  defp format_source_name(result) do
    author = result[:author] || "Unknown"
    year = result[:pubyear]
    title = result.name

    if year do
      "#{author} (#{year}): #{title}"
    else
      "#{author}: #{title}"
    end
  end

  defp search_type_to_rank("gall"), do: "species"
  defp search_type_to_rank("host"), do: "species"
  defp search_type_to_rank(type), do: type

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:subheader>
        <.region_scope
          continent_code={@continent_code}
          continent_name={@continent_name}
          default_continent_code={@default_continent_code}
        />
      </:subheader>
      <div id="search-container" phx-window-keydown="keydown" class="flex flex-col gap-section">
        <.page_header>
          <:title>Search</:title>
          <:description>Galls, host plants, sources, glossary terms, taxa and places.</:description>
        </.page_header>

        <form id="search-form" phx-submit="search" phx-change="search_input" class="max-w-xl">
          <.search_field
            id="global-search"
            name="q"
            value={@query}
            label="Search"
            placeholder="Search for galls, hosts, sources, glossary terms..."
          />
        </form>

        <div id="search-results-area">
          <.empty_state
            :if={@query == ""}
            id="search-empty-state"
            icon="ph-magnifying-glass"
            title="Enter a search term to find galls, hosts, sources, glossary entries, and more."
          />

          <div :if={@query != "" and @total_count == 0} id="search-no-results">
            <.empty_state
              :if={@continent_code}
              title={"No results for \"#{@query}\" in #{@continent_name}"}
            >
              You have a region filter active: try all regions, or adjust your search terms.
              <:action>
                <.button phx-click="change_region" phx-value-code="">All Regions</.button>
              </:action>
            </.empty_state>
            <.empty_state :if={!@continent_code} title={"No results for \"#{@query}\""}>
              Try adjusting your search terms or use fewer keywords.
            </.empty_state>
          </div>

          <.tab_nav :if={@total_count > 0} label="Result types" class="mb-4">
            <:tab patch={~p"/globalsearch?#{%{q: @query}}"} current={@type_filter == nil}>
              All <span class="text-meta tabular-nums text-muted">{format_number(@total_count)}</span>
            </:tab>
            <:tab
              :for={{type, count} <- @types}
              patch={~p"/globalsearch?#{%{q: @query, type: type}}"}
              current={@type_filter == type}
            >
              {type} <span class="text-meta tabular-nums text-muted">{format_number(count)}</span>
            </:tab>
          </.tab_nav>

          <.section
            :if={@total_count > 0}
            title={if @type_filter, do: "#{@type_filter} results", else: "Results"}
            count={"#{format_number(@shown_count)} for \"#{@query}\""}
          >
            <:aside>
              <span class="flex items-center gap-1">
                <kbd class="rounded-ctl border border-line-strong bg-surface-2 px-1 font-sans">↑</kbd>
                <kbd class="rounded-ctl border border-line-strong bg-surface-2 px-1 font-sans">↓</kbd>
                to move,
                <kbd class="rounded-ctl border border-line-strong bg-surface-2 px-1 font-sans">
                  Enter
                </kbd>
                to open
              </span>
            </:aside>
            <p id="results-count" class="sr-only">
              Found {@total_count} result{if @total_count != 1, do: "s", else: ""} for "{@query}"
            </p>
            <.data_table
              id="results-table"
              rows={@page_results}
              row_id={&"result-#{&1.index}"}
              row_click={&JS.push("select_result", value: %{index: &1.index})}
              active={&(&1.index == @selected_index)}
              sort={if @sort_by == :relevance, do: nil, else: %{field: @sort_by, dir: @sort_dir}}
              compact
            >
              <:col :let={result} label="Type" field={:type} sortable>
                <span class="inline-flex items-center gap-2 text-meta text-ink-2">
                  <.icon name={type_icon(result.type)} class="size-5 text-muted" />
                  <span data-part="type">{result.category}</span>
                </span>
              </:col>
              <:col :let={result} label="Name" field={:name} sortable grow full>
                <div class="flex items-center gap-3">
                  <% gall = result.type == "gall" && @details.galls[result.id] %>
                  <img
                    :if={gall && gall.image_url}
                    src={gall.image_url}
                    alt=""
                    loading="lazy"
                    class="size-10 shrink-0 rounded-ctl bg-surface-2 object-cover"
                  />
                  <span
                    :if={result.type == "gall" and !(gall && gall.image_url)}
                    class="flex size-10 shrink-0 items-center justify-center rounded-ctl bg-surface-2 text-muted"
                  >
                    <.icon name="gf-gall" class="size-5" />
                  </span>
                  <div class="min-w-0">
                    <.link href={result_link(result)}>
                      <.taxon_name
                        name={format_name(result)}
                        rank={search_type_to_rank(result.type)}
                        genus_placeholder={Map.get(result, :genus_placeholder, false) == true}
                      />
                    </.link>
                    <span :if={Map.get(result, :aliases, []) != []} class="ml-2 text-meta text-muted">
                      ({Enum.join(result.aliases, ", ")})
                    </span>
                    <p :if={detail_line(result, @details)} class="truncate text-meta text-ink-2">
                      {detail_line(result, @details)}
                    </p>
                  </div>
                </div>
              </:col>
              <:footer>
                <.pagination
                  :if={@total_pages_count > 1}
                  page={@current_page}
                  total_pages={@total_pages_count}
                  total_items={@total_count}
                  page_size={@page_size}
                  on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
                />
              </:footer>
            </.data_table>
          </.section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
