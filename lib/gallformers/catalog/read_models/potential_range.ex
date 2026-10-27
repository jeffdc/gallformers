defmodule Gallformers.Catalog.ReadModels.PotentialRange do
  @moduledoc """
  A Gall's potential range (`9449` §4; `8567` rule 10): where it could
  occur.

    1. The union of the ranges (`host_range`, native and introduced) of the
       plant taxa that are its current Hosts (`host_of`), read by
       `host_range.taxon_id`. A Host above species rank (a genus or
       section: today's "Genus spp" placeholders became genus Hosts) is
       the union of the ranges of every taxon in its subtree — the Gall can
       occur wherever any species of the genus grows (`803b` decision 8) —
       plus any rows stored on the genus itself (the data migration re-keys
       a genus placeholder's rows to the genus taxon,
       `Gallformers.CatalogMigration`). A species-rank Host reads its own
       rows only.
    2. Then its current range adjustments: `only` restricts it to those
       places, `exclude` removes places.

  Nothing widens it: a Gall's range never leaves every one of its Hosts'
  ranges. A place where a Source says the Gall occurs but none of its Hosts
  grows is a recorded occurrence, which this range does not read.

  **Missing data is not absence.** A Gall with no Host range data (no Host,
  or Hosts without range rows) appears in every region, as today
  (`search.ex`, "Galls with no range data should appear in every region"),
  so its range is `:everywhere`, never an empty list. Adjustments still
  apply to it: `only` gives it that range, and `exclude` leaves every other
  selectable place (`Gallformers.Places.list_places/0`). Following the plan,
  any computation that ends empty is `:everywhere` too.

  Places are compared as leaves: a country-level host-range row, or an
  adjustment naming a country, stands for the country's subdivisions (as
  `Gallformers.Ranges` expands country precision); a place with no
  subdivisions stands for itself. The result is a list of leaf places by
  code. `for_display/1` splits the same places for a map (exact,
  country-level, introduced), as `Gallformers.Ranges` splits host ranges.

  Computed on read from current Facts; the ID tool's lookup table
  (`Gallformers.Catalog.ReadModels.GallIndex`) stores `for_galls/1`'s
  result.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Places
  alias Gallformers.Places.Place
  alias Gallformers.Ranges
  alias Gallformers.Ranges.DisplayRange
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon

  @type place :: %{place_id: integer(), code: String.t()}

  @type t :: :everywhere | [place(), ...]

  @doc "A Gall's potential range: `:everywhere`, or its leaf places by code."
  @spec for_gall(integer()) :: t()
  def for_gall(gall_id) when is_integer(gall_id),
    do: gall_id |> List.wrap() |> for_galls() |> Map.fetch!(gall_id)

  @doc """
  The potential ranges of the Galls among `gall_ids`, by Gall ID, each as
  `for_gall/1` gives it (which is this for one Gall), in a few queries for
  all of them: the ID tool's lookup table
  (`Gallformers.Catalog.ReadModels.GallIndex`) is rebuilt with it.
  """
  @spec for_galls([integer()]) :: %{integer() => t()}
  def for_galls([]), do: %{}

  def for_galls(gall_ids) when is_list(gall_ids) do
    gall_ids = Enum.uniq(gall_ids)
    hosts = range_taxa(gall_ids)

    host_places =
      from(hr in "host_range",
        where: hr.taxon_id in ^Enum.uniq(List.flatten(Map.values(hosts))),
        distinct: true,
        select: {hr.taxon_id, hr.place_id}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    adjustments =
      from(r in Current.range_adjustments(gall_ids),
        select: {r.gall_id, r.adjustment, r.place_id}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})

    leaves_of =
      Places.leaf_descendant_ids_by_place(
        List.flatten(Map.values(host_places)) ++
          for({_gall, adjusted} <- adjustments, {_kind, place_id} <- adjusted, do: place_id)
      )

    leaves = &(&1 |> Enum.flat_map(fn id -> Map.get(leaves_of, id, []) end) |> Enum.uniq())
    selectable = if adjustments == %{}, do: [], else: Enum.map(Places.list_places(), & &1.id)

    gall_ids
    |> Map.new(fn gall_id ->
      adjusted = adjustments |> Map.get(gall_id, []) |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

      host_leaves =
        hosts |> Map.get(gall_id, []) |> Enum.flat_map(&Map.get(host_places, &1, [])) |> leaves.()

      range =
        case host_leaves do
          [] -> :everywhere
          ids -> ids
        end
        |> restrict(leaves.(Map.get(adjusted, :only, [])))
        |> exclude(leaves.(Map.get(adjusted, :exclude, [])), selectable)

      {gall_id, range}
    end)
    |> places()
  end

  @doc """
  A Gall's potential range as a map shows it: `:everywhere` when the range
  is, else its places split for colouring (`Gallformers.Ranges.DisplayRange`)
  as the `host_range` rows of its current Hosts (a Host above species rank
  with its subtree, as `for_gall/1` reads them) give them
  (`Gallformers.Ranges.get_display_range_for_taxa/1`): exact, country-level
  (inherited) and introduced. Places an `exclude` removed or an `only` left
  out are not shown; an `only` place no Host row gives (a Gall with no Host
  range data) is shown as exact. The places shown are always `for_gall/1`'s.
  """
  @spec for_display(integer()) :: :everywhere | DisplayRange.t()
  def for_display(gall_id) when is_integer(gall_id) do
    case for_gall(gall_id) do
      :everywhere ->
        :everywhere

      places ->
        codes = MapSet.new(places, & &1.code)
        hosts = gall_id |> List.wrap() |> range_taxa() |> Map.get(gall_id, [])
        hosts = Ranges.get_display_range_for_taxa(hosts)
        keep = &Enum.filter(&1, fn code -> MapSet.member?(codes, code) end)
        inherited = keep.(hosts.inherited_range)

        %DisplayRange{
          in_range: codes |> MapSet.difference(MapSet.new(inherited)) |> Enum.sort(),
          inherited_range: inherited,
          introduced_range: keep.(hosts.introduced_range)
        }
    end
  end

  # The taxa whose `host_range` rows make each Gall's range, by Gall ID: its
  # current Hosts, a Host above species rank (a genus or section, today's
  # "Genus spp" placeholders) with every taxon in its subtree (`803b`
  # decision 8). Galls without a current Host are left out.
  defp range_taxa(gall_ids) do
    hosts =
      Repo.all(
        from(r in Current.relationships("host_of"),
          join: t in Taxon,
          on: t.id == r.subject_taxon_id,
          where: r.object_gall_id in ^gall_ids,
          select: {r.object_gall_id, r.subject_taxon_id, t.rank}
        )
      )

    subtrees =
      hosts
      |> Enum.reject(fn {_gall, _taxon, rank} -> rank in Rank.species_and_below() end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Taxa.subtree_ids()

    Enum.group_by(
      hosts,
      &elem(&1, 0),
      fn {_gall, taxon_id, _rank} -> Map.get(subtrees, taxon_id, [taxon_id]) end
    )
    |> Map.new(fn {gall_id, taxa} -> {gall_id, taxa |> List.flatten() |> Enum.uniq()} end)
  end

  # Ranges are lists of leaf place IDs, or :everywhere. `selectable` is
  # every selectable place's ID (`Gallformers.Places.list_places/0`).

  defp restrict(range, []), do: range
  defp restrict(:everywhere, only), do: only

  defp restrict(range, only) do
    only = MapSet.new(only)
    Enum.filter(range, &MapSet.member?(only, &1))
  end

  defp exclude(range, [], _selectable), do: range
  defp exclude(:everywhere, excluded, selectable), do: exclude(selectable, excluded, selectable)

  defp exclude(range, excluded, _selectable) do
    excluded = MapSet.new(excluded)
    Enum.reject(range, &MapSet.member?(excluded, &1))
  end

  # Each range's places by code, in one query; a range left with no known
  # place is :everywhere.
  defp places(ranges) do
    ids = for {_gall, ids} when is_list(ids) <- ranges, id <- ids, uniq: true, do: id

    by_code =
      Repo.all(
        from(p in Place,
          where: p.id in ^ids,
          order_by: p.code,
          select: %{place_id: p.id, code: p.code}
        )
      )

    position = by_code |> Enum.with_index() |> Map.new(fn {place, i} -> {place.place_id, i} end)
    by_id = Map.new(by_code, &{&1.place_id, &1})

    Map.new(ranges, fn
      {gall_id, :everywhere} ->
        {gall_id, :everywhere}

      {gall_id, ids} ->
        case ids |> Enum.filter(&Map.has_key?(by_id, &1)) |> Enum.sort_by(&position[&1]) do
          [] -> {gall_id, :everywhere}
          known -> {gall_id, Enum.map(known, &by_id[&1])}
        end
    end)
  end
end
