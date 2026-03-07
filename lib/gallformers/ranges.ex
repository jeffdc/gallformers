defmodule Gallformers.Ranges do
  @moduledoc """
  The Ranges context.

  Manages geographic range data for species:
  - **Host ranges** (host_range table): Where host plants exist geographically
  - **Gall ranges** (gall_range table): Curated stored range for gall species

  Gall range is stored directly in the gall_range table as the source of truth.
  """

  import Ecto.Query

  alias Gallformers.GallHosts.GallHost
  alias Gallformers.Galls.GallTraits
  alias Gallformers.Places
  alias Gallformers.Places.Place
  alias Gallformers.Ranges.{DisplayRange, GallRange, HostRange}
  alias Gallformers.Repo
  alias Gallformers.Species.Species

  # ============================================
  # Host Range Queries
  # ============================================

  @doc """
  Gets hosts (plant species) for a Place with their aliases.
  """
  def get_hosts_for_place(place_id) do
    from(s in Species,
      join: hr in HostRange,
      on: hr.species_id == s.id,
      # No AliasSpecies schema exists; Alias uses "alias_species" as join_through
      left_join: als in "alias_species",
      on: als.species_id == s.id,
      left_join: a in "alias",
      on: a.id == als.alias_id,
      where: hr.place_id == ^place_id and s.taxoncode == "plant",
      group_by: [s.id, s.name],
      order_by: s.name,
      select: %{
        id: s.id,
        name: s.name,
        aliases: fragment("GROUP_CONCAT(?, ', ')", a.name)
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets place codes for a host species (range data).
  """
  @spec get_places_for_host(integer()) :: [String.t()]
  def get_places_for_host(host_species_id) do
    from(hr in HostRange,
      join: p in Place,
      on: hr.place_id == p.id,
      where: hr.species_id == ^host_species_id,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Gets place IDs (not codes) for a host species.
  """
  @spec get_place_ids_for_host(integer()) :: [integer()]
  def get_place_ids_for_host(host_species_id) do
    from(hr in HostRange,
      where: hr.species_id == ^host_species_id,
      select: hr.place_id
    )
    |> Repo.all()
  end

  @doc """
  Gets place codes, precision, and distribution type for a host species.
  """
  @spec get_places_for_host_with_precision(integer()) :: [map()]
  def get_places_for_host_with_precision(host_species_id) do
    from(hr in HostRange,
      join: p in Place,
      on: hr.place_id == p.id,
      where: hr.species_id == ^host_species_id,
      select: %{
        code: p.code,
        precision: hr.precision,
        place_id: p.id,
        distribution_type: hr.distribution_type
      }
    )
    |> Repo.all()
  end

  @doc """
  Checks whether a host species covers a given place, accounting for hierarchy.

  A host covers a place if there's a host_range row for that place or any
  of its ancestors (e.g., country-level range covers all subdivisions).
  """
  @spec host_covers_place?(integer(), integer()) :: boolean()
  def host_covers_place?(host_species_id, place_id) do
    ancestor_ids = Places.ancestor_ids(place_id)

    from(hr in HostRange,
      where: hr.species_id == ^host_species_id,
      where: hr.place_id in ^ancestor_ids,
      select: count()
    )
    |> Repo.one()
    |> Kernel.>(0)
  end

  @doc """
  Gets place codes for a list of host species IDs.

  Returns the union of all places where any of the hosts occur.
  Used for computing gall range from a local/pending list of hosts.
  """
  @spec get_places_for_host_species_ids([integer()]) :: [String.t()]
  def get_places_for_host_species_ids([]), do: []

  def get_places_for_host_species_ids(host_species_ids) do
    from(p in Place,
      join: hr in HostRange,
      on: hr.place_id == p.id,
      where: hr.species_id in ^host_species_ids,
      distinct: true,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Gets places for multiple hosts in a single query, grouped by host species ID.

  Returns a map of species_id => [place_code].
  """
  @spec get_places_for_hosts([integer()]) :: %{integer() => [String.t()]}
  def get_places_for_hosts([]), do: %{}

  def get_places_for_hosts(host_species_ids) do
    from(hr in HostRange,
      join: p in Place,
      on: hr.place_id == p.id,
      where: hr.species_id in ^host_species_ids,
      select: {hr.species_id, p.code}
    )
    |> Repo.all()
    |> Enum.group_by(fn {id, _code} -> id end, fn {_id, code} -> code end)
  end

  # ============================================
  # Host Range Management
  # ============================================

  @doc """
  Adds a place to a host's range with optional precision and distribution type.
  """
  @spec add_place_to_host(integer(), integer(), String.t(), String.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def add_place_to_host(
        host_species_id,
        place_id,
        precision \\ "exact",
        distribution_type \\ "native"
      ) do
    result =
      %HostRange{}
      |> HostRange.changeset(%{
        species_id: host_species_id,
        place_id: place_id,
        precision: precision,
        distribution_type: distribution_type
      })
      |> Repo.insert(on_conflict: :nothing)

    case result do
      {:ok, _} ->
        invalidate_gall_ranges_for_host(host_species_id)
        result

      error ->
        error
    end
  end

  @doc """
  Removes a place from a host's range.
  """
  @spec remove_place_from_host(integer(), integer()) :: {:ok, non_neg_integer()}
  def remove_place_from_host(host_species_id, place_id) do
    {count, _} =
      from(hr in HostRange,
        where: hr.species_id == ^host_species_id and hr.place_id == ^place_id
      )
      |> Repo.delete_all()

    invalidate_gall_ranges_for_host(host_species_id)
    {:ok, count}
  end

  @doc """
  Toggles a place in a host's range (add if not present, remove if present).
  Returns {:added, place_id} or {:removed, place_id}.
  """
  @spec toggle_place_for_host(integer(), integer()) ::
          {:added, integer()} | {:removed, integer()} | {:error, term()}
  def toggle_place_for_host(host_species_id, place_id) do
    result =
      Repo.transaction(fn ->
        query =
          from(hr in HostRange,
            where: hr.species_id == ^host_species_id and hr.place_id == ^place_id
          )

        case Repo.one(query) do
          nil ->
            %HostRange{}
            |> HostRange.changeset(%{species_id: host_species_id, place_id: place_id})
            |> Repo.insert!()

            {:added, place_id}

          _existing ->
            Repo.delete_all(query)
            {:removed, place_id}
        end
      end)
      |> case do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end

    case result do
      {:added, _} ->
        invalidate_gall_ranges_for_host(host_species_id)
        result

      {:removed, _} ->
        invalidate_gall_ranges_for_host(host_species_id)
        result

      {:error, _} ->
        result
    end
  end

  @doc """
  Bulk updates all places for a host (replaces existing).

  Accepts either plain place IDs or `{place_id, precision}` tuples.
  """
  @spec update_host_places(
          integer(),
          [{integer(), String.t(), String.t()} | {integer(), String.t()} | integer()]
        ) :: {:ok, :ok}
  def update_host_places(host_species_id, place_entries) do
    entries = normalize_entries(host_species_id, place_entries, distribution_type: true)

    result =
      Repo.transaction(fn ->
        from(hr in HostRange, where: hr.species_id == ^host_species_id) |> Repo.delete_all()
        if entries != [], do: Repo.insert_all(HostRange, entries)
        :ok
      end)

    case result do
      {:ok, :ok} ->
        invalidate_gall_ranges_for_host(host_species_id)
        {:ok, :ok}

      error ->
        error
    end
  end

  # ============================================
  # Gall Range Queries (from gall_range table)
  # ============================================

  @doc """
  Gets place codes for a gall species from the curated gall_range table.
  """
  @spec get_places_for_gall(integer()) :: [String.t()]
  def get_places_for_gall(gall_species_id) do
    get_gall_range_codes(gall_species_id)
  end

  @doc """
  Gets place codes for multiple gall species in a single query (batch version).

  Returns a map of gall_species_id => [place_codes].
  """
  @spec get_places_for_galls([integer()]) :: %{integer() => [String.t()]}
  def get_places_for_galls([]), do: %{}

  def get_places_for_galls(gall_species_ids) do
    from(gr in GallRange,
      join: p in Place,
      on: gr.place_id == p.id,
      where: gr.species_id in ^gall_species_ids,
      select: {gr.species_id, p.code}
    )
    |> Repo.all()
    |> Enum.group_by(fn {gall_id, _code} -> gall_id end, fn {_gall_id, code} -> code end)
  end

  @doc """
  Gets host ranges with precision for a list of host species IDs.
  Returns the union of all ranges with precision metadata.
  """
  @spec get_host_ranges_with_precision_for_species_ids([integer()]) :: [map()]
  def get_host_ranges_with_precision_for_species_ids([]), do: []

  def get_host_ranges_with_precision_for_species_ids(host_species_ids) do
    from(hr in HostRange,
      join: p in Place,
      on: hr.place_id == p.id,
      where: hr.species_id in ^host_species_ids,
      distinct: true,
      select: %{
        code: p.code,
        precision: hr.precision,
        place_id: p.id,
        distribution_type: hr.distribution_type
      }
    )
    |> Repo.all()
  end

  # ============================================
  # Display Range (expanding precision for maps)
  # ============================================

  @doc """
  Computes display range from raw range entries.

  Used by admin pages that have pending (unsaved) changes. Accepts the same
  format as `get_host_ranges_with_precision_for_gall/1` returns:
  `[%{code, precision, place_id}]`.

  ## Options

    * `:with_introduced` — when `true`, partitions entries by `distribution_type`
      and populates `introduced_range` with leaf codes from "introduced" entries.
  """
  @spec compute_display_range([map()], keyword()) :: DisplayRange.t()
  def compute_display_range(host_ranges, opts \\ []) do
    {exact_codes, inherited_codes} = split_by_precision(host_ranges)

    exact_set = MapSet.new(exact_codes)
    inherited_set = MapSet.new(inherited_codes)
    clean_inherited = MapSet.difference(inherited_set, exact_set)

    introduced_range =
      if Keyword.get(opts, :with_introduced, false) do
        introduced_entries =
          Enum.filter(host_ranges, &(Map.get(&1, :distribution_type) == "introduced"))

        {intro_exact, intro_inherited} = split_by_precision(introduced_entries)
        intro_set = MapSet.new(intro_exact ++ intro_inherited)
        all_range = MapSet.union(exact_set, clean_inherited)
        MapSet.intersection(intro_set, all_range) |> MapSet.to_list()
      else
        []
      end

    %DisplayRange{
      in_range: MapSet.to_list(exact_set),
      inherited_range: MapSet.to_list(clean_inherited),
      introduced_range: introduced_range
    }
  end

  @doc """
  Gets the full range display data for a gall from the curated gall_range table,
  expanding country-level ranges to leaf descendant codes for map display.

  Returns `%{in_range: [codes], inherited_range: [codes]}`.
  - `in_range`: exact subdivision codes
  - `inherited_range`: leaf codes expanded from country-level ranges
  """
  @spec get_display_range_for_gall(integer()) :: DisplayRange.t()
  def get_display_range_for_gall(gall_species_id) do
    gall_ranges = get_gall_range_with_precision(gall_species_id)
    {exact_codes, inherited_codes} = split_by_precision(gall_ranges)

    exact_set = MapSet.new(exact_codes)

    %DisplayRange{
      in_range: exact_codes,
      inherited_range: Enum.reject(inherited_codes, &MapSet.member?(exact_set, &1))
    }
  end

  @doc """
  Gets display range data for a host species, expanding country-level ranges.

  Returns `%{in_range: [codes], inherited_range: [codes]}`.
  """
  @spec get_display_range_for_host(integer()) :: DisplayRange.t()
  def get_display_range_for_host(host_species_id) do
    host_ranges = get_places_for_host_with_precision(host_species_id)
    compute_display_range(host_ranges, with_introduced: true)
  end

  # Splits host ranges into exact leaf codes and inherited leaf codes.
  # Country-level ranges are expanded to their leaf descendants in a single
  # batched query instead of one query per country.
  defp split_by_precision(host_ranges) do
    {exact, country_entries} =
      Enum.split_with(host_ranges, &(&1.precision == "exact"))

    exact_codes = Enum.map(exact, & &1.code)

    inherited_codes =
      case country_entries do
        [] ->
          []

        entries ->
          # Collect all country place_ids, expand each to leaf descendants,
          # then batch-fetch all leaf codes in a single query
          leaf_ids =
            entries
            |> Enum.flat_map(&Places.leaf_descendant_ids(&1.place_id))
            |> Enum.uniq()

          from(p in Place, where: p.id in ^leaf_ids, select: p.code)
          |> Repo.all()
      end

    {exact_codes, inherited_codes}
  end

  # ============================================
  # Gall Range Queries
  # ============================================

  @doc """
  Gets gall range entries with precision and place metadata.
  """
  @spec get_gall_range_with_precision(integer()) :: [map()]
  def get_gall_range_with_precision(gall_species_id) do
    from(gr in GallRange,
      join: p in Place,
      on: gr.place_id == p.id,
      where: gr.species_id == ^gall_species_id,
      select: %{code: p.code, precision: gr.precision, place_id: p.id}
    )
    |> Repo.all()
  end

  @doc """
  Gets gall range place IDs for a gall species.
  """
  @spec get_gall_range_place_ids(integer()) :: [integer()]
  def get_gall_range_place_ids(gall_species_id) do
    from(gr in GallRange,
      where: gr.species_id == ^gall_species_id,
      select: gr.place_id
    )
    |> Repo.all()
  end

  @doc """
  Gets gall range place codes for a gall species.
  """
  @spec get_gall_range_codes(integer()) :: [String.t()]
  def get_gall_range_codes(gall_species_id) do
    from(gr in GallRange,
      join: p in Place,
      on: gr.place_id == p.id,
      where: gr.species_id == ^gall_species_id,
      select: p.code
    )
    |> Repo.all()
  end

  # ============================================
  # Gall Range Management
  # ============================================

  @doc """
  Replaces all gall_range entries for a gall species.

  Accepts a list of `{place_id, precision}` tuples or plain place_ids
  (which default to "exact" precision).
  """
  @spec set_gall_range(integer(), [{integer(), String.t()} | integer()]) :: {:ok, :ok}
  def set_gall_range(gall_species_id, place_entries) do
    entries =
      Enum.map(place_entries, fn
        {place_id, precision} ->
          %{species_id: gall_species_id, place_id: place_id, precision: precision}

        place_id when is_integer(place_id) ->
          %{species_id: gall_species_id, place_id: place_id, precision: "exact"}
      end)

    Repo.transaction(fn ->
      from(gr in GallRange, where: gr.species_id == ^gall_species_id) |> Repo.delete_all()
      if entries != [], do: Repo.insert_all(GallRange, entries)
      :ok
    end)
  end

  # ============================================
  # Utility
  # ============================================

  @doc """
  Gets a place ID by its code.
  """
  @spec get_place_id_by_code(String.t()) :: integer() | nil
  def get_place_id_by_code(code) do
    from(p in Place,
      where: p.code == ^code,
      select: p.id
    )
    |> Repo.one()
  end

  # ============================================
  # Invalidation Cascade
  # ============================================

  @doc """
  Invalidates gall range confirmation for all galls linked to a host species.

  Called when a host's range data changes so that gall ranges can be reviewed.
  Sets `range_confirmed = false` on `gall_traits` for every gall linked to the host.
  """
  @spec invalidate_gall_ranges_for_host(integer()) :: :ok
  def invalidate_gall_ranges_for_host(host_species_id) do
    gall_ids =
      from(gh in GallHost,
        where: gh.host_species_id == ^host_species_id,
        select: gh.gall_species_id
      )
      |> Repo.all()

    if gall_ids != [] do
      from(gt in GallTraits,
        where: gt.species_id in ^gall_ids
      )
      |> Repo.update_all(set: [range_confirmed: false])
    end

    :ok
  end

  # ============================================
  # Private helpers
  # ============================================

  defp normalize_entries(species_id, entries, opts) do
    include_dt = Keyword.get(opts, :distribution_type, false)

    Enum.map(entries, fn entry ->
      base = normalize_entry(species_id, entry)
      if include_dt, do: Map.put_new(base, :distribution_type, "native"), else: base
    end)
  end

  defp normalize_entry(species_id, {place_id, precision, distribution_type}) do
    %{
      species_id: species_id,
      place_id: place_id,
      precision: precision,
      distribution_type: distribution_type
    }
  end

  defp normalize_entry(species_id, {place_id, precision}) do
    %{species_id: species_id, place_id: place_id, precision: precision}
  end

  defp normalize_entry(species_id, place_id) when is_integer(place_id) do
    %{species_id: species_id, place_id: place_id, precision: "exact"}
  end
end
