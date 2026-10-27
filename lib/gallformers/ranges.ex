defmodule Gallformers.Ranges do
  @moduledoc """
  The Ranges context.

  Manages the Host ranges of plant taxa (the `host_range` table, by
  `taxon_id`): where host plants grow.

  A Gall's range is `Gallformers.Catalog.potential_range/1` (its Hosts'
  ranges); its map split comes from `get_display_range_for_taxa/1`. The old
  model's stored Gall range (`gall_range`) is read only by the data
  migration and the old ID filter (`Gallformers.Galls.Identification`).

  See `docs/architecture/range-system.md` for the full range system architecture.
  """
  use Boundary,
    deps: [
      Gallformers.Audit,
      Gallformers.Repo,
      Gallformers.ChangesetHelpers,
      Gallformers.SchemaFields,
      Gallformers.Places,
      Gallformers.Taxa,
      Gallformers.TextMatch,
      Gallformers.Wcvp
    ],
    exports: :all

  import Ecto.Query

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Places
  alias Gallformers.Places.Place
  alias Gallformers.Ranges.{DisplayRange, HostRange}
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Event
  alias Gallformers.Taxa.Events

  # ============================================
  # Host Ranges by taxon
  # ============================================

  @typedoc "A Host range row as the range editor reads it."
  @type place_entry :: %{
          code: String.t(),
          precision: String.t(),
          place_id: integer(),
          distribution_type: String.t()
        }

  @typedoc """
  A place for `update_taxon_places/3`: `{place_id, precision,
  distribution_type}`, `{place_id, precision}` (native) or a place ID
  (exact, native).
  """
  @type taxon_place ::
          {integer(), String.t(), String.t()} | {integer(), String.t()} | integer()

  @doc """
  A plant taxon's `host_range` rows, by `taxon_id`: each place's code,
  precision, ID and distribution type.
  """
  @spec get_places_for_taxon_with_precision(integer()) :: [place_entry()]
  def get_places_for_taxon_with_precision(taxon_id) when is_integer(taxon_id) do
    from(hr in HostRange,
      join: p in Place,
      on: hr.place_id == p.id,
      where: hr.taxon_id == ^taxon_id,
      order_by: p.code,
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
  Replaces a plant taxon's Host range (`host_range` by `taxon_id`) with
  `entries` (`t:taxon_place/0`), as `actor`. A place given twice is kept
  once, native first. A migrated plant (one with a `species` row of the
  same ID) keeps its species ID on the rows, for today's code; a plant
  created since has none.

  `host_range` is not an audited table (Carbonite would record every row of
  ~1M on each data migration run): the write runs in an audit transaction
  naming `actor`, and the taxonomy admin's write path
  (`Gallformers.Import.record_taxonomy_edit/2`, `:set_host_range`) logs the
  whole new range in the audited replay log.

  The Galls whose potential range reads the taxon's rows — those with it,
  or a genus or section above it, as a Host — get their ID tool rows
  refreshed: a `:host_range` "taxon changed" event
  (`Gallformers.Taxa.Events`). Returns how many rows the taxon now has.
  """
  @spec update_taxon_places(Actor.t(), Taxa.taxon_ref(), [taxon_place()]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def update_taxon_places(%Actor{} = actor, taxon, entries) when is_list(entries) do
    taxon_id = taxon_ref_id(taxon)

    Audit.transaction(actor, "ranges.update_taxon_places", fn ->
      species_id = migrated_species_id(taxon_id)

      rows =
        for {place_id, precision, distribution_type} <- normalize_taxon_places(entries) do
          %{
            taxon_id: taxon_id,
            species_id: species_id,
            place_id: place_id,
            precision: precision,
            distribution_type: distribution_type
          }
        end

      from(hr in HostRange, where: hr.taxon_id == ^taxon_id) |> Repo.delete_all()

      # A migrated plant's rows written by today's code without a taxon.
      if species_id,
        do:
          from(hr in HostRange, where: hr.species_id == ^species_id and is_nil(hr.taxon_id))
          |> Repo.delete_all()

      {count, _} = Repo.insert_all(HostRange, rows)
      :ok = Events.dispatch(%Event{type: :host_range, taxon_id: taxon_id})
      count
    end)
  end

  defp taxon_ref_id(%{id: id}), do: id
  defp taxon_ref_id(id) when is_integer(id), do: id

  # Plant taxa keep their species IDs through the data migration.
  defp migrated_species_id(taxon_id) do
    Repo.one(
      from(s in "species",
        where: s.id == ^taxon_id and s.taxoncode == "plant",
        select: s.id
      )
    )
  end

  @doc """
  `update_taxon_places/3`'s entries as it writes them: each
  `{place_id, precision, distribution_type}`, a place given twice kept once
  (native first), in the order given.
  """
  @spec normalize_taxon_places([taxon_place()]) :: [{integer(), String.t(), String.t()}]
  def normalize_taxon_places(entries) when is_list(entries) do
    entries
    |> Enum.map(fn
      {place_id, precision, distribution_type} -> {place_id, precision, distribution_type}
      {place_id, precision} -> {place_id, precision, "native"}
      place_id when is_integer(place_id) -> {place_id, "exact", "native"}
    end)
    |> Enum.with_index()
    |> Enum.sort_by(fn {{_place, _precision, distribution}, i} ->
      {distribution != "native", i}
    end)
    |> Enum.uniq_by(fn {{place_id, _, _}, _i} -> place_id end)
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  # ============================================
  # Range entries expanded to leaf places
  # ============================================

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
end
