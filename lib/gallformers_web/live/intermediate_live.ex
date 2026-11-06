defmodule GallformersWeb.IntermediateLive do
  @moduledoc """
  The pages of a family and the ranks between family and genus (subfamily,
  tribe, subtribe), on the design system (matter bc0d; behavior in
  docs/design-system/inventory/rank-pages.md). The rank comes from the
  route's live action.

  A Gallformer taxon shows two tabs (`?tab=`): its Galls, every Gall whose
  Inducer is in its subtree, the undescribed ones placed at the taxon too
  (`GallformersWeb.RankGalls`), and the taxa within it with their Galls. A
  plant taxon shows its genera (or the taxa within it) with their species
  and the Galls on them, and any Galls it induces. One name filter narrows
  both; one sort orders them. An unknown name, a name of another rank, and
  the routes for ranks the taxonomy no longer has (infratribe, supertribe,
  infrafamily) are 404s.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.RankGalls
  alias GallformersWeb.RankPage
  alias GallformersWeb.TaxonomyURL

  import GallformersWeb.RankPageComponents

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    rank = socket.assigns.live_action

    lookup =
      if rank in Rank.all(),
        do: RankPage.lookup(name, rank),
        else: {:ok, []}

    case lookup do
      {:redirect, path} -> {:ok, push_navigate(socket, to: path, replace: true)}
      {:ok, []} -> raise GallformersWeb.NotFoundError, "No #{rank} named #{name}"
      {:ok, [taxon | _]} -> {:ok, load(socket, taxon, name, rank)}
    end
  end

  defp load(socket, taxon, name, rank) do
    plants? = taxon.kingdom == "Plantae"
    children = children(taxon.id, plants?)
    galls = RankGalls.load(%{inducer_family_id: taxon.id})
    label = rank |> Atom.to_string() |> String.capitalize()

    socket
    |> assign(
      page_title: if(rank == :family, do: name, else: "#{label}: #{name}"),
      page_description: "#{name} - A taxonomic #{rank} documented on Gallformers.",
      page_url: TaxonomyURL.public_path(%{rank: rank, name: name}),
      page_image: nil,
      page_json_ld: nil,
      page_noindex: false,
      taxon: %{id: taxon.id, name: name, rank: rank, label: label},
      description: RankPage.description(taxon.id),
      crumbs: RankPage.crumbs(taxon.id),
      plants?: plants?,
      children: children,
      galls: RankGalls.new(galls),
      galls_on: if(plants?, do: galls_on(taxon.id), else: nil),
      search_query: "",
      sort: %{field: :name, dir: :asc}
    )
    |> compute()
  end

  # The taxa within, with their Galls: for a plant taxon the Galls on it
  # (its Host count); for others the Galls their Inducers cause.
  defp children(taxon_id, false), do: RankPage.children(taxon_id)

  defp children(taxon_id, true) do
    counts = Catalog.host_gall_counts()

    taxon_id
    |> RankPage.children()
    |> Enum.map(&%{&1 | gall_count: counts |> Map.get(&1.id, %{count: 0}) |> Map.fetch!(:count)})
  end

  defp galls_on(taxon_id), do: Catalog.host_gall_counts() |> Map.get(taxon_id, %{count: 0})

  @impl true
  def handle_params(params, _uri, socket) do
    tabs = tab_list(socket.assigns)

    tab =
      Enum.find(
        Enum.map(tabs, & &1.key),
        List.first(Enum.map(tabs, & &1.key)),
        &(&1 == params["tab"])
      )

    {:noreply, assign(socket, tab: tab, tabs: tabs)}
  end

  # The Galls tab when it has Galls, then the taxa within.
  defp tab_list(assigns) do
    galls = length(assigns.galls.all)
    children = length(assigns.children)

    within =
      if Enum.all?(assigns.children, &(&1.rank == "genus")), do: "Genera", else: "Within it"

    [
      galls > 0 && %{key: "galls", label: "Galls", count: galls},
      children > 0 && %{key: "within", label: within, count: children}
    ]
    |> Enum.filter(& &1)
  end

  defp compute(socket) do
    %{search_query: query, sort: sort, children: children} = socket.assigns

    assign(socket,
      galls: RankGalls.compute(socket.assigns.galls, query, sort),
      shown_children:
        children
        |> RankPage.filter_children(query)
        |> RankPage.sort_children(children_field(sort.field), sort.dir)
    )
  end

  defp children_field(field) when field in [:name, :type, :gall_count, :host_count], do: field
  defp children_field(_field), do: :name

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     socket |> assign(search_query: query) |> update(:galls, &%{&1 | page: 1}) |> compute()}
  end

  def handle_event("sort", %{"field" => field}, socket)
      when field in ["name", "type", "gall_count", "host_count", "common_name", "count"] do
    %{field: current, dir: dir} = socket.assigns.sort
    {field, dir} = RankPage.toggle_sort(current, dir, String.to_existing_atom(field))
    # A count reads best from the most.
    dir =
      if field in [:gall_count, :host_count, :count] and field != current, do: :desc, else: dir

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
          <:crumb :for={c <- @crumbs} navigate={c.path} italic={c.italic}>{c.name}</:crumb>
          <:title>{@taxon.name}</:title>
          <:chip variant={:rank}>{@taxon.label}</:chip>
          <:chip :if={@plants?}>Host plants</:chip>
          <:meta :if={@description} label="Common name">{@description}</:meta>
          <:action>
            <.admin_edit_link current_user={@current_user} taxon_id={@taxon.id} />
          </:action>
        </.page_header>

        <.empty_state :if={@tabs == []} title="No children found." />

        <div :if={@tabs != []} class="flex flex-wrap items-end gap-x-10 gap-y-4">
          <.stat :if={@plants?} value={@galls_on.count} label="Galls on it" />
          <.stat
            :if={@plants?}
            value={@children |> Enum.map(& &1.host_count) |> Enum.sum()}
            label="Species"
          />
          <.stat :if={@galls.all != []} value={length(@galls.all)} label="Galls" />
          <.stat
            :if={@galls.all != []}
            value={@galls.all |> Enum.flat_map(& &1.host_genera) |> Enum.uniq() |> length()}
            label="Host genera"
          />
          <.stat
            :if={@galls.all != []}
            value={Enum.count(@galls.all, & &1.undescribed)}
            label="Undescribed"
          />
          <form
            id={if @taxon.rank == :family, do: "family-search-form", else: "intermediate-search-form"}
            phx-change="search"
            phx-submit="search"
            class="w-full sm:ml-auto sm:w-80"
          >
            <.search_field
              id={if @taxon.rank == :family, do: "family-search", else: "intermediate-search"}
              name="query"
              value={@search_query}
              label="Filter by name or common name"
              placeholder="Filter by name or common name…"
            />
          </form>
        </div>

        <.tab_nav :if={length(@tabs) > 1} label="Show" class="-mb-2">
          <:tab :for={tab <- @tabs} patch={"?tab=#{tab.key}"} current={tab.key == @tab}>
            {tab.label}
            <span class="text-meta tabular-nums text-muted">{format_number(tab.count)}</span>
          </:tab>
        </.tab_nav>

        <.rank_galls
          :if={@tab == "galls"}
          id="rank-galls"
          list={@galls}
          sort={@sort}
          narrowed={@search_query != ""}
        />

        <.section
          :if={@tab == "within"}
          id="within"
          title={Enum.find(@tabs, &(&1.key == "within")).label}
          count={
            if length(@shown_children) == length(@children),
              do: format_number(length(@children)),
              else: "#{length(@shown_children)} of #{length(@children)}"
          }
        >
          <.children_list children={@shown_children} sort={@sort} plants={@plants?} />
        </.section>
      </div>
    </Layouts.app>
    """
  end
end
