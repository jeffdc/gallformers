defmodule Gallformers.Taxa.ReadModels.Search do
  @moduledoc """
  Searches over taxa: the global search (`803b` Task 11) and typeaheads
  (`803b` Task 9, the ID tool's Host and Host genus pickers).

    * `taxa/2` — taxa of any rank and kingdom (or of some) by accepted
      name, synonym or common name, by accepted name; `taxon_ids/2` their
      IDs only.
    * `plants/2` — plants (Plantae at species rank or below) by accepted
      name, synonym or common name. Every word of the query must appear in
      one name of the plant or in its accepted name (as the old model's
      host search matched a host's name and its aliases); ranked an exact name first, then a name starting with the
      query, then the rest, each by accepted name.
    * `genera_and_sections/3` — genera, subgenera and sections whose name
      (accepted or synonym) starts with the query or whose common name
      contains it, genera first, each by name.
  """
  import Ecto.Query

  alias Gallformers.Repo
  alias Gallformers.Taxa.CommonName
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.ReadModels.Api
  alias Gallformers.Taxa.ReadModels.Browse
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TaxonName
  alias Gallformers.TextMatch

  @group_ranks [:genus, :subgenus, :section]

  @type plant :: %{
          id: integer(),
          name: String.t(),
          rank: Rank.t(),
          datacomplete: boolean(),
          aliases: [String.t()]
        }

  @type group :: %{id: integer(), name: String.t(), rank: Rank.t(), description: String.t() | nil}

  @type hit :: %{
          id: integer(),
          name: String.t(),
          rank: Rank.t(),
          kingdom: String.t() | nil,
          parent_id: integer() | nil,
          datacomplete: boolean(),
          aliases: [String.t()]
        }

  @doc "Plants matching `query`, best first, at most `limit`; `aliases` are their synonyms then common names."
  @spec plants(String.t(), pos_integer()) :: [plant()]
  def plants(query, limit) when is_binary(query) and is_integer(limit) do
    case TextMatch.parse_terms(query) do
      [] -> []
      terms -> search_plants(terms, query |> String.downcase() |> String.trim(), limit)
    end
  end

  defp search_plants(terms, raw, limit) do
    from([n, t, a] in matching(terms),
      where: t.kingdom == "Plantae" and t.rank in ^Rank.species_and_below(),
      group_by: [t.id, a.name, t.rank, t.datacomplete],
      order_by: [
        asc:
          fragment(
            "MIN(CASE WHEN lower(?) = ? THEN 0 WHEN ? ILIKE ? THEN 1 ELSE 2 END)",
            n.name,
            ^raw,
            n.name,
            ^"#{raw}%"
          ),
        asc: a.name,
        asc: t.id
      ],
      limit: ^limit,
      select: %{id: t.id, name: a.name, rank: t.rank, datacomplete: t.datacomplete}
    )
    |> Repo.all()
    |> with_aliases()
  end

  @doc """
  Taxa matching `query` (global search): every word of the query appears in
  one name of the taxon — its accepted name, a synonym or a common name — or
  in its accepted name. By accepted name, each with its rank, kingdom,
  parent, data-complete flag and `aliases` (synonyms, then common names).
  Options: `:ranks` (only taxa at these ranks), `:kingdom` (only taxa of
  this kingdom).
  """
  @spec taxa(String.t(), keyword()) :: [hit()]
  def taxa(query, opts) when is_binary(query) and is_list(opts) do
    case TextMatch.parse_terms(query) do
      [] ->
        []

      terms ->
        from([_n, t, a] in filtered(terms, opts),
          distinct: true,
          order_by: [a.name, t.id],
          select: %{
            id: t.id,
            name: a.name,
            rank: t.rank,
            kingdom: t.kingdom,
            parent_id: t.parent_id,
            datacomplete: t.datacomplete
          }
        )
        |> Repo.all()
        |> with_aliases()
    end
  end

  @doc "The IDs of the taxa `taxa/2` finds for `query` and `opts`, unordered."
  @spec taxon_ids(String.t(), keyword()) :: [integer()]
  def taxon_ids(query, opts) when is_binary(query) and is_list(opts) do
    case TextMatch.parse_terms(query) do
      [] -> []
      terms -> Repo.all(from([_n, t] in filtered(terms, opts), distinct: true, select: t.id))
    end
  end

  # Names (accepted, synonym, common) `n` of taxa `t` with accepted name `a`,
  # where every term (`TextMatch.parse_terms/1`) is in `n` or in `a`.
  defp matching(terms) do
    names =
      from(n in TaxonName, select: %{taxon_id: n.taxon_id, name: n.name})
      |> union_all(^from(c in CommonName, select: %{taxon_id: c.taxon_id, name: c.name}))

    base =
      from(n in subquery(names),
        join: t in Taxon,
        on: t.id == n.taxon_id,
        join: a in TaxonName,
        on: a.taxon_id == t.id and a.status == :accepted
      )

    Enum.reduce(terms, base, fn term, query ->
      where(query, [n, _t, a], ilike(n.name, ^term) or ilike(a.name, ^term))
    end)
  end

  defp filtered(terms, opts) do
    terms
    |> matching()
    |> filter_ranks(opts[:ranks])
    |> filter_matched_kingdom(opts[:kingdom])
  end

  defp filter_ranks(query, nil), do: query
  defp filter_ranks(query, ranks), do: where(query, [_n, t], t.rank in ^ranks)

  defp filter_matched_kingdom(query, nil), do: query
  defp filter_matched_kingdom(query, kingdom), do: where(query, [_n, t], t.kingdom == ^kingdom)

  # Each taxon with its `aliases`: its synonyms, then its common names, each
  # in the order added.
  defp with_aliases(taxa) do
    ids = Enum.map(taxa, & &1.id)
    synonyms = Api.list_synonyms_by_taxon(ids)
    common = Browse.common_names(ids)

    Enum.map(taxa, fn taxon ->
      names = synonyms |> Map.get(taxon.id, []) |> Enum.map(& &1.name)
      aliases = names ++ Map.get(common, taxon.id, [])
      Map.put(taxon, :aliases, aliases)
    end)
  end

  @doc """
  Genera, subgenera and sections matching `query`, at most `limit`.
  Options: `:kingdom` (e.g. `"Plantae"`), only taxa of that kingdom.
  """
  @spec genera_and_sections(String.t(), pos_integer(), keyword()) :: [group()]
  def genera_and_sections(query, limit, opts) when is_binary(query) and is_integer(limit) do
    case query |> String.trim() |> String.downcase() do
      "" -> []
      q -> search_groups(q, limit, opts[:kingdom])
    end
  end

  defp search_groups(q, limit, kingdom) do
    matching =
      from(n in TaxonName, where: ilike(n.name, ^"#{q}%"), select: n.taxon_id)
      |> union_all(^from(c in CommonName, where: ilike(c.name, ^"%#{q}%"), select: c.taxon_id))

    groups =
      from(t in Taxon,
        join: a in TaxonName,
        on: a.taxon_id == t.id and a.status == :accepted,
        where: t.id in subquery(matching) and t.rank in ^@group_ranks,
        order_by: [
          fragment("array_position(?::text[], ?)", ^Enum.map(@group_ranks, &to_string/1), t.rank),
          a.name,
          t.id
        ],
        limit: ^limit,
        select: %{id: t.id, name: a.name, rank: t.rank}
      )
      |> filter_kingdom(kingdom)
      |> Repo.all()

    common =
      from(c in CommonName,
        where: c.taxon_id in ^Enum.map(groups, & &1.id),
        order_by: c.id,
        select: {c.taxon_id, c.name}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Enum.map(groups, fn group ->
      description =
        case Map.get(common, group.id, []) do
          [] -> nil
          names -> Enum.join(names, ", ")
        end

      Map.put(group, :description, description)
    end)
  end

  defp filter_kingdom(query, nil), do: query
  defp filter_kingdom(query, kingdom), do: where(query, [t], t.kingdom == ^kingdom)
end
