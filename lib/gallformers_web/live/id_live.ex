defmodule GallformersWeb.IDLive do
  @moduledoc """
  LiveView for the gall identification tool.

  Allows users to filter galls by various characteristics (host, genus, plant part,
  color, shape, etc.) with URL-based state preservation for back/forward navigation.

  Reads `Gallformers.Catalog.identify/1` (one query over the stored per-Gall
  lookup table) and the `Gallformers.Taxa` typeaheads (`803b` §3, Task 10).

  ## URLs and old bookmarks

  URLs carry readable values: the host's name (`h`), the host genus or
  section's name and rank (`g`, `gt`), each Trait's values (`co=red`,
  `lo=upper leaf,lower leaf`) and the Inducer family's name (`fa`).

  Old bookmarks keep working:

    * integer Trait parameters are rows of the old vocabulary tables,
      translated through `Gallformers.Catalog.legacy_trait_values/0`;
    * an integer `fa` is an old taxonomy ID, translated through the legacy
      crosswalk (`Gallformers.Taxa.get_by_legacy_id/2`); an unknown ID is
      ignored, never matched to another taxon;
    * `h` matches a plant's accepted name or a synonym, so a renamed plant's
      old name still selects it;
    * `ng` (show non-galls) is ignored: non-galls are not in the catalog;
    * `lo=leaf_anywhere`, the old "leaf (anywhere)" option, is the plant
      part `leaf`, which matches every leaf value (`d213`);
    * V1 parameter names (`hostOrTaxon`, `color`, ...) are mapped as before.

  An unknown Trait value or ID is dropped.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.Galls.Summary
  alias Gallformers.Places
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.Live.ContinentScope

  # URL parameter keys (short codes for compact URLs)
  @url_params %{
    host: "h",
    genus: "g",
    genus_type: "gt",
    locations: "lo",
    location_logic: "lol",
    textures: "te",
    texture_logic: "tel",
    detachable: "de",
    place: "pl",
    family: "fa",
    undescribed: "un"
  }

  # Single-value Trait filters: filter key => {URL param, Trait}
  @single_traits [
    color: {"co", "color"},
    shape: {"sh", "shape"},
    alignment: {"al", "alignment"},
    form: {"fo", "form"},
    walls: {"wa", "walls"},
    cells: {"ce", "cells"},
    season: {"se", "season"}
  ]

  # Multi-value Trait filters: filter key => {URL param, Trait}
  @multi_traits [
    plant_parts: {"lo", "plant_part"},
    textures: {"te", "texture"}
  ]

  @trait_params Enum.map(@single_traits ++ @multi_traits, fn {_key, {param, _}} -> param end)

  # Host genus / section ranks, in the order a name without a rank is tried
  @group_ranks [:genus, :subgenus, :section]

  # V1 URL param names -> V2 param names (for backwards compatibility with old bookmarks)
  @v1_param_mapping %{
    "hostOrTaxon" => "h",
    "locations" => "lo",
    "textures" => "te",
    "color" => "co",
    "shape" => "sh",
    "alignment" => "al",
    "detachable" => "de",
    "walls" => "wa",
    "cells" => "ce",
    "season" => "se",
    "form" => "fo",
    "undescribed" => "un",
    "place" => "pl",
    "family" => "fa"
  }

  @impl true
  def mount(_params, _session, socket) do
    trait_values =
      Map.new(Catalog.identify_options(), fn {trait, values} ->
        {trait, Enum.map(values, & &1.value)}
      end)

    {:ok,
     assign(socket,
       page_title: "ID Tool",
       page_description:
         "Identify plant galls using our interactive tool - filter by host plant, genus, location, morphology, and other characteristics.",
       page_url: "/id",
       page_image: nil,
       page_json_ld: nil,
       page_noindex: true,
       trait_values: trait_values,
       plant_part_options: value_options(Map.get(trait_values, "plant_part", [])),
       texture_options: value_options(Map.get(trait_values, "texture", [])),
       families: [],
       # Current filter selections
       filters: default_filters(),
       # Typeahead state
       host_query: "",
       host_results: [],
       selected_host: nil,
       genus_query: "",
       genus_results: [],
       selected_genus: nil,
       place_query: "",
       place_results: [],
       selected_place: nil,
       # Multi-select typeahead state
       plant_part_query: "",
       plant_part_focused: false,
       texture_query: "",
       texture_focused: false,
       # Results
       results: [],
       filtered_results: [],
       summaries: %{},
       total_count: 0,
       name_filter: "",
       show_advanced: false,
       default_continent_code: socket.assigns[:continent_code],
       unscoped_count: 0
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Normalize V1 param names to V2 for backwards compatibility
    params = normalize_v1_params(params)
    filters = parse_url_params(params, socket.assigns.trait_values)
    socket = apply_url_filters(socket, filters, params)
    {:noreply, socket}
  end

  # Convert V1 URL param names to V2 short codes.
  # V1 used a single hostOrTaxon + type pair; V2 has separate host (h) and genus (g) params.
  # V1 used "true"/"false" for undescribed; V2 uses "1".
  defp normalize_v1_params(params) do
    params
    |> normalize_v1_host_or_taxon()
    |> normalize_v1_undescribed()
    |> rename_v1_keys()
  end

  defp normalize_v1_host_or_taxon(params) do
    case {Map.get(params, "hostOrTaxon"), Map.get(params, "type")} do
      {nil, _} ->
        Map.delete(params, "type")

      {name, type} when type in ["genus", "section"] ->
        params
        |> Map.delete("hostOrTaxon")
        |> Map.delete("type")
        |> Map.put("g", name)
        |> Map.put("gt", type)

      {_name, _} ->
        # "host" or nil — rename_v1_keys will convert hostOrTaxon → h
        Map.delete(params, "type")
    end
  end

  defp normalize_v1_undescribed(params) do
    case Map.get(params, "undescribed") do
      "true" -> Map.put(params, "undescribed", "1")
      _ -> params
    end
  end

  defp rename_v1_keys(params) do
    Enum.reduce(@v1_param_mapping, params, fn {v1_key, v2_key}, acc ->
      case Map.get(acc, v1_key) do
        nil -> acc
        value -> acc |> Map.delete(v1_key) |> Map.put(v2_key, value)
      end
    end)
  end

  # Parse URL parameters into filter map
  defp parse_url_params(params, trait_values) do
    legacy = legacy_trait_values(params)

    single =
      Map.new(@single_traits, fn {key, {param, trait}} ->
        {key, parse_trait_value(params[param], trait, trait_values, legacy)}
      end)

    multi =
      Map.new(@multi_traits, fn {key, {param, trait}} ->
        {key, parse_trait_values(params[param], trait, trait_values, legacy)}
      end)

    %{
      plant_part_logic: parse_logic(params[@url_params.location_logic]),
      texture_logic: parse_logic(params[@url_params.texture_logic]),
      detachable: parse_detachable(params[@url_params.detachable]),
      place: blank_to_nil(params[@url_params.place]),
      family: parse_family(params[@url_params.family]),
      undescribed: params[@url_params.undescribed] == "1"
    }
    |> Map.merge(single)
    |> Map.merge(multi)
  end

  defp parse_logic("and"), do: :and
  defp parse_logic(_), do: :or

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  # The old vocabulary tables' row IDs, read only when a Trait parameter holds one.
  defp legacy_trait_values(params) do
    old_ids? =
      Enum.any?(@trait_params, fn param ->
        params
        |> Map.get(param, "")
        |> to_string()
        |> String.split(",")
        |> Enum.any?(&integer_token?/1)
      end)

    with true <- old_ids?, {:ok, values} <- Catalog.legacy_trait_values() do
      values
    else
      _ -> %{}
    end
  end

  defp integer_token?(token), do: match?({_, ""}, Integer.parse(token))

  defp parse_trait_value(raw, trait, trait_values, legacy) do
    case blank_to_nil(raw) do
      nil -> nil
      token -> trait_value(token, trait, trait_values, legacy)
    end
  end

  defp parse_trait_values(raw, trait, trait_values, legacy) do
    case blank_to_nil(raw) do
      nil ->
        []

      str ->
        str
        |> String.split(",")
        |> Enum.map(&list_item(&1, trait, trait_values, legacy))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    end
  end

  # The old "leaf (anywhere)" option is the plant part `leaf` (d213).
  defp list_item("leaf_anywhere", "plant_part", trait_values, legacy),
    do: trait_value("leaf", "plant_part", trait_values, legacy)

  defp list_item(token, trait, trait_values, legacy),
    do: trait_value(token, trait, trait_values, legacy)

  # A token's Trait value: a value of the vocabulary, or an old row ID
  # translated through the legacy file; anything else is nil.
  defp trait_value(token, trait, trait_values, legacy) do
    value =
      case Integer.parse(token) do
        {old_id, ""} -> get_in(legacy, [{trait, old_id}, :value])
        _ -> token
      end

    if value in Map.get(trait_values, trait, []), do: value
  end

  # Parse detachable param - converts V1 integer values to V2 strings for backwards compatibility
  defp parse_detachable(nil), do: nil
  defp parse_detachable(""), do: nil
  defp parse_detachable("0"), do: "unknown"
  defp parse_detachable("1"), do: "integral"
  defp parse_detachable("2"), do: "detachable"
  defp parse_detachable("3"), do: "both"
  # V2 string values pass through
  defp parse_detachable(val) when val in ["unknown", "integral", "detachable", "both"], do: val
  defp parse_detachable(_), do: nil

  # The Inducer family: a name, or an old taxonomy ID through the legacy crosswalk.
  defp parse_family(raw) do
    case blank_to_nil(raw) do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {old_id, ""} -> family_ref(Taxa.get_by_legacy_id(:taxonomy, old_id))
          _ -> family_by_name(value)
        end
    end
  end

  defp family_by_name(name) do
    case Enum.reject(Taxa.get_by_name(name, :family), &(&1.kingdom == "Plantae")) do
      [taxon] -> family_ref(taxon)
      _ -> nil
    end
  end

  defp family_ref(nil), do: nil
  defp family_ref(taxon), do: %{id: taxon.id, name: Taxa.accepted_name(taxon)}

  # Apply filters from URL and load host/genus if specified
  defp apply_url_filters(socket, filters, params) do
    selected_host = load_host_from_params(params)
    selected_genus = load_genus_from_params(params)
    selected_place = load_place_from_params(filters)
    families = load_families_for_selection(selected_host, selected_genus)

    # Normalize place filter to code (V1 URLs used names like "Quebec")
    filters = normalize_place_filter(filters, selected_place)

    socket
    |> assign(filters: filters)
    |> assign(selected_host: selected_host)
    |> assign(selected_genus: selected_genus)
    |> assign(selected_place: selected_place)
    |> assign(families: families)
    |> maybe_load_results()
  end

  defp load_place_from_params(%{place: nil}), do: nil

  defp load_place_from_params(%{place: place_value}) do
    # Try as code first, then as name (V1 compatibility)
    case Places.get_place_by_code(place_value) do
      nil -> Places.get_place_by_name(place_value)
      place -> place
    end
  end

  defp normalize_place_filter(filters, nil), do: %{filters | place: nil}
  defp normalize_place_filter(filters, place), do: %{filters | place: place.code}

  defp load_host_from_params(params) do
    case decode_url_param(params[@url_params.host]) do
      nil -> nil
      "" -> nil
      name -> find_plant(name)
    end
  end

  defp load_genus_from_params(params) do
    case decode_url_param(params[@url_params.genus]) do
      nil -> nil
      "" -> nil
      name -> find_group(name, decode_url_param(params[@url_params.genus_type]))
    end
  end

  defp decode_url_param(nil), do: nil
  defp decode_url_param(value), do: URI.decode(value)

  # A plant (Plantae at species rank or below) by accepted name or synonym.
  defp find_plant(name) do
    name
    |> plant_taxa(kingdom: "Plantae")
    |> Enum.filter(&(&1.rank in Rank.species_and_below()))
    |> pick_taxon()
    |> host_ref()
  end

  # A plant genus, subgenus or section by name, trying `type`'s rank first.
  defp find_group(name, type) do
    preferred = Enum.filter(@group_ranks, &(to_string(&1) == type))

    (preferred ++ (@group_ranks -- preferred))
    |> Enum.find_value(&pick_taxon(plant_taxa(name, rank: &1, kingdom: "Plantae")))
    |> group_ref()
  end

  defp plant_taxa(name, opts) do
    case Taxa.resolve_name(name, opts) do
      {:ok, taxon} -> [taxon]
      {:ambiguous, taxa} -> taxa
      :none -> []
    end
  end

  # One taxon, or the one matched by its accepted name among several.
  defp pick_taxon([taxon]), do: taxon

  defp pick_taxon(taxa) do
    case Enum.filter(taxa, &(&1.matched_name.status == :accepted)) do
      [taxon] -> taxon
      _ -> nil
    end
  end

  # A plant taxon by ID, as the host picker shows it, or nil.
  defp get_plant(id) do
    case Taxa.get_taxon(id) do
      %{kingdom: "Plantae", rank: rank} = taxon ->
        if rank in Rank.species_and_below(), do: host_ref(taxon)

      _ ->
        nil
    end
  end

  # A plant genus, subgenus or section by ID, as the genus picker shows it, or nil.
  defp get_group(id) do
    case Taxa.get_taxon(id) do
      %{kingdom: "Plantae", rank: rank} = taxon when rank in @group_ranks -> group_ref(taxon)
      _ -> nil
    end
  end

  defp host_ref(nil), do: nil

  defp host_ref(taxon),
    do: %{id: taxon.id, name: Taxa.accepted_name(taxon), datacomplete: taxon.datacomplete}

  defp group_ref(nil), do: nil

  defp group_ref(taxon) do
    description =
      case Map.get(Taxa.common_names([taxon.id]), taxon.id, []) do
        [] -> nil
        names -> Enum.join(names, ", ")
      end

    %{id: taxon.id, name: Taxa.accepted_name(taxon), rank: taxon.rank, description: description}
  end

  # Load families relevant to the current host/genus selection
  defp load_families_for_selection(nil, nil), do: []
  # When both are selected, the host's families (the genus's are among them)
  defp load_families_for_selection(%{id: id}, _genus), do: Catalog.gall_families_for_hosts([id])
  defp load_families_for_selection(nil, %{id: id}), do: Catalog.gall_families_for_hosts([id])

  defp default_filters do
    %{
      plant_parts: [],
      plant_part_logic: :or,
      color: nil,
      shape: nil,
      textures: [],
      texture_logic: :or,
      alignment: nil,
      detachable: nil,
      place: nil,
      family: nil,
      form: nil,
      walls: nil,
      cells: nil,
      season: nil,
      undescribed: false
    }
  end

  # Event handlers

  @impl true
  def handle_event("search_host", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Taxa.search_plants(query, 50)
      else
        []
      end

    {:noreply,
     assign(socket,
       host_query: query,
       host_results: results,
       # Clear genus when typing in host (mutually exclusive)
       selected_genus: nil,
       genus_query: "",
       genus_results: []
     )}
  end

  @impl true
  def handle_event("select_host", %{"id" => id_str}, socket) do
    host = get_plant(String.to_integer(id_str))

    socket =
      socket
      |> assign(
        selected_host: host,
        host_query: "",
        host_results: [],
        # Clear genus when selecting host (mutually exclusive)
        selected_genus: nil,
        genus_query: "",
        genus_results: []
      )
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_host", _params, socket) do
    socket =
      socket
      |> assign(selected_host: nil)
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_genus", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        # Only show plant genera/sections for host plant filter
        Taxa.search_genera_and_sections(query, 10, kingdom: "Plantae")
      else
        []
      end

    {:noreply,
     assign(socket,
       genus_query: query,
       genus_results: results,
       # Clear host when typing in genus (mutually exclusive)
       selected_host: nil,
       host_query: "",
       host_results: []
     )}
  end

  @impl true
  def handle_event("select_genus", %{"id" => id_str}, socket) do
    genus = get_group(String.to_integer(id_str))

    socket =
      socket
      |> assign(
        selected_genus: genus,
        genus_query: "",
        genus_results: [],
        # Clear host when selecting genus (mutually exclusive)
        selected_host: nil,
        host_query: "",
        host_results: []
      )
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_genus", _params, socket) do
    socket =
      socket
      |> assign(selected_genus: nil)
      |> push_filter_patch()

    {:noreply, socket}
  end

  # Plant part multi-select handlers
  @impl true
  def handle_event("plant_part_search", %{"value" => query}, socket) do
    {:noreply, assign(socket, plant_part_query: query)}
  end

  @impl true
  def handle_event("plant_part_focus", _params, socket) do
    {:noreply, assign(socket, plant_part_focused: true)}
  end

  @impl true
  def handle_event("plant_part_blur", _params, socket) do
    {:noreply, assign(socket, plant_part_focused: false)}
  end

  @impl true
  def handle_event("plant_part_select", %{"id" => id}, socket) do
    socket =
      socket
      |> select_option(:plant_parts, id, socket.assigns.plant_part_options)
      |> assign(plant_part_query: "")
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("plant_part_remove", %{"id" => id}, socket) do
    new_plant_parts = List.delete(socket.assigns.filters.plant_parts, id)

    socket =
      socket
      |> update_filter(:plant_parts, new_plant_parts)
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("plant_part_clear", _params, socket) do
    socket =
      socket
      |> update_filter(:plant_parts, [])
      |> assign(plant_part_query: "", plant_part_focused: false)
      |> push_filter_patch()

    {:noreply, socket}
  end

  # Texture multi-select handlers
  @impl true
  def handle_event("texture_search", %{"value" => query}, socket) do
    {:noreply, assign(socket, texture_query: query)}
  end

  @impl true
  def handle_event("texture_focus", _params, socket) do
    {:noreply, assign(socket, texture_focused: true)}
  end

  @impl true
  def handle_event("texture_blur", _params, socket) do
    {:noreply, assign(socket, texture_focused: false)}
  end

  @impl true
  def handle_event("texture_select", %{"id" => id}, socket) do
    socket =
      socket
      |> select_option(:textures, id, socket.assigns.texture_options)
      |> assign(texture_query: "")
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("texture_remove", %{"id" => id}, socket) do
    new_textures = List.delete(socket.assigns.filters.textures, id)

    socket =
      socket
      |> update_filter(:textures, new_textures)
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("texture_clear", _params, socket) do
    socket =
      socket
      |> update_filter(:textures, [])
      |> assign(texture_query: "", texture_focused: false)
      |> push_filter_patch()

    {:noreply, socket}
  end

  # Logic toggle handlers
  @impl true
  def handle_event("toggle_plant_part_logic", _params, socket) do
    new_logic = if socket.assigns.filters.plant_part_logic == :or, do: :and, else: :or

    socket =
      socket
      |> update_filter(:plant_part_logic, new_logic)
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_texture_logic", _params, socket) do
    new_logic = if socket.assigns.filters.texture_logic == :or, do: :and, else: :or

    socket =
      socket
      |> update_filter(:texture_logic, new_logic)
      |> push_filter_patch()

    {:noreply, socket}
  end

  @single_trait_filters Enum.map(@single_traits, fn {key, _} -> to_string(key) end)
  @valid_filter_keys ~w(detachable family undescribed) ++ @single_trait_filters

  @impl true
  def handle_event("change_filter", %{"filter" => filter, "value" => value}, socket)
      when filter in @valid_filter_keys do
    filter_key = String.to_existing_atom(filter)

    socket =
      socket
      |> update_filter(filter_key, filter_value(filter_key, value, socket.assigns))
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_place", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Places.search_places_grouped(query, 10, socket.assigns[:continent_code])
      else
        []
      end

    {:noreply, assign(socket, place_query: query, place_results: results)}
  end

  @impl true
  def handle_event("select_place", %{"id" => id_str}, socket) do
    place_id = String.to_integer(id_str)
    place = Places.get_place(place_id)

    socket =
      socket
      |> assign(selected_place: place, place_query: "", place_results: [])
      |> update_filter(:place, place && place.code)
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_place", _params, socket) do
    socket =
      socket
      |> assign(selected_place: nil, place_query: "", place_results: [])
      |> update_filter(:place, nil)
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_advanced", _params, socket) do
    {:noreply, assign(socket, show_advanced: !socket.assigns.show_advanced)}
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
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_all", _params, socket) do
    socket =
      socket
      |> assign(filters: default_filters())
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_by_name", %{"value" => value}, socket) do
    filtered = Catalog.filter_identified(socket.assigns.results, value)
    {:noreply, assign(socket, name_filter: value, filtered_results: filtered)}
  end

  @impl true
  def handle_event("clear_name_filter", _params, socket) do
    {:noreply, assign(socket, name_filter: "", filtered_results: socket.assigns.results)}
  end

  # The value a "change_filter" event sets: a Trait value of the vocabulary,
  # one of the host's families, or a detachable value.
  defp filter_value(:undescribed, value, _assigns), do: value == "true"
  defp filter_value(:detachable, value, _assigns), do: parse_detachable(value)

  defp filter_value(:family, value, assigns) do
    Enum.find(assigns.families, &(to_string(&1.id) == value))
  end

  defp filter_value(key, value, assigns) do
    {_param, trait} = Keyword.fetch!(@single_traits, key)
    if value in Map.get(assigns.trait_values, trait, []), do: value
  end

  # Adds an option of a multi-select to its filter, if it is one of the options.
  defp select_option(socket, key, id, options) do
    selected = Map.fetch!(socket.assigns.filters, key)

    if id in selected or not Enum.any?(options, &(&1.id == id)) do
      socket
    else
      update_filter(socket, key, [id | selected])
    end
  end

  defp update_filter(socket, key, value) do
    filters = Map.put(socket.assigns.filters, key, value)
    assign(socket, filters: filters)
  end

  # Build URL parameters and push patch to update URL
  defp push_filter_patch(socket) do
    params = build_url_params(socket)
    push_patch(socket, to: ~p"/id?#{params}")
  end

  defp build_url_params(socket) do
    filters = socket.assigns.filters

    params =
      %{}
      |> maybe_add_param(@url_params.host, socket.assigns.selected_host, & &1.name)
      |> maybe_add_param(@url_params.genus, socket.assigns.selected_genus, & &1.name)
      |> maybe_add_param(
        @url_params.genus_type,
        socket.assigns.selected_genus,
        &to_string(&1.rank)
      )
      |> maybe_add_logic_param(@url_params.location_logic, filters.plant_part_logic)
      |> maybe_add_logic_param(@url_params.texture_logic, filters.texture_logic)
      |> maybe_add_param(@url_params.detachable, filters.detachable)
      |> maybe_add_param(@url_params.place, filters.place)
      |> maybe_add_param(@url_params.family, filters.family, & &1.name)

    params =
      Enum.reduce(@single_traits, params, fn {key, {param, _trait}}, acc ->
        maybe_add_param(acc, param, Map.fetch!(filters, key))
      end)

    params =
      Enum.reduce(@multi_traits, params, fn {key, {param, _trait}}, acc ->
        maybe_add_list_param(acc, param, Map.fetch!(filters, key))
      end)

    if filters.undescribed,
      do: Map.put(params, @url_params.undescribed, "1"),
      else: params
  end

  defp maybe_add_param(params, key, value, fun \\ & &1)
  defp maybe_add_param(params, _key, nil, _fun), do: params
  defp maybe_add_param(params, key, value, fun), do: Map.put(params, key, fun.(value))

  # Only add logic param if it's :and (since :or is default)
  defp maybe_add_logic_param(params, _key, :or), do: params
  defp maybe_add_logic_param(params, key, :and), do: Map.put(params, key, "and")

  defp maybe_add_list_param(params, _key, []), do: params

  defp maybe_add_list_param(params, key, values) do
    Map.put(params, key, Enum.join(values, ","))
  end

  # Load results if host or genus is selected
  defp maybe_load_results(socket) do
    if socket.assigns.selected_host || socket.assigns.selected_genus do
      load_results(socket)
    else
      assign(socket, results: [], filtered_results: [], summaries: %{}, name_filter: "")
    end
  end

  defp load_results(socket) do
    filters = identify_filters(socket)
    results = Catalog.identify(filters)

    # Summaries for galls without images
    summaries =
      for gall <- results, is_nil(gall.image_url), into: %{} do
        {gall.id, Summary.generate(Summary.from_traits(gall.traits), mode: :medium)}
      end

    # When results are empty and a place/region filter is active, check if
    # galls exist without the geographic filter so we can hint to the user.
    unscoped_count =
      if results == [] && filters.place_codes != nil do
        Catalog.count_identified(%{filters | place_codes: nil})
      else
        0
      end

    name_filter = socket.assigns.name_filter
    filtered_results = Catalog.filter_identified(results, name_filter)

    socket =
      assign(socket,
        results: results,
        filtered_results: filtered_results,
        summaries: summaries,
        name_filter: name_filter,
        unscoped_count: unscoped_count
      )

    # The Host's (or genus's) count before any filter: from these results
    # when no filter is set, otherwise counted with the filters reset, so a
    # page opened with filters, or a new Host under filters, reports it truly.
    total_count =
      if socket.assigns.filters == default_filters(),
        do: length(results),
        else:
          socket
          |> assign(filters: default_filters())
          |> identify_filters()
          |> Catalog.count_identified()

    assign(socket, total_count: total_count)
  end

  # The page's selections as `Gallformers.Catalog.identify/1` filters.
  defp identify_filters(socket) do
    filters = socket.assigns.filters

    # Use explicit place if selected, otherwise fall back to continent scope
    place_codes =
      cond do
        filters.place -> [filters.place]
        socket.assigns[:continent_code] -> [socket.assigns[:continent_code]]
        true -> nil
      end

    single =
      for {key, {_param, trait}} <- @single_traits,
          value = Map.fetch!(filters, key),
          into: %{},
          do: {trait, [value]}

    traits =
      Map.merge(single, %{
        "plant_part" => filters.plant_parts,
        "texture" => filters.textures
      })

    %{
      host_id: socket.assigns.selected_host && socket.assigns.selected_host.id,
      host_group_id: socket.assigns.selected_genus && socket.assigns.selected_genus.id,
      inducer_family_id: filters.family && filters.family.id,
      traits: traits,
      trait_logic: %{"plant_part" => filters.plant_part_logic, "texture" => filters.texture_logic},
      detachable: filters.detachable,
      undescribed: filters.undescribed,
      place_codes: place_codes
    }
  end

  defp value_options(values), do: Enum.map(values, &%{id: &1, label: &1})

  # Helper for formatting host display with aliases
  defp format_host_display(%{name: name, aliases: aliases}) when is_list(aliases) do
    case aliases do
      [] -> name
      alias_list -> "#{name} (#{Enum.join(alias_list, ", ")})"
    end
  end

  defp format_host_display(%{name: name}), do: name

  # Helper for formatting genus display
  defp format_genus_display(%{name: name, rank: rank, description: desc}) do
    desc_text = if desc in [nil, ""], do: "", else: " - #{desc}"
    "#{name}#{rank_label(rank)}#{desc_text}"
  end

  defp format_genus_display(%{name: name}), do: name

  defp rank_label(:section), do: " [Section]"
  defp rank_label(:subgenus), do: " [Subgenus]"
  defp rank_label(_rank), do: ""

  defp trait_options(trait_values, trait),
    do: Enum.map(Map.get(trait_values, trait, []), &{&1, &1})

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <:subheader>
        <.region_scope
          continent_code={@continent_code}
          continent_name={@continent_name}
          default_continent_code={@default_continent_code}
        />
      </:subheader>
      <div class="flex flex-col gap-block">
        <.page_header>
          <:title>Identify a gall</:title>
        </.page_header>

        <%!-- Host / genus pickers: always visible --%>
        <div class="grid grid-cols-1 items-end gap-3 rounded-panel border border-line bg-surface p-panel md:grid-cols-12">
          <div class="md:col-span-6">
            <.typeahead
              id="host-picker"
              label="Host plant"
              placeholder="Species or common name: Quercus rubra, red oak…"
              query={@host_query}
              results={@host_results}
              selected={@selected_host}
              search_event="search_host"
              select_event="select_host"
              clear_event="clear_host"
              display_fn={&format_host_display/1}
            >
              <:result :let={host}>
                <.taxon_name name={format_host_display(host)} />
                <.chip :if={!host.datacomplete} variant={:warn} size="sm" class="ml-2">
                  incomplete
                </.chip>
              </:result>
            </.typeahead>
          </div>
          <div class="text-center text-meta text-muted md:col-span-1 md:pb-2">or</div>
          <div class="md:col-span-5">
            <.typeahead
              id="genus-picker"
              label="Host genus or section"
              placeholder="Quercus, sect. Lobatae…"
              query={@genus_query}
              results={@genus_results}
              selected={@selected_genus}
              search_event="search_genus"
              select_event="select_genus"
              clear_event="clear_genus"
              display_fn={&format_genus_display/1}
            >
              <:result :let={genus}>
                <.taxon_name name={genus.name} rank={to_string(genus.rank)} />
                <span :if={rank_label(genus.rank) != ""} class="ml-1 text-caption text-muted">
                  {String.trim(rank_label(genus.rank))}
                </span>
                <span :if={genus.description} class="block truncate text-caption text-muted">
                  {genus.description}
                </span>
              </:result>
            </.typeahead>
          </div>
        </div>

        <%!-- Filters: once a host or genus is chosen; they apply to the traits only --%>
        <div :if={@selected_host != nil or @selected_genus != nil} class="flex flex-col gap-3">
          <div class="flex flex-wrap items-center gap-2">
            <h2 class="text-subsection">Narrow it down</h2>
            <%!-- Phones: the filters fold behind one button (markup only) --%>
            <button
              type="button"
              class="gf-btn gf-btn-secondary md:hidden"
              phx-click={JS.toggle_class("hidden", to: "#id-filter-panel")}
            >
              <.icon name="ph-funnel" /> Filters
              <span :if={active_filters(@filters) > 0} class="text-autumn-ink tabular-nums">
                {active_filters(@filters)}
              </span>
            </button>
            <div class="ml-auto flex items-center gap-2">
              <.button variant="ghost" phx-click="toggle_advanced">
                {if @show_advanced, do: "Fewer filters", else: "More filters"}
              </.button>
              <.button
                :if={active_filters(@filters) > 0}
                icon="ph-x"
                phx-click="clear_all"
                title="Clears the trait filters. The Host, your region and the name filter stay."
              >
                Clear {active_filters(@filters)} {if active_filters(@filters) == 1,
                  do: "filter",
                  else: "filters"}
              </.button>
            </div>
          </div>

          <div id="id-filter-panel" class="hidden flex-col gap-3 md:flex">
            <div class="grid grid-cols-1 items-start gap-3 sm:grid-cols-2 lg:grid-cols-6">
              <div class="sm:col-span-2">
                <.multi_select_typeahead
                  id="plant_parts"
                  name="plant_part"
                  label="Plant parts"
                  placeholder="Leaf, stem, bud…"
                  options={@plant_part_options}
                  selected={@filters.plant_parts}
                  option_label={:label}
                  query={@plant_part_query}
                  focused={@plant_part_focused}
                />
                <.logic_toggle
                  :if={length(@filters.plant_parts) > 1}
                  logic={@filters.plant_part_logic}
                  toggle_event="toggle_plant_part_logic"
                />
              </div>
              <.detachable_filter value={@filters.detachable} counts={counts(@results, "detachable")} />
              <div>
                <.typeahead
                  id="place-filter"
                  label="Region"
                  placeholder="Country, state…"
                  search_event="search_place"
                  select_event="select_place"
                  clear_event="clear_place"
                  query={@place_query}
                  results={@place_results}
                  selected={@selected_place}
                  display_fn={
                    fn place ->
                      type = Map.get(place, :type)
                      parent = Map.get(place, :parent_name)

                      if type in ["state", "province"] and parent not in [nil, ""] do
                        "#{place.name} — #{parent}"
                      else
                        place.name
                      end
                    end
                  }
                  group_key={:group}
                />
              </div>
              <.family_filter families={@families} value={@filters.family && @filters.family.id} />
              <.trait_filter
                filter="season"
                label="Season (forms and grows)"
                prompt="Any"
                options={trait_options(@trait_values, "season")}
                value={@filters.season}
                counts={counts(@results, "season")}
              />
            </div>

            <div :if={@show_advanced} class="flex flex-col gap-3 rounded-panel bg-surface-2 p-panel">
              <p class="text-meta text-muted">
                Many galls have no recorded value for these, so filtering on them can hide a match.
              </p>
              <div class="grid grid-cols-1 items-start gap-3 sm:grid-cols-2 lg:grid-cols-6">
                <div class="sm:col-span-2">
                  <.multi_select_typeahead
                    id="textures"
                    name="texture"
                    label="Textures"
                    placeholder="Hairy, smooth…"
                    options={@texture_options}
                    selected={@filters.textures}
                    option_label={:label}
                    query={@texture_query}
                    focused={@texture_focused}
                  />
                  <.logic_toggle
                    :if={length(@filters.textures) > 1}
                    logic={@filters.texture_logic}
                    toggle_event="toggle_texture_logic"
                  />
                </div>
                <.trait_filter
                  :for={
                    {trait, label} <- [
                      {"form", "Form"},
                      {"shape", "Shape"},
                      {"color", "Color"},
                      {"alignment", "Alignment"},
                      {"walls", "Walls"},
                      {"cells", "Cells"}
                    ]
                  }
                  filter={trait}
                  label={label}
                  prompt="Any"
                  options={trait_options(@trait_values, trait)}
                  value={Map.get(@filters, String.to_existing_atom(trait))}
                  counts={counts(@results, trait)}
                />
              </div>
              <.undescribed_filter value={@filters.undescribed} />
            </div>
          </div>
        </div>

        <.results_grid
          results={@filtered_results}
          summaries={@summaries}
          total_count={@total_count}
          filter_count={length(@results)}
          name_filter={@name_filter}
          has_selection={@selected_host != nil or @selected_genus != nil}
          selected_host={@selected_host}
          unscoped_count={@unscoped_count}
          continent_name={@continent_name}
        />
      </div>
    </Layouts.app>
    """
  end

  # How many filters are set (the count on Clear filters).
  defp active_filters(filters) do
    length(filters.plant_parts) + length(filters.textures) +
      Enum.count(
        [
          :detachable,
          :place,
          :family,
          :season,
          :alignment,
          :form,
          :walls,
          :cells,
          :shape,
          :color
        ],
        &(Map.get(filters, &1) not in [nil, ""])
      ) + if(filters.undescribed, do: 1, else: 0)
  end

  # How many of the loaded results have each value of `trait`: the galls a
  # single-value filter would leave. (Shown only while that filter is unset.)
  defp counts(results, "detachable"),
    do: results |> Enum.map(& &1.detachable) |> Enum.reject(&is_nil/1) |> Enum.frequencies()

  defp counts(results, trait),
    do: results |> Enum.flat_map(&Map.get(&1.traits, trait, [])) |> Enum.frequencies()

  # Component: Logic Toggle (AND/OR) — same event and title, restyled
  attr :logic, :atom, required: true
  attr :toggle_event, :string, required: true

  defp logic_toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@toggle_event}
      class="mt-1 inline-flex items-center gap-1 rounded-ctl text-caption font-semibold text-muted hover:text-ink"
      title={
        if @logic == :or,
          do: "Match ANY selected (click to require ALL)",
          else: "Match ALL selected (click to require ANY)"
      }
    >
      Match
      <span class={["rounded-ctl px-1.5 py-0.5", @logic == :or && "bg-sky-soft text-ink"]}>ANY</span>
      <span class={["rounded-ctl px-1.5 py-0.5", @logic == :and && "bg-sky-soft text-ink"]}>ALL</span>
    </button>
    """
  end

  # The single-value filters: each its own form sending `change_filter` with
  # the filter's name, as before (docs/design-system/inventory/typeahead-and-id.md).
  attr :value, :string, required: true
  attr :counts, :map, default: %{}

  defp detachable_filter(assigns) do
    ~H"""
    <.filter_select
      id="filter-detachable"
      name="value"
      label="Detachable"
      prompt="Any"
      options={[{"Integral", "integral"}, {"Detachable", "detachable"}, {"Both", "both"}]}
      value={@value}
      counts={@counts}
      phx-change="change_filter"
      phx-value-filter="detachable"
    />
    """
  end

  attr :families, :list, required: true
  attr :value, :integer, required: true

  defp family_filter(assigns) do
    ~H"""
    <.filter_select
      id="filter-family"
      name="value"
      label="Family"
      prompt="Any Family"
      options={Enum.map(@families, &{&1.name, &1.id})}
      value={@value}
      phx-change="change_filter"
      phx-value-filter="family"
    />
    """
  end

  attr :filter, :string, required: true
  attr :label, :string, required: true
  attr :prompt, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, required: true
  attr :counts, :map, default: %{}

  defp trait_filter(assigns) do
    ~H"""
    <.filter_select
      id={"filter-#{@filter}"}
      name="value"
      label={@label}
      prompt={@prompt}
      options={@options}
      value={@value}
      counts={@counts}
      phx-change="change_filter"
      phx-value-filter={@filter}
    />
    """
  end

  attr :value, :boolean, required: true

  defp undescribed_filter(assigns) do
    ~H"""
    <form phx-change="change_filter" phx-value-filter="undescribed">
      <input type="hidden" name="value" value="false" />
      <label class="inline-flex items-center gap-2 text-ui text-ink">
        <input type="checkbox" name="value" value="true" checked={@value} class="accent-brand-fill" />
        Show only undescribed galls
      </label>
    </form>
    """
  end

  attr :results, :list, required: true
  attr :summaries, :map, required: true
  attr :has_selection, :boolean, required: true
  attr :selected_host, :any, required: true
  attr :total_count, :integer, required: true
  attr :filter_count, :integer, required: true
  attr :name_filter, :string, required: true
  attr :unscoped_count, :integer, required: true
  attr :continent_name, :string, default: nil

  defp results_grid(assigns) do
    ~H"""
    <div class="flex flex-col gap-3 border-t border-line pt-3">
      <%= if !@has_selection do %>
        <.notice>
          Select a Host Plant or Plant Genus/Section to see matching galls. Then you can use the filters to narrow down the list.
        </.notice>
      <% else %>
        <.notice :if={@selected_host && !@selected_host.datacomplete} kind={:warn}>
          This host does not yet have all known galls added to the database.
        </.notice>

        <div class="flex flex-wrap items-center justify-between gap-3">
          <p class="text-ui text-ink-2">
            Showing <span class="font-semibold text-ink tabular-nums">{length(@results)}</span>
            <span :if={length(@results) != @filter_count}>of {@filter_count}</span>
            <span :if={@filter_count != @total_count}>
              (<span class="font-semibold tabular-nums">{@total_count}</span> unfiltered)
            </span>
            galls
          </p>
          <div :if={@filter_count > 0} class="relative w-full sm:w-72">
            <.icon
              name="ph-magnifying-glass"
              class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted"
            />
            <input
              type="text"
              value={@name_filter}
              placeholder="Filter by name or trait..."
              aria-label="Filter by name or trait"
              phx-keyup="filter_by_name"
              phx-debounce="200"
              class="h-ctl w-full rounded-ctl border border-line-strong bg-surface pl-8 pr-8 text-ui text-ink"
            />
            <button
              :if={@name_filter != ""}
              type="button"
              phx-click="clear_name_filter"
              aria-label="Clear the name filter"
              class="absolute right-2 top-1/2 -translate-y-1/2 text-muted hover:text-ink"
            >
              <.icon name="ph-x" class="size-4" />
            </button>
          </div>
        </div>

        <%= if length(@results) == 0 do %>
          <.notice :if={@unscoped_count > 0}>
            No galls found in <strong>{@continent_name || "your selected region"}</strong>, but
            there {if @unscoped_count == 1, do: "is", else: "are"}
            <strong>{@unscoped_count}</strong>
            {if @unscoped_count == 1, do: "gall", else: "galls"} matching your filters in other regions.
            Try changing your region or selecting "All Regions" to see them.
          </.notice>
          <.notice :if={@unscoped_count == 0}>
            There are no galls that match your filter. It's possible there are no described species that fit this set of traits and your gall is undescribed.
            However, before giving up, try <.link href="/articles/IDGuide#troubleshooting">altering your filter choices</.link>.
          </.notice>
        <% else %>
          <div class="gf-photo-grid">
            <.gall_card
              :for={gall <- @results}
              navigate={"/gall/#{gall.id}"}
              name={gall.name}
              image_url={gall.image_url}
              image_alt=""
              subtitle={@summaries[gall.id]}
            >
              <:chip :if={gall.undescribed} variant={:info}>Undescribed</:chip>
            </.gall_card>
          </div>
          <.notice>
            If none of these results match your gall, you may have found an undescribed species. However, before concluding that your gall is not in the database, try <.link href="/articles/IDGuide#troubleshooting">altering your filter choices</.link>.
          </.notice>
        <% end %>
      <% end %>
    </div>
    """
  end
end
