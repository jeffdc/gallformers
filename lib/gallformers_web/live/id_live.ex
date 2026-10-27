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

  # Special marker for "leaf (anywhere)" virtual location option
  @leaf_anywhere_id "leaf_anywhere"

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
       plant_part_options: plant_part_options(trait_values),
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

  defp list_item(@leaf_anywhere_id, "plant_part", _trait_values, _legacy), do: @leaf_anywhere_id

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
    filtered =
      if value == "" do
        socket.assigns.results
      else
        term = String.downcase(value)
        Enum.filter(socket.assigns.results, &String.contains?(String.downcase(&1.name), term))
      end

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
    filtered_results = apply_name_filter(results, name_filter)

    socket =
      assign(socket,
        results: results,
        filtered_results: filtered_results,
        summaries: summaries,
        name_filter: name_filter,
        unscoped_count: unscoped_count
      )

    if socket.assigns.filters == default_filters(),
      do: assign(socket, total_count: length(results)),
      else: socket
  end

  defp apply_name_filter(results, ""), do: results

  defp apply_name_filter(results, filter) do
    term = String.downcase(filter)
    Enum.filter(results, &String.contains?(String.downcase(&1.name), term))
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
        "plant_part" => expand_plant_parts(filters.plant_parts, socket.assigns.trait_values),
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

  # The plant part options: each value, and "leaf (anywhere)", by label.
  defp plant_part_options(trait_values) do
    virtual_option = %{id: @leaf_anywhere_id, label: "leaf (anywhere)"}

    [virtual_option | value_options(Map.get(trait_values, "plant_part", []))]
    |> Enum.sort_by(& &1.label)
  end

  defp value_options(values), do: Enum.map(values, &%{id: &1, label: &1})

  # Expand "leaf (anywhere)" to every plant part value naming a leaf
  defp expand_plant_parts(plant_parts, trait_values) do
    if @leaf_anywhere_id in plant_parts do
      leaf_values =
        trait_values |> Map.get("plant_part", []) |> Enum.filter(&String.contains?(&1, "leaf"))

      Enum.uniq(leaf_values ++ List.delete(plant_parts, @leaf_anywhere_id))
    else
      plant_parts
    end
  end

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
      <div class="py-4">
        <%!-- Host/Genus Pickers --%>
        <div class="mb-2">
          <div class="grid grid-cols-1 md:grid-cols-11 gap-2 items-end">
            <div class="md:col-span-5">
              <.typeahead
                id="host-picker"
                label="Host Plant Species:"
                placeholder="Search species..."
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
                  <span :if={!host.datacomplete} class="ml-2 text-xs text-yellow-600">
                    (incomplete)
                  </span>
                </:result>
              </.typeahead>
            </div>
            <div class="md:col-span-1 text-center text-sm text-gray-500 pb-2">
              OR
            </div>
            <div class="md:col-span-5">
              <.typeahead
                id="genus-picker"
                label="Host Plant Genus / Section:"
                placeholder="Search genera..."
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
                  <span :if={rank_label(genus.rank) != ""} class="ml-1 text-xs text-gray-500">
                    {String.trim(rank_label(genus.rank))}
                  </span>
                  <span :if={genus.description} class="block text-xs text-gray-500 truncate">
                    {genus.description}
                  </span>
                </:result>
              </.typeahead>
            </div>
          </div>
        </div>

        <hr class="border-gray-200 mb-4" />

        <%!-- Filter Panel (only shown when host/genus selected) --%>
        <div :if={@selected_host != nil or @selected_genus != nil} class="mb-2">
          <%!-- Primary Filters (4-column grid) --%>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
            <div>
              <.multi_select_typeahead
                id="plant_parts"
                name="plant_part"
                label="Plant Part(s):"
                placeholder="Plant Parts"
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
            <.detachable_filter value={@filters.detachable} />
            <div>
              <.typeahead
                id="place-filter"
                label="Region"
                placeholder="Search regions..."
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
          </div>

          <%!-- Advanced Filters Toggle and Clear --%>
          <div class="flex justify-between items-center pt-2">
            <button
              type="button"
              phx-click="toggle_advanced"
              class="text-sm hover:underline"
            >
              {if @show_advanced, do: "Hide Advanced Filters", else: "Show Advanced Filters"}
            </button>
            <.button type="button" phx-click="clear_all" variant="danger" size="sm">
              Clear Filters
            </.button>
          </div>

          <%!-- Advanced Filters (Collapsible) --%>
          <div :if={@show_advanced} class="border-t border-gray-200 pt-3 mt-3">
            <p class="text-sm text-gray-500 italic mb-3">
              Be aware that many galls do not have associated information for all of the below properties.
            </p>

            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
              <.trait_filter
                filter="season"
                label="Season (forms and grows)"
                prompt="Any Season"
                options={trait_options(@trait_values, "season")}
                value={@filters.season}
              />
              <div>
                <.multi_select_typeahead
                  id="textures"
                  name="texture"
                  label="Texture(s):"
                  placeholder="Textures"
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
                filter="alignment"
                label="Alignment"
                prompt="Any Alignment"
                options={trait_options(@trait_values, "alignment")}
                value={@filters.alignment}
              />
              <.trait_filter
                filter="form"
                label="Form"
                prompt="Any Form"
                options={trait_options(@trait_values, "form")}
                value={@filters.form}
              />
              <.trait_filter
                filter="walls"
                label="Walls"
                prompt="Any Walls"
                options={trait_options(@trait_values, "walls")}
                value={@filters.walls}
              />
              <.trait_filter
                filter="cells"
                label="Cells"
                prompt="Any Cells"
                options={trait_options(@trait_values, "cells")}
                value={@filters.cells}
              />
              <.trait_filter
                filter="shape"
                label="Shape"
                prompt="Any Shape"
                options={trait_options(@trait_values, "shape")}
                value={@filters.shape}
              />
              <.trait_filter
                filter="color"
                label="Color"
                prompt="Any Color"
                options={trait_options(@trait_values, "color")}
                value={@filters.color}
              />
            </div>

            <div class="mt-3 flex flex-wrap gap-6">
              <.undescribed_filter value={@filters.undescribed} />
            </div>
          </div>
        </div>

        <hr class="border-gray-200 my-3" />

        <%!-- Results Grid --%>
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

  # Component: Logic Toggle (AND/OR)
  attr :logic, :atom, required: true
  attr :toggle_event, :string, required: true

  defp logic_toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@toggle_event}
      class="mt-1 text-xs text-gray-600 hover:text-gf-maroon flex items-center gap-1"
      title={
        if @logic == :or,
          do: "Match ANY selected (click to require ALL)",
          else: "Match ALL selected (click to require ANY)"
      }
    >
      <span class={["px-1.5 py-0.5 rounded", @logic == :or && "bg-blue-100 text-blue-700"]}>
        ANY
      </span>
      <span class="text-gray-400">/</span>
      <span class={["px-1.5 py-0.5 rounded", @logic == :and && "bg-green-100 text-green-700"]}>
        ALL
      </span>
    </button>
    """
  end

  # Component: Detachable Filter
  attr :value, :string, required: true

  defp detachable_filter(assigns) do
    ~H"""
    <form phx-change="change_filter" phx-value-filter="detachable">
      <.input
        type="select"
        name="value"
        label="Detachable"
        prompt="Any"
        options={[{"Integral", "integral"}, {"Detachable", "detachable"}, {"Both", "both"}]}
        value={@value}
      />
    </form>
    """
  end

  # Component: Family Filter
  attr :families, :list, required: true
  attr :value, :integer, required: true

  defp family_filter(assigns) do
    ~H"""
    <form phx-change="change_filter" phx-value-filter="family">
      <.input
        type="select"
        name="value"
        label="Family"
        prompt="Any Family"
        options={Enum.map(@families, &{&1.name, &1.id})}
        value={@value}
      />
    </form>
    """
  end

  # Component: a single-value Trait filter (a select of the Trait's values)
  attr :filter, :string, required: true
  attr :label, :string, required: true
  attr :prompt, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, required: true

  defp trait_filter(assigns) do
    ~H"""
    <form phx-change="change_filter" phx-value-filter={@filter}>
      <.input
        type="select"
        name="value"
        label={@label}
        prompt={@prompt}
        options={@options}
        value={@value}
      />
    </form>
    """
  end

  # Component: Undescribed Filter
  attr :value, :boolean, required: true

  defp undescribed_filter(assigns) do
    ~H"""
    <div class="mb-2">
      <form phx-change="change_filter" phx-value-filter="undescribed">
        <.input
          type="checkbox"
          name="value"
          checked={@value}
          label="Show only undescribed galls"
        />
      </form>
    </div>
    """
  end

  # Component: Results Grid
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
    <div>
      <%= if !@has_selection do %>
        <div class="text-center py-8 text-gray-600 bg-blue-50 rounded border border-blue-200">
          <p class="text-base">
            Select a Host Plant or Plant Genus/Section to see matching galls. Then you can use the filters to narrow down the list.
          </p>
        </div>
      <% else %>
        <%= if @selected_host && !@selected_host.datacomplete do %>
          <div class="mb-3 p-2 bg-yellow-50 border border-yellow-200 rounded text-sm text-yellow-800">
            This host does not yet have all known galls added to the database.
          </div>
        <% end %>

        <div class="flex items-center justify-between gap-4 mb-3">
          <p class="text-sm text-gray-600">
            Showing <span class="font-semibold">{length(@results)}</span>
            <span :if={length(@results) != @filter_count}>of {@filter_count}</span>
            <span :if={@filter_count != @total_count}>
              (<span class="font-semibold">{@total_count}</span> unfiltered)
            </span>
            galls
          </p>
          <div :if={@filter_count > 0} class="relative">
            <input
              type="text"
              value={@name_filter}
              placeholder="Filter by name..."
              phx-keyup="filter_by_name"
              phx-debounce="200"
              class="text-sm border border-gray-300 rounded-md pl-7 pr-7 py-1 w-48 focus:ring-1 focus:ring-gf-maroon focus:border-gf-maroon"
            />
            <.icon
              name="ph-magnifying-glass"
              class="absolute left-2 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400"
            />
            <button
              :if={@name_filter != ""}
              type="button"
              phx-click="clear_name_filter"
              class="absolute right-2 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
            >
              <.icon name="ph-x" class="h-4 w-4" />
            </button>
          </div>
        </div>

        <%= if length(@results) == 0 do %>
          <div class="p-4 bg-blue-50 border border-blue-200 rounded text-sm">
            <%= if @unscoped_count > 0 do %>
              <p>
                No galls found in <strong>{@continent_name || "your selected region"}</strong>, but
                there {if @unscoped_count == 1, do: "is", else: "are"}
                <strong>{@unscoped_count}</strong>
                {if @unscoped_count == 1, do: "gall", else: "galls"} matching your filters in other regions.
                Try changing your region or selecting "All Regions" to see them.
              </p>
            <% else %>
              <p>
                There are no galls that match your filter. It's possible there are no described species that fit this set of traits and your gall is undescribed.
              </p>
              <p class="mt-2">
                However, before giving up, try <.link
                  href="/articles/IDGuide#troubleshooting"
                  class="underline"
                >altering your filter choices</.link>.
              </p>
            <% end %>
          </div>
        <% else %>
          <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
            <.gall_card :for={gall <- @results} gall={gall} summary={@summaries[gall.id]} />
          </div>
          <div class="mt-4 p-3 bg-blue-50 border border-blue-200 rounded text-sm">
            <p>
              If none of these results match your gall, you may have found an undescribed species. However, before concluding that your gall is not in the database, try <.link
                href="/articles/IDGuide#troubleshooting"
                class="underline"
              >altering your filter choices</.link>.
            </p>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Component: Individual Gall Card
  attr :gall, :map, required: true
  attr :summary, :string, default: nil

  defp gall_card(assigns) do
    ~H"""
    <div class="bg-white border border-gray-200 rounded-lg overflow-hidden hover:shadow-md transition-shadow">
      <.link href={"/gall/#{@gall.id}"} class="block group">
        <div class="aspect-square bg-gray-100">
          <img
            src={@gall.image_url || ~p"/images/noimage.jpg"}
            alt=""
            class={[
              "w-full h-full object-cover",
              !@gall.image_url && "opacity-60"
            ]}
            loading="lazy"
          />
        </div>
        <div class="p-2">
          <p class="text-sm font-medium text-gray-900 group-hover:text-gf-maroon truncate">
            <.taxon_name name={@gall.name} />
          </p>
          <p :if={!@gall.image_url && @summary} class="text-xs text-gray-600 mt-1" title={@summary}>
            {@summary}
          </p>
        </div>
      </.link>
      <div :if={@gall.undescribed} class="flex flex-wrap gap-1 px-2 pb-2">
        <span
          class="inline-flex items-center px-1.5 py-0.5 text-xs font-medium rounded bg-red-100 text-red-700 cursor-help"
          title="This species has not yet been formally described in scientific literature."
        >
          Undescribed
        </span>
      </div>
    </div>
    """
  end
end
