defmodule Gallformers.Catalog.ReadModels.Api do
  @moduledoc """
  Gall reads for API v2 (`803b` Task 13), in the shapes its responses keep
  from the old "everything is a species" model (`GallformersWeb.Schemas`).

  A Gall row is its ID, the name shown, its editorial `datacomplete`,
  `abundance_id` and abundance name, its current `detachable` Trait value,
  whether it is `undescribed` (no current Inducer at species rank or below,
  as `Gallformers.Catalog.ReadModels.GallPage` says) and its `aliases`:

    * its current alias Facts — `type` `"common"` for a common name,
      `"former_label"` or `"code"` for the others — each with its Fact ID as
      `id`, common names first, then former labels, then codes, each by name;
    * then its current Inducers' synonyms — `type` `"scientific"`, with the
      name's ID as `id` and its sensu as `description` — in the order added.

  An alias's `id` is unique only together with its `type`.

  Lists are by the name shown, then ID. A list's `:q` finds Galls as the
  global search does (`Gallformers.Catalog.search_galls/2`).
  """
  import Ecto.Query

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.LegacyCitation
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.ReadModels.GallPage
  alias Gallformers.Catalog.ReadModels.GallSummary
  alias Gallformers.Catalog.ReadModels.Search
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon

  @alias_types %{common_name: "common", former_label: "former_label", code: "code"}
  @alias_order %{common_name: 0, former_label: 1, code: 2}

  @typedoc "Paging options: `:q` (a search query; blank for none), `:limit` (nil for all), `:offset`."
  @type page_opts :: [q: String.t() | nil, limit: pos_integer() | nil, offset: non_neg_integer()]

  @type alias_entry :: %{
          id: integer(),
          name: String.t(),
          type: String.t(),
          description: String.t() | nil
        }

  @type row :: %{
          id: integer(),
          name: String.t(),
          datacomplete: boolean(),
          abundance_id: integer() | nil,
          abundance: String.t() | nil,
          detachable: String.t() | nil,
          undescribed: boolean(),
          aliases: [alias_entry()]
        }

  @type trait_value :: %{id: integer(), value: String.t(), definition: String.t() | nil}

  @type details :: %{
          id: integer(),
          name: String.t(),
          datacomplete: boolean(),
          abundance_id: integer() | nil,
          abundance: String.t() | nil,
          detachable: String.t() | nil,
          undescribed: boolean(),
          aliases: [alias_entry()],
          hosts: [%{id: integer(), name: String.t()}],
          traits: %{String.t() => [trait_value()]}
        }

  @doc "A page of Gall rows, with how many Galls there are in all (matching `:q`)."
  @spec paginate_galls(page_opts()) :: %{entries: [row()], total: non_neg_integer()}
  def paginate_galls(opts) when is_list(opts) do
    offset = opts[:offset] || 0

    {ids, total} =
      case query_text(opts[:q]) do
        nil ->
          ids =
            from(g in Gall,
              order_by: [fragment("COALESCE(?, ?)", g.name_override, g.name), g.id],
              offset: ^offset,
              select: g.id
            )
            |> limit_to(opts[:limit])
            |> Repo.all()

          {ids, Repo.aggregate(Gall, :count)}

        q ->
          found = q |> Search.galls([]) |> Enum.map(& &1.id)
          {found |> Enum.drop(offset) |> take(opts[:limit]), length(found)}
      end

    %{entries: rows(ids), total: total}
  end

  @doc """
  Gall `id`'s row with its current Hosts (`%{id, name}`, by name) and its
  current Trait values with their IDs and definitions, by Trait; or
  `:not_found`.
  """
  @spec gall_details(integer()) :: {:ok, details()} | :not_found
  def gall_details(id) when is_integer(id) do
    case rows([id]) do
      [] ->
        :not_found

      [row] ->
        hosts = Enum.map(GallSummary.for_gall(id).hosts, &%{id: &1.taxon_id, name: &1.name})
        {:ok, row |> Map.put(:hosts, hosts) |> Map.put(:traits, traits(id))}
    end
  end

  @doc "Gall `id`'s Sources as its page lists them (`GallPage.sources/1`), or `:not_found`."
  @spec list_gall_sources(integer()) :: {:ok, [GallPage.source()]} | :not_found
  def list_gall_sources(id) when is_integer(id) do
    case Repo.get(Gall, id) do
      nil -> :not_found
      gall -> {:ok, GallPage.sources(gall)}
    end
  end

  @doc "Each card (a map with the Gall's `id`) with whether its Gall is `undescribed`."
  @spec add_undescribed([map()]) :: [map()]
  def add_undescribed([]), do: []

  def add_undescribed(cards) when is_list(cards) do
    described = cards |> Enum.map(& &1.id) |> described_ids()
    Enum.map(cards, &Map.put(&1, :undescribed, not MapSet.member?(described, &1.id)))
  end

  @doc """
  Each card (a map with the Gall's `id`) with what Source `source_id` says
  of its Gall: the legacy citation's `description` and `externallink`, or
  for a Gall with a note of the Source (the Gallformers Source's notes) the
  newest note's text as `description`; nil where it has neither.
  """
  @spec add_citations([map()], integer()) :: [map()]
  def add_citations([], _source_id), do: []

  def add_citations(cards, source_id) when is_list(cards) and is_integer(source_id) do
    ids = Enum.map(cards, & &1.id)

    citations =
      from(c in LegacyCitation,
        where: c.source_id == ^source_id and c.gall_id in ^ids,
        select: {c.gall_id, %{description: c.description, externallink: c.externallink}}
      )
      |> Repo.all()
      |> Map.new()

    notes = Sources.newest_note_texts(source_id)

    Enum.map(cards, fn card ->
      citation =
        Map.get(citations, card.id, %{description: Map.get(notes, card.id), externallink: nil})

      Map.merge(card, citation)
    end)
  end

  # -- rows --------------------------------------------------------------------

  # The rows of the Galls `ids`, in that order (unknown IDs left out).
  defp rows([]), do: []

  defp rows(ids) do
    galls = Repo.all(from(g in Gall, where: g.id in ^ids)) |> Map.new(&{&1.id, &1})
    abundances = galls |> Map.values() |> Enum.map(& &1.abundance_id) |> abundance_names()
    detachable = detachable(ids)
    described = described_ids(ids)
    aliases = aliases(ids)

    for id <- ids, gall = galls[id], gall != nil do
      %{
        id: id,
        name: Gall.display_name(gall),
        datacomplete: gall.datacomplete,
        abundance_id: gall.abundance_id,
        abundance: Map.get(abundances, gall.abundance_id),
        detachable: Map.get(detachable, id),
        undescribed: not MapSet.member?(described, id),
        aliases: Map.get(aliases, id, [])
      }
    end
  end

  defp abundance_names(ids) do
    case ids |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] ->
        %{}

      ids ->
        from(a in "abundance", where: a.id in ^ids, select: {a.id, a.abundance})
        |> Repo.all()
        |> Map.new()
    end
  end

  defp detachable(ids) do
    from(t in Current.traits(ids),
      join: v in TraitValue,
      on: v.id == t.trait_value_id,
      where: v.trait == "detachable",
      select: {t.gall_id, v.value}
    )
    |> Repo.all()
    |> Map.new()
  end

  # The Galls among `ids` with a current Inducer at species rank or below.
  defp described_ids(ids) do
    from(r in Current.relationships("inducer_of"),
      join: t in Taxon,
      on: t.id == r.subject_taxon_id,
      where: r.object_gall_id in ^ids and t.rank in ^Rank.species_and_below(),
      distinct: true,
      select: r.object_gall_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp aliases(ids) do
    facts =
      from(a in Current.aliases(ids), select: {a.gall_id, a.fact_id, a.name, a.kind})
      |> Repo.all()
      |> Enum.sort_by(fn {gall_id, _fact_id, name, kind} ->
        {gall_id, @alias_order[kind], name}
      end)
      |> Enum.group_by(&elem(&1, 0), fn {_gall_id, fact_id, name, kind} ->
        %{id: fact_id, name: name, type: @alias_types[kind], description: nil}
      end)

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

    Map.new(ids, fn id ->
      scientific =
        for taxon_id <- Map.get(inducers, id, []),
            synonym <- Map.get(synonyms, taxon_id, []) do
          %{id: synonym.id, name: synonym.name, type: "scientific", description: synonym.sensu}
        end

      {id, Map.get(facts, id, []) ++ scientific}
    end)
  end

  defp traits(gall_id) do
    from(t in Current.traits(gall_id),
      join: v in TraitValue,
      on: v.id == t.trait_value_id,
      order_by: [v.trait, v.value],
      select: {v.trait, %{id: v.id, value: v.value, definition: v.definition}}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # -- paging ------------------------------------------------------------------

  defp query_text(q) when is_binary(q) do
    case String.trim(q) do
      "" -> nil
      text -> text
    end
  end

  defp query_text(_q), do: nil

  defp limit_to(query, nil), do: query
  defp limit_to(query, limit), do: limit(query, ^limit)

  defp take(list, nil), do: list
  defp take(list, limit), do: Enum.take(list, limit)
end
