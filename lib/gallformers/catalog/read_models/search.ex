defmodule Gallformers.Catalog.ReadModels.Search do
  @moduledoc """
  The gall part of the global search (`803b` Task 11).

  A Gall is found when every word of the query is in:

    * its display name (`name_override`, else `name`);
    * one of its current alias Facts, of any kind (common names, former
      labels, codes);
    * a name of its current Inducer at species rank or below — the
      accepted name or a synonym, as `Gallformers.Taxa.search_ids/2` matches
      them — so an old scientific name finds the Gall. A higher-rank
      Inducer's names (the genus or tribe of an undescribed Gall) find the
      taxon in the search's taxonomy results, not every Gall under it.

  Each Gall comes with its `aliases` (its current alias Facts, then its
  current Inducers' synonyms, as the Gall page shows them) and whether it is
  `undescribed`, read from the ID tool's lookup table (`gall_index`, which
  also holds the potential range the `:place_ids` option filters on). A
  Gall with no `gall_index` row yet has no Facts the table reads: it is
  undescribed and everywhere.
  """
  import Ecto.Query

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.TextMatch

  @type hit :: %{
          id: integer(),
          name: String.t(),
          undescribed: boolean(),
          aliases: [String.t()]
        }

  @doc """
  The Galls matching `query`, by display name. Options: `:place_ids` (a
  list of place IDs, e.g. a continent's descendants; `nil` for no filter)
  keeps only the Galls whose potential range has one of those places, and
  every Gall whose range is everywhere.
  """
  @spec galls(String.t(), keyword()) :: [hit()]
  def galls(query, opts) when is_binary(query) and is_list(opts) do
    case TextMatch.parse_terms(query) do
      [] -> []
      terms -> search(query, terms, opts[:place_ids])
    end
  end

  defp search(query, terms, place_ids) do
    by_alias =
      from(a in Current.aliases(),
        where: ^TextMatch.build_filter(query, [:name]),
        select: a.gall_id
      )

    inducer_ids = Taxa.search_ids(query, ranks: Rank.species_and_below())

    by_inducer =
      from(r in Current.relationships("inducer_of"),
        where: r.subject_taxon_id in ^inducer_ids,
        select: r.object_gall_id
      )

    found =
      dynamic(
        [g],
        ^display_name_matches(terms) or g.id in subquery(by_alias) or
          g.id in subquery(by_inducer)
      )

    from(g in Gall,
      left_join: i in GallIndex,
      on: i.gall_id == g.id,
      where: ^found,
      order_by: [fragment("COALESCE(?, ?)", g.name_override, g.name), g.id],
      select: %{
        id: g.id,
        name: fragment("COALESCE(?, ?)", g.name_override, g.name),
        undescribed: coalesce(i.undescribed, true)
      }
    )
    |> filter_places(place_ids)
    |> Repo.all()
    |> with_aliases()
  end

  defp display_name_matches(terms) do
    Enum.reduce(terms, dynamic(true), fn term, acc ->
      dynamic([g], ^acc and ilike(fragment("COALESCE(?, ?)", g.name_override, g.name), ^term))
    end)
  end

  defp filter_places(query, nil), do: query

  defp filter_places(query, place_ids) when is_list(place_ids) do
    where(
      query,
      [_g, i],
      coalesce(i.everywhere, true) or
        fragment("? && ?", i.place_ids, type(^place_ids, {:array, :id}))
    )
  end

  # Each Gall with its `aliases`: its current alias Facts, in the order
  # recorded, then its current Inducers' synonyms.
  defp with_aliases([]), do: []

  defp with_aliases(galls) do
    ids = Enum.map(galls, & &1.id)

    aliases =
      from(a in Current.aliases(ids), order_by: a.fact_id, select: {a.gall_id, a.name})
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    inducers =
      from(r in Current.relationships("inducer_of"),
        where: r.object_gall_id in ^ids,
        distinct: true,
        order_by: [r.object_gall_id, r.subject_taxon_id],
        select: {r.object_gall_id, r.subject_taxon_id}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    synonyms = inducers |> Map.values() |> List.flatten() |> Taxa.list_synonyms_by_taxon()

    Enum.map(galls, fn gall ->
      inducer_synonyms =
        inducers
        |> Map.get(gall.id, [])
        |> Enum.flat_map(&Map.get(synonyms, &1, []))
        |> Enum.map(& &1.name)

      Map.put(gall, :aliases, Map.get(aliases, gall.id, []) ++ inducer_synonyms)
    end)
  end
end
