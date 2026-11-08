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

  import GallformersWeb.FactsComponents,
    only: [facts_view: 1, entries: 1, fact_ref: 1, fact_inspector: 1, trait_label: 1]

  alias Gallformers.Catalog.ReadModels.GallPage
  alias Gallformers.Images.Image
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.Admin.PlaceDrillDown
  alias GallformersWeb.FactKey
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
       pending: %{},
       adding: nil,
       observation: nil,
       observing: [],
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
      |> select_fact(params["fact"])
      |> observe(editing && params["observation"])

    {:noreply, select_source(socket, params["source"])}
  end

  # The Fact `?fact=` names (`GallformersWeb.FactKey`), when it is one of the
  # page's; anything else opens nothing.
  defp select_fact(socket, text) when is_binary(text) do
    with {:ok, key} <- FactKey.decode(text),
         %{} = fact <- find_fact(socket.assigns.gall_facts, key) do
      assign(socket, selected: key, fact: fact, adding: nil)
    else
      _ -> assign(socket, selected: nil, fact: nil)
    end
  end

  defp select_fact(socket, _none), do: assign(socket, selected: nil, fact: nil)

  # `?edit&observation=<id>` (from `/admin/observation`): the inspector on
  # that observation, read at once.
  defp observe(socket, id) when is_binary(id) and id != "",
    do: assign(socket, adding: "observation", observation: id)

  defp observe(socket, _none), do: assign(socket, observation: nil)

  defp find_fact(facts, key) do
    traits = Enum.flat_map(facts.traits, & &1.facts)

    Enum.find(
      facts.inducer ++ facts.hosts ++ traits ++ facts.range ++ facts.aliases,
      &(&1.key == key)
    )
  end

  # The page's path with the Fact `key` selected (nil: none), in Edit mode
  # still when it is on.
  defp fact_path(socket, key) do
    query =
      [socket.assigns.editing && "edit", key && "fact=" <> FactKey.param(key)]
      |> Enum.filter(& &1)
      |> Enum.join("&")

    "/gall/#{socket.assigns.gall.id}" <> if(query == "", do: "", else: "?" <> query)
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

  # Edit mode: the curator's tray items here (marked on the page and in the
  # inspector), and other curators' unapplied changes.
  defp load_others_pending(%{assigns: %{editing: true, curator: curator, gall: gall}} = socket) do
    assign(socket,
      others_pending: Curation.others_pending({:gall, gall.id}, curator),
      pending: Curation.pending_for(curator, {:gall, gall.id})
    )
  end

  defp load_others_pending(socket), do: assign(socket, others_pending: [], pending: %{})

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

  # The inspector put something in the tray (`GallLive.FactActions`,
  # `GallLive.FromObservation`).
  def handle_info({module, :added}, socket)
      when module in [
             GallformersWeb.GallLive.FactActions,
             GallformersWeb.GallLive.FromObservation
           ],
      do:
        {:noreply,
         socket |> assign(adding: nil, observing: []) |> put_flash(:info, "Added to your tray")}

  # What an observation would add, ticked: previewed on the page.
  def handle_info({GallformersWeb.GallLive.FromObservation, :proposing, keys}, socket),
    do: {:noreply, assign(socket, observing: keys)}

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
        :selected,
        :modal_font_size,
        :sources_expanded,
        :sources_order,
        :map_open
      ])

    case load_gall(socket, socket.assigns.gall.id) do
      {:ok, reloaded} -> reloaded |> assign(keep) |> reselect()
      {:redirect, to} -> push_navigate(socket, to: ~p"/gall/#{to}")
    end
  end

  # The selected Fact as it is now; gone, the inspector closes.
  defp reselect(%{assigns: %{selected: key}} = socket) when key != nil do
    case find_fact(socket.assigns.gall_facts, key) do
      nil -> assign(socket, selected: nil, fact: nil)
      fact -> assign(socket, fact: fact)
    end
  end

  defp reselect(socket), do: socket

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
           facts: load_facts(socket, gall_id),
           # Every Fact-backed value on the page, on the first render too
           # (what search engines read).
           gall_facts: Import.gall_facts(gall_id)
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

  # Each Trait's row: its values as Facts, and its Sources' words with no
  # value of their own ("also described as “reticulate”"), kept as text.
  defp trait_rows(facts, gall) do
    by_trait = Map.new(facts.traits, &{&1.trait, &1.facts})

    for {_label, trait} <- @traits do
      values = Map.get(by_trait, trait, [])
      text_terms = Map.get(gall.text_terms, trait, [])

      %{
        trait: trait,
        label: trait_label(trait),
        facts: values,
        text_terms: text_terms,
        shown?: values != [] or text_terms != []
      }
    end
  end

  # A Trait value as the page shows it (Detachable's labelled).
  defp trait_shown(%{trait: "detachable", value: %{value: value}}),
    do: Map.get(@detachable_values, value, value)

  defp trait_shown(%{value: %{value: value}}), do: value

  defp common_names(facts), do: Enum.filter(facts.aliases, &(&1.value[:kind] == :common_name))

  # What the curator's tray adds here that the Gall doesn't hold yet, in
  # words, by group (`:host`, `{:trait, trait}`, `:range`, `:alias`): shown
  # on the page as proposed.
  defp proposed(pending, observing, facts) do
    held = MapSet.new(all_facts(facts), & &1.key)

    adds =
      for {key, items} <- pending,
          Enum.any?(items, &match?(%{kind: :fact, spec: %{action: :add}}, &1)),
          do: key

    for key <- Enum.uniq(adds ++ observing),
        not MapSet.member?(held, key),
        group = proposed_group(key),
        group != nil,
        reduce: %{} do
      acc -> Map.update(acc, group, [proposed_words(key)], &(&1 ++ [proposed_words(key)]))
    end
  end

  defp all_facts(facts) do
    facts.inducer ++
      facts.hosts ++ Enum.flat_map(facts.traits, & &1.facts) ++ facts.range ++ facts.aliases
  end

  defp proposed_group({:host, _id}), do: :host
  defp proposed_group({:trait, trait, _value}), do: {:trait, trait}
  defp proposed_group({kind, _id}) when kind == :occurrence, do: :range
  defp proposed_group({:range, _adjustment, _id}), do: :range
  defp proposed_group({:alias, _name}), do: :alias
  defp proposed_group(_key), do: nil

  defp proposed_words({:occurrence, _} = key), do: "recorded in " <> Curation.value_words(key)
  defp proposed_words({:range, :exclude, _} = key), do: "not in " <> Curation.value_words(key)
  defp proposed_words({:range, :only, _} = key), do: "only in " <> Curation.value_words(key)
  defp proposed_words(key), do: Curation.value_words(key)

  attr :group, :string, required: true
  attr :small, :boolean, default: false
  slot :inner_block, required: true

  # A group's Add (Edit mode).
  defp add(assigns) do
    ~H"""
    <.button
      variant="link"
      icon="ph-plus"
      size={if @small, do: "sm", else: "md"}
      phx-click="add_fact"
      phx-value-group={@group}
    >
      {render_slot(@inner_block)}
    </.button>
    """
  end

  attr :values, :list, default: nil

  # What the tray would add here, marked proposed.
  defp proposed(%{values: values} = assigns) when values in [nil, []], do: ~H""

  defp proposed(assigns) do
    ~H"""
    <span class="mt-2 flex flex-wrap gap-2">
      <.fact_ref :for={value <- @values} proposed text={value} />
    </span>
    """
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

  # -- the Fact inspector (matter 87a1) ---------------------------------------------

  def handle_event("select_fact", %{"key" => text}, socket) do
    case FactKey.decode(text) do
      {:ok, key} -> {:noreply, push_patch(socket, to: fact_path(socket, key))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("close_fact", _params, %{assigns: %{selected: nil}} = socket),
    do: {:noreply, assign(socket, adding: nil, observing: [])}

  def handle_event("close_fact", _params, socket),
    do: {:noreply, push_patch(socket, to: fact_path(socket, nil))}

  # A group's Add (Edit mode): the inspector on a new Fact of that group.
  def handle_event("add_fact", %{"group" => group}, %{assigns: %{editing: true}} = socket) do
    socket = assign(socket, adding: group, observing: [])

    if socket.assigns.selected,
      do: {:noreply, push_patch(socket, to: fact_path(socket, nil))},
      else: {:noreply, socket}
  end

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
        fact_entries: entries(assigns.facts || []),
        trait_rows: trait_rows(assigns.gall_facts, assigns.gall),
        proposed: proposed(assigns.pending, assigns.observing, assigns.gall_facts)
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
            <.button
              id="add-from-observation"
              variant="secondary"
              icon="ph-eye"
              phx-click="add_fact"
              phx-value-group="observation"
            >
              Add from observation…
            </.button>
          </:action>
          <:action :if={@curator}>
            <.edit_toggle editing={@editing} path={"/gall/#{@gall.id}"} />
          </:action>
        </.page_header>

        <div :if={@editing} id="editing" class="flex flex-col gap-2">
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

            <%!-- The readers' hint: the underline means something (matter 87a1).
                 Hidden until the Dismissible hook finds it wasn't dismissed. --%>
            <p
              :if={!@editing}
              id="fact-hint"
              phx-hook="Dismissible"
              data-key="gf-fact-hint"
              hidden
              class="flex items-start gap-2 text-ui text-ink-2"
            >
              <.icon name="ph-info" class="mt-0.5 size-4 shrink-0 text-muted" />
              <span class="flex-1">
                Underlined values show the Sources that state them. Select one to see who says so.
              </span>
              <.button
                size="sm"
                variant="ghost"
                icon="ph-x"
                icon_only
                label="Dismiss"
                data-dismiss
              />
            </p>

            <.notice :if={@editing} id="editing-how" title="Editing">
              Select a value to change it, or Add to a group. The page stays as readers see it; every change waits in your tray until you apply it.
            </.notice>

            <.section id="gall-inducer" title="Inducer">
              <div class="flex flex-col gap-1">
                <.fact_ref
                  :for={inducer <- @gall_facts.inducer}
                  fact={inducer}
                  selected={@selected}
                  on_select="select_fact"
                />
                <p :if={@gall_facts.inducer == []} class="text-ui text-muted">
                  No Inducer: the Gall is undescribed.
                </p>
              </div>
            </.section>

            <.section id="gall-hosts" title="Hosts" count={length(@gall_facts.hosts)}>
              <:aside :if={@editing}>
                <.add group="host">Add a host</.add>
              </:aside>
              <.name_list items={@gall_facts.hosts} columns={4}>
                <:item :let={host}>
                  <.fact_ref fact={host} selected={@selected} on_select="select_fact" />
                </:item>
              </.name_list>
              <.proposed values={@proposed[:host]} />
            </.section>

            <.section
              id="gall-traits-section"
              title="Traits"
              count={"#{Enum.count(@traits, &elem(&1, 1))} of #{length(@traits)} recorded"}
            >
              <.fact_list
                id="gall-traits"
                columns={2}
                missing_label={if @editing, do: nil, else: "Not recorded"}
              >
                <:item :for={row <- @trait_rows} :if={row.shown?} label={row.label}>
                  <span class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
                    <.fact_ref
                      :for={fact <- row.facts}
                      fact={fact}
                      selected={@selected}
                      on_select="select_fact"
                    >
                      {trait_shown(fact)}
                    </.fact_ref>
                    <span :if={row.text_terms != []} class="text-ink-2">
                      {if row.facts == [], do: "described as", else: "also described as"} {quoted(
                        row.text_terms
                      )}
                    </span>
                    <.proposed values={@proposed[{:trait, row.trait}]} />
                    <.add :if={@editing} group={"trait:" <> row.trait} small>Add</.add>
                  </span>
                </:item>
                <:item :for={row <- @trait_rows} :if={!row.shown?} label={row.label} value={nil} />
                <:item label="Abundance" value={@gall.abundance} />
              </.fact_list>
              <p
                :if={@editing and Enum.any?(@trait_rows, &(!&1.shown?))}
                class="mt-2 flex flex-wrap items-baseline gap-x-3 gap-y-1 text-meta text-muted"
              >
                Not recorded:
                <.add
                  :for={row <- Enum.reject(@trait_rows, & &1.shown?)}
                  group={"trait:" <> row.trait}
                  small
                >
                  {String.downcase(row.label)}
                </.add>
              </p>
            </.section>

            <.section :if={@editing or @gall_facts.range != []} id="gall-range" title="Range">
              <:aside :if={@editing}>
                <.add group="range">Add a place</.add>
              </:aside>
              <p class="mb-2 text-meta text-muted">
                Where the Hosts grow, adjusted by these places.
              </p>
              <div class="flex flex-wrap gap-x-4 gap-y-1">
                <.fact_ref
                  :for={place <- @gall_facts.range}
                  fact={place}
                  selected={@selected}
                  on_select="select_fact"
                />
              </div>
              <.proposed values={@proposed[:range]} />
            </.section>

            <.section
              :if={@editing or common_names(@gall_facts) != []}
              id="gall-common-names"
              title="Common names"
            >
              <:aside :if={@editing}>
                <.add group="alias">Add a common name</.add>
              </:aside>
              <div class="flex flex-wrap gap-x-4 gap-y-1">
                <.fact_ref
                  :for={name <- common_names(@gall_facts)}
                  fact={name}
                  selected={@selected}
                  on_select="select_fact"
                />
              </div>
              <.proposed values={@proposed[:alias]} />
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
            <.live_component
              :if={@editing and @adding == "observation"}
              module={GallformersWeb.GallLive.FromObservation}
              id="from-observation"
              gall={@gall}
              curator={@curator}
              observation={@observation}
            />
            <.live_component
              :if={@editing and (@fact || (@adding && @adding != "observation"))}
              module={GallformersWeb.GallLive.FactActions}
              id="fact-actions"
              fact={@fact}
              new={@adding}
              gall={@gall}
              curator={@curator}
              pending={(@fact && Map.get(@pending, @fact.key)) || []}
            />
            <.fact_inspector
              :if={!@editing and @fact}
              id="fact-inspector"
              fact={@fact}
              of={@gall}
              on_close="close_fact"
            />
            <%!-- While a Fact is open the inspector takes the rail's place on
                 wide screens; on phones it is a sheet over the page. --%>
            <div
              data-part="rail-content"
              data-inspecting={(@fact || @adding) && true}
              class={["flex flex-col gap-block", (@fact || @adding) && "lg:hidden"]}
            >
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
                <div :if={@name_rows != []}>
                  <dt class="text-meta text-muted">
                    Also known as
                  </dt>
                  <dd id="gall-names" class="text-ink-2">
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
            </div>
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
