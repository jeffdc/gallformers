defmodule GallformersWeb.GallLive do
  @moduledoc """
  The Gall page, on the design system (matter bc0d; behavior in
  docs/design-system/inventory/gall-page.md). A Gall from
  `Gallformers.Catalog.gall_page/1`: its Inducer's lineage, name and
  generation, the other generation, Hosts, Traits, the Gallformers ID Notes
  (pinned, in full), its Sources by year (each opens in the reader; a
  `?source=` link opens it there directly), its Facts with their Sources
  (`Gallformers.Import.facts_for_gall/1`, the history collapsed), its
  photos, the range map (framed on the native range; Enlarge opens a large
  map) and its names.
  An unknown or malformed ID is a 404.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{
    Accounts,
    Catalog,
    Curation,
    Galls,
    Glossaries,
    Import,
    Markdown,
    Places
  }

  import GallformersWeb.FactsComponents, only: [facts_view: 1, entries: 1]

  alias Gallformers.Catalog.ReadModels.GallPage
  alias Gallformers.Images.Image
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.Admin.PlaceDrillDown
  alias GallformersWeb.GallLive.RangeEdit
  alias GallformersWeb.SEO
  alias GallformersWeb.TaxonomyURL

  @sources_initial_limit 8
  # Names italic in the breadcrumb: genus, section and the Inducer itself.
  @italic_ranks [:genus, :section, :species, :subspecies, :variety, :form]

  @detachable_values %{
    "unknown" => "",
    "integral" => "Integral",
    "detachable" => "Detachable",
    "both" => "Both"
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {gall_id, ""} ->
        mount_gall(socket, gall_id)

      _ ->
        mount_code(socket, id)
    end
  end

  # A Gall merged into another (live navigation; the HTTP request is
  # redirected by `GallformersWeb.Plugs.LegacyEntityRedirect`).
  defp mount_code(socket, code) do
    case Catalog.gall_redirect(code) do
      nil -> raise GallformersWeb.NotFoundError, "No gall #{code}"
      to -> {:ok, push_navigate(socket, to: ~p"/gall/#{to}")}
    end
  end

  defp mount_gall(socket, gall_id) do
    case load_gall(socket, gall_id) do
      {:ok, socket} -> mount_loaded(socket, gall_id)
      {:redirect, to} -> {:ok, push_navigate(socket, to: ~p"/gall/#{to}")}
    end
  end

  defp mount_loaded(socket, gall_id) do
    curator = socket.assigns[:curator]

    # A curator keeps up with their tray and others' (Edit mode, ec2c).
    if curator && connected?(socket) do
      Curation.subscribe(curator)
      Curation.subscribe_subject({:gall, gall_id})
      Import.subscribe_records()
    end

    {:ok,
     assign(socket,
       editing: false,
       photos_open: false,
       others_pending: [],
       range_edit: nil,
       range_bounds_edit: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Edit mode (`?edit`): curators only; for anyone else the public page.
    editing = Map.has_key?(params, "edit") and socket.assigns[:curator] != nil

    socket =
      socket
      |> assign(editing: editing, photos_open: editing and Map.has_key?(params, "photos"))
      |> load_others_pending()

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

  defp load_others_pending(%{assigns: %{editing: true, curator: curator, gall: gall}} = socket),
    do: assign(socket, others_pending: Curation.others_pending({:gall, gall.id}, curator))

  defp load_others_pending(socket), do: assign(socket, others_pending: [])

  # The tray changed (this curator's, or another's about this Gall): refresh
  # Edit mode's marks.
  @impl true
  def handle_info({PlaceDrillDown, {:toggle_place, code}}, socket),
    do: {:noreply, RangeEdit.mark(socket, code)}

  def handle_info({PlaceDrillDown, {:include_all, codes}}, socket),
    do: {:noreply, RangeEdit.include_all(socket, codes)}

  def handle_info({PlaceDrillDown, {:exclude_all, codes}}, socket),
    do: {:noreply, RangeEdit.exclude_all(socket, codes)}

  def handle_info({PlaceDrillDown, :zoom_out}, socket),
    do: {:noreply, push_event(socket, "range-zoom-out", %{})}

  # Another curator deleted or merged this Gall (`Gallformers.Import`'s
  # records topic): go where it went. The curator's own delete or merge
  # navigates from `GallformersWeb.RecordRemoval`.
  def handle_info({event, %{by: by}}, %{assigns: %{curator: %{name: by}}} = socket)
      when event in [:records_merged, :records_deleted],
      do: {:noreply, socket}

  def handle_info(
        {:records_merged, %{type: :gall, absorbed_id: id, survivor_id: to, by: by}},
        socket
      )
      when id == socket.assigns.gall.id do
    {:noreply,
     socket
     |> put_flash(:info, "#{by} merged this Gall into another; here it is.")
     |> push_navigate(
       to: if(socket.assigns.editing, do: ~p"/gall/#{to}?edit", else: ~p"/gall/#{to}")
     )}
  end

  def handle_info({:records_deleted, %{galls: ids, by: by}}, socket) do
    if socket.assigns.gall.id in ids do
      {:noreply,
       socket |> put_flash(:info, "#{by} deleted this Gall.") |> push_navigate(to: ~p"/galls")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({event, _payload}, socket) when event in [:records_merged, :records_deleted],
    do: {:noreply, socket}

  # Photos imported from an observation (Add from observation).
  def handle_info({:inat_import_complete, _owner}, socket), do: {:noreply, reload_gall(socket)}

  def handle_info({:change_set, _change}, socket) do
    # The Editor's marks change even when the Gall's data doesn't.
    if socket.assigns.editing,
      do: send_update(GallformersWeb.GallLive.Editor, id: "gall-editor", refresh: true)

    {:noreply, socket |> reload_gall() |> load_others_pending()}
  end

  # Something may have been applied: the Gall's data again, keeping what the
  # reader has open.
  defp reload_gall(socket) do
    keep =
      Map.take(socket.assigns, [
        :editing,
        :selected_source,
        :modal_font_size,
        :sources_expanded,
        :sources_order,
        :map_open
      ])

    case load_gall(socket, socket.assigns.gall.id) do
      {:ok, reloaded} -> assign(reloaded, keep)
      {:redirect, to} -> push_navigate(socket, to: ~p"/gall/#{to}")
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

        # Parse the generation qualifier off the name and fetch its definition
        {base_name, generation_term, glossary_word, generation_definition} =
          parse_generation_term(gall.name, gall.generation)

        # Build SEO data
        page_url = "/gall/#{gall_id}"

        page_description =
          Galls.Summary.for_seo(gall.name, Galls.Summary.from_traits(gall.traits))

        page_image =
          case images do
            [first | _] -> first.url
            [] -> nil
          end

        # Build JSON-LD structured data
        json_ld = build_species_json_ld(gall, page_url, page_description, page_image)

        {:ok,
         assign(socket,
           page_title: gall.name,
           page_description: page_description,
           page_url: page_url,
           page_image: page_image,
           page_json_ld: json_ld,
           page_noindex: false,
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
           # The map frames the native range; introduced places are drawn, not framed.
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
           facts: load_facts(socket, gall_id)
         )}
    end
  end

  # The Gall's Facts with their Sources, read on the connected mount (and
  # again after an apply): the first render, what search engines read, has
  # the page without waiting for them.
  defp load_facts(socket, gall_id),
    do: if(connected?(socket), do: Import.facts_for_gall(gall_id))

  defp current_count(entries), do: Enum.count(entries, &(&1.standing in [nil, :current]))

  # The breadcrumb: the (first) Inducer's lineage, the ranks that have a
  # page (family … genus), each linked by its encoded name, then the Inducer
  # itself at species rank or below, linked to its species page.
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

  # The names table: the Inducer's synonyms, then the Gall's former labels
  # and codes (never common names, which are listed apart).
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

  # The eleven Traits in today's order, and Abundance, each with its shown
  # value; nil when not recorded (`fact_list` collects those into one line).
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

  defp trait_values(gall) do
    traits = for {label, key} <- @traits, do: {label, blank(trait_display(gall, key))}
    traits ++ [{"Abundance", blank(gall.abundance)}]
  end

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: value

  defp trait_value(traits, label),
    do: Enum.find_value(traits, fn {l, value} -> l == label && value end)

  # Sources by year (n.d. last), oldest or newest first; the note is shown apart.
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

  # A Source's text for a two-line preview: no markup.
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

  defp build_species_json_ld(gall, url, description, image) do
    json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "Thing",
      "name" => gall.name,
      "description" => description,
      "url" => SEO.base_url() <> url,
      "identifier" => gall.name
    }

    json_ld = if image, do: Map.put(json_ld, "image", image), else: json_ld

    Jason.encode!(json_ld)
  end

  defp format_images(images) do
    base_url = Image.base_url()

    Enum.map(images, fn img ->
      # Replace "original" with size name in the path
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

  # A Trait's line: its values, each with the Sources' terms under it
  # ("globular (oval, ovoid)"), then the terms it has no category for, as
  # text ("; also described as “reticulate”"). Detachable shows its one
  # value's label.
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

  # Splits the generation qualifier (e.g. "agamic", "sexgen") off the Gall's
  # name and gives its definition: the vocabulary's, else the glossary entry
  # named by the qualifier. Returns {base_name, term, glossary_word,
  # definition}, or {name, nil, nil, nil} when the name carries none.
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

  @impl true
  # -- range exclusions (Edit mode; GallformersWeb.GallLive.RangeEdit) -----------

  def handle_event("open_range", _params, %{assigns: %{editing: true}} = socket),
    do: {:noreply, RangeEdit.open(socket)}

  def handle_event("close_range", _params, socket), do: {:noreply, RangeEdit.close(socket)}

  def handle_event("toggle_region", %{"code" => code}, socket),
    do: {:noreply, RangeEdit.mark(socket, code)}

  def handle_event("toggle_country", %{"code" => code}, socket),
    do: {:noreply, RangeEdit.country(socket, code)}

  def handle_event("range_to_tray", _params, %{assigns: %{range_edit: %{}}} = socket),
    do: {:noreply, RangeEdit.to_tray(socket)}

  def handle_event("clipboard_copy_success", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied to clipboard")}
  end

  @impl true
  def handle_event("clipboard_copy_error", _params, socket) do
    {:noreply, put_flash(socket, :error, "Failed to copy to clipboard")}
  end

  @impl true
  def handle_event("gallery_index_changed", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_source_detail", %{"id" => id_str}, socket) do
    source_id = String.to_integer(id_str)
    source = Enum.find(socket.assigns.sources, fn s -> s.id == source_id end)
    {:noreply, assign(socket, selected_source: source)}
  end

  @impl true
  def handle_event("close_source_modal", _params, socket) do
    {:noreply, assign(socket, selected_source: nil, modal_font_size: :base)}
  end

  @font_sizes [:sm, :base, :lg, :xl]

  @impl true
  def handle_event("increase_font_size", _params, socket) do
    current = socket.assigns.modal_font_size
    current_idx = Enum.find_index(@font_sizes, &(&1 == current))
    new_size = Enum.at(@font_sizes, min(current_idx + 1, length(@font_sizes) - 1))
    {:noreply, assign(socket, modal_font_size: new_size)}
  end

  @impl true
  def handle_event("decrease_font_size", _params, socket) do
    current = socket.assigns.modal_font_size
    current_idx = Enum.find_index(@font_sizes, &(&1 == current))
    new_size = Enum.at(@font_sizes, max(current_idx - 1, 0))
    {:noreply, assign(socket, modal_font_size: new_size)}
  end

  @impl true
  def handle_event("expand_sources", _params, socket) do
    {:noreply, assign(socket, sources_expanded: true)}
  end

  @impl true
  def handle_event("sources_order", %{"order" => order}, socket) when order in ["asc", "desc"],
    do: {:noreply, assign(socket, sources_order: String.to_existing_atom(order))}

  @impl true
  def handle_event("open_map", _params, socket), do: {:noreply, assign(socket, map_open: true)}

  @impl true
  def handle_event("close_map", _params, socket), do: {:noreply, assign(socket, map_open: false)}

  @impl true
  def handle_event("navigate_to_place", %{"code" => code}, socket) do
    {:noreply, push_navigate(socket, to: "/place/#{code}")}
  end

  defp visible_sources(sources, expanded?)
       when expanded? or length(sources) <= @sources_initial_limit do
    sources
  end

  defp visible_sources(sources, _expanded?) do
    # Always include the Gallformers note if there is one
    gallformers_notes = Enum.find(sources, & &1.note?)

    case gallformers_notes do
      nil ->
        Enum.take(sources, @sources_initial_limit)

      _ ->
        other_sources = Enum.reject(sources, & &1.note?)
        # Take 7 other sources + Gallformers Notes = 8 total
        limited_sources = Enum.take(other_sources, @sources_initial_limit - 1)
        # Maintain original order by sorting by position in original list
        Enum.sort_by([gallformers_notes | limited_sources], fn s ->
          Enum.find_index(sources, &(&1.id == s.id))
        end)
    end
  end

  defp show_expand_button?(sources, expanded?) do
    !expanded? and length(sources) > @sources_initial_limit
  end

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
      <div class="flex flex-col gap-section">
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
            <span title={
              if @gall.datacomplete,
                do:
                  "All sources containing unique information relevant to this gall have been added and are reflected in its associated data.",
                else: "We are still working on this gall so data might be missing."
            }>
              {if @gall.datacomplete, do: "Complete", else: "In progress"}
            </span>
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
            <%!-- The dialog is the Editor's (GallLive.Editor). --%>
            <.button
              id="add-from-observation"
              variant="secondary"
              icon="ph-eye"
              phx-click="open_observation"
              phx-target="#gall-editor"
            >
              Add from observation…
            </.button>
          </:action>
          <:action :if={@curator}>
            <.edit_toggle editing={@editing} path={"/gall/#{@gall.id}"} />
          </:action>
        </.page_header>

        <div :if={@editing} id="editing" class="flex flex-col gap-2">
          <.notice kind={:info} title="Editing">
            Each change goes into your tray at the foot of the screen. Nothing changes until you Review and apply; Fact history is kept, so nothing is lost.
          </.notice>
          <.notice :if={@others_pending != []} id="others-pending" kind={:warn}>
            <span :for={{other, i} <- Enum.with_index(@others_pending)}>
              {if i > 0, do: "; "}{other.user.name} has {other.count} unapplied {if other.count == 1,
                do: "change",
                else: "changes"} here
            </span>. Applying yours first means theirs are checked again against it.
          </.notice>
          <.edit_scope
            :if={@gall.inducers != []}
            kind={:elsewhere}
            href={TaxonomyURL.inducer_path(hd(@gall.inducers), edit: true)}
          >
            The lineage and the Inducer's synonyms: on the page of <i>{hd(@gall.inducers).name}</i>.
          </.edit_scope>
          <.edit_scope :if={@related_galls != []} kind={:follows}>
            The other generation follows from the Inducer: Galls with the same Inducer.
          </.edit_scope>
          <.edit_scope kind={:follows}>
            Season, Location and Form above follow from the Traits below; the range map from the Hosts' ranges.
          </.edit_scope>
        </div>

        <.notice
          :if={@gall.undescribed? && @gallformers_code}
          kind={:warn}
          title="The inducer of this gall is unknown or undescribed."
        >
          Gallformers Code
          <button
            id="copy-gallformers-code"
            type="button"
            phx-hook="CopyToClipboard"
            data-copy-text={@gallformers_code}
            title="Copy"
            class="rounded-ctl border border-line bg-surface px-1.5 font-mono text-ui"
          >
            {@gallformers_code} <.icon name="ph-copy" class="size-3.5" />
          </button>
          ·
          <a
            href={"https://www.inaturalist.org/observations?verifiable=any&place_id=any&field:Gallformers%20Code=#{URI.encode(@gallformers_code)}"}
            target="_blank"
            rel="noreferrer"
          >
            Observations with this code on iNaturalist ↗
          </a>
          · <.link href="/articles/link-undescribed-inat">How it works</.link>
        </.notice>
        <p :if={!@gall.undescribed? && @gallformers_code} class="-mt-4 text-meta text-muted">
          Formerly tracked as undescribed:
          <a
            href={"https://www.inaturalist.org/observations?verifiable=any&place_id=any&field:Gallformers%20Code=#{URI.encode(@gallformers_code)}"}
            target="_blank"
            rel="noreferrer"
          >
            iNaturalist observations under "{@gallformers_code}" ↗
          </a>
        </p>

        <div class="gf-with-rail">
          <div class="flex min-w-0 flex-col gap-section">
            <.live_component
              :if={@editing}
              module={GallformersWeb.GallLive.Editor}
              id="gall-editor"
              gall={@gall}
              curator={@curator}
              photos_open={@photos_open}
            />

            <.section :if={!@editing} title="Hosts" count={length(@gall.hosts)}>
              <.name_list items={@gall.hosts} columns={4}>
                <:item :let={host}>
                  <.link navigate={host_href(host)}>
                    <.taxon_name name={host.name} genus_placeholder={host.rank == :genus} />
                  </.link>
                </:item>
              </.name_list>
            </.section>

            <.section
              :if={!@editing}
              id="gall-traits-section"
              title="Traits"
              count={"#{Enum.count(@traits, &elem(&1, 1))} of #{length(@traits)} recorded"}
            >
              <.fact_list id="gall-traits" columns={2}>
                <:item :for={{label, value} <- @traits} label={label} value={value} />
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
                <button
                  id={"copy-source-link-#{@note.id}"}
                  type="button"
                  phx-hook="CopyToClipboard"
                  data-copy-text={"/gall/#{@gall.id}?source=#{@note.id}"}
                  data-copy-url
                  class="ml-auto text-muted"
                  title="Copy link to the ID Notes"
                >
                  <.icon name="ph-link" class="size-4" />
                </button>
              </div>
              <.prose markdown={@note.description} size={:sm} font={:serif} class="mt-2" />
              <button
                type="button"
                phx-click="show_source_detail"
                phx-value-id={@note.id}
                class="block text-left text-meta text-link"
              >
                Read
              </button>
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
              <%!-- PROPOSED: source_entry with Markdown (matter bc0d) --%>
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
                    <div class="flex items-baseline gap-2">
                      <span class="min-w-0 flex-1">
                        <.link navigate={"/source/#{source.id}"} class="font-semibold">
                          {source.title}
                        </.link>
                        <span :if={source.author} class="text-meta text-ink-2">
                          · {source.author}
                        </span>
                      </span>
                      <span class="flex shrink-0 items-center gap-2 text-muted">
                        <.link
                          :if={valid_url?(source.externallink)}
                          href={source.externallink}
                          target="_blank"
                          rel="noopener noreferrer"
                          title="View external source"
                        >
                          <.icon name="ph-arrow-square-out" class="size-4" />
                        </.link>
                        <button
                          id={"copy-source-link-#{source.id}"}
                          type="button"
                          phx-hook="CopyToClipboard"
                          data-copy-text={"/gall/#{@gall.id}?source=#{source.id}"}
                          data-copy-url
                          title="Copy link to this description"
                        >
                          <.icon name="ph-link" class="size-4" />
                        </button>
                      </span>
                    </div>
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
                    <p :if={source.license} class="text-caption text-muted">{source.license}</p>
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
              :if={@fact_entries != []}
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
              edit_href={"/gall/#{@gall.id}?edit&photos"}
              admin={Accounts.admin?(@current_user)}
            />

            <.panel title="Possible range">
              <:header_action>
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

            <dl class="flex flex-col gap-3 text-ui">
              <div :if={@name_rows != [] or @common_names != []}>
                <dt class="text-meta font-semibold uppercase tracking-wide text-muted">
                  Also known as
                </dt>
                <dd id="gall-names" class="text-ink-2">
                  <span :for={{name, i} <- Enum.with_index(@common_names)}>
                    {if i > 0, do: " · "}{name}<span class="text-meta text-muted"> (common name)</span>
                  </span>{if @common_names !=
                                                                                                                                                                                                            [] and
                                                                                                                                                                                                            @name_rows !=
                                                                                                                                                                                                              [],
                                                                                                                                                                                                          do:
                                                                                                                                                                                                            " · "}
                  <span :for={{a, i} <- Enum.with_index(@name_rows)}>
                    {if i > 0, do: " · "}<.taxon_name :if={not a.label?} name={a.name} />
                    <span :if={a.label?}>
                      {a.name}
                    </span>
                    <span
                      :if={a.type != "synonym" or a.notes}
                      class="text-meta text-muted"
                    >
                      ({[a.type != "synonym" && a.type, a.notes]
                      |> Enum.filter(& &1)
                      |> Enum.join(", ")})
                    </span>
                  </span>
                </dd>
              </div>
            </dl>
            <.see_also name={@gall.name} type={:gall} undescribed={@gall.undescribed?} />

            <.record_metadata inserted_at={@gall.inserted_at} updated_at={@gall.updated_at} />

            <.live_component
              :if={@editing}
              module={GallformersWeb.RecordRemoval}
              id="record-removal"
              subject={{:gall, @gall.id}}
              name={@gall.name}
              actor={@curator}
              merge={:gall}
              deleted_path={~p"/galls"}
              merged_path={&"/gall/#{&1}?edit"}
            />
          </.rail>
        </div>
      </div>

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
        <p class="mt-2 text-caption text-muted">
          Where the hosts grow, not where the gall was found. The map's full-screen button gives more room; Esc closes.
        </p>
      </.dialog>
      <.dialog
        :if={@selected_source}
        id="source-detail-modal"
        title={@selected_source.title}
        size={:lg}
        show
        on_cancel={JS.push("close_source_modal")}
      >
        <div class="flex flex-col gap-3">
          <div class="flex items-center gap-2 text-meta text-ink-2">
            {@selected_source.author}{if @selected_source.pubyear,
              do: " (#{@selected_source.pubyear})"}
            <span class="ml-auto flex gap-1">
              <.button
                variant="ghost"
                size="sm"
                phx-click="decrease_font_size"
                disabled={@modal_font_size == :sm}
                title="Decrease font size"
              >
                A−
              </.button>
              <.button
                variant="ghost"
                size="sm"
                phx-click="increase_font_size"
                disabled={@modal_font_size == :xl}
                title="Increase font size"
              >
                A+
              </.button>
            </span>
          </div>
          <.prose markdown={@selected_source.description} size={@modal_font_size} font={:serif} />
          <p :if={@selected_source.license} class="border-t border-line pt-2 text-meta text-muted">
            License:
            <.link
              :if={valid_url?(@selected_source.licenselink)}
              href={@selected_source.licenselink}
              target="_blank"
              rel="noopener noreferrer"
            >
              {@selected_source.license}
            </.link>
            <span :if={!valid_url?(@selected_source.licenselink)}>{@selected_source.license}</span>
          </p>
        </div>
        <:actions>
          <button
            id="copy-source-link"
            type="button"
            phx-hook="CopyToClipboard"
            data-copy-text={"/gall/#{@gall.id}?source=#{@selected_source.id}"}
            data-copy-url
            class="mr-auto text-meta text-link"
          >
            Copy link
          </button>
          <.button
            :if={valid_url?(@selected_source.externallink)}
            href={@selected_source.externallink}
            target="_blank"
            rel="noopener noreferrer"
            variant="ghost"
          >
            External link ↗
          </.button>
          <.button navigate={"/source/#{@selected_source.id}"}>Source page</.button>
        </:actions>
      </.dialog>
      <RangeEdit.range_dialog :if={@range_edit} edit={@range_edit} bounds={@range_bounds_edit} />
    </Layouts.app>
    """
  end
end
