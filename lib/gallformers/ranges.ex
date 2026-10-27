defmodule Gallformers.Ranges do
  @moduledoc """
  The Ranges context.

  Manages geographic range data for species:
  - **Host ranges** (host_range table): Where host plants exist geographically
  - **Gall ranges** (gall_range table): Curated stored range for gall species

  A Gall's range on the new back-end is `Gallformers.Catalog.potential_range/1`
  (its Hosts' ranges, read by `host_range.taxon_id`); its map split comes
  from `get_display_range_for_taxa/1`. The old admin still reads and writes
  `gall_range`.

  See `docs/architecture/range-system.md` for the full range system architecture.
  """
  use Boundary,
    deps: [
      Gallformers.Repo,
      Gallformers.ChangesetHelpers,
      Gallformers.SchemaFields,
      Gallformers.Species,
      Gallformers.Places
    ],
    exports: :all

  import Ecto.Query

  alias Gallformers.Places
  alias Gallformers.Places.Place
  alias Gallformers.Ranges.{DisplayRange, GallRange, HostRange}
  alias Gallformers.Repo

  # ============================================
  # Host Range Queries
  # ============================================

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

    result
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

    result
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
    entries =
      host_species_id
      |> normalize_entries(place_entries, distribution_type: true)
      |> dedup_by_place_id()

    result =
      Repo.transaction(fn ->
        from(hr in HostRange, where: hr.species_id == ^host_species_id) |> Repo.delete_all()
        if entries != [], do: Repo.insert_all(HostRange, entries)
        :ok
      end)

    result
  end

  # ============================================
  # Gall Range Queries (from gall_range table)
  # ============================================

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

  @doc """
  Expands raw range entries into effective leaf-level coverage.

  Exact entries win over country-level inherited coverage for the same leaf code.
  Returns a map of leaf code => metadata including the effective distribution type
  and the source entry that produced it.
  """
  @spec expand_range_entries_to_leaf_status(map()) :: %{String.t() => map()}
  def expand_range_entries_to_leaf_status(range_entries) when is_map(range_entries) do
    exact_status =
      range_entries
      |> Enum.filter(fn {_code, %{precision: precision}} -> precision == "exact" end)
      |> Map.new(fn {code, %{distribution_type: distribution_type}} ->
        {code,
         %{
           precision: "exact",
           distribution_type: distribution_type,
           source_code: code,
           source_precision: "exact"
         }}
      end)

    Enum.reduce(range_entries, exact_status, fn
      {code, %{precision: "country", distribution_type: distribution_type}}, acc ->
        case Places.get_place_by_code(code) do
          nil ->
            acc

          place ->
            expand_country_leaf_status(acc, code, distribution_type, place.id)
        end

      _, acc ->
        acc
    end)
  end

  @doc """
  Expands place entries into comparable leaf-level codes.

  Country-precision entries are expanded to their leaf descendants so callers can
  diff them against leaf-expanded current range coverage.
  """
  @spec expand_place_entries_to_leaf_codes([map()]) :: MapSet.t(String.t())
  def expand_place_entries_to_leaf_codes(place_entries) when is_list(place_entries) do
    place_entries
    |> Enum.flat_map(fn
      %{code: code, precision: "country"} ->
        case Places.get_place_by_code(code) do
          nil -> []
          place -> Places.leaf_descendant_codes(place.id)
        end

      %{code: code} ->
        [code]
    end)
    |> MapSet.new()
  end

  defp expand_country_leaf_status(acc, code, distribution_type, place_id) do
    place_id
    |> Places.leaf_descendant_codes()
    |> Enum.reduce(acc, fn leaf_code, expanded ->
      Map.put_new(expanded, leaf_code, %{
        precision: "exact",
        distribution_type: distribution_type,
        source_code: code,
        source_precision: "country"
      })
    end)
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

        # Exact native entries override inherited introduced country-level entries.
        # This lets curators mark an introduced country while clearing the
        # introduced status for specific documented subdivisions.
        exact_native_set =
          host_ranges
          |> Enum.filter(
            &(&1.precision == "exact" and Map.get(&1, :distribution_type) != "introduced")
          )
          |> Enum.map(& &1.code)
          |> MapSet.new()

        intro_set
        |> MapSet.intersection(all_range)
        |> MapSet.difference(exact_native_set)
        |> MapSet.to_list()
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
  Gets the display range of plant taxa: the union of their `host_range` rows,
  read by `host_range.taxon_id` (the new taxa key the catalog data migration
  fills; a genus taxon carries its former genus placeholder's rows), split
  for the map as `compute_display_range/2` with introduced places marked.
  """
  @spec get_display_range_for_taxa([integer()]) :: DisplayRange.t()
  def get_display_range_for_taxa([]), do: %DisplayRange{}

  def get_display_range_for_taxa(taxon_ids) when is_list(taxon_ids) do
    from(hr in HostRange,
      join: p in Place,
      on: hr.place_id == p.id,
      where: hr.taxon_id in ^taxon_ids,
      distinct: true,
      select: %{
        code: p.code,
        precision: hr.precision,
        place_id: p.id,
        distribution_type: hr.distribution_type
      }
    )
    |> Repo.all()
    |> compute_display_range(with_introduced: true)
  end

  @doc """
  The place codes of plant taxa's `host_range` rows as stored (a
  country-level row is its country's code), by `host_range.taxon_id`, each
  taxon's codes sorted; taxa without rows are left out.
  """
  @spec get_places_for_taxa([integer()]) :: %{integer() => [String.t()]}
  def get_places_for_taxa([]), do: %{}

  def get_places_for_taxa(taxon_ids) when is_list(taxon_ids) do
    from(hr in HostRange,
      join: p in Place,
      on: hr.place_id == p.id,
      where: hr.taxon_id in ^taxon_ids,
      distinct: true,
      order_by: [hr.taxon_id, p.code],
      select: {hr.taxon_id, p.code}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
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
          leaf_ids =
            entries
            |> Enum.map(& &1.place_id)
            |> Places.batch_leaf_descendant_ids()

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
  # Private helpers
  # ============================================

  # Deduplicates entries by place_id. Multiple TDWG botanical regions can map to
  # the same ISO place code (219 cases), so WCVP sync can produce the same
  # place_id with conflicting distribution types. Native wins over introduced.
  defp dedup_by_place_id(entries) do
    entries
    |> Enum.sort_by(fn entry -> if entry[:distribution_type] == "native", do: 0, else: 1 end)
    |> Enum.uniq_by(& &1.place_id)
  end

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
