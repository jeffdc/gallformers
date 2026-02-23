defmodule Gallformers.Ranges do
  @moduledoc """
  The Ranges context.

  Manages geographic range data for species:
  - **Host ranges** (host_range table): Where host plants exist geographically
  - **Gall range exclusions** (gall_range_exclusion table): Where galls do NOT occur
    despite suitable hosts existing

  Gall effective range is computed as:
      (union of all host plant ranges) - (explicit exclusions)

  This is not stored directly but computed from the two tables.
  """

  import Ecto.Query

  alias Gallformers.GallHosts.GallHost
  alias Gallformers.Places
  alias Gallformers.Places.Place
  alias Gallformers.Ranges.{DisplayRange, GallRangeExclusion, HostRange}
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
  Gets place codes and precision for a host species.
  """
  @spec get_places_for_host_with_precision(integer()) :: [map()]
  def get_places_for_host_with_precision(host_species_id) do
    from(hr in HostRange,
      join: p in Place,
      on: hr.place_id == p.id,
      where: hr.species_id == ^host_species_id,
      select: %{code: p.code, precision: hr.precision, place_id: p.id}
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
  Adds a place to a host's range with optional precision.
  """
  @spec add_place_to_host(integer(), integer(), String.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def add_place_to_host(host_species_id, place_id, precision \\ "exact") do
    %HostRange{}
    |> HostRange.changeset(%{
      species_id: host_species_id,
      place_id: place_id,
      precision: precision
    })
    |> Repo.insert(on_conflict: :nothing)
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

    {:ok, count}
  end

  @doc """
  Toggles a place in a host's range (add if not present, remove if present).
  Returns {:added, place_id} or {:removed, place_id}.
  """
  @spec toggle_place_for_host(integer(), integer()) ::
          {:added, integer()} | {:removed, integer()} | {:error, term()}
  def toggle_place_for_host(host_species_id, place_id) do
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
  end

  @doc """
  Bulk updates all places for a host (replaces existing).

  Accepts either plain place IDs or `{place_id, precision}` tuples.
  """
  @spec update_host_places(integer(), [{integer(), String.t()}] | [integer()]) :: {:ok, :ok}
  def update_host_places(host_species_id, place_entries) do
    entries = normalize_entries(host_species_id, place_entries)

    Repo.transaction(fn ->
      from(hr in HostRange, where: hr.species_id == ^host_species_id) |> Repo.delete_all()
      if entries != [], do: Repo.insert_all(HostRange, entries)
      :ok
    end)
  end

  # ============================================
  # Gall Range Queries (via hosts)
  # ============================================

  @doc """
  Gets place codes for a gall species via its hosts.
  This is the POTENTIAL range (before exclusions are applied).
  """
  @spec get_places_for_gall(integer()) :: [String.t()]
  def get_places_for_gall(gall_species_id) do
    from(p in Place,
      join: hr in HostRange,
      on: hr.place_id == p.id,
      join: h in GallHost,
      on: h.host_species_id == hr.species_id,
      where: h.gall_species_id == ^gall_species_id,
      distinct: true,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Gets place codes for multiple gall species in a single query (batch version).

  Returns a map of gall_species_id => [place_codes].
  """
  @spec get_places_for_galls([integer()]) :: %{integer() => [String.t()]}
  def get_places_for_galls([]), do: %{}

  def get_places_for_galls(gall_species_ids) do
    from(p in Place,
      join: hr in HostRange,
      on: hr.place_id == p.id,
      join: h in GallHost,
      on: h.host_species_id == hr.species_id,
      where: h.gall_species_id in ^gall_species_ids,
      distinct: true,
      select: {h.gall_species_id, p.code}
    )
    |> Repo.all()
    |> Enum.group_by(fn {gall_id, _code} -> gall_id end, fn {_gall_id, code} -> code end)
  end

  @doc """
  Gets the union of all host places for a gall as place IDs (not codes).
  Used for computing which places can potentially be excluded.
  """
  @spec get_host_place_ids_for_gall(integer()) :: [integer()]
  def get_host_place_ids_for_gall(gall_species_id) do
    from(hr in HostRange,
      join: h in GallHost,
      on: h.host_species_id == hr.species_id,
      where: h.gall_species_id == ^gall_species_id,
      distinct: true,
      select: hr.place_id
    )
    |> Repo.all()
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
      select: %{code: p.code, precision: hr.precision, place_id: p.id}
    )
    |> Repo.all()
  end

  # ============================================
  # Display Range (expanding precision for maps)
  # ============================================

  @doc """
  Computes display range from raw host range entries and exclusions.

  Used by admin pages that have pending (unsaved) changes. Accepts the same
  format as `get_host_ranges_with_precision_for_gall/1` returns:
  `[%{code, precision, place_id}]`.

  Exclusions is a list of place codes to subtract from the range.
  """
  @spec compute_display_range([map()], [String.t()]) :: DisplayRange.t()
  def compute_display_range(host_ranges, excluded_codes \\ []) do
    excluded = MapSet.new(excluded_codes)
    {exact_codes, inherited_codes} = split_by_precision(host_ranges)

    exact_set = MapSet.new(exact_codes)
    inherited_set = MapSet.new(inherited_codes)

    effective_exact = MapSet.difference(exact_set, excluded)

    effective_inherited =
      inherited_set
      |> MapSet.difference(exact_set)
      |> MapSet.difference(excluded)

    %DisplayRange{
      in_range: MapSet.to_list(effective_exact),
      inherited_range: MapSet.to_list(effective_inherited),
      excluded_range: MapSet.to_list(excluded)
    }
  end

  @doc """
  Gets the full range display data for a gall, expanding country-level ranges
  to leaf descendant codes for map display.

  Returns `%{in_range: [codes], inherited_range: [codes], excluded_range: [codes]}`.
  - `in_range`: exact subdivision codes (host confirmed in this specific state)
  - `inherited_range`: leaf codes expanded from country/continent-level ranges
  - `excluded_range`: explicitly excluded codes
  """
  @spec get_display_range_for_gall(integer()) :: DisplayRange.t()
  def get_display_range_for_gall(gall_species_id) do
    host_ranges = get_host_ranges_with_precision_for_gall(gall_species_id)
    excluded = get_excluded_places_for_gall(gall_species_id)
    compute_display_range(host_ranges, excluded)
  end

  @doc """
  Gets display range data for a host species, expanding country-level ranges.

  Returns `%{in_range: [codes], inherited_range: [codes]}`.
  """
  @spec get_display_range_for_host(integer()) :: DisplayRange.t()
  def get_display_range_for_host(host_species_id) do
    host_ranges = get_places_for_host_with_precision(host_species_id)
    compute_display_range(host_ranges)
  end

  # Gets host ranges with precision for a gall (via host relationships)
  defp get_host_ranges_with_precision_for_gall(gall_species_id) do
    from(p in Place,
      join: hr in HostRange,
      on: hr.place_id == p.id,
      join: h in GallHost,
      on: h.host_species_id == hr.species_id,
      where: h.gall_species_id == ^gall_species_id,
      distinct: true,
      select: %{code: p.code, precision: hr.precision, place_id: p.id}
    )
    |> Repo.all()
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
  # Gall Range Exclusion Queries
  # ============================================

  @doc """
  Gets excluded place codes for a gall species (direct range exclusions).
  """
  @spec get_excluded_places_for_gall(integer()) :: [String.t()]
  def get_excluded_places_for_gall(gall_species_id) do
    from(p in Place,
      join: gre in GallRangeExclusion,
      on: gre.place_id == p.id,
      where: gre.species_id == ^gall_species_id,
      distinct: true,
      select: p.code
    )
    |> Repo.all()
  end

  @doc """
  Gets excluded place IDs (not codes) for a gall species.
  """
  @spec get_excluded_place_ids_for_gall(integer()) :: [integer()]
  def get_excluded_place_ids_for_gall(gall_species_id) do
    from(gre in GallRangeExclusion,
      where: gre.species_id == ^gall_species_id,
      select: gre.place_id
    )
    |> Repo.all()
  end

  # ============================================
  # Gall Range Exclusion Management
  # ============================================

  @doc """
  Bulk updates all range exclusions for a gall (replaces existing).

  Accepts either plain place IDs or `{place_id, precision}` tuples.
  """
  @spec set_range_exclusions_for_gall(integer(), [{integer(), String.t()}] | [integer()]) ::
          {:ok, :ok}
  def set_range_exclusions_for_gall(gall_species_id, place_entries) do
    entries = normalize_entries(gall_species_id, place_entries)

    Repo.transaction(fn ->
      from(gre in GallRangeExclusion, where: gre.species_id == ^gall_species_id)
      |> Repo.delete_all()

      if entries != [], do: Repo.insert_all(GallRangeExclusion, entries)
      :ok
    end)
  end

  @doc """
  Gets excluded places with precision metadata for a gall species.
  """
  @spec get_excluded_places_with_precision_for_gall(integer()) :: [map()]
  def get_excluded_places_with_precision_for_gall(gall_species_id) do
    from(p in Place,
      join: gre in GallRangeExclusion,
      on: gre.place_id == p.id,
      where: gre.species_id == ^gall_species_id,
      select: %{code: p.code, precision: gre.precision}
    )
    |> Repo.all()
  end

  @doc """
  Toggles a place exclusion for a gall (add if not excluded, remove if excluded).
  Returns {:added, place_id} or {:removed, place_id}.

  Note: "added" means the place is now EXCLUDED from the gall's range.
  """
  @spec toggle_exclusion_for_gall(integer(), integer()) ::
          {:added, integer()} | {:removed, integer()} | {:error, term()}
  def toggle_exclusion_for_gall(gall_species_id, place_id) do
    Repo.transaction(fn ->
      query =
        from(gre in GallRangeExclusion,
          where: gre.species_id == ^gall_species_id and gre.place_id == ^place_id
        )

      case Repo.one(query) do
        nil ->
          # Add exclusion (place is now excluded)
          %GallRangeExclusion{}
          |> GallRangeExclusion.changeset(%{species_id: gall_species_id, place_id: place_id})
          |> Repo.insert!()

          {:added, place_id}

        _existing ->
          # Remove exclusion (place is now in range)
          Repo.delete_all(query)
          {:removed, place_id}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
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
  # Private helpers
  # ============================================

  defp normalize_entries(species_id, entries) do
    Enum.map(entries, fn
      {place_id, precision} ->
        %{species_id: species_id, place_id: place_id, precision: precision}

      place_id when is_integer(place_id) ->
        %{species_id: species_id, place_id: place_id, precision: "exact"}
    end)
  end
end
