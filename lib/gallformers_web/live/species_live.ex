defmodule GallformersWeb.SpeciesLive do
  @moduledoc """
  The species page (`/species/:id`; matter `803b`, "The species page"): an
  organism that induces Galls, a non-plant taxon at species rank or below
  (`Gallformers.Taxa.species_page/1`; plants have their Host pages).

    * **Header:** the name with its authorship and rank, its lineage linked
      to the rank pages, its common names.
    * **Galls:** every Gall it induces, every generation, as the rank pages'
      photo cards or table (`GallformersWeb.RankGalls`).
    * **Taxonomy:** where it stands and on whose word
      (`Gallformers.Import.taxonomic_position/1`: its placement and name
      with their Sources, the papers that disagree), its synonyms, and its
      split and lump history (`Gallformers.Import.taxon_splits/1`, the taxa
      merged into it).
    * **Sources:** every Source citing it or one of its Galls
      (`Gallformers.Catalog.species_sources/2`).
    * **Rail:** its Galls' ranges together on one map
      (`Gallformers.Catalog.display_range_for_galls/1`), More info, the
      dates.

  A plant's ID goes to its Host page and a higher taxon's to its rank page;
  a taxon merged into another follows `Gallformers.Taxa.taxon_redirect/1`
  (the HTTP request is redirected by
  `GallformersWeb.Plugs.LegacyEntityRedirect`); anything else is a 404.

  Edit mode (`?edit`, curators): the name, placement, synonyms and common
  names (`GallformersWeb.SpeciesLive.Editor`), each through "Based on which
  Source?" (`GallformersWeb.Admin.TaxonomyLive.BasisPicker`) and made as
  that Source's statement (`Gallformers.Import.record_taxonomy_change/3`).
  The Galls are edited on their own pages; photos and deletion in the
  taxonomy admin.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Catalog, Import, Places, Taxa}
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.ReadModels.SpeciesPage
  alias GallformersWeb.Admin.TaxonomyLive.BasisPicker
  alias GallformersWeb.RankGalls
  alias GallformersWeb.RankPage
  alias GallformersWeb.SEO
  alias GallformersWeb.SpeciesLive.Editor
  alias GallformersWeb.TaxonomyURL

  import GallformersWeb.FactsComponents, only: [taxonomic_position: 1]
  import GallformersWeb.RankPageComponents, only: [rank_galls: 1]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {taxon_id, ""} ->
        socket
        |> assign(editing: false, map_open: false, rank_sort: %{field: :name, dir: :asc})
        |> assign(actor: socket.assigns[:curator])
        |> Editor.init()
        |> load(taxon_id)

      _ ->
        raise GallformersWeb.NotFoundError, "No species #{id}"
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Edit mode (`?edit`): curators only; for anyone else the public page.
    editing = Map.has_key?(params, "edit") and socket.assigns[:curator] != nil
    {:noreply, assign(socket, editing: editing)}
  end

  defp load(socket, taxon_id) do
    case Taxa.species_page(taxon_id) do
      {:ok, %SpeciesPage{} = species} ->
        {:ok, assign_species(socket, species)}

      {:plant, id} ->
        {:ok, push_navigate(socket, to: ~p"/host/#{id}")}

      {:higher, taxon} ->
        case TaxonomyURL.public_path(taxon) do
          nil -> raise GallformersWeb.NotFoundError, "No species #{taxon_id}"
          path -> {:ok, push_navigate(socket, to: path)}
        end

      :not_found ->
        # Merged into another (live navigation; the HTTP request is
        # redirected by `GallformersWeb.Plugs.LegacyEntityRedirect`).
        case Taxa.taxon_redirect(taxon_id) do
          nil -> raise GallformersWeb.NotFoundError, "No species #{taxon_id}"
          to -> {:ok, push_navigate(socket, to: TaxonomyURL.species_path(to))}
        end
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

    page_url = TaxonomyURL.species_path(species.id)
    page_image = Enum.find_value(galls, & &1.image_url)

    page_description =
      "#{species.name} - a gallformer documented on Gallformers with #{galls_text(length(galls))}."

    assign(socket,
      page_title: species.name,
      page_description: page_description,
      page_url: page_url,
      page_image: page_image,
      page_json_ld: json_ld(species, page_url, page_description, page_image),
      page_noindex: false,
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
      # Framed on the native range; introduced places are drawn, not framed.
      range_bounds: Places.get_bounds_for_codes((range -- introduced) ++ inherited)
    )
  end

  defp reload(socket) do
    case Taxa.species_page(socket.assigns.species.id) do
      {:ok, species} -> assign_species(socket, species)
      _ -> push_navigate(socket, to: ~p"/admin/taxonomy")
    end
  end

  defp json_ld(species, url, description, image) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Taxon",
      "name" => species.name,
      "taxonRank" => Atom.to_string(species.rank),
      "description" => description,
      "url" => SEO.base_url() <> url
    }
    |> then(&if(image, do: Map.put(&1, "image", image), else: &1))
    |> Jason.encode!()
  end

  # The lineage above it with a page each: the rank pages, and the species
  # a subspecies or variety belongs to.
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

  defp galls_text(1), do: "1 gall"
  defp galls_text(n), do: "#{n} galls"

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

  def handle_event(event, params, %{assigns: %{editing: true}} = socket) do
    if event in Editor.events(),
      do: {:noreply, Editor.handle_event(event, params, socket)},
      else: {:noreply, socket}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({BasisPicker, {:chosen, basis}}, %{assigns: %{editing: true}} = socket) do
    case BasisPicker.run(socket, basis) do
      {:ok, socket, _result, done} ->
        {:noreply, socket |> Editor.close() |> reload() |> put_flash(:info, done)}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # -- render ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, list: RankGalls.compute(assigns.galls, "", assigns.rank_sort))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:crumb :for={c <- @crumbs} navigate={c.path} italic={c.italic}>{c.name}</:crumb>
          <:title name>
            <.taxon_name name={@species.name} />
            <span
              :if={@species.authorship}
              class="font-normal not-italic text-ink-2"
            >
              {@species.authorship}
            </span>
          </:title>
          <:chip variant={:rank}>{rank_label(@species.rank)}</:chip>
          <:chip>Gallformer</:chip>
          <:meta :if={@species.common_names != []} label="Common name">
            {Enum.map_join(@species.common_names, ", ", & &1.name)}
          </:meta>
          <:action :if={@curator}>
            <.edit_toggle editing={@editing} path={TaxonomyURL.species_path(@species.id)} />
          </:action>
        </.page_header>

        <div :if={@editing} id="editing" class="flex flex-col gap-2">
          <.notice kind={:info} title="Editing">
            Its names and placement follow the Sources: each change asks which Source it follows, and is made as that Source's statement.
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
            <Editor.editor
              :if={@editing}
              species={@species}
              parent={@parent}
              open={@editor_open}
              parent_query={@parent_query}
              parent_results={@parent_results}
              selected_parent={@selected_parent}
            />

            <.rank_galls
              :if={@galls.all != []}
              id="species-galls"
              list={@list}
              sort={@rank_sort}
              narrowed={false}
              edit_path={if @editing, do: &"/gall/#{&1.id}?edit"}
            />
            <.empty_state :if={@galls.all == []} title="No galls recorded for it yet." />

            <.section id="species-taxonomy" title="Taxonomy">
              <div class="flex flex-col gap-block">
                <.taxonomic_position id="species-position" position={@position} />

                <.fact_list
                  :if={!@editing and @species.synonyms != []}
                  id="species-synonyms"
                  layout={:inline}
                  missing_label={nil}
                >
                  <:item label="Synonyms">
                    <span :for={{s, i} <- Enum.with_index(@species.synonyms)}>
                      {if i > 0, do: " · "}<.taxon_name name={s.name} />
                      <span
                        :if={s.sensu}
                        class="text-meta text-muted"
                      >
                        sensu {s.sensu}
                      </span>
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
                    <ul class="grid gap-0.5">
                      <li :for={s <- @splits} data-part="split">
                        <%= if s.taxon.taxon_id == @species.id do %>
                          Split into <.taxa_names taxa={s.into} />
                        <% else %>
                          Split from <.taxon_link taxon={s.taxon} />, with
                          <.taxa_names taxa={Enum.reject(s.into, &(&1.taxon_id == @species.id))} />
                        <% end %>
                        <span :if={s.source} class="text-caption text-muted">
                          · from
                          <.link navigate={~p"/source/#{s.source.source_id}"} class="hover:underline">
                            {s.source.name}
                          </.link>
                        </span>
                      </li>
                    </ul>
                  </:item>
                  <:item :if={@species.merged != []} label="Merged into it">
                    <ul class="grid gap-0.5">
                      <li :for={m <- @species.merged} data-part="merged">
                        <.taxon_name :if={m.name} name={m.name} />
                        <span :if={!m.name}>A taxon (ID {m.taxon_id})</span>
                        <span class="text-caption text-muted">· {format_date(m.at, :short)}</span>
                      </li>
                    </ul>
                  </:item>
                </.fact_list>

                <p
                  :if={
                    @position.placement == nil and @position.name == nil and
                      @position.disagreeing == [] and @species.synonyms == [] and @splits == [] and
                      @species.merged == []
                  }
                  class="text-ui text-muted"
                >
                  No Source places or names it yet.
                </p>
              </div>
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
              <:footer :if={@range != [] or @inherited_range != []}>
                <.range_map_legend
                  :if={@inherited_range != [] or @introduced_range != []}
                  mode={:public}
                />
                <p class="text-caption text-muted">
                  Where the hosts of its {length(@galls.all)} {if length(@galls.all) == 1,
                    do: "gall",
                    else: "galls"} grow, not where it was found.
                </p>
              </:footer>
            </.panel>

            <.see_also name={@species.name} type={:gall} />
            <.record_metadata inserted_at={@species.inserted_at} updated_at={@species.updated_at} />
          </.rail>
        </div>
      </div>

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

      <.live_component
        :if={@editing and @pending}
        module={BasisPicker}
        id="basis-picker"
        change={@pending.summary}
        confirm_label={@pending.confirm}
        error={@basis_error}
        error_kind={@basis_error_kind}
        remembered={@last_source}
        cancel_event="cancel_basis"
      />
    </Layouts.app>
    """
  end

  attr :taxa, :list, required: true

  defp taxa_names(assigns) do
    ~H"""
    <span :for={{t, i} <- Enum.with_index(@taxa)}>
      {if i > 0,
        do: if(i == length(@taxa) - 1, do: " and ", else: ", ")}<.taxon_link taxon={t} />
    </span>
    """
  end

  attr :taxon, :map, required: true

  defp taxon_link(assigns) do
    ~H"""
    <.link :if={@taxon.name} navigate={TaxonomyURL.species_path(@taxon.taxon_id)}>
      <.taxon_name name={@taxon.name} />
    </.link>
    """
  end

  # What a Source covers: the Galls it cites, and the taxonomy.
  defp covers(source, gall_names) do
    galls = for id <- source.gall_ids, name = gall_names[id], do: name

    case {galls, source.taxonomy} do
      {[], true} -> "Its taxonomy"
      {galls, true} -> Enum.join(galls ++ ["its taxonomy"], ", ")
      {galls, false} -> Enum.join(galls, ", ")
    end
  end

  defp rank_label(rank), do: rank |> Atom.to_string() |> String.capitalize()
end
