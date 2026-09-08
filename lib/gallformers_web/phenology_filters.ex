defmodule GallformersWeb.PhenologyFilters do
  @moduledoc """
  Shared filter parsing for `/phenology`.

  Both the LiveView (`GallformersWeb.PhenologyLive`) and the CSV export
  controller (`GallformersWeb.PhenologyController.export/2`) take the
  same filter URL params and need to apply the same defaults / validation
  rules. Putting that logic here ensures the on-screen view and downloaded
  CSV can't drift apart — if we change the default search from
  "Dryocosmus quercuspalustris" to something else, there's one place
  to change.

  Two parsing entry points with different "absent key" semantics:

  - `from_url_params/1` — for URL params on initial mount or controller
    requests. Absent key means "use the default for this filter";
    present-but-empty key means "user has explicitly cleared this filter"
    (e.g. `?search=` → no search; `?phen=` → strict empty).

  - `from_form_params/1` — for LV form change events. Absent key means
    "user has cleared this filter" (e.g. all phenophase checkboxes off →
    browsers omit the `phenophases` key entirely).
  """

  alias Gallformers.Phenology
  alias Gallformers.Species

  @default_search ["Dryocosmus quercuspalustris"]
  @default_phenophases ~w(maturing perimature Free-living)
  @default_target_lat 42.0

  # Phenophases offered in the explorer UI, in display order. Validates
  # incoming param values. `senescent` is intentionally omitted.
  @explorer_phenophases ~w(oviscar developing dormant maturing Free-living perimature)

  @doc "The explorer's phenophase vocabulary, in display order."
  def explorer_phenophases, do: @explorer_phenophases

  @doc "Evidence scope: stage visibility never restricts prediction input."
  def prediction_scope(filters),
    do: Map.drop(filters, [:phenophases, :display_mode, :target_lat, :sort, :sort_dir])

  @doc "Select visible dots from the independently loaded evidence scope."
  def visible_observations(observations, filters) do
    Enum.filter(observations, &(&1.phenophase in (filters[:phenophases] || [])))
  end

  @doc "Default search filter (a list of name fragments)."
  def default_search, do: @default_search

  @doc "Default phenophase filter."
  def default_phenophases, do: @default_phenophases

  @doc "Default target latitude for predictions."
  def default_target_lat, do: @default_target_lat

  @doc """
  Parse filters from URL query params. Used by both LV mount and the
  CSV export controller.
  """
  def from_url_params(params) when is_map(params) do
    %{
      search: parse_search_url(params),
      species_id: parse_positive_id(params["species_id"]),
      generation: parse_generation(params["gen"]),
      phenophases: parse_phenophases_url(params),
      taxon_id: parse_positive_id(params["taxon"]),
      place_id: parse_positive_id(params["place"]),
      plant_part_ids: parse_id_list(params["pp"]),
      color_ids: parse_id_list(params["color"]),
      shape_ids: parse_id_list(params["shape"]),
      display_mode: parse_display_mode(params["display"]),
      sort: parse_sort(params["sort"]),
      sort_dir: parse_sort_dir(params["dir"], parse_sort(params["sort"])),
      target_lat: parse_target_lat(params["lat"]),
      min_lat: parse_lat_bound(params["min_lat"]),
      max_lat: parse_lat_bound(params["max_lat"]),
      min_lng: parse_lng_bound(params["min_lng"]),
      max_lng: parse_lng_bound(params["max_lng"])
    }
  end

  @doc """
  Parse filters from a Phoenix LV form-change params map. Differs from
  `from_url_params/1` in how it treats absent keys (form sends nothing
  for unchecked checkbox groups, which we interpret as "user cleared
  the filter" rather than "use default").
  """
  def from_form_params(params) when is_map(params) do
    %{
      search: parse_search_value(params["search"]),
      generation: parse_generation(params["generation"]),
      phenophases: parse_phenophases_form(params["phenophases"]),
      taxon_id: parse_positive_id(params["taxon"]),
      place_id: parse_positive_id(params["place"]),
      plant_part_ids: parse_id_list(params["plant_part_ids"]),
      color_ids: parse_id_list(params["color_ids"]),
      shape_ids: parse_id_list(params["shape_ids"]),
      display_mode: parse_display_mode(params["display"]),
      sort: parse_sort(params["sort"]),
      sort_dir: parse_sort_dir(params["dir"], parse_sort(params["sort"])),
      target_lat: parse_target_lat(params["target_lat"]),
      min_lat: parse_lat_bound(params["min_lat"]),
      max_lat: parse_lat_bound(params["max_lat"]),
      min_lng: parse_lng_bound(params["min_lng"]),
      max_lng: parse_lng_bound(params["max_lng"])
    }
  end

  @doc """
  Reverse of `from_url_params/1`. Returns a keyword list suitable for
  Phoenix verified-route interpolation. Emits explicit empty values
  when the user has cleared a filter that has a non-empty default, so
  reload preserves the cleared state instead of restoring the default.
  """
  def to_query(filters) when is_map(filters) do
    []
    |> maybe_put_search(filters[:search])
    |> maybe_put_species_id(filters[:species_id])
    |> maybe_put_gen(filters[:generation])
    |> maybe_put_phen(filters[:phenophases])
    |> maybe_put_taxon(filters[:taxon_id])
    |> maybe_put_place(filters[:place_id])
    |> maybe_put_id_list(:pp, filters[:plant_part_ids])
    |> maybe_put_id_list(:color, filters[:color_ids])
    |> maybe_put_id_list(:shape, filters[:shape_ids])
    |> maybe_put_display(filters[:display_mode])
    |> maybe_put_sort(filters[:sort])
    |> maybe_put_dir(filters[:sort], filters[:sort_dir])
    |> maybe_put_lat(filters[:target_lat])
    |> maybe_put_coord(:min_lat, filters[:min_lat])
    |> maybe_put_coord(:max_lat, filters[:max_lat])
    |> maybe_put_coord(:min_lng, filters[:min_lng])
    |> maybe_put_coord(:max_lng, filters[:max_lng])
  end

  defp maybe_put_species_id(query, nil), do: query
  defp maybe_put_species_id(query, id), do: Keyword.put(query, :species_id, id)

  @doc """
  Parse brush-selection bounds from URL params (`doy_min`, `doy_max`,
  `lat_min`, `lat_max`). Returns a map or `nil`. All four params must
  be parseable for the brush to apply. The CSV export endpoint reads
  brush bounds this way; the brush itself is appended to the URL
  client-side by the chrome JS hook on every brush gesture.
  """
  def parse_brush(params) when is_map(params) do
    with {:ok, dmin} <- to_number(params["doy_min"]),
         {:ok, dmax} <- to_number(params["doy_max"]),
         {:ok, lmin} <- to_number(params["lat_min"]),
         {:ok, lmax} <- to_number(params["lat_max"]) do
      %{doy_min: trunc(dmin), doy_max: trunc(dmax), lat_min: lmin, lat_max: lmax}
    else
      _ -> nil
    end
  end

  @doc """
  Parse the display-only selection lens from URL params. Returns one of:

    * `{:date_range, doy, days}`   — center DOY ± days (circular window)
    * `{:seasonal_landmark, {low, high}}` — shared clock edges computed from
      `sel_doy`, `sel_lat` and `sel_days`, matching the client selection
    * `{:error, :invalid_landmark_selection}` — invalid or incomplete reference
    * `nil`                        — no lens (or brush handled separately)

  The lens narrows the CSV export only; it never affects predictions.
  """
  def parse_selection(%{"sel_mode" => "date_range"} = params) do
    with {:ok, doy} <- to_number(params["sel_doy"]),
         {:ok, days} <- to_number(params["sel_days"]) do
      {:date_range, trunc(doy), trunc(days)}
    else
      _ -> nil
    end
  end

  def parse_selection(%{"sel_mode" => "seasonal_landmark"} = params) do
    with {:ok, doy} <- selection_number(params["sel_doy"]),
         {:ok, lat} <- selection_number(params["sel_lat"]),
         {:ok, days} <- selection_number(params["sel_days"]),
         {:ok, window} <- Phenology.seasonal_window(doy, lat, days) do
      {:seasonal_landmark, window}
    else
      _ -> {:error, :invalid_landmark_selection}
    end
  end

  def parse_selection(_params), do: nil

  defp selection_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp selection_number(value) when is_number(value), do: {:ok, value}
  defp selection_number(_), do: :error

  # ----------------------------------------------------------------------
  # Search
  # ----------------------------------------------------------------------

  defp parse_search_url(params) do
    case Map.fetch(params, "search") do
      {:ok, value} ->
        parse_search_value(value)

      :error ->
        species_id_to_search(params["species_id"]) || @default_search
    end
  end

  defp parse_search_value(nil), do: nil
  defp parse_search_value(""), do: nil

  defp parse_search_value(value) when is_binary(value) do
    terms =
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case terms do
      [] -> nil
      list -> list
    end
  end

  defp parse_search_value(_), do: nil

  defp species_id_to_search(nil), do: nil
  defp species_id_to_search(""), do: nil

  defp species_id_to_search(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} ->
        case Species.get_species(id) do
          %{name: name} when is_binary(name) -> [name]
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp species_id_to_search(_), do: nil

  # ----------------------------------------------------------------------
  # Generation
  # ----------------------------------------------------------------------

  defp parse_generation("sexgen"), do: :sexgen
  defp parse_generation("agamic"), do: :agamic
  defp parse_generation(_), do: :all

  # ----------------------------------------------------------------------
  # Phenophases
  # ----------------------------------------------------------------------

  defp parse_phenophases_url(params) do
    case Map.fetch(params, "phen") do
      :error -> @default_phenophases
      {:ok, nil} -> @default_phenophases
      {:ok, value} -> parse_phenophases_value(value)
    end
  end

  defp parse_phenophases_form(nil), do: []
  defp parse_phenophases_form(value), do: parse_phenophases_value(value)

  defp parse_phenophases_value(""), do: []

  defp parse_phenophases_value(value) when is_list(value) do
    Enum.filter(value, &(&1 in @explorer_phenophases))
  end

  defp parse_phenophases_value(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in @explorer_phenophases))
  end

  defp parse_phenophases_value(_), do: []

  # ----------------------------------------------------------------------
  # Taxon (family / tribe / genus node id)
  # ----------------------------------------------------------------------

  # A single positive id from a <select> (taxon node or place). Absent /
  # empty / non-positive means "no filter" — the same nil in both URL and
  # form parsing, since an empty <select> option submits "".
  defp parse_positive_id(nil), do: nil
  defp parse_positive_id(""), do: nil

  defp parse_positive_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp parse_positive_id(value) when is_integer(value) and value > 0, do: value
  defp parse_positive_id(_), do: nil

  # ----------------------------------------------------------------------
  # Trait id lists (plant_part / color / shape)
  # ----------------------------------------------------------------------

  # A list of positive integer filter-field ids. Accepts a comma-joined URL
  # string ("1,2") or a form checkbox-group list (["1", "2"]). Unparseable /
  # non-positive entries are dropped; the result is deduped. Empty = no
  # filter for that facet.
  defp parse_id_list(nil), do: []
  defp parse_id_list(""), do: []

  defp parse_id_list(value) when is_binary(value) do
    value |> String.split(",") |> parse_id_list()
  end

  defp parse_id_list(value) when is_list(value) do
    value
    |> Enum.map(&parse_positive_int/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_id_list(_), do: []

  defp parse_positive_int(v) when is_integer(v) and v > 0, do: v

  defp parse_positive_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp parse_positive_int(_), do: nil

  # ----------------------------------------------------------------------
  # Display mode
  # ----------------------------------------------------------------------

  # This chooses the panel below the chart, not prediction lines on the plot.
  # Legacy `chart` URLs select the predictions panel.
  defp parse_display_mode("table"), do: :data_table
  defp parse_display_mode("species"), do: :species_list
  defp parse_display_mode(_), do: :predictions

  # ----------------------------------------------------------------------
  # Sort order (species list). Display-only, so it never reloads the obs set.
  # ----------------------------------------------------------------------

  @doc """
  Parses a raw `sort` value into a sort key, for the clickable column-header
  sort control which drives its own event rather than the filter form.
  """
  @spec sort_from_param(term()) :: :name | :obs_count | :recency
  def sort_from_param(value), do: parse_sort(value)

  @doc """
  Parses a raw `dir` value into `:asc` / `:desc`, falling back to the natural
  default for `key` (name ascending, everything else descending).
  """
  @spec sort_dir_from_param(term(), atom()) :: :asc | :desc
  def sort_dir_from_param(value, key), do: parse_sort_dir(value, key)

  @doc "Natural sort direction for a species-list sort key."
  @spec default_sort_dir(atom()) :: :asc | :desc
  def default_sort_dir(:name), do: :asc
  def default_sort_dir(_), do: :desc

  defp parse_sort("obs_count"), do: :obs_count
  defp parse_sort("recency"), do: :recency
  defp parse_sort(_), do: :name

  defp parse_sort_dir("asc", _key), do: :asc
  defp parse_sort_dir("desc", _key), do: :desc
  defp parse_sort_dir(_other, key), do: default_sort_dir(key)

  # ----------------------------------------------------------------------
  # Target latitude
  # ----------------------------------------------------------------------

  defp parse_target_lat(nil), do: @default_target_lat
  defp parse_target_lat(""), do: @default_target_lat

  defp parse_target_lat(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {f, _} when f >= -90.0 and f <= 90.0 -> f
      _ -> @default_target_lat
    end
  end

  defp parse_target_lat(value) when is_number(value) and value >= -90 and value <= 90,
    do: value * 1.0

  defp parse_target_lat(_), do: @default_target_lat

  # ----------------------------------------------------------------------
  # Geographic filters (observation coordinate bounds)
  # ----------------------------------------------------------------------

  # Persistent lat/lng range filters on the observation coordinates, in
  # the same spirit as the legacy Shiny `doyCalc` viewer's lat/lng inputs.
  # Distinct from the chart brush's lat_min/lat_max — the brush is a
  # transient on-chart selection that lives only on the CSV download URL.

  defp parse_lat_bound(nil), do: nil
  defp parse_lat_bound(""), do: nil

  defp parse_lat_bound(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {f, _} when f >= -90.0 and f <= 90.0 -> f
      _ -> nil
    end
  end

  defp parse_lat_bound(value) when is_number(value) and value >= -90 and value <= 90,
    do: value * 1.0

  defp parse_lat_bound(_), do: nil

  defp parse_lng_bound(nil), do: nil
  defp parse_lng_bound(""), do: nil

  defp parse_lng_bound(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {f, _} when f >= -180.0 and f <= 180.0 -> f
      _ -> nil
    end
  end

  defp parse_lng_bound(value) when is_number(value) and value >= -180 and value <= 180,
    do: value * 1.0

  defp parse_lng_bound(_), do: nil

  # ----------------------------------------------------------------------
  # URL emit (to_query helpers)
  # ----------------------------------------------------------------------

  defp maybe_put_search(query, terms) when is_list(terms) and terms != [] do
    if terms == @default_search,
      do: query,
      else: query ++ [search: Enum.join(terms, ",")]
  end

  defp maybe_put_search(query, _empty_or_nil),
    do: query ++ [search: ""]

  defp maybe_put_gen(query, :all), do: query

  defp maybe_put_gen(query, gen) when gen in [:sexgen, :agamic],
    do: query ++ [gen: Atom.to_string(gen)]

  defp maybe_put_gen(query, _), do: query

  defp maybe_put_phen(query, phens) when is_list(phens) and phens != [] do
    if phens == @default_phenophases,
      do: query,
      else: query ++ [phen: Enum.join(phens, ",")]
  end

  defp maybe_put_phen(query, _empty_or_nil),
    do: query ++ [phen: ""]

  defp maybe_put_taxon(query, id) when is_integer(id) and id > 0,
    do: query ++ [taxon: id]

  defp maybe_put_taxon(query, _), do: query

  defp maybe_put_place(query, id) when is_integer(id) and id > 0,
    do: query ++ [place: id]

  defp maybe_put_place(query, _), do: query

  defp maybe_put_id_list(query, key, ids) when is_list(ids) and ids != [],
    do: query ++ [{key, Enum.join(ids, ",")}]

  defp maybe_put_id_list(query, _key, _), do: query

  defp maybe_put_display(query, :predictions), do: query
  defp maybe_put_display(query, :data_table), do: query ++ [display: "table"]
  defp maybe_put_display(query, :species_list), do: query ++ [display: "species"]
  defp maybe_put_display(query, _), do: query

  defp maybe_put_sort(query, :obs_count), do: query ++ [sort: "obs_count"]
  defp maybe_put_sort(query, :recency), do: query ++ [sort: "recency"]
  defp maybe_put_sort(query, _), do: query

  # Only emit `dir` when it differs from the key's natural default, keeping
  # URLs clean (an absent `dir` round-trips back to the default).
  defp maybe_put_dir(query, key, dir) do
    if dir == default_sort_dir(key), do: query, else: query ++ [dir: to_string(dir)]
  end

  defp maybe_put_lat(query, lat) when is_number(lat) do
    if lat == @default_target_lat, do: query, else: query ++ [lat: to_string(lat)]
  end

  defp maybe_put_lat(query, _), do: query

  defp maybe_put_coord(query, _key, nil), do: query

  defp maybe_put_coord(query, key, value) when is_number(value),
    do: query ++ [{key, value}]

  defp maybe_put_coord(query, _key, _other), do: query

  # ----------------------------------------------------------------------
  # Misc
  # ----------------------------------------------------------------------

  defp to_number(nil), do: :error
  defp to_number(""), do: :error
  defp to_number(n) when is_number(n), do: {:ok, n}

  defp to_number(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> {:ok, f}
      :error -> :error
    end
  end

  defp to_number(_), do: :error
end
