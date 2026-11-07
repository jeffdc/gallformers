defmodule GallformersWeb.Dev.Mockups.GenusFactsLive do
  @moduledoc """
  Mockup (matter `d3b0`): the genus page (`GallformersWeb.GenusLive`) with
  an Edit mode (rank pages have none today) whose taxonomy edits are all in
  a Facts panel. `/dev/mockups/genus-facts/:name?edit`.

  A copy of `GallformersWeb.GenusLive`: its mount and data as they are
  (a name used more than once takes the first genus, or `?family=`), its
  render changed. It adds a Taxonomy section (proposed for rank pages:
  `taxonomic_position` and the genus's names, as presentation) and, in Edit
  mode, the Facts panel of the genus's placement, name with authorship,
  synonyms, common names, splits and lumps. A plant genus's taxonomy is
  editorial, not Facts (matter `d3b0`, rule 5): it says so instead.
  Read-only: see `GallformersWeb.Dev.Mockups.FactEditMock`.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Catalog, Import, Taxa}
  alias GallformersWeb.Dev.Mockups.FactEditMock, as: Mock
  alias GallformersWeb.RankGalls
  alias GallformersWeb.RankPage

  import GallformersWeb.FactsComponents, only: [taxonomic_position: 1]
  import GallformersWeb.RankPageComponents

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
  def mount(%{"name" => name} = params, _session, socket) do
    case RankPage.lookup(name, :genus) do
      {:redirect, path} ->
        {:ok, push_navigate(socket, to: path, replace: true)}

      {:ok, []} ->
        raise GallformersWeb.NotFoundError, "No genus named #{name}"

      {:ok, genera} ->
        genus = pick(genera, params["family"])
        {:ok, socket |> assign_genus_data(genus.id, name) |> assign_mock(genus.id, params)}
    end
  end

  defp pick([genus], _family), do: genus

  defp pick(genera, family) do
    lineages = genera |> Enum.map(& &1.id) |> Taxa.lineages()

    Enum.find(genera, hd(genera), fn g ->
      Enum.any?(Map.get(lineages, g.id, []), &(&1.rank == :family and &1.name == family))
    end)
  end

  defp assign_mock(socket, id, params) do
    taxon = Taxa.get_taxon!(id)
    plant? = not Taxa.follows_facts?(taxon)
    panel = if plant?, do: [], else: Mock.taxon_panel(id)
    accepted = Enum.find(taxon.names, &(&1.status == :accepted))
    seed = if Map.has_key?(params, "empty"), do: [], else: Mock.examples(panel, [])

    socket
    |> assign(
      editing: false,
      plant?: plant?,
      panel: panel,
      authorship: accepted && accepted.authorship,
      parent: id |> Taxa.lineage() |> Enum.drop(-1) |> List.last(),
      synonyms: Taxa.list_synonyms(id),
      common: Taxa.list_common_names(id),
      position: Import.taxonomic_position(id),
      splits: Import.taxon_splits(id),
      merged: Taxa.merged_into(id)
    )
    |> Mock.init(seed)
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
      page_title: "Mockup: genus #{name}",
      page_description: nil,
      page_url: nil,
      page_image: nil,
      page_json_ld: nil,
      page_noindex: true,
      genus: %{id: id, name: name, description: RankPage.description(id)},
      crumbs: RankPage.crumbs(id),
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
  def handle_params(params, _uri, socket),
    do: {:noreply, assign(socket, editing: Map.has_key?(params, "edit"))}

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

  def handle_event(event, params, socket) do
    if event in Mock.events(),
      do: {:noreply, Mock.handle(event, params, socket)},
      else: {:noreply, socket}
  end

  defp first_fact(panel, id) do
    case Enum.find(panel, &(&1.id == id)) do
      %{facts: [fact | _]} -> fact_dom(fact.key)
      _ -> category_dom(id)
    end
  end

  defp named_fact(panel, id, name) do
    with %{facts: facts} <- Enum.find(panel, &(&1.id == id)),
         %{key: key} <- Enum.find(facts, &String.contains?(&1.text, name)) do
      fact_dom(key)
    else
      _ -> category_dom(id)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class={["flex flex-col gap-section", @editing && @mock_items != [] && "pb-72"]}>
        <.mockup_notice real="the genus, its lineage, its Galls (or plants), its synonyms and common names, every taxonomic statement about it and its standing (taxonomic_position, taxon_splits, the Sources' taxonomic statements), the taxon searches.">
          Rank pages have no Edit mode and no Taxonomy section today: both are proposed here (the Edit toggle, the Taxonomy section, its Facts panel). This database holds no taxonomic statement about a genus: what the tree holds is shown as such, with its Gallformers actions.
        </.mockup_notice>

        <.page_header>
          <:crumb :for={c <- @crumbs} navigate={c.path} italic={c.italic}>{c.name}</:crumb>
          <:title name>
            {@genus.name}
            <span :if={@authorship} class="font-normal not-italic text-ink-2">{@authorship}</span>
          </:title>
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
          </:action>
          <:action>
            <%!-- PROPOSED: rank pages' Edit mode (the real edit_toggle) --%>
            <.edit_toggle editing={@editing} path={"/dev/mockups/genus-facts/#{@genus.name}"} />
          </:action>
        </.page_header>

        <div :if={@editing} id="editing" class="flex flex-col gap-2">
          <.notice :if={!@plant?} kind={:info} title="Editing">
            The genus's taxonomy is edited in the Facts panel: a Gallformers change, or a correction under the Source that stated it. Each change goes into your tray at the foot of the screen.
            <:action><.fact_link to="genus-facts-panel" label="Go to the Facts panel" /></:action>
          </.notice>
          <.notice :if={@plant?} kind={:info} title="Editing">
            A plant genus's taxonomy is editorial, not Facts: it follows WCVP, edited in the taxonomy admin.
          </.notice>
          <.edit_scope kind={:follows}>
            Its Galls follow from each Gall's Inducer; each species' placement under it is that species' Fact, on its page.
          </.edit_scope>
          <.edit_scope kind={:elsewhere} href={~p"/admin/taxonomy/#{@genus.id}"}>
            Photos, rank and deletion: on the taxonomy of <i>{@genus.name}</i>.
          </.edit_scope>
        </div>

        <.empty_state :if={@total == 0} title="No species found for this genus." />

        <div :if={@total > 0} class="flex flex-wrap items-end gap-x-10 gap-y-4">
          <.stat :if={@galls.all != []} value={length(@galls.all)} label="Galls" />
          <.stat
            :if={@galls.all != []}
            value={@galls.all |> Enum.flat_map(& &1.host_genera) |> Enum.uniq() |> length()}
            label="Host genera"
          />
          <.stat :if={@plants != []} value={length(@plants)} label="Species" />
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

        <%!-- PROPOSED: a Taxonomy section on rank pages, as the species page's --%>
        <.section :if={!@plant?} id="genus-taxonomy" title="Taxonomy">
          <:aside :if={@editing}><.fact_link to="genus-facts-panel" /></:aside>
          <div class="flex flex-col gap-block">
            <.taxonomic_position id="genus-position" position={@position} />
            <.fact_list id="genus-names" layout={:inline} missing_label={nil}>
              <:item :if={@parent} label="Placed">
                under {@parent.rank} {@parent.name}
                <.fact_link :if={@editing} to={first_fact(@panel, "placement")} />
              </:item>
              <:item label="Name">
                <.taxon_name name={@genus.name} rank="genus" />
                <span :if={@authorship}>{@authorship}</span>
                <span :if={!@authorship} class="text-caption text-muted">no authorship recorded</span>
                <.fact_link :if={@editing} to={first_fact(@panel, "name")} />
              </:item>
              <:item :if={@synonyms != []} label="Synonyms">
                <span :for={{s, i} <- Enum.with_index(@synonyms)}>
                  {if i > 0, do: " · "}<.taxon_name name={s.name} rank="genus" />
                  <.fact_link :if={@editing} to={named_fact(@panel, "synonyms", s.name)} />
                </span>
              </:item>
              <:item :if={@common != []} label="Common names">
                <span :for={{c, i} <- Enum.with_index(@common)}>
                  {if i > 0, do: " · "}{c.name}
                  <.fact_link :if={@editing} to={named_fact(@panel, "common_names", c.name)} />
                </span>
              </:item>
              <:item :if={@splits != [] or @merged != []} label="Splits and lumps">
                {length(@splits)} split, {length(@merged)} merged into it
                <.fact_link :if={@editing} to={category_dom("splits")} />
              </:item>
            </.fact_list>
          </div>
        </.section>

        <.section :if={@editing and !@plant?} id="genus-facts" title="Facts">
          <:aside>Every edit of its taxonomy begins and ends here</:aside>
          <.facts_panel
            id="genus-facts-panel"
            title={"#{@genus.name}: its taxonomy"}
            categories={@panel}
            edit={@mock_edit}
            pick={@mock_pick}
            error={@mock_error}
            items={@mock_items}
          />
        </.section>

        <.rank_galls
          :if={@galls.all != []}
          id="genus-galls"
          list={@galls}
          sort={@sort}
          narrowed={@search_query != ""}
          edit_path={if @editing, do: &"/dev/mockups/gall-facts/#{&1.id}?edit"}
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
    </Layouts.app>
    """
  end
end
