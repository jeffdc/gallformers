defmodule Gallformers.Ranges.Wcvp do
  @moduledoc """
  WCVP (the World Checklist of Vascular Plants) for plant taxa (`a856`
  Task 8): a plant's link to its WCVP record, its Host range taken from
  WCVP, and the bulk range review — by taxon: the successor on the new
  back-end of the old Host admin's, which worked by species
  (`host_traits`).

  The link is a `Gallformers.Ranges.TaxonWcvp` (audited). A sync writes the
  plant's range through `Gallformers.Ranges.update_taxon_places/3`. Every
  write is audited as the given actor; the taxonomy admin's writes go
  through `Gallformers.Import.record_wcvp_edit/2`, which also records them
  in the replay log.

  The WCVP data comes from the configured lookup (`:wcvp_lookup`, default
  `Gallformers.Wcvp.Lookup`; a stub in tests).
  """
  import Ecto.Query

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Places
  alias Gallformers.Ranges
  alias Gallformers.Ranges.HostRange
  alias Gallformers.Ranges.TaxonWcvp
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TaxonName
  alias Gallformers.TextMatch
  alias Gallformers.Wcvp.Tdwg

  @typedoc "Preloaded data for syncing many plants (`load_sync_ref_data/0`)."
  @type ref_data :: %{optional(:tdwg_lookup) => map(), optional(:place_code_to_id) => map()}

  @typedoc "What a sync did: how many WCVP regions, and the places written."
  @type sync_summary :: %{
          native_count: non_neg_integer(),
          introduced_count: non_neg_integer(),
          total_places: non_neg_integer()
        }

  defp lookup, do: Application.get_env(:gallformers, :wcvp_lookup, Gallformers.Wcvp.Lookup)

  # -- the link ----------------------------------------------------------------

  @doc "A plant taxon's WCVP link, or nil when it has none."
  @spec get_link(integer()) :: TaxonWcvp.t() | nil
  def get_link(taxon_id) when is_integer(taxon_id), do: Repo.get(TaxonWcvp, taxon_id)

  @doc "The plant taxa linked to the WCVP record `wcvp_id`, by ID."
  @spec linked_taxon_ids(String.t()) :: [integer()]
  def linked_taxon_ids(wcvp_id) when is_binary(wcvp_id) do
    Repo.all(
      from(w in TaxonWcvp, where: w.wcvp_id == ^wcvp_id, order_by: w.taxon_id, select: w.taxon_id)
    )
  end

  @doc """
  Sets fields of a plant taxon's WCVP link (`Gallformers.Ranges.TaxonWcvp`),
  creating it when there is none. A new `wcvp_id` clears a `no_match`
  status but keeps `ignored`, unless `attrs` gives the status.
  """
  @spec put_link(Actor.t(), Taxa.taxon_ref(), map()) ::
          {:ok, TaxonWcvp.t()} | {:error, Ecto.Changeset.t()}
  def put_link(%Actor{} = actor, taxon, attrs) when is_map(attrs) do
    Audit.transaction(actor, "ranges.wcvp.put_link", fn ->
      taxon_id = taxon_id(taxon)
      link = get_link(taxon_id) || %TaxonWcvp{taxon_id: taxon_id}

      link
      |> TaxonWcvp.changeset(link_attrs(link, attrs))
      |> Repo.insert_or_update()
      |> unwrap_or_rollback()
    end)
  end

  defp link_attrs(link, attrs) do
    cond do
      Map.has_key?(attrs, :wcvp_match_status) -> attrs
      Map.get(attrs, :wcvp_id) in [nil, ""] -> attrs
      link.wcvp_match_status == "ignored" -> attrs
      true -> Map.put(attrs, :wcvp_match_status, nil)
    end
  end

  @doc """
  Links a plant taxon to the WCVP record its accepted name matches
  (synonyms resolved), without taking its range. `{:ok, :already_linked}`
  when it has a link. When nothing matches, its status becomes `no_match`
  (an `ignored` plant stays ignored) and `{:error, message}` is returned.
  """
  @spec match(Actor.t(), Taxa.taxon_ref()) ::
          {:ok, :linked | :already_linked} | {:error, String.t()}
  def match(%Actor{} = actor, taxon) do
    actor
    |> Audit.transaction("ranges.wcvp.match", fn ->
      case ensure_link(actor, taxon_id(taxon)) do
        {:ok, _link, status} -> {:ok, status}
        {:error, message} -> {:error, message}
      end
    end)
    |> flatten()
  end

  defp ensure_link(actor, taxon_id) do
    case get_link(taxon_id) do
      %TaxonWcvp{wcvp_id: id} = link when id not in [nil, ""] ->
        {:ok, link, :already_linked}

      link ->
        link_by_name(actor, taxon_id, link)
    end
  end

  defp link_by_name(actor, taxon_id, link) do
    name = Taxa.accepted_name(taxon_id)

    case lookup().match_by_name(name, resolve_synonyms: true) do
      nil ->
        status = if link && link.wcvp_match_status == "ignored", do: "ignored", else: "no_match"
        {:ok, _} = put_link(actor, taxon_id, %{wcvp_match_status: status})
        {:error, "No WCVP match found for #{name}"}

      found ->
        {:ok, link} =
          put_link(actor, taxon_id, %{wcvp_id: found.plant_name_id, powo_id: found.powo_id})

        {:ok, link, :linked}
    end
  end

  # -- sync --------------------------------------------------------------------

  @doc """
  Takes a plant taxon's Host range from WCVP: links it first if it has no
  link (`match/2`), then replaces its range
  (`Gallformers.Ranges.update_taxon_places/3`) with WCVP's native and
  introduced regions as places, and stamps `wcvp_synced_at`. `ref_data`
  (`load_sync_ref_data/0`) saves reloading the region mapping per plant in
  a bulk sync. `{:error, message}` when it cannot be linked or WCVP has no
  such record; its range is then left as it is.
  """
  @spec sync(Actor.t(), Taxa.taxon_ref(), ref_data()) ::
          {:ok, sync_summary()} | {:error, String.t()}
  def sync(%Actor{} = actor, taxon, ref_data \\ %{}) do
    taxon_id = taxon_id(taxon)

    actor
    |> Audit.transaction("ranges.wcvp.sync", fn ->
      with {:ok, link, _status} <- ensure_link(actor, taxon_id),
           %{} = record <- lookup().get(link.wcvp_id) || {:error, not_found(link)} do
        {entries, native_count, introduced_count} = range_entries(record, ref_data)
        {:ok, total} = Ranges.update_taxon_places(actor, taxon_id, entries)

        {:ok, _} =
          put_link(actor, taxon_id, %{wcvp_synced_at: DateTime.utc_now(:second)})

        {:ok,
         %{native_count: native_count, introduced_count: introduced_count, total_places: total}}
      end
    end)
    |> flatten()
  end

  defp not_found(link), do: "WCVP record not found for ID #{link.wcvp_id}"

  @doc """
  The Host range entries for a WCVP record (`{place_id, precision,
  distribution_type}`, as `Gallformers.Ranges.update_taxon_places/3` and
  today's `update_host_places/2` take them), with how many native and
  introduced regions it maps. Regions with no place here are left out.
  """
  @spec range_entries(map(), ref_data()) ::
          {[{integer(), String.t(), String.t()}], non_neg_integer(), non_neg_integer()}
  def range_entries(record, ref_data \\ %{}) do
    tdwg = Map.get_lazy(ref_data, :tdwg_lookup, &Tdwg.load/0)
    code_to_id = Map.get_lazy(ref_data, :place_code_to_id, &place_code_to_id/0)

    native = Tdwg.convert_tdwg_codes(record.native_distribution, tdwg)
    introduced = Tdwg.convert_tdwg_codes(record.introduced_distribution, tdwg)

    entries =
      for {places, distribution} <- [{native, "native"}, {introduced, "introduced"}],
          %{code: code, precision: precision} <- places,
          place_id = code_to_id[code],
          place_id != nil,
          do: {place_id, precision, distribution}

    {entries, length(native), length(introduced)}
  end

  @doc "The region mapping and place IDs a bulk sync loads once (`sync/3`)."
  @spec load_sync_ref_data() :: ref_data()
  def load_sync_ref_data, do: %{tdwg_lookup: Tdwg.load(), place_code_to_id: place_code_to_id()}

  defp place_code_to_id, do: Map.new(Places.list_all_places(), &{&1.code, &1.id})

  @doc """
  The difference between a range and WCVP's, in six buckets (the 3×3
  state matrix: existing native / introduced / absent against WCVP
  native / introduced / absent). `range_entries` is
  `%{code => %{precision, distribution_type}}`; the WCVP sides are place
  codes already converted from TDWG.

  | Existing \\ POWO | Not present | Native               | Introduced               |
  |------------------|-------------|----------------------|--------------------------|
  | Not present      | no-op       | add_native           | add_introduced           |
  | Native           | remove      | agree                | reclassify_to_introduced |
  | Introduced       | remove      | reclassify_to_native | agree                    |
  """
  @spec compute_powo_diff(map(), MapSet.t(), MapSet.t()) :: map()
  def compute_powo_diff(range_entries, native_codes, introduced_codes) do
    current_codes = MapSet.new(Map.keys(range_entries))
    all_powo = MapSet.union(native_codes, introduced_codes)
    current_native = codes_of(range_entries, "native")
    current_introduced = codes_of(range_entries, "introduced")

    add_native = MapSet.difference(native_codes, current_codes)
    add_introduced = MapSet.difference(introduced_codes, current_codes)
    remove = MapSet.difference(current_codes, all_powo)
    reclassify_to_introduced = MapSet.intersection(current_native, introduced_codes)
    reclassify_to_native = MapSet.intersection(current_introduced, native_codes)

    agree_count =
      MapSet.size(MapSet.intersection(current_native, native_codes)) +
        MapSet.size(MapSet.intersection(current_introduced, introduced_codes))

    changes = [add_native, add_introduced, remove, reclassify_to_introduced, reclassify_to_native]

    %{
      add_native: MapSet.to_list(add_native),
      add_introduced: MapSet.to_list(add_introduced),
      remove: MapSet.to_list(remove),
      reclassify_to_introduced: MapSet.to_list(reclassify_to_introduced),
      reclassify_to_native: MapSet.to_list(reclassify_to_native),
      agree_count: agree_count,
      has_changes: Enum.any?(changes, &(MapSet.size(&1) > 0))
    }
  end

  defp codes_of(range_entries, distribution) do
    for {code, %{distribution_type: ^distribution}} <- range_entries, into: MapSet.new(), do: code
  end

  # -- bulk review -------------------------------------------------------------

  @doc """
  Marks plant taxa's ranges as confirmed by a curator. Returns how many
  were marked.
  """
  @spec bulk_confirm_ranges(Actor.t(), [integer()]) :: {:ok, non_neg_integer()} | {:error, term()}
  def bulk_confirm_ranges(%Actor{} = actor, taxon_ids) when is_list(taxon_ids),
    do: bulk_put(actor, "ranges.wcvp.bulk_confirm_ranges", taxon_ids, range_confirmed: true)

  @doc """
  Leaves plant taxa out of WCVP matching and sync (status `ignored`); their
  links stay. Returns how many were marked.
  """
  @spec bulk_ignore(Actor.t(), [integer()]) :: {:ok, non_neg_integer()} | {:error, term()}
  def bulk_ignore(%Actor{} = actor, taxon_ids) when is_list(taxon_ids),
    do: bulk_put(actor, "ranges.wcvp.bulk_ignore", taxon_ids, wcvp_match_status: "ignored")

  @doc "Clears plant taxa's WCVP match status. Returns how many links changed."
  @spec bulk_clear_match_status(Actor.t(), [integer()]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def bulk_clear_match_status(%Actor{} = actor, taxon_ids) when is_list(taxon_ids) do
    Audit.transaction(actor, "ranges.wcvp.bulk_clear_match_status", fn ->
      {count, _} =
        from(w in TaxonWcvp, where: w.taxon_id in ^taxon_ids and not is_nil(w.wcvp_match_status))
        |> Repo.update_all(set: [wcvp_match_status: nil, updated_at: DateTime.utc_now(:second)])

      count
    end)
  end

  defp bulk_put(_actor, _operation, [], _set), do: {:ok, 0}

  defp bulk_put(actor, operation, taxon_ids, set) do
    Audit.transaction(actor, operation, fn ->
      now = DateTime.utc_now(:second)
      fields = Keyword.keys(set) ++ [:updated_at]

      rows =
        for id <- Enum.uniq(taxon_ids) do
          Map.merge(Map.new(set), %{taxon_id: id, inserted_at: now, updated_at: now})
        end

      {count, _} =
        Repo.insert_all(TaxonWcvp, rows,
          on_conflict: {:replace, fields},
          conflict_target: :taxon_id
        )

      count
    end)
  end

  @typedoc "A plant in the range review list."
  @type review_row :: %{
          id: integer(),
          name: String.t(),
          family_name: String.t() | nil,
          genus_name: String.t() | nil,
          range_count: non_neg_integer(),
          wcvp_id: String.t() | nil,
          wcvp_match_status: String.t() | nil,
          wcvp_synced_at: DateTime.t() | nil,
          range_confirmed: boolean()
        }

  @doc """
  Plants (Plantae at species rank or below) for range review, by name,
  each with its genus and family, how many range rows it has and its WCVP
  link. Options:

    * `:filter` — `:unconfirmed` (default; with `:wcvp_built_at`, also
      those synced before that WCVP build), `:confirmed`, `:all`
    * `:wcvp_match` — `:active` (default: not ignored), `:all`, `:linked`,
      `:unmatched`, `:no_match`, `:ignored`
    * `:has_range` — `:all` (default), `:yes`, `:no`
    * `:sync_status` — `:all` (default), `:never`, `:stale`, `:current`
      (against `:wcvp_built_at`)
    * `:search` — every word in the plant's, its genus's or its family's name
    * `:limit` (default 50), `:offset` (default 0)
  """
  @spec list_for_range_review(keyword()) :: [review_row()]
  def list_for_range_review(opts \\ []) do
    opts
    |> review_query()
    |> order_by([name: n, taxon: t], [n.name, t.id])
    |> limit(^Keyword.get(opts, :limit, 50))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> select([taxon: t, name: n, link: w, range: hr, genus: g, family: f], %{
      id: t.id,
      name: n.name,
      family_name: f.name,
      genus_name: g.name,
      range_count: count(hr.place_id),
      wcvp_id: w.wcvp_id,
      wcvp_match_status: w.wcvp_match_status,
      wcvp_synced_at: w.wcvp_synced_at,
      range_confirmed: coalesce(w.range_confirmed, false)
    })
    |> Repo.all()
  end

  @doc """
  Every plant `list_for_range_review/1`'s filters select, without paging,
  as `%{id, name}` by name: what a bulk action on the whole list acts on.
  """
  @spec list_refs_for_range_review(keyword()) :: [%{id: integer(), name: String.t()}]
  def list_refs_for_range_review(opts \\ []) do
    opts
    |> review_query()
    |> order_by([name: n, taxon: t], [n.name, t.id])
    |> select([taxon: t, name: n], %{id: t.id, name: n.name})
    |> Repo.all()
  end

  @doc "How many plants `list_for_range_review/1`'s filters select."
  @spec count_for_range_review(keyword()) :: non_neg_integer()
  def count_for_range_review(opts \\ []) do
    ids = opts |> review_query() |> select([taxon: t], t.id)
    Repo.one(from(x in subquery(ids), select: count()))
  end

  defp review_query(opts) do
    built_at = Keyword.get(opts, :wcvp_built_at)

    from(t in Taxon,
      as: :taxon,
      join: n in TaxonName,
      as: :name,
      on: n.taxon_id == t.id and n.status == :accepted,
      left_join: w in TaxonWcvp,
      as: :link,
      on: w.taxon_id == t.id,
      left_join: hr in HostRange,
      as: :range,
      on: hr.taxon_id == t.id,
      left_join: g in subquery(ancestor_named(:genus)),
      as: :genus,
      on: g.taxon_id == t.id,
      left_join: f in subquery(ancestor_named(:family)),
      as: :family,
      on: f.taxon_id == t.id,
      where: t.kingdom == "Plantae" and t.rank in ^Rank.species_and_below(),
      group_by: [t.id, n.name, w.taxon_id, g.name, f.name]
    )
    |> filter_confirmed(Keyword.get(opts, :filter, :unconfirmed), built_at)
    |> filter_match(Keyword.get(opts, :wcvp_match, :active))
    |> filter_has_range(Keyword.get(opts, :has_range, :all))
    |> filter_sync(Keyword.get(opts, :sync_status, :all), built_at)
    |> filter_search(TextMatch.parse_terms(Keyword.get(opts, :search)))
  end

  # Each taxon with the accepted name of its ancestor of `rank`.
  defp ancestor_named(rank) do
    from(a in "taxon_ancestry",
      join: x in Taxon,
      on: x.id == a.ancestor_id and x.rank == ^rank,
      join: xn in TaxonName,
      on: xn.taxon_id == x.id and xn.status == :accepted,
      select: %{taxon_id: a.descendant_id, name: xn.name}
    )
  end

  defp filter_confirmed(query, :all, _built_at), do: query

  defp filter_confirmed(query, :confirmed, _built_at),
    do: where(query, [link: w], w.range_confirmed == true)

  defp filter_confirmed(query, :unconfirmed, nil),
    do: where(query, [link: w], is_nil(w.range_confirmed) or w.range_confirmed == false)

  defp filter_confirmed(query, :unconfirmed, built_at) do
    where(
      query,
      [link: w],
      is_nil(w.range_confirmed) or w.range_confirmed == false or
        (not is_nil(w.wcvp_synced_at) and w.wcvp_synced_at < ^built_at)
    )
  end

  defp filter_match(query, :all), do: query

  defp filter_match(query, :active),
    do: where(query, [link: w], is_nil(w.wcvp_match_status) or w.wcvp_match_status != "ignored")

  defp filter_match(query, :linked), do: where(query, [link: w], not is_nil(w.wcvp_id))

  defp filter_match(query, :unmatched),
    do: where(query, [link: w], is_nil(w.wcvp_id) and is_nil(w.wcvp_match_status))

  defp filter_match(query, status) when status in [:no_match, :ignored],
    do: where(query, [link: w], w.wcvp_match_status == ^Atom.to_string(status))

  defp filter_has_range(query, :all), do: query
  defp filter_has_range(query, :yes), do: having(query, [range: hr], count(hr.place_id) > 0)
  defp filter_has_range(query, :no), do: having(query, [range: hr], count(hr.place_id) == 0)

  defp filter_sync(query, :all, _built_at), do: query

  defp filter_sync(query, :never, _built_at),
    do: where(query, [link: w], is_nil(w.wcvp_synced_at))

  defp filter_sync(query, :stale, nil), do: query

  defp filter_sync(query, :stale, built_at),
    do: where(query, [link: w], w.wcvp_synced_at < ^built_at)

  defp filter_sync(query, :current, nil),
    do: where(query, [link: w], not is_nil(w.wcvp_synced_at))

  defp filter_sync(query, :current, built_at),
    do: where(query, [link: w], w.wcvp_synced_at >= ^built_at)

  defp filter_search(query, terms) do
    Enum.reduce(terms, query, fn term, query ->
      where(
        query,
        [name: n, genus: g, family: f],
        ilike(n.name, ^term) or ilike(coalesce(g.name, ""), ^term) or
          ilike(coalesce(f.name, ""), ^term)
      )
    end)
  end

  # -- helpers -----------------------------------------------------------------

  defp taxon_id(%Taxon{id: id}), do: id
  defp taxon_id(id) when is_integer(id), do: id

  # An audited transaction whose function returned {:ok, _} or {:error, _}
  # without rolling back (a no-match status is kept).
  defp flatten({:ok, {:ok, _} = ok}), do: ok
  defp flatten({:ok, {:error, _} = error}), do: error
  defp flatten({:error, reason}), do: {:error, reason}

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
