defmodule GallformersWeb.GenusLive do
  @moduledoc """
  The genus page (design system, matter bc0d; behavior in
  docs/design-system/inventory/rank-pages.md). A genus
  (`Gallformers.Taxa.get_by_name/2`) with its lineage and up to three
  lists, each shown when it has rows (a genus can have both, e.g.
  mistletoes):

    * **Galls** — the Galls whose Inducer is in the genus (its species, the
      genus itself for undescribed Galls, a section in it), as photos or a
      table with facets (`GallformersWeb.RankGalls`);
    * **Species** — the plants in the genus with their Galls, filterable by
      the Gallformer genera with Galls on them (the rail);
    * **Galls on the genus as a whole** — the Galls whose Host is the genus
      itself (today's "Genus spp." placeholder plants), in the rail.

  One name filter narrows every list, and one sort orders both tables.

  A genus name used more than once (e.g. in two kingdoms) offers each,
  with its family; `?family=` picks one. Data through
  `GallformersWeb.RankPage` and `Gallformers.Catalog`.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.Taxa
  alias GallformersWeb.RankGalls
  alias GallformersWeb.RankPage
  alias GallformersWeb.TaxonomyURL

  import GallformersWeb.RankPageComponents

  @impl true
  def mount(%{"name" => name} = params, _session, socket) do
    case RankPage.lookup(name, :genus) do
      {:redirect, path} ->
        {:ok, push_navigate(socket, to: path, replace: true)}

      {:ok, []} ->
        raise GallformersWeb.NotFoundError, "No genus named #{name}"

      {:ok, [genus]} ->
        {:ok, assign_genus_data(socket, genus.id, name)}

      {:ok, genera} ->
        {:ok, resolve_disambiguation(socket, name, params["family"], genera)}
    end
  end

  defp resolve_disambiguation(socket, name, family_hint, genera) do
    lineages = genera |> Enum.map(& &1.id) |> Taxa.lineages()
    family_of = &Enum.find(Map.get(lineages, &1.id, []), fn t -> t.rank == :family end)

    case Enum.find(genera, &(family_hint != nil && match?(%{name: ^family_hint}, family_of.(&1)))) do
      %{id: id} -> assign_genus_data(socket, id, name)
      nil -> assign_disambiguation(socket, name, genera, family_of)
    end
  end

  defp assign_disambiguation(socket, name, genera, family_of) do
    ids = Enum.map(genera, & &1.id)
    gall_counts = Catalog.count_galls_under(ids)
    host_counts = Taxa.count_plants_under(ids)

    options =
      Enum.map(genera, fn genus ->
        family = family_of.(genus)

        %{
          name: name,
          family_name: (family && family.name) || "Unknown",
          family_description: family && RankPage.description(family.taxon_id),
          species_count: gall_counts[genus.id] + host_counts[genus.id]
        }
      end)

    assign(socket,
      page_title: "Genus #{name} — Disambiguation",
      page_description:
        "Multiple genera named #{name} exist on Gallformers under different families.",
      page_url: nil,
      page_image: nil,
      page_json_ld: nil,
      page_noindex: true,
      genus: nil,
      disambiguation: options
    )
  end

  defp assign_genus_data(socket, id, name) do
    galls = RankGalls.load(%{inducer_family_id: id})
    plants = RankPage.host_rows(id)
    on_genus = RankPage.galls_on_hosts([id])

    inducers =
      if plants == [],
        do: [],
        else: plants |> Enum.map(& &1.id) |> Catalog.inducer_genera_on_hosts()

    total = length(galls) + length(plants) + length(on_genus)

    socket
    |> assign(
      page_title: "Genus #{name}",
      page_description:
        "#{name} - A taxonomic genus documented on Gallformers with #{total} species.",
      page_url: TaxonomyURL.public_path(%{rank: :genus, name: name}),
      page_image: nil,
      page_json_ld: nil,
      page_noindex: total == 0,
      genus: %{id: id, name: name, description: RankPage.description(id)},
      crumbs: RankPage.crumbs(id),
      disambiguation: nil,
      galls: RankGalls.new(galls),
      plants: plants,
      on_genus: on_genus,
      inducers: inducers,
      selected_inducer: nil,
      total: total,
      search_query: "",
      sort: %{field: :name, dir: :asc}
    )
    |> compute()
  end

  # The lists as shown: narrowed by the name filter (and the plants by the
  # chosen Gallformer genus), sorted by the page's sort.
  defp compute(%{assigns: %{genus: nil}} = socket), do: socket

  defp compute(socket) do
    %{search_query: query, sort: sort, selected_inducer: selected} = socket.assigns
    field = if sort.field in [:name, :common_name, :count], do: sort.field, else: :name

    plants =
      case Enum.find(socket.assigns.inducers, &(&1.taxon_id == selected)) do
        nil -> socket.assigns.plants
        genus -> Enum.filter(socket.assigns.plants, &(&1.id in genus.focal_ids))
      end

    assign(socket,
      galls: RankGalls.compute(socket.assigns.galls, query, sort),
      shown_plants: plants |> RankPage.filter_rows(query) |> RankPage.sort_rows(field, sort.dir),
      shown_on_genus: RankPage.filter_rows(socket.assigns.on_genus, query)
    )
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     socket |> assign(search_query: query) |> update(:galls, &%{&1 | page: 1}) |> compute()}
  end

  def handle_event("sort", %{"field" => field}, socket)
      when field in ["name", "common_name", "count"] do
    %{field: current, dir: dir} = socket.assigns.sort
    {field, dir} = RankPage.toggle_sort(current, dir, String.to_existing_atom(field))
    {:noreply, socket |> assign(sort: %{field: field, dir: dir}) |> compute()}
  end

  def handle_event("plants_filter", %{"id" => id}, socket) do
    selected = if id == "all", do: nil, else: String.to_integer(id)
    {:noreply, socket |> assign(selected_inducer: selected) |> compute()}
  end

  def handle_event("galls_" <> _ = event, params, socket) do
    {:noreply, socket |> update(:galls, &RankGalls.handle(&1, event, params)) |> compute()}
  end

  @impl true
  def render(%{disambiguation: options} = assigns) when options != nil do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:title name>Genus {hd(@disambiguation).name}</:title>
          <:description>
            This genus name exists under multiple families. Select the one you're looking for:
          </:description>
        </.page_header>
        <ul class="grid max-w-form gap-3">
          <li :for={option <- @disambiguation}>
            <.link
              navigate={"/genus/#{URI.encode(option.name)}?family=#{URI.encode(option.family_name)}"}
              class="flex flex-col gap-0.5 rounded-panel border border-line bg-surface p-3 hover:border-line-strong hover:no-underline"
            >
              <span class="font-semibold">
                <.taxon_name name={option.name} rank="genus" />
                <span class="font-normal text-ink-2">
                  in Family {option.family_name}
                  <span :if={option.family_description not in [nil, ""]}>
                    ({option.family_description})
                  </span>
                </span>
              </span>
              <span class="text-meta text-muted">{option.species_count} species</span>
            </.link>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:crumb :for={c <- @crumbs} navigate={c.path} italic={c.italic}>{c.name}</:crumb>
          <:title name>{@genus.name}</:title>
          <:chip variant={:rank}>Genus</:chip>
          <:chip :if={@plants != [] and @galls.all == []}>Host plants</:chip>
          <:meta :if={@genus.description} label="Common name">{@genus.description}</:meta>
          <:action>
            <.button
              :if={@plants != []}
              navigate={"/id?g=#{URI.encode_www_form(@genus.name)}"}
              variant="primary"
              icon="ph-magnifying-glass-plus"
            >
              Identify a gall on {@genus.name}
            </.button>
            <.admin_edit_link current_user={@current_user} taxon_id={@genus.id} />
          </:action>
        </.page_header>

        <.empty_state :if={@total == 0} title="No species found for this genus." />

        <div :if={@total > 0} class="flex flex-wrap items-end gap-x-10 gap-y-4">
          <.stat :if={@galls.all != []} value={length(@galls.all)} label="Galls" />
          <.stat
            :if={@galls.all != []}
            value={@galls.all |> Enum.flat_map(& &1.host_genera) |> Enum.uniq() |> length()}
            label="Host genera"
          />
          <.stat :if={@plants != []} value={length(@plants)} label="Species" />
          <.stat
            :if={@plants != []}
            value={Enum.count(@plants, &(&1.count > 0))}
            label="Species with galls"
          />
          <.stat :if={@inducers != []} value={length(@inducers)} label="Gallformer genera" />
          <form
            id="genus-search-form"
            phx-change="search"
            phx-submit="search"
            class="w-full sm:ml-auto sm:w-80"
          >
            <.search_field
              id="genus-search"
              name="query"
              value={@search_query}
              label="Filter by name or common name"
              placeholder="Filter by name or common name…"
            />
          </form>
        </div>

        <.rank_galls
          :if={@galls.all != []}
          id="genus-galls"
          list={@galls}
          sort={@sort}
          narrowed={@search_query != ""}
        />

        <div :if={@plants != [] or @on_genus != []} class="gf-with-rail">
          <div class="min-w-0">
            <.plant_table
              :if={@plants != []}
              id="genus-hosts"
              rows={@shown_plants}
              total={length(@plants)}
              sort={@sort}
            />
          </div>
          <.rail width={:narrow} stack={:last}>
            <.inducer_genera_panel
              :if={@inducers != []}
              name={@genus.name}
              genera={@inducers}
              selected={@selected_inducer}
            />
            <.galls_on_panel :if={@shown_on_genus != []} name={@genus.name} galls={@shown_on_genus} />
          </.rail>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
