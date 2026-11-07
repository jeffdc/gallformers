defmodule GallformersWeb.Dev.Mockups.SpeciesFactsLive do
  @moduledoc """
  Mockup (matter `d3b0`): the species page (`GallformersWeb.SpeciesLive`)
  with its taxonomy edited in a Facts panel.
  `/dev/mockups/species-facts/:id?edit`.

  A copy of `GallformersWeb.SpeciesLive`: its mount and data as they are,
  its render changed. In Edit mode the Taxonomy section is presentation,
  each part with "✎ in Facts"; the Facts panel (placement, name with
  authorship, synonyms, common names, splits and lumps) holds every edit,
  as a Gallformers change or a correction under the Source that stated
  it, in place of today's Names and placement panel and its "Based on
  which Source?" dialog. Read-only: see
  `GallformersWeb.Dev.Mockups.FactEditMock`.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Catalog, Import, Places, Taxa}
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.ReadModels.SpeciesPage
  alias GallformersWeb.Dev.Mockups.FactEditMock, as: Mock
  alias GallformersWeb.RankGalls
  alias GallformersWeb.RankPage
  alias GallformersWeb.TaxonomyURL

  import GallformersWeb.FactsComponents, only: [taxonomic_position: 1]
  import GallformersWeb.RankPageComponents, only: [rank_galls: 1]

  import GallformersWeb.Dev.Mockups.FactEditMock,
    only: [
      mockup_notice: 1,
      fact_link: 1,
      facts_panel: 1,
      authority_tray: 1,
      review_dialog: 1,
      fact_dom: 1,
      category_dom: 1
    ]

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    case Integer.parse(id) do
      {taxon_id, ""} ->
        socket
        |> assign(editing: false, map_open: false, rank_sort: %{field: :name, dir: :asc})
        |> load(taxon_id, params)

      _ ->
        raise GallformersWeb.NotFoundError, "No species #{id}"
    end
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, assign(socket, editing: Map.has_key?(params, "edit"))}

  defp load(socket, taxon_id, params) do
    case Taxa.species_page(taxon_id) do
      {:ok, %SpeciesPage{} = species} ->
        panel = Mock.taxon_panel(species.id)
        seed = if Map.has_key?(params, "empty"), do: [], else: Mock.examples(panel, [])

        {:ok,
         socket
         |> assign_species(species)
         |> assign(panel: panel)
         |> Mock.init(seed)}

      _ ->
        raise GallformersWeb.NotFoundError, "No species #{taxon_id} (the mockup takes a species)"
    end
  end

  defp assign_species(socket, %SpeciesPage{} = species) do
    galls = RankGalls.load(%{inducer_family_id: species.id})
    gall_ids = Enum.map(galls, & &1.id)

    {range, inherited, introduced} =
      case Catalog.display_range_for_galls(gall_ids) do
        :everywhere -> {[], [], []}
        range -> {range.in_range, range.inherited_range, range.introduced_range}
      end

    assign(socket,
      page_title: "Mockup: " <> species.name,
      page_description: nil,
      page_url: nil,
      page_image: nil,
      page_json_ld: nil,
      page_noindex: true,
      species: species,
      crumbs: crumbs(species.lineage),
      parent: species.lineage |> Enum.drop(-1) |> List.last(),
      galls: RankGalls.new(galls),
      gall_names: Map.new(galls, &{&1.id, &1.name}),
      position: Import.taxonomic_position(species.id),
      splits: Import.taxon_splits(species.id),
      sources: Catalog.species_sources(species.id, gall_ids),
      range: range,
      inherited_range: inherited,
      introduced_range: introduced,
      range_bounds: Places.get_bounds_for_codes((range -- introduced) ++ inherited)
    )
  end

  defp crumbs(lineage) do
    for taxon <- Enum.drop(lineage, -1), path = crumb_path(taxon), path != nil do
      %{
        name: crumb_name(taxon),
        path: path,
        italic: taxon.rank in [:genus, :section | Rank.species_and_below()]
      }
    end
  end

  defp crumb_path(%{rank: rank, taxon_id: id} = taxon) do
    if rank in Rank.species_and_below(),
      do: TaxonomyURL.species_path(id),
      else: TaxonomyURL.public_path(taxon)
  end

  defp crumb_name(%{rank: :section, name: name}), do: "sect. " <> name
  defp crumb_name(%{name: name}), do: name

  # -- events ------------------------------------------------------------------

  @impl true
  def handle_event("galls_" <> _ = event, params, socket),
    do: {:noreply, update(socket, :galls, &RankGalls.handle(&1, event, params))}

  def handle_event("sort", %{"field" => field}, socket)
      when field in ["name", "common_name", "count"] do
    %{field: current, dir: dir} = socket.assigns.rank_sort
    {field, dir} = RankPage.toggle_sort(current, dir, String.to_existing_atom(field))
    {:noreply, assign(socket, rank_sort: %{field: field, dir: dir})}
  end

  def handle_event("open_map", _params, socket), do: {:noreply, assign(socket, map_open: true)}
  def handle_event("close_map", _params, socket), do: {:noreply, assign(socket, map_open: false)}

  def handle_event("navigate_to_place", %{"code" => code}, socket),
    do: {:noreply, push_navigate(socket, to: "/place/#{code}")}

  def handle_event(event, params, socket) do
    if event in Mock.events(),
      do: {:noreply, Mock.handle(event, params, socket)},
      else: {:noreply, socket}
  end

  # The panel's first Fact in category `id`, as its DOM id.
  defp first_fact(panel, id) do
    case Enum.find(panel, &(&1.id == id)) do
      %{facts: [fact | _]} -> fact_dom(fact.key)
      _ -> category_dom(id)
    end
  end

  # The panel's Fact in category `id` whose text names `name`.
  defp named_fact(panel, id, name) do
    with %{facts: facts} <- Enum.find(panel, &(&1.id == id)),
         %{key: key} <- Enum.find(facts, &String.contains?(&1.text, name)) do
      fact_dom(key)
    else
      _ -> category_dom(id)
    end
  end

  # -- render ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, list: RankGalls.compute(assigns.galls, "", assigns.rank_sort))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class={["flex flex-col gap-section", @editing && @mock_items != [] && "pb-72"]}>
        <.mockup_notice real="the species, its Galls, its lineage, synonyms and common names, every taxonomic statement about it and its standing (taxonomic_position, taxon_splits, the Sources' taxonomic statements), the taxon searches.">
          This database holds almost no taxonomic statements (one common name, Aphis rubifolii's, from InfluentialPoints, awaiting a curator): what the tree holds without one is shown as such, with its Gallformers actions; "Correct &lt;Source&gt;'s statement…" shows where a Source has one.
        </.mockup_notice>

        <.page_header>
          <:crumb :for={c <- @crumbs} navigate={c.path} italic={c.italic}>{c.name}</:crumb>
          <:title name>
            <.taxon_name name={@species.name} />
            <span :if={@species.authorship} class="font-normal not-italic text-ink-2">
              {@species.authorship}
            </span>
          </:title>
          <:chip variant={:rank}>{@species.rank |> Atom.to_string() |> String.capitalize()}</:chip>
          <:chip>Gallformer</:chip>
          <:meta :if={@species.common_names != []} label="Common name">
            {Enum.map_join(@species.common_names, ", ", & &1.name)}
          </:meta>
          <:action>
            <.edit_toggle editing={@editing} path={"/dev/mockups/species-facts/#{@species.id}"} />
          </:action>
        </.page_header>

        <div :if={@editing} id="editing" class="flex flex-col gap-2">
          <.notice kind={:info} title="Editing">
            Its taxonomy is edited in the Facts panel: a Gallformers change, or a correction under the Source that stated it. No "Based on which Source?" dialog: the action you choose says whose authority it is under. Each change goes into your tray at the foot of the screen.
            <:action><.fact_link to="species-facts-panel" label="Go to the Facts panel" /></:action>
          </.notice>
          <.edit_scope kind={:follows}>
            Its Galls follow from each Gall's Inducer: edit a Gall on its own page (✎ on its card).
          </.edit_scope>
          <.edit_scope kind={:elsewhere} href={~p"/admin/taxonomy/#{@species.id}"}>
            Its photos, and deleting it: on the taxonomy of <i>{@species.name}</i>.
          </.edit_scope>
        </div>

        <div class="gf-with-rail">
          <div class="flex min-w-0 flex-col gap-section">
            <.rank_galls
              :if={@galls.all != []}
              id="species-galls"
              list={@list}
              sort={@rank_sort}
              narrowed={false}
              edit_path={if @editing, do: &"/dev/mockups/gall-facts/#{&1.id}?edit"}
            />
            <.empty_state :if={@galls.all == []} title="No galls recorded for it yet." />

            <.section id="species-taxonomy" title="Taxonomy">
              <:aside :if={@editing}><.fact_link to="species-facts-panel" /></:aside>
              <div class="flex flex-col gap-block">
                <.taxonomic_position id="species-position" position={@position} />

                <.fact_list
                  :if={@editing}
                  id="species-presentation"
                  layout={:inline}
                  missing_label={nil}
                >
                  <:item :if={@parent} label="Placed">
                    under <.taxon_name name={@parent.name} rank={to_string(@parent.rank)} />
                    <.fact_link to={first_fact(@panel, "placement")} />
                  </:item>
                  <:item label="Name">
                    <.taxon_name name={@species.name} />
                    <span :if={@species.authorship}>{@species.authorship}</span>
                    <.fact_link to={first_fact(@panel, "name")} />
                  </:item>
                </.fact_list>

                <.fact_list
                  :if={@species.synonyms != []}
                  id="species-synonyms"
                  layout={:inline}
                  missing_label={nil}
                >
                  <:item label="Synonyms">
                    <span :for={{s, i} <- Enum.with_index(@species.synonyms)}>
                      {if i > 0, do: " · "}<.taxon_name name={s.name} />
                      <span :if={s.sensu} class="text-meta text-muted">sensu {s.sensu}</span>
                      <.fact_link :if={@editing} to={named_fact(@panel, "synonyms", s.name)} />
                    </span>
                  </:item>
                </.fact_list>

                <.fact_list
                  :if={@editing and @species.common_names != []}
                  id="species-common-names"
                  layout={:inline}
                  missing_label={nil}
                >
                  <:item label="Common names">
                    <span :for={{c, i} <- Enum.with_index(@species.common_names)}>
                      {if i > 0, do: " · "}{c.name}
                      <.fact_link to={named_fact(@panel, "common_names", c.name)} />
                    </span>
                  </:item>
                </.fact_list>

                <.fact_list
                  :if={@splits != [] or @species.merged != []}
                  id="species-history"
                  layout={:inline}
                  missing_label={nil}
                >
                  <:item :if={@splits != []} label="Split">
                    <span :for={s <- @splits} data-part="split">
                      {if s.taxon.taxon_id == @species.id, do: "Split into ", else: "Split from "}
                      {if s.taxon.taxon_id == @species.id,
                        do: Enum.map_join(s.into, ", ", & &1.name),
                        else: s.taxon.name}
                    </span>
                  </:item>
                  <:item :if={@species.merged != []} label="Merged into it">
                    <span :for={m <- @species.merged} data-part="merged">
                      <.taxon_name :if={m.name} name={m.name} />
                      <span class="text-caption text-muted">· {format_date(m.at, :short)}</span>
                    </span>
                  </:item>
                </.fact_list>
              </div>
            </.section>

            <.section :if={@editing} id="species-facts" title="Facts">
              <:aside>Every edit of its taxonomy begins and ends here</:aside>
              <.facts_panel
                id="species-facts-panel"
                title={"#{@species.name}: its taxonomy"}
                categories={@panel}
                edit={@mock_edit}
                pick={@mock_pick}
                error={@mock_error}
                items={@mock_items}
              />
            </.section>

            <.section id="species-sources-section" title="Sources" count={length(@sources)}>
              <.data_table :if={@sources != []} id="species-sources" rows={@sources}>
                <:col :let={s} label="Year" numeric>{s.pubyear || "n.d."}</:col>
                <:col :let={s} label="Source" grow wrap>
                  <.link navigate={~p"/source/#{s.id}"} class="font-semibold">{s.title}</.link>
                  <span :if={s.author} class="text-meta text-ink-2">· {s.author}</span>
                </:col>
                <:col :let={s} label="Covers" wrap>
                  {covers(s, @gall_names)}
                </:col>
              </.data_table>
              <p :if={@sources == []} class="text-ui text-muted">
                No Source cites it or its galls yet.
              </p>
            </.section>
          </div>

          <.rail width={:wide}>
            <.panel title="Where it occurs">
              <:header_action>
                <.button
                  :if={@range != [] or @inherited_range != []}
                  variant="ghost"
                  size="sm"
                  icon="ph-arrows-out"
                  phx-click="open_map"
                >
                  Enlarge
                </.button>
              </:header_action>
              <p :if={@range == [] and @inherited_range == []} class="text-ui text-muted">
                Range unknown: no host range data for its galls.
              </p>
              <.range_map
                :if={(@range != [] or @inherited_range != []) and not @map_open}
                id="species-range-map"
                class="h-72"
                in_range={@range}
                inherited_range={@inherited_range}
                introduced_range={@introduced_range}
                bounds={@range_bounds}
                navigable
              />
              <:footer :if={@editing}>
                <.edit_scope kind={:follows}>
                  Its Galls' ranges: each Gall's Range Facts, on its page.
                </.edit_scope>
              </:footer>
            </.panel>
            <.see_also name={@species.name} type={:gall} />
            <.record_metadata inserted_at={@species.inserted_at} updated_at={@species.updated_at} />
          </.rail>
        </div>
      </div>

      <.authority_tray :if={@editing} items={@mock_items} open={@mock_tray_open} />
      <.review_dialog
        show={@editing and @mock_review}
        items={@mock_items}
        evidence={@mock_evidence}
        confirmed={@mock_confirmed}
        source={@mock_evidence_source}
        source_query={@mock_source_query}
        source_results={@mock_source_results}
      />

      <.dialog
        :if={@map_open}
        id="range-dialog"
        title={"Where #{@species.name} occurs"}
        size={:full}
        show
        on_cancel={JS.push("close_map")}
      >
        <.range_map
          id="species-range-map-large"
          class="h-160"
          in_range={@range}
          inherited_range={@inherited_range}
          introduced_range={@introduced_range}
          bounds={@range_bounds}
          navigable
        />
      </.dialog>
    </Layouts.app>
    """
  end

  defp covers(source, gall_names) do
    galls = for id <- source.gall_ids, name = gall_names[id], do: name

    case {galls, source.taxonomy} do
      {[], true} -> "Its taxonomy"
      {galls, true} -> Enum.join(galls ++ ["its taxonomy"], ", ")
      {galls, false} -> Enum.join(galls, ", ")
    end
  end
end
