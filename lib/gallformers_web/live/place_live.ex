defmodule GallformersWeb.PlaceLive do
  @moduledoc """
  The place page (`/place/:code`), on the design system (matter bc0d): the
  place in its breadcrumb, on the range map (a click on a sub-place opens
  its page), its sub-places with how many Galls are known to occur in each,
  and the Galls known to occur there (`gall_index.known_place_ids`: where
  their Hosts are native, or introduced and the Gall is recorded in the
  country), as photos or a table with facets (`GallformersWeb.RankGalls`).
  Galls with no range data, which the ID tool shows in every region, are
  known nowhere. The counts are read once the page connects.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.Places
  alias GallformersWeb.RankGalls

  import GallformersWeb.RankPageComponents, only: [rank_galls: 1]

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    place = Places.get_place_by_code!(code)
    descendant_codes = Places.get_descendant_codes(place.id)

    {:ok,
     socket
     |> assign(
       page_title: place.name,
       page_description:
         "#{place.name} (#{place.code}) — geographic place in the Gallformers database.",
       page_url: "/place/#{place.code}",
       page_image: nil,
       page_json_ld: nil,
       place: place,
       ancestors: Places.get_ancestors(place.id),
       children: Places.get_children(place.id),
       descendant_codes: descendant_codes,
       bounds: Places.get_bounds_for_codes(descendant_codes),
       search_query: "",
       sort: %{field: :name, dir: :asc}
     )
     |> load(connected?(socket))}
  end

  defp load(socket, false), do: assign(socket, galls: nil, counts: %{})

  defp load(socket, true) do
    galls = RankGalls.load(%{known_place_codes: [socket.assigns.place.code]})

    %{counts: counts} = Catalog.place_gall_counts()

    socket
    |> assign(galls: RankGalls.new(galls), counts: counts)
    |> compute()
  end

  defp compute(%{assigns: %{galls: nil}} = socket), do: socket

  defp compute(socket) do
    %{galls: galls, search_query: query, sort: sort} = socket.assigns
    assign(socket, galls: RankGalls.compute(galls, query, sort))
  end

  @impl true
  def handle_event("navigate_to_place", %{"code" => code}, socket) do
    {:noreply, push_navigate(socket, to: "/place/#{code}")}
  end

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     socket |> assign(search_query: query) |> update(:galls, &%{&1 | page: 1}) |> compute()}
  end

  def handle_event("sort", %{"field" => field}, socket)
      when field in ["name", "common_name", "count"] do
    %{field: current, dir: dir} = socket.assigns.sort

    {field, dir} =
      GallformersWeb.RankPage.toggle_sort(current, dir, String.to_existing_atom(field))

    {:noreply, socket |> assign(sort: %{field: field, dir: dir}) |> compute()}
  end

  def handle_event("galls_" <> _ = event, params, socket) do
    {:noreply, socket |> update(:galls, &RankGalls.handle(&1, event, params)) |> compute()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:crumb navigate="/places">Places</:crumb>
          <:crumb :for={ancestor <- @ancestors} navigate={"/place/#{ancestor.code}"}>
            {ancestor.name}
          </:crumb>
          <:title>{@place.name}</:title>
          <:chip variant={:rank}>{String.capitalize(@place.type)}</:chip>
          <:meta label="Code">{@place.code}</:meta>
        </.page_header>

        <div class="flex flex-wrap items-end gap-x-10 gap-y-4">
          <.stat :if={@galls} value={length(@galls.all)} label="Galls known here" />
          <.stat :if={@children != []} value={length(@children)} label={children_label(@place.type)} />
          <form
            :if={@galls && @galls.all != []}
            id="place-search-form"
            phx-change="search"
            phx-submit="search"
            class="w-full sm:ml-auto sm:w-80"
          >
            <.search_field
              id="place-search"
              name="query"
              value={@search_query}
              label="Filter galls by name or common name"
              placeholder="Filter galls by name or common name…"
            />
          </form>
        </div>

        <div class={if @children != [], do: "gf-with-rail", else: "max-w-text"}>
          <.range_map
            id="place-range-map"
            in_range={@descendant_codes}
            bounds={@bounds}
            navigable
            place_mode
            class="h-96 md:h-140"
          />
          <.rail :if={@children != []} width={:narrow} stack={:last}>
            <.panel title={children_label(@place.type)}>
              <ul id="sub-places" class="-mr-2 flex max-h-112 flex-col overflow-y-auto pr-2 text-ui">
                <li
                  :for={child <- Enum.sort_by(@children, &{-Map.get(@counts, &1.code, 0), &1.name})}
                  class="flex items-baseline justify-between gap-2 border-b border-line py-1 last:border-b-0"
                >
                  <.link navigate={"/place/#{child.code}"}>{child.name}</.link>
                  <span :if={@galls} class="text-meta tabular-nums text-muted">
                    {format_number(Map.get(@counts, child.code, 0))}
                  </span>
                </li>
              </ul>
            </.panel>
          </.rail>
        </div>

        <.rank_galls
          :if={@galls && @galls.all != []}
          id="place-galls"
          list={@galls}
          sort={@sort}
          narrowed={@search_query != ""}
          title="Galls known here"
        />

        <p class="text-meta text-muted">
          Galls whose host plants are native here, and galls recorded here on introduced hosts.
          <.link navigate="/places">Browse all places</.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  defp children_label("region"), do: "Continents"
  defp children_label("continent"), do: "Countries"
  defp children_label("country"), do: "Subdivisions"
  defp children_label(_), do: "Places within"
end
