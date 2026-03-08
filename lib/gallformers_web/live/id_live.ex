defmodule GallformersWeb.IDLive do
  @moduledoc """
  LiveView for the gall identification tool.

  Allows users to filter galls by various characteristics (host, genus, plant part,
  color, shape, etc.) with URL-based state preservation for back/forward navigation.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Galls, Places, Taxonomy}
  alias Gallformers.Plants
  alias GallformersWeb.Live.ContinentScope

  # URL parameter keys (short codes for compact URLs)
  @url_params %{
    host: "h",
    genus: "g",
    genus_type: "gt",
    locations: "lo",
    location_logic: "lol",
    color: "co",
    shape: "sh",
    textures: "te",
    texture_logic: "tel",
    alignment: "al",
    detachable: "de",
    place: "pl",
    family: "fa",
    form: "fo",
    walls: "wa",
    cells: "ce",
    season: "se",
    undescribed: "un",
    show_non_galls: "ng"
  }

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
    filter_options = Galls.get_filter_options()

    # Add "leaf (anywhere)" virtual option to plant_parts, sorted alphabetically
    plant_parts_with_virtual = add_leaf_anywhere_option(filter_options.plant_parts)
    filter_options = Map.put(filter_options, :plant_parts, plant_parts_with_virtual)

    {:ok,
     assign(socket,
       page_title: "ID Tool",
       page_description:
         "Identify plant galls using our interactive tool - filter by host plant, genus, location, morphology, and other characteristics.",
       page_url: "/id",
       page_image: nil,
       page_json_ld: nil,
       page_noindex: true,
       filter_options: filter_options,
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
    filters = parse_url_params(params)
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
  defp parse_url_params(params) do
    %{
      plant_parts: parse_list(params[@url_params.locations]),
      plant_part_logic: parse_logic(params[@url_params.location_logic]),
      color: parse_int(params[@url_params.color]),
      shape: parse_int(params[@url_params.shape]),
      textures: parse_list(params[@url_params.textures]),
      texture_logic: parse_logic(params[@url_params.texture_logic]),
      alignment: parse_int(params[@url_params.alignment]),
      detachable: parse_detachable(params[@url_params.detachable]),
      place: params[@url_params.place],
      family: parse_int(params[@url_params.family]),
      form: parse_int(params[@url_params.form]),
      walls: parse_int(params[@url_params.walls]),
      cells: parse_int(params[@url_params.cells]),
      season: parse_int(params[@url_params.season]),
      undescribed: params[@url_params.undescribed] == "1",
      show_non_galls: params[@url_params.show_non_galls] != "0"
    }
  end

  defp parse_logic("and"), do: :and
  defp parse_logic(_), do: :or

  defp parse_list(nil), do: []

  defp parse_list(str) when is_binary(str) do
    str
    |> String.split(",")
    |> Enum.map(&parse_list_item/1)
    |> Enum.reject(&is_nil/1)
  end

  # Parse list item - handles integers and special string markers like "leaf_anywhere"
  defp parse_list_item(@leaf_anywhere_id), do: @leaf_anywhere_id

  defp parse_list_item(str) do
    parse_int(str)
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
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
      name -> Plants.get_host_by_name(name)
    end
  end

  defp load_genus_from_params(params) do
    case decode_url_param(params[@url_params.genus]) do
      nil -> nil
      "" -> nil
      name -> find_genus_by_name(name, params)
    end
  end

  defp find_genus_by_name(name, params) do
    genus_type = decode_url_param(params[@url_params.genus_type]) || "genus"

    case Taxonomy.get_taxonomy_by_name(name, genus_type) do
      nil -> Taxonomy.find_taxonomy_by_name(name)
      tax -> tax
    end
  end

  defp decode_url_param(nil), do: nil
  defp decode_url_param(value), do: URI.decode(value)

  # Load families relevant to the current host/genus selection
  defp load_families_for_selection(nil, nil), do: []

  defp load_families_for_selection(host, nil) do
    Taxonomy.list_gall_families_for_host(host.id)
  end

  defp load_families_for_selection(nil, genus) do
    Taxonomy.list_gall_families_for_host_genus(genus.id)
  end

  defp load_families_for_selection(host, _genus) do
    # When both are selected, get families for host (genus family should be in there)
    Taxonomy.list_gall_families_for_host(host.id)
  end

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
      undescribed: false,
      show_non_galls: true
    }
  end

  # Event handlers

  @impl true
  def handle_event("search_host", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Plants.search_hosts(query, 50)
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
    host_id = String.to_integer(id_str)
    host = Plants.get_host(host_id)

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
        Taxonomy.search_genera_and_sections(query, 10, taxoncode: "plant")
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
    genus_id = String.to_integer(id_str)
    genus = Taxonomy.get_taxonomy(genus_id)

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
    plant_part_id = parse_plant_part_id(id)
    plant_parts = socket.assigns.filters.plant_parts

    new_plant_parts =
      if plant_part_id in plant_parts do
        plant_parts
      else
        [plant_part_id | plant_parts]
      end

    socket =
      socket
      |> update_filter(:plant_parts, new_plant_parts)
      |> assign(plant_part_query: "")
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("plant_part_remove", %{"id" => id}, socket) do
    plant_part_id = parse_plant_part_id(id)
    new_plant_parts = List.delete(socket.assigns.filters.plant_parts, plant_part_id)

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
    texture_id = String.to_integer(id)
    textures = socket.assigns.filters.textures

    new_textures =
      if texture_id in textures do
        textures
      else
        [texture_id | textures]
      end

    socket =
      socket
      |> update_filter(:textures, new_textures)
      |> assign(texture_query: "")
      |> push_filter_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("texture_remove", %{"id" => id}, socket) do
    texture_id = String.to_integer(id)
    new_textures = List.delete(socket.assigns.filters.textures, texture_id)

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

  # Valid filter keys from @url_params
  @valid_filter_keys ~w(host genus genus_type locations color shape textures alignment detachable place family form walls cells season undescribed show_non_galls)

  @impl true
  def handle_event("change_filter", %{"filter" => filter, "value" => value}, socket)
      when filter in @valid_filter_keys do
    filter_key = String.to_atom(filter)

    parsed_value =
      case filter_key do
        :show_non_galls -> value == "true"
        :undescribed -> value == "true"
        :detachable -> if value == "", do: nil, else: value
        :place -> if value == "", do: nil, else: value
        _ -> if value == "", do: nil, else: String.to_integer(value)
      end

    socket =
      socket
      |> update_filter(filter_key, parsed_value)
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
    params = %{}
    filters = socket.assigns.filters

    params =
      if socket.assigns.selected_host do
        Map.put(params, @url_params.host, socket.assigns.selected_host.name)
      else
        params
      end

    params =
      if socket.assigns.selected_genus do
        params
        |> Map.put(@url_params.genus, socket.assigns.selected_genus.name)
        |> Map.put(@url_params.genus_type, socket.assigns.selected_genus.type)
      else
        params
      end

    params = maybe_add_list_param(params, @url_params.locations, filters.plant_parts)
    params = maybe_add_logic_param(params, @url_params.location_logic, filters.plant_part_logic)
    params = maybe_add_param(params, @url_params.color, filters.color)
    params = maybe_add_param(params, @url_params.shape, filters.shape)
    params = maybe_add_list_param(params, @url_params.textures, filters.textures)
    params = maybe_add_logic_param(params, @url_params.texture_logic, filters.texture_logic)
    params = maybe_add_param(params, @url_params.alignment, filters.alignment)
    params = maybe_add_param(params, @url_params.detachable, filters.detachable)
    params = maybe_add_param(params, @url_params.place, filters.place)
    params = maybe_add_param(params, @url_params.family, filters.family)
    params = maybe_add_param(params, @url_params.form, filters.form)
    params = maybe_add_param(params, @url_params.walls, filters.walls)
    params = maybe_add_param(params, @url_params.cells, filters.cells)
    params = maybe_add_param(params, @url_params.season, filters.season)

    params =
      if filters.undescribed,
        do: Map.put(params, @url_params.undescribed, "1"),
        else: params

    params =
      if filters.show_non_galls,
        do: params,
        else: Map.put(params, @url_params.show_non_galls, "0")

    params
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)

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
    filter_params = build_filter_params(socket)
    results = Galls.filter_galls(filter_params)

    # Generate summaries for galls without images
    summaries = generate_summaries_for_imageless(results)

    # When results are empty and a place/region filter is active, check if
    # galls exist without the geographic filter so we can hint to the user.
    unscoped_count =
      if results == [] && filter_params[:place_codes] != nil do
        Galls.count_filtered_galls(%{filter_params | place_codes: nil})
      else
        0
      end

    if socket.assigns.filters == default_filters() do
      assign(socket,
        results: results,
        filtered_results: results,
        summaries: summaries,
        total_count: length(results),
        name_filter: "",
        unscoped_count: unscoped_count
      )
    else
      assign(socket,
        results: results,
        filtered_results: results,
        summaries: summaries,
        name_filter: "",
        unscoped_count: unscoped_count
      )
    end
  end

  defp generate_summaries_for_imageless(results) do
    # Find galls without images
    gall_ids_without_images =
      results
      |> Enum.filter(&is_nil(&1.image_url))
      |> Enum.map(& &1.gall_id)

    if Enum.empty?(gall_ids_without_images) do
      %{}
    else
      # Fetch summary data and generate summaries
      summary_data = Galls.get_summary_data(gall_ids_without_images)

      summary_data
      |> Enum.map(fn {gall_id, filters} ->
        {gall_id, Galls.Summary.generate(filters, mode: :medium)}
      end)
      |> Enum.into(%{})
    end
  end

  defp build_filter_params(socket) do
    filters = socket.assigns.filters

    # Expand "leaf (anywhere)" to actual leaf plant part IDs
    expanded_plant_parts = expand_plant_part_ids(filters.plant_parts)

    # Use explicit place if selected, otherwise fall back to continent scope
    place_codes =
      cond do
        filters.place -> [filters.place]
        socket.assigns[:continent_code] -> [socket.assigns[:continent_code]]
        true -> nil
      end

    %{
      host_ids: wrap_in_list(socket.assigns.selected_host, & &1.id),
      genus_id: maybe_get(socket.assigns.selected_genus, :id),
      plant_part_ids: non_empty_list(expanded_plant_parts),
      plant_part_logic: filters.plant_part_logic,
      color_ids: wrap_value(filters.color),
      shape_ids: wrap_value(filters.shape),
      texture_ids: non_empty_list(filters.textures),
      texture_logic: filters.texture_logic,
      alignment_ids: wrap_value(filters.alignment),
      detachable: parse_detachable(filters.detachable),
      place_codes: place_codes,
      family_id: filters.family,
      form_ids: wrap_value(filters.form),
      walls_ids: wrap_value(filters.walls),
      cells_ids: wrap_value(filters.cells),
      season_ids: wrap_value(filters.season),
      undescribed: filters.undescribed,
      exclude_non_galls: !filters.show_non_galls
    }
  end

  defp wrap_in_list(nil, _fun), do: nil
  defp wrap_in_list(value, fun), do: [fun.(value)]

  defp wrap_value(nil), do: nil
  defp wrap_value(value), do: [value]

  defp maybe_get(nil, _key), do: nil
  defp maybe_get(map, key), do: Map.get(map, key)

  defp non_empty_list([]), do: nil
  defp non_empty_list(list), do: list

  # Add "leaf (anywhere)" virtual option to locations list, sorted alphabetically
  defp add_leaf_anywhere_option(plant_parts) do
    virtual_option = %{id: @leaf_anywhere_id, part: "leaf (anywhere)"}

    [virtual_option | plant_parts]
    |> Enum.sort_by(& &1.part)
  end

  # Parse plant part ID - handles both integer IDs and "leaf_anywhere" string
  defp parse_plant_part_id(@leaf_anywhere_id), do: @leaf_anywhere_id
  defp parse_plant_part_id(id) when is_binary(id), do: String.to_integer(id)
  defp parse_plant_part_id(id) when is_integer(id), do: id

  # Expand plant part IDs, replacing "leaf_anywhere" marker with actual leaf plant part IDs
  defp expand_plant_part_ids(plant_part_ids) do
    if @leaf_anywhere_id in plant_part_ids do
      leaf_ids = Galls.leaf_plant_part_ids()
      other_ids = Enum.reject(plant_part_ids, &(&1 == @leaf_anywhere_id))
      Enum.uniq(leaf_ids ++ other_ids)
    else
      plant_part_ids
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
  defp format_genus_display(%{name: name, type: type, description: desc}) do
    type_label = if type == "section", do: " [Section]", else: ""
    desc_text = if desc && desc != "", do: " - #{desc}", else: ""
    "#{name}#{type_label}#{desc_text}"
  end

  defp format_genus_display(%{name: name}), do: name

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
                  <.taxon_name name={genus.name} rank="genus" />
                  <span :if={genus.type == "section"} class="ml-1 text-xs text-gray-500">
                    [Section]
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
                options={@filter_options.plant_parts}
                selected={@filters.plant_parts}
                option_label={:part}
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
            <.family_filter families={@families} value={@filters.family} />
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
              <.season_filter options={@filter_options.seasons} value={@filters.season} />
              <div>
                <.multi_select_typeahead
                  id="textures"
                  name="texture"
                  label="Texture(s):"
                  placeholder="Textures"
                  options={@filter_options.textures}
                  selected={@filters.textures}
                  option_label={:texture}
                  query={@texture_query}
                  focused={@texture_focused}
                />
                <.logic_toggle
                  :if={length(@filters.textures) > 1}
                  logic={@filters.texture_logic}
                  toggle_event="toggle_texture_logic"
                />
              </div>
              <.alignment_filter options={@filter_options.alignments} value={@filters.alignment} />
              <.form_filter options={@filter_options.forms} value={@filters.form} />
              <.walls_filter options={@filter_options.walls} value={@filters.walls} />
              <.cells_filter options={@filter_options.cells} value={@filters.cells} />
              <.shape_filter options={@filter_options.shapes} value={@filters.shape} />
              <.color_filter options={@filter_options.colors} value={@filters.color} />
            </div>

            <div class="mt-3 flex flex-wrap gap-6">
              <.show_non_galls_filter value={@filters.show_non_galls} />
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
          show_non_galls={@filters.show_non_galls}
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

  # Component: Color Filter
  attr :options, :list, required: true
  attr :value, :integer, required: true

  defp color_filter(assigns) do
    ~H"""
    <form phx-change="change_filter" phx-value-filter="color">
      <.input
        type="select"
        name="value"
        label="Color"
        prompt="Any Color"
        options={Enum.map(@options, &{&1.color, &1.id})}
        value={@value}
      />
    </form>
    """
  end

  # Component: Shape Filter
  attr :options, :list, required: true
  attr :value, :integer, required: true

  defp shape_filter(assigns) do
    ~H"""
    <form phx-change="change_filter" phx-value-filter="shape">
      <.input
        type="select"
        name="value"
        label="Shape"
        prompt="Any Shape"
        options={Enum.map(@options, &{&1.shape, &1.id})}
        value={@value}
      />
    </form>
    """
  end

  # Component: Alignment Filter
  attr :options, :list, required: true
  attr :value, :integer, required: true

  defp alignment_filter(assigns) do
    ~H"""
    <form phx-change="change_filter" phx-value-filter="alignment">
      <.input
        type="select"
        name="value"
        label="Alignment"
        prompt="Any Alignment"
        options={Enum.map(@options, &{&1.alignment, &1.id})}
        value={@value}
      />
    </form>
    """
  end

  # Component: Form Filter
  attr :options, :list, required: true
  attr :value, :integer, required: true

  defp form_filter(assigns) do
    filtered_options = Enum.reject(assigns.options, &(&1.form == "non-gall"))
    assigns = assign(assigns, :filtered_options, filtered_options)

    ~H"""
    <form phx-change="change_filter" phx-value-filter="form">
      <.input
        type="select"
        name="value"
        label="Form"
        prompt="Any Form"
        options={Enum.map(@filtered_options, &{&1.form, &1.id})}
        value={@value}
      />
    </form>
    """
  end

  # Component: Walls Filter
  attr :options, :list, required: true
  attr :value, :integer, required: true

  defp walls_filter(assigns) do
    ~H"""
    <form phx-change="change_filter" phx-value-filter="walls">
      <.input
        type="select"
        name="value"
        label="Walls"
        prompt="Any Walls"
        options={Enum.map(@options, &{&1.walls, &1.id})}
        value={@value}
      />
    </form>
    """
  end

  # Component: Cells Filter
  attr :options, :list, required: true
  attr :value, :integer, required: true

  defp cells_filter(assigns) do
    ~H"""
    <form phx-change="change_filter" phx-value-filter="cells">
      <.input
        type="select"
        name="value"
        label="Cells"
        prompt="Any Cells"
        options={Enum.map(@options, &{&1.cells, &1.id})}
        value={@value}
      />
    </form>
    """
  end

  # Component: Season Filter
  attr :options, :list, required: true
  attr :value, :integer, required: true

  defp season_filter(assigns) do
    ~H"""
    <form phx-change="change_filter" phx-value-filter="season">
      <.input
        type="select"
        name="value"
        label="Season"
        prompt="Any Season"
        options={Enum.map(@options, &{&1.season, &1.id})}
        value={@value}
      />
    </form>
    """
  end

  # Component: Show Non-Galls Filter
  attr :value, :boolean, required: true

  defp show_non_galls_filter(assigns) do
    ~H"""
    <div class="mb-2">
      <form phx-change="change_filter" phx-value-filter="show_non_galls">
        <.input
          type="checkbox"
          name="value"
          checked={@value}
          label="Show Non-Galls"
        />
      </form>
    </div>
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
  attr :show_non_galls, :boolean, required: true
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
            {if @show_non_galls, do: "species", else: "galls"}
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
            <.gall_card :for={gall <- @results} gall={gall} summary={@summaries[gall.gall_id]} />
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
      <div
        :if={@gall.undescribed || @gall.non_gall || @gall[:place_match] == :country_level}
        class="flex flex-wrap gap-1 px-2 pb-2"
      >
        <span
          :if={@gall.undescribed}
          class="inline-flex items-center px-1.5 py-0.5 text-xs font-medium rounded bg-red-100 text-red-700 cursor-help"
          title="This species has not yet been formally described in scientific literature."
        >
          Undescribed
        </span>
        <span
          :if={@gall.non_gall}
          class="inline-flex items-center px-1.5 py-0.5 text-xs font-medium rounded bg-amber-100 text-amber-700 cursor-help"
          title="This is not a true gall but a different type of plant growth or damage caused by an organism that is often mistaken for a gall."
        >
          Non-gall
        </span>
        <span
          :if={@gall[:place_match] == :country_level}
          class="inline-flex items-center px-1.5 py-0.5 text-xs font-medium rounded bg-blue-100 text-blue-700 cursor-help"
          title="This gall occurs on hosts with country-level range records — state-level data unavailable for your selected region."
        >
          Country-level
        </span>
      </div>
    </div>
    """
  end
end
