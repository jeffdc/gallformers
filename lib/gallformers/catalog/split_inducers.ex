defmodule Gallformers.Catalog.SplitInducers do
  @moduledoc """
  The Catalog's side of split questions (matter `f923`, "Splits"): nearly
  all Facts are about Galls, not the Inducer, so a split changes each
  affected Gall's Inducer and nothing else. The questions themselves are
  admin queue items (`Gallformers.Import.SplitQuestions`); this says which
  Galls a split of a taxon reaches, what the splitting Sources state of
  them, and keeps the mark of an Inducer known only in its broad sense.

    * `galls_on/1` — the Galls whose current Inducer is the split taxon.
    * `stated_inducers/3` — the daughters the splitting Sources state as a
      Gall's Inducer (their own gall statements): such a Gall settles
      without a question.
    * `suggestions/3` — for the other Galls, the daughter the splitting
      Sources' statements suggest: the one daughter whose Galls they state
      share a Host with the Gall.
    * The **broad-sense mark** (`mark_broad_sense/4`): an `inducer_of` Fact
      whose Inducer stays the split taxon because which daughter induces
      the Gall is not known yet. It holds the split Fact
      (`relationship_facts.broad_sense_split_id`); re-pointing the Gall's
      Inducer (`Gallformers.Catalog.Records.move_gall_inducer/4`) leaves it
      behind with the emptied Fact. `broad_sense_inducers/1` reads it with
      the splitting Source, for the Gall page's Inducer.

  Re-pointing never rewrites a Source's statement: its attributions move
  with their `name_as_written`, so readers see an older paper said "A" for
  the broad A.
  """
  import Ecto.Query

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa

  @typedoc "A splitting Source: its ID and its name in the copy (short name, else title)."
  @type source :: %{source_id: integer(), source: String.t()}

  @typedoc "A broad-sense mark: the split taxon, the split Fact and its Source."
  @type mark :: %{
          taxon_id: integer(),
          split_fact_id: integer(),
          source_id: integer() | nil,
          source: String.t() | nil
        }

  @doc "The Galls whose current Inducer is `taxon_id`, by ID."
  @spec galls_on(integer()) :: [integer()]
  def galls_on(taxon_id) when is_integer(taxon_id) do
    from(r in Current.relationships("inducer_of"),
      where: r.subject_taxon_id == ^taxon_id,
      distinct: true,
      order_by: r.object_gall_id,
      select: r.object_gall_id
    )
    |> Repo.all()
  end

  @doc """
  The Inducers among `taxon_ids` that Sources `source_ids` confirm for each
  of Galls `gall_ids` (their own gall statements), by Gall: `%{gall_id =>
  [taxon_id]}`. A Gall none states is absent.
  """
  @spec stated_inducers([integer()], [integer()], [integer()]) :: %{integer() => [integer()]}
  def stated_inducers(gall_ids, source_ids, taxon_ids)
      when gall_ids == [] or source_ids == [] or taxon_ids == [],
      do: %{}

  def stated_inducers(gall_ids, source_ids, taxon_ids) do
    from(r in RelationshipFact,
      join: a in Attribution,
      on: a.fact_id == r.fact_id,
      where:
        r.type == "inducer_of" and r.object_gall_id in ^gall_ids and
          r.subject_taxon_id in ^taxon_ids and a.source_id in ^source_ids and
          a.stance == :confirm,
      distinct: true,
      select: {r.object_gall_id, r.subject_taxon_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {gall, taxa} -> {gall, Enum.sort(taxa)} end)
  end

  @doc """
  The daughter Sources `source_ids` suggest for each of Galls `gall_ids`:
  the one among `daughter_ids` whose Galls those Sources state as its own
  share a current Host with the Gall. `%{gall_id => %{taxon_id, hosts}}`,
  `hosts` the shared Hosts' names; a Gall with no such daughter, or more
  than one, is absent.
  """
  @spec suggestions([integer()], [integer()], [integer()]) :: %{
          integer() => %{taxon_id: integer(), hosts: [String.t()]}
        }
  def suggestions(gall_ids, source_ids, daughter_ids)
      when gall_ids == [] or source_ids == [] or daughter_ids == [],
      do: %{}

  def suggestions(gall_ids, source_ids, daughter_ids) do
    stated =
      from(r in RelationshipFact,
        join: a in Attribution,
        on: a.fact_id == r.fact_id,
        where:
          r.type == "inducer_of" and r.subject_taxon_id in ^daughter_ids and
            a.source_id in ^source_ids and a.stance == :confirm and
            r.object_gall_id not in ^gall_ids,
        distinct: true,
        select: {r.object_gall_id, r.subject_taxon_id}
      )
      |> Repo.all()

    hosts = hosts(Enum.uniq(gall_ids ++ Enum.map(stated, &elem(&1, 0))))

    by_daughter =
      Enum.reduce(stated, %{}, fn {gall, daughter}, acc ->
        Map.update(
          acc,
          daughter,
          MapSet.new(hosts[gall] || []),
          &MapSet.union(&1, MapSet.new(hosts[gall] || []))
        )
      end)

    for gall <- gall_ids,
        own = MapSet.new(hosts[gall] || []),
        [{daughter, shared}] <- [shared_hosts(by_daughter, own)],
        into: %{} do
      {gall,
       %{taxon_id: daughter, hosts: shared |> Enum.map(&Taxa.accepted_name/1) |> Enum.sort()}}
    end
  end

  defp shared_hosts(by_daughter, own) do
    for {daughter, hosts} <- by_daughter,
        shared = MapSet.intersection(hosts, own),
        MapSet.size(shared) > 0,
        do: {daughter, MapSet.to_list(shared)}
  end

  defp hosts(gall_ids) do
    from(r in Current.relationships("host_of"),
      where: r.object_gall_id in ^gall_ids,
      select: {r.object_gall_id, r.subject_taxon_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc """
  The Sources whose statements of split Facts `split_fact_ids` count (a
  confirmation, accepted or Gallformers' own), the newest first, by split
  Fact.
  """
  @spec split_sources([integer()]) :: %{integer() => [source()]}
  def split_sources(split_fact_ids) do
    ids = split_fact_ids |> Enum.filter(&is_integer/1) |> Enum.uniq()
    own = Sources.own_source_ids()
    by_fact = Facts.list_attributions_for_facts(ids)

    names =
      by_fact
      |> Map.values()
      |> List.flatten()
      |> Enum.map(& &1.source_id)
      |> Enum.uniq()
      |> Sources.list_sources_by_id()
      |> Map.new(&{&1.id, Sources.short_name(&1) || &1.title})

    Map.new(by_fact, fn {fact_id, attributions} ->
      sources =
        attributions
        |> Enum.filter(&(&1.stance == :confirm and Facts.counts?("taxon_split", &1, own)))
        |> Enum.sort_by(
          &{&1.stated_on != nil, &1.stated_on && Date.to_gregorian_days(&1.stated_on)},
          :desc
        )
        |> Enum.map(&%{source_id: &1.source_id, source: names[&1.source_id]})

      {fact_id, sources}
    end)
  end

  @doc """
  Marks Gall `gall_id`'s current `inducer_of` Facts naming `taxon_id` as
  naming it in its old broad sense, before split Fact `split_fact_id` (nil
  clears the mark). Audited.
  """
  @spec mark_broad_sense(Actor.t(), integer(), integer(), integer() | nil) ::
          {:ok, non_neg_integer()}
  def mark_broad_sense(%Actor{} = actor, gall_id, taxon_id, split_fact_id) do
    Audit.transaction(actor, "catalog.mark_broad_sense", fn ->
      ids =
        Repo.all(
          from(r in Current.relationships("inducer_of"),
            where: r.object_gall_id == ^gall_id and r.subject_taxon_id == ^taxon_id,
            select: r.fact_id
          )
        )

      {count, _} =
        Repo.update_all(from(r in RelationshipFact, where: r.fact_id in ^ids),
          set: [broad_sense_split_id: split_fact_id]
        )

      count
    end)
  end

  @doc """
  The broad-sense marks on Gall `gall_id`'s current Inducers, by Inducer:
  `%{taxon_id => t:mark/0}`, the Source the newest that made the split.
  """
  @spec broad_sense_inducers(integer()) :: %{integer() => mark()}
  def broad_sense_inducers(gall_id) when is_integer(gall_id) do
    marks =
      Repo.all(
        from(r in Current.relationships("inducer_of"),
          where: r.object_gall_id == ^gall_id and not is_nil(r.broad_sense_split_id),
          select: {r.subject_taxon_id, r.broad_sense_split_id}
        )
      )

    sources = split_sources(Enum.map(marks, &elem(&1, 1)))

    Map.new(marks, fn {taxon_id, split_id} ->
      first = sources |> Map.get(split_id, []) |> List.first() || %{}

      {taxon_id,
       %{
         taxon_id: taxon_id,
         split_fact_id: split_id,
         source_id: first[:source_id],
         source: first[:source]
       }}
    end)
  end
end
