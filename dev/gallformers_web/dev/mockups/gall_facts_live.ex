defmodule GallformersWeb.Dev.Mockups.GallFactsLive do
  @moduledoc """
  Mockup (matter `d3b0`): the Gall page (`GallformersWeb.GallLive`) with
  every Fact edit in the Facts panel. `/dev/mockups/gall-facts/:id?edit`.

  A copy of `GallformersWeb.GallLive`: its mount and data as they are, its
  render changed. In Edit mode the main view is presentation, each Fact
  with "✎ in Facts" to it in the panel; the editorial fields (completeness,
  abundance, code, name parts, lead Source, photos, ID note) are edited in
  place as today; the Facts panel holds every Fact edit; the tray groups
  its items by authority. Read-only: see
  `GallformersWeb.Dev.Mockups.FactEditMock`.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Accounts, Catalog, Galls, Glossaries, Markdown, Places}
  alias Gallformers.Catalog.ReadModels.GallPage
  alias Gallformers.Images.Image
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.Dev.Mockups.FactEditMock, as: Mock
  alias GallformersWeb.TaxonomyURL

  import GallformersWeb.FactsComponents, only: [facts_view: 1, entries: 1]

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

  @sources_initial_limit 8
  @italic_ranks [:genus, :section, :species, :subspecies, :variety, :form]

  @detachable_values %{
    "unknown" => "",
    "integral" => "Integral",
    "detachable" => "Detachable",
    "both" => "Both"
  }

  @traits [
    {"Detachable", "detachable"},
    {"Color", "color"},
    {"Texture", "texture"},
    {"Shape", "shape"},
    {"Season", "season"},
    {"Alignment", "alignment"},
    {"Walls", "walls"},
    {"Location", "plant_part"},
    {"Form", "form"},
    {"Cells", "cells"}
  ]

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    case Integer.parse(id) do
      {gall_id, ""} ->
        case load_gall(socket, gall_id) do
          {:ok, socket} ->
            {:ok, mount_mock(socket, params)}

          {:redirect, to} ->
            {:ok, push_navigate(socket, to: "/dev/mockups/gall-facts/#{to}?edit")}
        end

      _ ->
        raise GallformersWeb.NotFoundError, "No gall #{id}"
    end
  end

  defp mount_mock(socket, params) do
    gall = socket.assigns.gall
    panel = Mock.gall_panel(gall.id)
    record = Catalog.get_gall!(gall.id)

    seed =
      if Map.has_key?(params, "empty"),
        do: [],
        else:
          Mock.examples(panel, [
            if(record.datacomplete,
              do: "Mark in progress (example)",
              else: "Mark complete (example)"
            )
          ])

    socket
    |> assign(
      panel: panel,
      record: record,
      lock: Catalog.datacomplete_lock(record),
      lead_sources: Catalog.gall_sources(record.id),
      abundances: Catalog.list_abundances(),
      editing: false
    )
    |> Mock.init(seed)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, editing: Map.has_key?(params, "edit"))
    {:noreply, select_source(socket, params["source"])}
  end

  defp select_source(socket, nil), do: socket

  defp select_source(socket, source_id_str) do
    with {source_id, ""} <- Integer.parse(source_id_str),
         source when not is_nil(source) <-
           Enum.find(socket.assigns[:sources] || [], fn s -> s.id == source_id end) do
      assign(socket, selected_source: source, sources_expanded: true)
    else
      _ -> socket
    end
  end

  defp load_gall(socket, gall_id) do
    case Catalog.gall_page(gall_id) do
      :not_found ->
        case Catalog.gall_redirect(gall_id) do
          nil -> raise GallformersWeb.NotFoundError, "No gall #{gall_id}"
          to -> {:redirect, to}
        end

      {:ok, %GallPage{} = gall} ->
        images = format_images(gall.images)

        {range, inherited_range, introduced_range} =
          case gall.display_range do
            :everywhere -> {[], [], []}
            range -> {range.in_range, range.inherited_range, range.introduced_range}
          end

        {base_name, generation_term, glossary_word, generation_definition} =
          parse_generation_term(gall.name, gall.generation)

        {:ok,
         assign(socket,
           page_title: "Mockup: " <> gall.name,
           page_description:
             Galls.Summary.for_seo(gall.name, Galls.Summary.from_traits(gall.traits)),
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           gall: gall,
           base_name: base_name,
           generation_term: generation_term,
           glossary_word: glossary_word,
           generation_definition: generation_definition,
           images: images,
           sources: gall.sources,
           crumbs: crumbs(gall.inducers),
           range: range,
           inherited_range: inherited_range,
           introduced_range: introduced_range,
           range_bounds:
             Places.get_bounds_for_codes((range -- introduced_range) ++ inherited_range),
           range_unknown?: gall.display_range == :everywhere,
           related_galls: gall.related_galls,
           common_names: gall.common_names,
           name_rows: name_rows(gall),
           gallformers_code: gall.gallformers_code,
           traits: trait_values(gall),
           selected_source: nil,
           modal_font_size: :base,
           sources_expanded: false,
           sources_order: :asc,
           map_open: false,
           facts: Gallformers.Import.facts_for_gall(gall_id)
         )}
    end
  end

  defp current_count(entries), do: Enum.count(entries, &(&1.standing in [nil, :current]))

  defp crumbs([]), do: []

  defp crumbs([%{lineage: lineage} | _]) do
    for taxon <- lineage, path = crumb_path(taxon), path != nil do
      %{name: taxon.name, path: path, italic: taxon.rank in @italic_ranks}
    end
  end

  defp crumb_path(%{rank: rank} = taxon) do
    if rank in Rank.species_and_below(),
      do: TaxonomyURL.species_path(taxon.taxon_id),
      else: TaxonomyURL.public_path(taxon)
  end

  defp name_rows(gall) do
    synonyms =
      for s <- gall.synonyms do
        type = if s.sensu, do: "misapplied", else: "synonym"
        %{name: s.name, type: type, notes: s.sensu, label?: false}
      end

    labels =
      for l <- gall.labels do
        %{name: l.name, type: label_type(l.kind), notes: nil, label?: true}
      end

    synonyms ++ labels
  end

  defp label_type(:former_label), do: "former label"
  defp label_type(:code), do: "code"

  defp trait_keys, do: @traits

  defp trait_values(gall) do
    traits = for {label, key} <- @traits, do: {label, blank(trait_display(gall, key))}
    traits ++ [{"Abundance", blank(gall.abundance)}]
  end

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: value

  defp trait_value(traits, label),
    do: Enum.find_value(traits, fn {l, value} -> l == label && value end)

  defp listed_sources(sources, order) do
    {dated, undated} = sources |> Enum.reject(& &1.note?) |> Enum.split_with(&year(&1.pubyear))
    Enum.sort_by(dated, &year(&1.pubyear), order) ++ undated
  end

  defp year(nil), do: nil

  defp year(text) do
    case Regex.run(~r/\d{4}/, text) do
      [y] -> String.to_integer(y)
      nil -> nil
    end
  end

  defp excerpt_text(markdown) do
    markdown
    |> Markdown.render!()
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(["&amp;", "&quot;", "&#39;", "&lt;", "&gt;"], fn
      "&amp;" -> "&"
      "&quot;" -> "\""
      "&#39;" -> "'"
      "&lt;" -> "<"
      "&gt;" -> ">"
    end)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp host_href(%{link: {:host, id}}), do: "/host/#{id}"
  defp host_href(%{link: {rank, name}}), do: "/#{rank}/#{name}"

  defp format_images(images) do
    base_url = Image.base_url()

    Enum.map(images, fn img ->
      small_path = String.replace(img.path, "original", "small")
      full_url = "#{base_url}/#{img.path}"

      Map.merge(img, %{
        url: full_url,
        src: full_url,
        thumb: "#{base_url}/#{small_path}",
        small_url: "#{base_url}/#{small_path}",
        alt: nil
      })
    end)
  end

  defp trait_display(gall, "detachable") do
    case Map.get(gall.traits, "detachable", []) do
      [value | _] -> trait_line(gall, "detachable", [value], &Map.get(@detachable_values, &1, ""))
      [] -> trait_line(gall, "detachable", [], & &1)
    end
  end

  defp trait_display(gall, trait),
    do: trait_line(gall, trait, Map.get(gall.traits, trait, []), & &1)

  defp trait_line(gall, trait, values, label) do
    terms = Map.get(gall.trait_terms, trait, %{})

    values
    |> Enum.map(&with_terms(label.(&1), Map.get(terms, &1, [])))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
    |> with_text_terms(Map.get(gall.text_terms, trait, []))
  end

  defp with_terms(shown, terms) when shown == "" or terms == [], do: shown
  defp with_terms(shown, terms), do: "#{shown} (#{Enum.join(terms, ", ")})"

  defp with_text_terms(shown, []), do: shown
  defp with_text_terms("", terms), do: "described as " <> quoted(terms)
  defp with_text_terms(shown, terms), do: shown <> "; also described as " <> quoted(terms)

  defp quoted(terms), do: Enum.map_join(terms, ", ", &"“#{&1}”")

  defp parse_generation_term(name, %{name_qualifier: qualifier} = generation)
       when is_binary(qualifier) do
    suffix = " (#{qualifier})"

    if String.ends_with?(name, suffix) do
      definition =
        generation.definition || Map.get(Glossaries.get_definitions([qualifier]), qualifier)

      {String.replace_suffix(name, suffix, ""), qualifier, qualifier, definition}
    else
      {name, nil, nil, nil}
    end
  end

  defp parse_generation_term(name, _generation), do: {name, nil, nil, nil}

  # -- events ------------------------------------------------------------------------

  @font_sizes [:sm, :base, :lg, :xl]

  @impl true
  def handle_event("clipboard_copy_success", _params, socket),
    do: {:noreply, put_flash(socket, :info, "Copied to clipboard")}

  def handle_event("clipboard_copy_error", _params, socket),
    do: {:noreply, put_flash(socket, :error, "Failed to copy to clipboard")}

  def handle_event("gallery_index_changed", _params, socket), do: {:noreply, socket}

  def handle_event("show_source_detail", %{"id" => id_str}, socket) do
    source_id = String.to_integer(id_str)
    source = Enum.find(socket.assigns.sources, fn s -> s.id == source_id end)
    {:noreply, assign(socket, selected_source: source)}
  end

  def handle_event("close_source_modal", _params, socket),
    do: {:noreply, assign(socket, selected_source: nil, modal_font_size: :base)}

  def handle_event("increase_font_size", _params, socket) do
    i = Enum.find_index(@font_sizes, &(&1 == socket.assigns.modal_font_size))
    size = Enum.at(@font_sizes, min(i + 1, length(@font_sizes) - 1))
    {:noreply, assign(socket, modal_font_size: size)}
  end

  def handle_event("decrease_font_size", _params, socket) do
    i = Enum.find_index(@font_sizes, &(&1 == socket.assigns.modal_font_size))
    {:noreply, assign(socket, modal_font_size: Enum.at(@font_sizes, max(i - 1, 0)))}
  end

  def handle_event("expand_sources", _params, socket),
    do: {:noreply, assign(socket, sources_expanded: true)}

  def handle_event("sources_order", %{"order" => order}, socket) when order in ["asc", "desc"],
    do: {:noreply, assign(socket, sources_order: String.to_existing_atom(order))}

  def handle_event("open_map", _params, socket), do: {:noreply, assign(socket, map_open: true)}
  def handle_event("close_map", _params, socket), do: {:noreply, assign(socket, map_open: false)}

  def handle_event("navigate_to_place", %{"code" => code}, socket),
    do: {:noreply, push_navigate(socket, to: "/place/#{code}")}

  def handle_event(event, params, socket) do
    if event in Mock.events(),
      do: {:noreply, Mock.handle(event, params, socket)},
      else: {:noreply, socket}
  end

  defp visible_sources(sources, expanded?)
       when expanded? or length(sources) <= @sources_initial_limit,
       do: sources

  defp visible_sources(sources, _expanded?), do: Enum.take(sources, @sources_initial_limit)

  defp show_expand_button?(sources, expanded?),
    do: !expanded? and length(sources) > @sources_initial_limit

  # The panel key of a main-view Fact, as its DOM id.
  defp to_fact(panel, ref), do: panel |> Mock.key_for(ref) |> fact_dom()

  defp in_tray?(items, field), do: Enum.any?(items, &(&1[:field] == field))

  defp lock_reason({:locked, :no_sources}), do: "it has no Sources yet"
  defp lock_reason({:locked, :undescribed}), do: "it's undescribed (no species-rank Inducer)"

  # -- render ------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        note: Enum.find(assigns.sources, & &1.note?),
        listed: listed_sources(assigns.sources, assigns.sources_order),
        fact_entries: entries(assigns.facts || [])
      )

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class={["flex flex-col gap-section", @editing && @mock_items != [] && "pb-72"]}>
        <.mockup_notice real="the Gall, its Facts and every Source's statement of each (date, words, whether it counts), the editorial values, the plant and taxon searches, the Trait values.">
          This database's Galls have at most two Sources: Gall 5076 has the one outside Source (InfluentialPoints), so "Corrections to" a Source not Gallformers' own shows best there.
        </.mockup_notice>

        <.page_header>
          <:crumb :for={c <- @crumbs} navigate={c.path} italic={c.italic}>{c.name}</:crumb>
          <:title name>
            {@base_name}
            <.glossary_tooltip
              :if={@generation_term}
              term={@generation_term}
              glossary_word={@glossary_word}
              definition={@generation_definition}
            />
          </:title>
          <:chip :if={@gall.undescribed?} variant={:info}>Undescribed</:chip>
          <:chip variant={if @gall.datacomplete, do: :ok, else: :warn}>
            {if @gall.datacomplete, do: "Complete", else: "In progress"}
          </:chip>
          <:meta
            :if={@related_galls != []}
            label={if length(@related_galls) == 1, do: "Other generation", else: "Related galls"}
          >
            <span :for={{related, i} <- Enum.with_index(@related_galls)}>
              {if i > 0, do: " · "}<.link navigate={"/gall/#{related.id}"}><.taxon_name name={
                  related.name
                } /></.link>
            </span>
          </:meta>
          <:meta :if={@common_names != []} label="Common name">
            {Enum.join(@common_names, ", ")}
          </:meta>
          <:meta
            :for={label <- ["Season", "Location", "Form"]}
            :if={trait_value(@traits, label)}
            label={label}
          >
            {trait_value(@traits, label)}
          </:meta>
          <:action :if={@editing}>
            <.button
              id="add-from-observation"
              variant="secondary"
              icon="ph-eye"
              phx-click="mock_flash"
              phx-value-message="As today (ObservationIntake): its proposals go into the tray's Gallformers group, each with the observation as its evidence."
            >
              Add from observation…
            </.button>
          </:action>
          <:action>
            <.edit_toggle editing={@editing} path={"/dev/mockups/gall-facts/#{@gall.id}"} />
          </:action>
        </.page_header>

        <div :if={@editing} id="editing" class="flex flex-col gap-2">
          <.notice kind={:info} title="Editing">
            Every Fact is edited in the Facts panel below: ✎ in Facts on the page takes you to it. The editorial fields are edited here, in place. Each change goes into your tray at the foot of the screen, grouped by whose authority it is under.
            <:action><.fact_link to="gall-facts-panel" label="Go to the Facts panel" /></:action>
          </.notice>
          <.edit_scope
            :if={@gall.inducers != []}
            kind={:elsewhere}
            href={"/dev/mockups/species-facts/#{hd(@gall.inducers).taxon_id}?edit"}
          >
            The lineage and the Inducer's names: in the Facts panel of <i>{hd(@gall.inducers).name}</i>'s page.
          </.edit_scope>
          <.edit_scope :if={@related_galls != []} kind={:follows}>
            The other generation follows from the Inducer: Galls with the same Inducer.
          </.edit_scope>
          <.edit_scope kind={:follows}>
            Season, Location and Form above follow from the Traits; the range map from the Hosts' ranges and the Range Facts.
          </.edit_scope>
        </div>

        <div class="gf-with-rail">
          <div class="flex min-w-0 flex-col gap-section">
            <.panel :if={@editing} id="editorial" title="Editorial">
              <div class="flex flex-wrap items-start gap-x-8 gap-y-4 text-ui">
                <div id="editorial-completeness" class="flex max-w-xs flex-col gap-1">
                  <span class="gf-label">Completeness</span>
                  <div class="flex flex-wrap items-center gap-2">
                    <span>{if @record.datacomplete, do: "Complete", else: "In progress"}</span>
                    <.button
                      size="sm"
                      variant="secondary"
                      phx-click="mock_editorial"
                      phx-value-field="completeness"
                      phx-value-text={
                        if @record.datacomplete, do: "Mark in progress", else: "Mark complete"
                      }
                      disabled={!@record.datacomplete and @lock != :unlocked}
                    >
                      Mark {if @record.datacomplete, do: "in progress", else: "complete"}
                    </.button>
                    <.chip :if={in_tray?(@mock_items, "completeness")} variant={:info} size="sm">
                      in your tray
                    </.chip>
                  </div>
                  <p :if={!@record.datacomplete and @lock != :unlocked} class="gf-hint">
                    It can't be complete: {lock_reason(@lock)}.
                  </p>
                </div>

                <form
                  id="editorial-abundance"
                  phx-change="mock_editorial_select"
                  class="flex flex-col gap-1"
                >
                  <input type="hidden" name="field" value="abundance" />
                  <input type="hidden" name="label" value="Abundance" />
                  <label class="gf-label" for="editorial-abundance-select">Abundance</label>
                  <div class="flex flex-wrap items-center gap-2">
                    <select
                      id="editorial-abundance-select"
                      name="value"
                      class="gf-select h-8 w-auto"
                    >
                      <option value="">Unknown</option>
                      <option
                        :for={a <- @abundances}
                        value={a.abundance}
                        selected={a.id == @record.abundance_id}
                      >
                        {a.abundance}
                      </option>
                    </select>
                    <.chip :if={in_tray?(@mock_items, "abundance")} variant={:info} size="sm">
                      in your tray
                    </.chip>
                  </div>
                </form>

                <div id="editorial-code" class="flex flex-col gap-1">
                  <span class="gf-label">Gallformers code</span>
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="font-mono">{@record.gallformers_code || "None"}</span>
                    <.button
                      size="sm"
                      variant="secondary"
                      phx-click="mock_editorial"
                      phx-value-field="code"
                      phx-value-text="Change the Gallformers code (its dialog, as today)"
                    >
                      Change…
                    </.button>
                    <.chip :if={in_tray?(@mock_items, "code")} variant={:info} size="sm">
                      in your tray
                    </.chip>
                  </div>
                </div>

                <div id="editorial-name" class="flex flex-col gap-1">
                  <span class="gf-label">Name</span>
                  <div class="flex flex-wrap items-center gap-2">
                    <.button
                      size="sm"
                      variant="secondary"
                      phx-click="mock_editorial"
                      phx-value-field="name_parts"
                      phx-value-text="Change the name's parts (its dialog, as today)"
                    >
                      Name parts…
                    </.button>
                    <.chip :if={in_tray?(@mock_items, "name_parts")} variant={:info} size="sm">
                      in your tray
                    </.chip>
                  </div>
                </div>

                <form
                  id="editorial-lead"
                  phx-change="mock_editorial_select"
                  class="flex flex-col gap-1"
                >
                  <input type="hidden" name="field" value="lead" />
                  <input type="hidden" name="label" value="Lead Source" />
                  <label class="gf-label" for="editorial-lead-source">Lead Source</label>
                  <div class="flex flex-wrap items-center gap-2">
                    <select
                      id="editorial-lead-source"
                      name="value"
                      class="gf-select h-8 w-auto max-w-xs"
                    >
                      <option value="">None</option>
                      <option
                        :for={source <- @lead_sources}
                        value={source.title}
                        selected={source.id == @record.default_source_id}
                      >
                        {source.title}
                      </option>
                    </select>
                    <.chip :if={in_tray?(@mock_items, "lead")} variant={:info} size="sm">
                      in your tray
                    </.chip>
                  </div>
                </form>
              </div>
              <div class="mt-block flex flex-wrap gap-2 border-t border-line pt-block">
                <.button
                  size="sm"
                  variant="secondary"
                  icon="ph-image"
                  phx-click="mock_flash"
                  phx-value-message="As today: the photo manager opens here; photos save as you change them, outside the tray."
                >
                  Photos…
                </.button>
                <.button
                  size="sm"
                  variant="secondary"
                  icon="ph-article"
                  phx-click="mock_flash"
                  phx-value-message="As today: the ID note dialog; ID notes are editorial (matter d3b0) and save at once."
                >
                  ID note…
                </.button>
              </div>
              <p class="mt-2 text-caption text-muted">
                Range exclusions are Facts: they moved to the Facts panel's Range.
              </p>
            </.panel>

            <.section :if={@editing and @gall.inducers != []} title="Inducer">
              <:aside><.fact_link to={category_dom("inducer")} /></:aside>
              <ul class="flex flex-col gap-1">
                <li :for={i <- @gall.inducers} class="flex flex-wrap items-baseline gap-2 text-ui">
                  <.link navigate={"/species/#{i.taxon_id}"}><.taxon_name name={i.name} /></.link>
                  <.fact_link to={to_fact(@panel, {:inducer, i.taxon_id})} />
                </li>
              </ul>
            </.section>

            <.section title="Hosts" count={length(@gall.hosts)}>
              <:aside :if={@editing}><.fact_link to={category_dom("hosts")} /></:aside>
              <.name_list items={@gall.hosts} columns={if @editing, do: 3, else: 4}>
                <:item :let={host}>
                  <.link navigate={host_href(host)}>
                    <.taxon_name name={host.name} genus_placeholder={host.rank == :genus} />
                  </.link>
                  <.fact_link :if={@editing} to={to_fact(@panel, {:host, host.taxon_id})} />
                </:item>
              </.name_list>
            </.section>

            <.section
              id="gall-traits-section"
              title="Traits"
              count={"#{Enum.count(@traits, &elem(&1, 1))} of #{length(@traits)} recorded"}
            >
              <:aside :if={@editing}><.fact_link to={category_dom("traits")} /></:aside>
              <.fact_list :if={!@editing} id="gall-traits" columns={2}>
                <:item :for={{label, value} <- @traits} label={label} value={value} />
              </.fact_list>
              <.fact_list :if={@editing} id="gall-traits" columns={2}>
                <:item
                  :for={{label, key} <- trait_keys()}
                  :if={Map.get(@gall.traits, key, []) != []}
                  label={label}
                >
                  <span :for={{value, i} <- Enum.with_index(Map.get(@gall.traits, key, []))}>
                    {if i > 0, do: ", "}{value}<.fact_link to={to_fact(@panel, {:trait, key, value})} />
                  </span>
                </:item>
                <:item
                  :for={{label, key} <- trait_keys()}
                  :if={Map.get(@gall.traits, key, []) == []}
                  label={label}
                  value={nil}
                />
                <:item label="Abundance">
                  {@gall.abundance || "Unknown"}
                  <span class="text-caption text-muted">· editorial, edited above</span>
                </:item>
              </.fact_list>
            </.section>

            <.panel :if={@note} id="id-notes" variant={:info}>
              <div class="flex flex-wrap items-baseline gap-x-3">
                <h2 class="text-subsection">
                  <.link navigate={"/source/#{@note.id}"} class="text-ink">
                    Gallformers ID Notes
                  </.link>
                </h2>
                <span class="text-meta text-muted">
                  {@note.pubyear}{if @note.license, do: " · #{@note.license}"}
                </span>
                <span :if={@editing} class="ml-auto text-caption text-muted">
                  Editorial: ID note… above
                </span>
              </div>
              <.prose markdown={@note.description} size={:sm} font={:serif} class="mt-2" />
            </.panel>

            <.section id="gall-sources-section" title="Sources" count={length(@listed)}>
              <:aside>
                <span class="flex gap-2" role="group" aria-label="Order">
                  <button
                    :for={{order, label} <- [asc: "Oldest first", desc: "Newest first"]}
                    type="button"
                    phx-click="sources_order"
                    phx-value-order={order}
                    aria-pressed={to_string(@sources_order == order)}
                    class={
                      if @sources_order == order, do: "font-semibold text-ink", else: "text-link"
                    }
                  >
                    {label}
                  </button>
                </span>
              </:aside>
              <ul id="gall-sources" class="flex flex-col">
                <li
                  :for={source <- visible_sources(@listed, @sources_expanded)}
                  id={"source-#{source.id}"}
                  class="flex items-baseline gap-3 border-b border-line py-2"
                >
                  <span class="w-10 shrink-0 text-meta tabular-nums text-muted">
                    {source.pubyear || "n.d."}
                  </span>
                  <div class="min-w-0 flex-1">
                    <.link navigate={"/source/#{source.id}"} class="font-semibold">
                      {source.title}
                    </.link>
                    <span :if={source.author} class="text-meta text-ink-2">· {source.author}</span>
                    <button
                      :if={source.description not in [nil, ""]}
                      type="button"
                      phx-click="show_source_detail"
                      phx-value-id={source.id}
                      class="mt-0.5 block w-full text-left"
                    >
                      <span class="line-clamp-2 font-serif text-ui text-ink-2">
                        {excerpt_text(source.description)}
                      </span>
                      <span class="text-meta text-link">Read</span>
                    </button>
                  </div>
                </li>
              </ul>
              <p :if={@sources == []} class="text-ui text-muted">
                No further information available for this species.
              </p>
              <.button
                :if={show_expand_button?(@listed, @sources_expanded)}
                variant="secondary"
                phx-click="expand_sources"
                class="mt-3"
              >
                Show all {length(@listed)} sources
              </.button>
            </.section>

            <.section
              :if={@editing}
              id="gall-facts"
              title="Facts"
              count={current_count(@fact_entries)}
            >
              <:aside>Every Fact edit begins and ends here</:aside>
              <.facts_panel
                id="gall-facts-panel"
                title={@gall.name}
                categories={@panel}
                edit={@mock_edit}
                pick={@mock_pick}
                error={@mock_error}
                items={@mock_items}
              />
            </.section>

            <.section
              :if={!@editing and @fact_entries != []}
              id="gall-facts"
              title="Facts"
              count={current_count(@fact_entries)}
            >
              <:aside>What Gallformers holds about this gall, with the Sources that say it</:aside>
              <.facts_view
                id="gall-facts-view"
                galls={@facts}
                mode={:public}
                gall_header={false}
                history
              />
            </.section>
          </div>

          <.rail width={:wide}>
            <.photo_viewer
              id="gall-images"
              photos={@images}
              name={@gall.name}
              admin={Accounts.admin?(@current_user)}
            />

            <.panel title="Possible range">
              <:header_action>
                <.fact_link :if={@editing} to={category_dom("range")} />
                <.button
                  :if={not @range_unknown?}
                  variant="ghost"
                  size="sm"
                  icon="ph-arrows-out"
                  phx-click="open_map"
                >
                  Enlarge
                </.button>
              </:header_action>
              <p :if={@range_unknown?} class="text-ui text-muted">
                Range unknown: no host range data.
              </p>
              <.range_map
                :if={not @range_unknown? and not @map_open}
                id="gall-range-map"
                class="h-72"
                in_range={@range}
                inherited_range={@inherited_range}
                introduced_range={@introduced_range}
                bounds={@range_bounds}
                navigable
              />
              <:footer :if={not @range_unknown?}>
                <.range_map_legend
                  :if={@inherited_range != [] or @introduced_range != []}
                  mode={:public}
                />
                <p class="text-caption text-muted">
                  Where the {length(@gall.hosts)} hosts grow, not where the gall was found.
                </p>
              </:footer>
            </.panel>

            <dl :if={@name_rows != [] or @common_names != []} class="flex flex-col gap-3 text-ui">
              <div>
                <dt class="text-meta font-semibold uppercase tracking-wide text-muted">
                  Also known as
                </dt>
                <dd id="gall-names" class="text-ink-2">
                  <span :for={{name, i} <- Enum.with_index(@common_names)}>
                    {if i > 0, do: " · "}{name}<span class="text-meta text-muted"> (common name)</span>
                    <.fact_link :if={@editing} to={to_fact(@panel, {:alias, name})} />
                  </span>
                  <span :for={a <- @name_rows}>
                    · <.taxon_name :if={not a.label?} name={a.name} />
                    <span :if={a.label?}>{a.name}</span>
                    <span class="text-meta text-muted">({a.type})</span>
                  </span>
                </dd>
                <dd :if={@editing and @name_rows != []} class="mt-1">
                  <.edit_scope kind={:follows}>
                    Synonyms are the Inducer's (its page's Facts); former labels and codes follow from renames and merges.
                  </.edit_scope>
                </dd>
              </div>
            </dl>
            <.see_also name={@gall.name} type={:gall} undescribed={@gall.undescribed?} />
            <.record_metadata inserted_at={@gall.inserted_at} updated_at={@gall.updated_at} />
            <.panel :if={@editing} variant={:danger} title="Delete or merge">
              <p class="text-meta text-ink-2">
                As today (RecordRemoval): left out of the mockup, which writes nothing.
              </p>
            </.panel>
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
        title={"Possible range of #{@gall.name}"}
        size={:full}
        show
        on_cancel={JS.push("close_map")}
      >
        <.range_map
          id="gall-range-map-large"
          class="h-160"
          in_range={@range}
          inherited_range={@inherited_range}
          introduced_range={@introduced_range}
          bounds={@range_bounds}
          navigable
        />
      </.dialog>
      <.dialog
        :if={@selected_source}
        id="source-detail-modal"
        title={@selected_source.title}
        size={:lg}
        show
        on_cancel={JS.push("close_source_modal")}
      >
        <.prose markdown={@selected_source.description} size={@modal_font_size} font={:serif} />
        <:actions>
          <.button navigate={"/source/#{@selected_source.id}"}>Source page</.button>
        </:actions>
      </.dialog>
    </Layouts.app>
    """
  end
end
