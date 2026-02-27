defmodule GallformersWeb.SearchLive do
  @moduledoc """
  LiveView for global search across all entity types.

  Provides a unified search experience with:
  - Debounced search input
  - Results grouped by type (galls, hosts, sources, glossary, taxonomy, places)
  - Pagination (50 results per page)
  - Sortable results table
  - Keyboard navigation
  - URL sync via push_patch
  """
  use GallformersWeb, :live_view

  alias Gallformers.Search
  alias GallformersWeb.Live.ContinentScope

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

    {:noreply, assign(socket, query: query, page_title: page_title)}
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
    page = max(1, min(page, total_pages(socket.assigns.results, socket.assigns.page_size)))
    {:noreply, assign(socket, current_page: page, selected_index: -1)}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket) when column in @valid_sort_columns do
    column_atom = String.to_atom(column)

    {new_sort_by, new_sort_dir} =
      if socket.assigns.sort_by == column_atom do
        new_dir = if socket.assigns.sort_dir == :asc, do: :desc, else: :asc
        {column_atom, new_dir}
      else
        {column_atom, :asc}
      end

    {:noreply,
     assign(socket,
       sort_by: new_sort_by,
       sort_dir: new_sort_dir,
       current_page: 1,
       selected_index: -1
     )}
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
      page_results =
        socket.assigns.results
        |> sorted_results(socket.assigns.sort_by, socket.assigns.sort_dir)
        |> paginated_results(socket.assigns.current_page, socket.assigns.page_size)

      case Enum.at(page_results, selected_index) do
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
  def handle_event("select_result", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
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
    glossary = Enum.map(grouped.glossary, &Map.put(&1, :category, "Glossary"))
    sources = Enum.map(grouped.sources, &Map.put(&1, :category, "Source"))

    taxonomy =
      Enum.map(grouped.taxonomy, fn t ->
        category =
          case t.type do
            "genus" -> "Genus"
            "family" -> "Family"
            "section" -> "Section"
            _ -> "Taxonomy"
          end

        Map.put(t, :category, category)
      end)

    places = Enum.map(grouped.places, &Map.put(&1, :category, "Place"))

    galls ++ hosts ++ glossary ++ sources ++ taxonomy ++ places
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

  defp paginated_results(results, current_page, page_size) do
    results
    |> Enum.drop((current_page - 1) * page_size)
    |> Enum.take(page_size)
  end

  defp total_pages(results, page_size) do
    max(1, ceil(length(results) / page_size))
  end

  defp current_page_count(assigns) do
    total = length(assigns.results)
    page_start = (assigns.current_page - 1) * assigns.page_size
    max(0, min(assigns.page_size, total - page_start))
  end

  @type_icons %{
    "gall" => "gf-gall",
    "host" => "gf-host",
    "glossary" => "gf-entry",
    "source" => "gf-source",
    "genus" => "gf-taxon",
    "family" => "gf-taxon",
    "section" => "gf-taxon",
    "place" => "gf-place"
  }

  defp result_link(%{type: "glossary", name: name}), do: ~p"/glossary##{String.downcase(name)}"
  defp result_link(%{type: "place", code: code}), do: "/place/#{code}"
  defp result_link(%{type: type, id: id}), do: build_entity_link(type, id)

  defp build_entity_link(type, id) when type in ~w(gall host source genus family section) do
    "/#{type}/#{id}"
  end

  defp build_entity_link(_type, _id), do: "/"

  defp type_icon(type), do: Map.get(@type_icons, type, "ph-question")

  # Gall icon (wasp) needs larger size like V1 (45px vs 25px ratio)
  defp search_result_icon_class("gall"), do: "w-10 h-8 text-gray-500"
  defp search_result_icon_class(_type), do: "w-6 h-6 text-gray-500"

  defp format_name(result) do
    case result.type do
      "gall" -> result.name
      "host" -> result.name
      "genus" -> format_taxonomy_with_parent(result, "Genus", "Family")
      "section" -> format_taxonomy_with_parent(result, "Section", "Genus")
      "family" -> "Family #{result.name}"
      "place" -> "#{result.name} - #{result.code}"
      "source" -> format_source_name(result)
      _ -> result.name
    end
  end

  defp format_taxonomy_with_parent(result, type_label, parent_type_label) do
    base = "#{type_label} #{result.name}"

    case Map.get(result, :parent_name) do
      nil -> base
      parent -> "#{base} - #{parent_type_label} #{parent}"
    end
  end

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
    sorted = sorted_results(assigns.results, assigns.sort_by, assigns.sort_dir)
    page_results = paginated_results(sorted, assigns.current_page, assigns.page_size)

    assigns =
      assigns
      |> assign(:page_results, page_results)
      |> assign(:total_pages_count, total_pages(assigns.results, assigns.page_size))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:subheader>
        <.region_scope
          continent_code={@continent_code}
          continent_name={@continent_name}
          default_continent_code={@default_continent_code}
        />
      </:subheader>
      <div id="search-container" phx-window-keydown="keydown">
        <form id="search-form" phx-submit="search" phx-change="search_input" class="mb-6">
          <.search_input
            id="global-search"
            name="q"
            value={@query}
            placeholder="Search for galls, hosts, sources, glossary terms..."
            phx-debounce="300"
          />
        </form>

        <div id="search-results-area">
          <%= if @query == "" do %>
            <div id="search-empty-state" class="bg-gray-50 rounded-lg p-8 text-center text-gray-600">
              <.icon name="ph-magnifying-glass" class="w-12 h-12 mx-auto mb-4 text-gray-400" />
              <p class="text-lg">
                Enter a search term to find galls, hosts, sources, glossary entries, and more.
              </p>
            </div>
          <% else %>
            <%= if @total_count == 0 do %>
              <div
                id="search-no-results"
                class="bg-gray-50 border border-gray-200 px-6 py-4 rounded-lg"
              >
                <p class="font-medium text-gray-900">No results for "{@query}"</p>
                <p class="text-sm text-gray-600 mt-1">
                  Try adjusting your search terms or use fewer keywords.
                </p>
              </div>
            <% else %>
              <div id="results-count" class="mb-4 text-sm text-gray-600">
                Found {@total_count} result{if @total_count != 1, do: "s", else: ""} for "{@query}"
              </div>

              <div class="bg-white rounded-lg shadow overflow-hidden">
                <table class="gf-table gf-table-compact" id="results-table">
                  <thead>
                    <tr>
                      <th
                        class="sortable w-16"
                        phx-click="sort"
                        phx-value-column="type"
                      >
                        Type
                        <span :if={@sort_by == :type} class="ml-1">
                          {if @sort_dir == :asc, do: "↑", else: "↓"}
                        </span>
                      </th>
                      <th
                        class="sortable"
                        phx-click="sort"
                        phx-value-column="name"
                      >
                        Name
                        <span :if={@sort_by == :name} class="ml-1">
                          {if @sort_dir == :asc, do: "↑", else: "↓"}
                        </span>
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={{result, index} <- Enum.with_index(@page_results)}
                      id={"result-#{index}"}
                      class={[
                        "cursor-pointer",
                        if(index == @selected_index, do: "!bg-canary")
                      ]}
                      phx-click="select_result"
                      phx-value-index={index}
                    >
                      <td class="!py-1 !px-2 w-16 align-middle">
                        <div class="w-12 h-8 flex items-center justify-center">
                          <.icon
                            name={type_icon(result.type)}
                            class={search_result_icon_class(result.type)}
                          />
                        </div>
                      </td>
                      <td class="!py-1 !px-2 align-middle">
                        <.link
                          href={result_link(result)}
                          class="hover:underline"
                        >
                          <.taxon_name
                            name={format_name(result)}
                            rank={search_type_to_rank(result.type)}
                          />
                        </.link>
                        <span
                          :if={Map.get(result, :aliases, []) != []}
                          class="text-sm text-gray-500 ml-2"
                        >
                          ({Enum.join(result.aliases, ", ")})
                        </span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <.pagination
                :if={@total_pages_count > 1}
                page={@current_page}
                total_pages={@total_pages_count}
                total_items={@total_count}
                page_size={@page_size}
                on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
                class="mt-4"
              />

              <div class="mt-4 text-xs text-gray-500 flex items-center gap-1">
                <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded">↑</kbd>
                <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded">↓</kbd>
                <span>to navigate,</span>
                <kbd class="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded">Enter</kbd>
                <span>to select</span>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
