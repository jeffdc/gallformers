defmodule Gallformers.Catalog.Records do
  @moduledoc """
  What deleting and merging Galls and plants (matter `ec2c`, "Deletes")
  needs from the Catalog: the gall Facts that rest on a Gall or name a
  taxon, deleting them, moving a merged Gall's (or plant's) Facts onto the
  survivor with their attributions, the rest of a Gall merge (alias,
  citations, waiting terms, redirect) and deleting Galls.

  Called through `Gallformers.Catalog`; the deletes and merges themselves
  are `Gallformers.Import`'s, which also cleans up the import tables that
  name the records and logs them for replay.

  ## Moving Facts

  Each Fact naming the absorbed record is matched to the Fact with the
  same natural key on the survivor (found, or made with no attribution:
  `Gallformers.Catalog.Assert.find_or_create/3`), and every attribution
  moves to it with `Gallformers.Facts.move_attribution/3`: the same Fact
  on both combines its Sources, one attribution per Fact and Source (a
  Source stating it on both keeps the survivor's), and standings are
  recomputed, so a single-valued disagreement follows recency and a
  same-date tie comes back as a conflict. A qualifier moves with its
  Relationship. A Fact that would join the two records to each other (an
  alternate generation of the survivor) has no place after the merge: its
  attributions are removed. Its notes go with a Fact. The emptied Facts
  are left for the caller to delete (`delete_facts/2`) once nothing else
  names them.

  A split's answer moves one Gall's Inducer Facts the same way
  (`move_gall_inducer/4`); its undo moves back exactly what moved
  (`inducer_facts/2` read before, `return_gall_inducer/5`).
  """
  import Ecto.Query

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Assert
  alias Gallformers.Catalog.FactNote
  alias Gallformers.Catalog.Facts.AliasFact
  alias Gallformers.Catalog.Facts.DescriptionFact
  alias Gallformers.Catalog.Facts.OccurrenceFact
  alias Gallformers.Catalog.Facts.QualifierFact
  alias Gallformers.Catalog.Facts.RangeFact
  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Catalog.Facts.TraitFact
  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.GallRedirect
  alias Gallformers.Catalog.LegacyCitation
  alias Gallformers.Catalog.PendingTraitTerm
  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Catalog.Vocab.GenerationGroupTaxon
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Facts
  alias Gallformers.Places.Place
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa

  @typedoc "A Gall or a taxon, by ID."
  @type record :: {:gall, integer()} | {:taxon, integer()}

  @typedoc """
  A gall Fact naming a record: its Fact ID, kind (`facts.kind`), what it is
  about (`about`: the Gall it describes, or a taxon for a Relationship
  between taxa), the record among those asked about that it rests on
  (`rests_on`) and its words ("host: Quercus alba").
  """
  @type fact_row :: %{
          fact_id: integer(),
          kind: String.t(),
          about: record(),
          rests_on: record(),
          text: String.t()
        }

  @gall_kinds [TraitFact, AliasFact, RangeFact, OccurrenceFact, DescriptionFact]

  # -- reading -------------------------------------------------------------------

  @doc """
  The gall Facts resting on Galls `gall_ids`: every Fact about one (its
  Traits, aliases, range adjustments, occurrences, description), every
  Relationship one is an endpoint or the context of, and the qualifiers of
  those Relationships. Each Fact once, by Fact ID.
  """
  @spec facts_about_galls([integer()]) :: [fact_row()]
  def facts_about_galls([]), do: []

  def facts_about_galls(gall_ids) when is_list(gall_ids) do
    plain =
      Enum.flat_map(@gall_kinds, fn schema ->
        from(d in schema, where: d.gall_id in ^gall_ids) |> Repo.all()
      end)

    relationships =
      from(r in RelationshipFact,
        where:
          r.object_gall_id in ^gall_ids or r.subject_gall_id in ^gall_ids or
            r.gall_context_id in ^gall_ids
      )
      |> Repo.all()

    rows(plain ++ relationships ++ qualifiers_of(relationships), {:gall, gall_ids})
  end

  @doc """
  The gall Facts naming taxa `taxon_ids`: the Relationships one is an
  endpoint of (a Gall's Inducer or Host, an organism in a Gall) and their
  qualifiers. Each Fact once, by Fact ID.
  """
  @spec facts_naming_taxa([integer()]) :: [fact_row()]
  def facts_naming_taxa([]), do: []

  def facts_naming_taxa(taxon_ids) when is_list(taxon_ids) do
    relationships =
      from(r in RelationshipFact,
        where: r.subject_taxon_id in ^taxon_ids or r.object_taxon_id in ^taxon_ids
      )
      |> Repo.all()

    rows(relationships ++ qualifiers_of(relationships), {:taxon, taxon_ids})
  end

  defp qualifiers_of([]), do: []

  defp qualifiers_of(relationships) do
    ids = Enum.map(relationships, & &1.fact_id)
    Repo.all(from(q in QualifierFact, where: q.of_fact_id in ^ids))
  end

  defp rows(details, asked) do
    names = names(details)
    by_relationship = for %RelationshipFact{} = r <- details, into: %{}, do: {r.fact_id, r}

    details
    |> Enum.uniq_by(& &1.fact_id)
    |> Enum.sort_by(& &1.fact_id)
    |> Enum.map(fn detail ->
      %{
        fact_id: detail.fact_id,
        kind: kind(detail),
        about: about(detail, by_relationship),
        rests_on: rests_on(detail, asked, by_relationship),
        text: text(detail, names, by_relationship)
      }
    end)
  end

  defp kind(%module{}), do: module.kind()

  defp about(%RelationshipFact{object_gall_id: id}, _rels) when is_integer(id), do: {:gall, id}
  defp about(%RelationshipFact{gall_context_id: id}, _rels) when is_integer(id), do: {:gall, id}
  defp about(%RelationshipFact{subject_taxon_id: id}, _rels), do: {:taxon, id}
  defp about(%QualifierFact{of_fact_id: of}, rels), do: about(Map.fetch!(rels, of), rels)
  defp about(%{gall_id: id}, _rels), do: {:gall, id}

  defp rests_on(%QualifierFact{of_fact_id: of}, asked, rels),
    do: rests_on(Map.fetch!(rels, of), asked, rels)

  defp rests_on(%RelationshipFact{} = r, {type, ids}, _rels) do
    fields =
      if type == :gall,
        do: [r.object_gall_id, r.subject_gall_id, r.gall_context_id],
        else: [r.subject_taxon_id, r.object_taxon_id]

    {type, Enum.find(fields, &(&1 in ids))}
  end

  defp rests_on(%{gall_id: id}, {:gall, _ids}, _rels), do: {:gall, id}

  defp names(details) do
    taxon_ids =
      for %RelationshipFact{} = r <- details,
          id <- [r.subject_taxon_id, r.object_taxon_id],
          id,
          uniq: true,
          do: id

    gall_ids =
      for %RelationshipFact{} = r <- details,
          id <- [r.subject_gall_id, r.object_gall_id],
          id,
          uniq: true,
          do: id

    place_ids = for %{place_id: id} <- details, uniq: true, do: id
    value_ids = for %TraitFact{trait_value_id: id} <- details, uniq: true, do: id

    %{
      taxa: taxon_names(taxon_ids),
      galls:
        Repo.all(
          from(g in Gall,
            where: g.id in ^gall_ids,
            select: {g.id, fragment("COALESCE(?, ?)", g.name_override, g.name)}
          )
        )
        |> Map.new(),
      places:
        Repo.all(from(p in Place, where: p.id in ^place_ids, select: {p.id, p.name})) |> Map.new(),
      values:
        Repo.all(
          from(t in TraitValue, where: t.id in ^value_ids, select: {t.id, {t.trait, t.value}})
        )
        |> Map.new()
    }
  end

  defp taxon_names(ids) do
    ids
    |> Taxa.lineages()
    |> Map.new(fn {id, lineage} -> {id, lineage |> List.last() |> Map.fetch!(:name)} end)
  end

  defp text(%TraitFact{trait_value_id: id}, names, _rels) do
    {trait, value} = Map.fetch!(names.values, id)
    "#{String.replace(trait, "_", " ")}: #{value}"
  end

  defp text(%AliasFact{name: name}, _names, _rels), do: "also known as " <> name

  defp text(%RangeFact{adjustment: adjustment, place_id: id}, names, _rels),
    do: "range #{adjustment}: #{names.places[id]}"

  defp text(%OccurrenceFact{place_id: id}, names, _rels), do: "recorded in #{names.places[id]}"
  defp text(%DescriptionFact{}, _names, _rels), do: "description"

  defp text(%QualifierFact{qualifier: q, value: v, of_fact_id: of}, names, rels),
    do: "#{text(Map.fetch!(rels, of), names, rels)} (#{q}: #{v})"

  defp text(%RelationshipFact{type: "inducer_of", subject_taxon_id: id}, names, _rels),
    do: "inducer: #{names.taxa[id]}"

  defp text(%RelationshipFact{type: "host_of", subject_taxon_id: id}, names, _rels),
    do: "host: #{names.taxa[id]}"

  defp text(%RelationshipFact{subject_gall_id: s, object_gall_id: o} = r, names, _rels)
       when is_integer(s),
       do: "#{names.galls[s]} #{words(r.type)} #{names.galls[o]}"

  defp text(%RelationshipFact{object_taxon_id: o} = r, names, _rels) when is_integer(o),
    do: "#{names.taxa[r.subject_taxon_id]} #{words(r.type)} #{names.taxa[o]}"

  defp text(%RelationshipFact{} = r, names, _rels),
    do: "#{words(r.type)}: #{names.taxa[r.subject_taxon_id]}"

  defp words(type), do: String.replace(type, "_", " ")

  @doc """
  The Galls named after taxa `taxon_ids`: those an Inducer Fact (whatever
  its standing) gives one of them as Inducer.
  """
  @spec galls_named_after([integer()]) :: [integer()]
  def galls_named_after([]), do: []

  def galls_named_after(taxon_ids) when is_list(taxon_ids) do
    from(r in RelationshipFact,
      where: r.type == "inducer_of" and r.subject_taxon_id in ^taxon_ids,
      distinct: true,
      order_by: r.object_gall_id,
      select: r.object_gall_id
    )
    |> Repo.all()
  end

  @doc "The Galls whose name a plant among `taxon_ids` qualifies (\"(on Quercus douglasii)\"), with that plant."
  @spec galls_qualified_by([integer()]) :: [
          %{id: integer(), name: String.t(), taxon_id: integer()}
        ]
  def galls_qualified_by([]), do: []

  def galls_qualified_by(taxon_ids) when is_list(taxon_ids) do
    from(g in Gall,
      where: g.host_qualifier_taxon_id in ^taxon_ids,
      order_by: g.id,
      select: %{
        id: g.id,
        name: fragment("COALESCE(?, ?)", g.name_override, g.name),
        taxon_id: g.host_qualifier_taxon_id
      }
    )
    |> Repo.all()
  end

  @doc "The generation groups listing a taxon among `taxon_ids`: `%{group, taxon_id}`."
  @spec generation_groups_naming([integer()]) :: [%{group: String.t(), taxon_id: integer()}]
  def generation_groups_naming([]), do: []

  def generation_groups_naming(taxon_ids) when is_list(taxon_ids) do
    from(t in GenerationGroupTaxon,
      join: g in assoc(t, :group),
      where: t.taxon_id in ^taxon_ids,
      order_by: [g.name, t.taxon_id],
      select: %{group: g.name, taxon_id: t.taxon_id}
    )
    |> Repo.all()
  end

  @doc """
  The Galls' records that are not Facts: legacy citations (`%{gall_id,
  source_id}`) and the Sources' Trait terms still waiting on a question
  (`%{gall_id, source_id, count}`).
  """
  @spec gall_records([integer()]) :: %{
          legacy_citations: [%{gall_id: integer(), source_id: integer()}],
          waiting_terms: [%{gall_id: integer(), source_id: integer(), count: pos_integer()}]
        }
  def gall_records(gall_ids) when is_list(gall_ids) do
    %{
      legacy_citations:
        Repo.all(
          from(c in LegacyCitation,
            where: c.gall_id in ^gall_ids,
            order_by: [c.gall_id, c.source_id],
            select: %{gall_id: c.gall_id, source_id: c.source_id}
          )
        ),
      waiting_terms:
        Repo.all(
          from(p in PendingTraitTerm,
            where: p.gall_id in ^gall_ids and is_nil(p.settled_at),
            group_by: [p.gall_id, p.source_id],
            order_by: [p.gall_id, p.source_id],
            select: %{gall_id: p.gall_id, source_id: p.source_id, count: count()}
          )
        )
    }
  end

  # -- deleting ------------------------------------------------------------------

  @doc """
  Deletes the gall Facts `fact_ids` (and the qualifiers of any Relationship
  among them): their details, then the Facts with their attributions and
  notes (`Gallformers.Facts.delete_facts/2`). The ID tool's rows of the
  Galls they were about are refreshed. Returns how many Facts were deleted.
  """
  @spec delete_facts(Actor.t(), [integer()]) :: {:ok, non_neg_integer()}
  def delete_facts(%Actor{} = actor, fact_ids) when is_list(fact_ids) do
    Audit.transaction(actor, "catalog.delete_facts", fn ->
      qualifiers =
        Repo.all(from(q in QualifierFact, where: q.of_fact_id in ^fact_ids, select: q.fact_id))

      ids = Enum.uniq(fact_ids ++ qualifiers)
      galls = gall_ids_of(ids)

      deleted =
        Enum.flat_map([QualifierFact, RelationshipFact | @gall_kinds], fn schema ->
          {_count, deleted} =
            from(d in schema, where: d.fact_id in ^ids, select: d.fact_id) |> Repo.delete_all()

          deleted
        end)

      {:ok, _conflicts} = Facts.delete_facts(actor, deleted)
      :ok = GallIndex.enqueue_refresh(galls)
      length(deleted)
    end)
  end

  defp gall_ids_of(fact_ids) do
    plain =
      Enum.flat_map(@gall_kinds, fn schema ->
        Repo.all(from(d in schema, where: d.fact_id in ^fact_ids, select: d.gall_id))
      end)

    relationships =
      from(r in RelationshipFact,
        where: r.fact_id in ^fact_ids,
        select: [r.object_gall_id, r.subject_gall_id, r.gall_context_id]
      )
      |> Repo.all()
      |> List.flatten()

    (plain ++ relationships) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  @doc """
  The columns that refer to a Gall and keep it from being deleted, as
  `{table, column}`: every foreign key to `galls` that does not delete its
  rows with the Gall (its Facts' details, images, import statements, note
  documents, legacy citations). Read from the database's foreign keys.
  """
  @spec reference_columns() :: [{String.t(), String.t()}]
  def reference_columns do
    """
    SELECT c.conrelid::regclass::text, a.attname::text
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
    WHERE c.contype = 'f' AND c.confrelid = 'galls'::regclass AND c.confdeltype <> 'c'
    ORDER BY 1, 2
    """
    |> Repo.query!()
    |> Map.fetch!(:rows)
    |> Enum.map(fn [table, column] -> {table, column} end)
  end

  @doc "What refers to Gall `gall_id` (`reference_columns/0`), by table and column: `%{table, column, count}`."
  @spec references(integer()) :: [%{table: String.t(), column: String.t(), count: pos_integer()}]
  def references(gall_id) when is_integer(gall_id) do
    reference_columns()
    |> Enum.map_join(" UNION ALL ", fn {table, column} ->
      ~s|SELECT '#{table}', '#{column}', count(*) FROM "#{table}" WHERE "#{column}" = $1|
    end)
    |> Repo.query!([gall_id])
    |> Map.fetch!(:rows)
    |> Enum.filter(fn [_table, _column, count] -> count > 0 end)
    |> Enum.map(fn [table, column, count] -> %{table: table, column: column, count: count} end)
  end

  @doc """
  Deletes Galls `gall_ids` once their Facts, images and notes are gone:
  their legacy citations and waiting Trait terms, then the Galls (their ID
  tool rows and the redirects to them go with them). `{:error,
  {:referenced, gall_id, references}}` when anything else still refers to
  one (`references/1`); nothing is deleted then.
  """
  @spec delete_galls(Actor.t(), [integer()]) ::
          {:ok, non_neg_integer()} | {:error, {:referenced, integer(), list()}}
  def delete_galls(%Actor{} = actor, gall_ids) when is_list(gall_ids) do
    Audit.transaction(actor, "catalog.delete_galls", fn ->
      ids = Enum.uniq(gall_ids)
      Repo.all(from(g in Gall, where: g.id in ^ids, order_by: g.id, lock: "FOR UPDATE"))
      Repo.delete_all(from(c in LegacyCitation, where: c.gall_id in ^ids))
      Repo.delete_all(from(p in PendingTraitTerm, where: p.gall_id in ^ids))

      for id <- ids do
        case references(id) do
          [] -> :ok
          references -> Repo.rollback({:referenced, id, references})
        end
      end

      {count, _} = Repo.delete_all(from(g in Gall, where: g.id in ^ids))
      count
    end)
  end

  # -- merging -------------------------------------------------------------------

  @typedoc """
  A Fact moved by a merge: from the absorbed record's Fact (`from`) to the
  survivor's (`to`; nil when it was `:dropped`), `:moved` to a Fact the
  survivor did not hold or `:combined` with one it did; each Source's
  attribution `:moved`, `:already_held` (the Source stated it on the
  survivor too: the survivor's stands) or `:dropped`; `with_gall` the other
  Gall of a Relationship between two Galls (an alternate generation), now
  pointing at the survivor.
  """
  @type move :: %{
          from: integer(),
          to: integer() | nil,
          kind: String.t(),
          text: String.t(),
          outcome: :moved | :combined | :dropped,
          sources: [%{id: integer(), outcome: :moved | :already_held | :dropped}],
          with_gall: integer() | nil
        }

  @type moves :: %{moves: [move()], conflicts: [Facts.Standing.Conflict.t()]}

  @doc """
  Moves every gall Fact resting on Gall `from_id` onto Gall `to_id` (see
  the module doc). The emptied Facts stay, for `delete_facts/2`.
  """
  @spec move_gall_facts(Actor.t(), integer(), integer()) :: {:ok, moves()}
  def move_gall_facts(%Actor{} = actor, from_id, to_id) do
    Audit.transaction(actor, "catalog.move_gall_facts", fn ->
      move_all(actor, facts_about_galls([from_id]), &swap(&1, from_id, to_id))
    end)
  end

  @doc """
  Moves every gall Fact naming taxon `from_id` (a Host, mostly) onto taxon
  `to_id`, as `move_gall_facts/3` does for Galls.
  """
  @spec move_taxon_facts(Actor.t(), integer(), integer()) :: {:ok, moves()}
  def move_taxon_facts(%Actor{} = actor, from_id, to_id) do
    Audit.transaction(actor, "catalog.move_taxon_facts", fn ->
      move_all(actor, facts_naming_taxa([from_id]), &swap(&1, from_id, to_id))
    end)
  end

  @doc """
  Re-points Gall `gall_id`'s Inducer from taxon `from_id` to `to_id` (a
  split's answer, `f923` "Splits"): its `inducer_of` Facts naming `from_id`
  (and their qualifiers) move onto `to_id` as `move_gall_facts/3` moves
  Facts, every attribution kept as it was (`name_as_written` untouched),
  combined with the Fact `to_id` holds already; the emptied Facts are
  deleted. The Gall's other Facts stay. Returns the moves.
  """
  @spec move_gall_inducer(Actor.t(), integer(), integer(), integer()) :: {:ok, moves()}
  def move_gall_inducer(%Actor{} = actor, gall_id, from_id, to_id) do
    Audit.transaction(actor, "catalog.move_gall_inducer", fn ->
      inducers = inducers_of(gall_id, from_id)
      rows = rows(inducers ++ qualifiers_of(inducers), {:taxon, [from_id]})
      moved = move_all(actor, rows, &swap(&1, from_id, to_id))
      {:ok, _} = delete_facts(actor, Enum.map(moved.moves, & &1.from))
      moved
    end)
  end

  defp inducers_of(gall_id, taxon_id) do
    Repo.all(
      from(r in RelationshipFact,
        where:
          r.type == "inducer_of" and r.object_gall_id == ^gall_id and
            r.subject_taxon_id == ^taxon_id,
        order_by: r.fact_id
      )
    )
  end

  @typedoc """
  One of a Gall's `inducer_of` Facts, or a qualifier of one (`qualifier`
  `{qualifier, value}`; nil for the Fact itself), with the Gall it is
  stated in the context of and its notes; as `return_gall_inducer/5`
  takes it back, with the Sources whose statements go back (`source_ids`).
  """
  @type inducer_fact :: %{
          optional(:fact_id) => integer(),
          optional(:source_ids) => [integer()],
          qualifier: {String.t(), String.t()} | nil,
          gall_context_id: integer() | nil,
          notes: [%{text: String.t(), author_name: String.t() | nil}]
        }

  @doc """
  Gall `gall_id`'s `inducer_of` Facts naming taxon `taxon_id`, then their
  qualifiers, each with its `fact_id` and notes: what `move_gall_inducer/4`
  moves, read before it does.
  """
  @spec inducer_facts(integer(), integer()) :: [inducer_fact()]
  def inducer_facts(gall_id, taxon_id) when is_integer(gall_id) and is_integer(taxon_id) do
    inducers = inducers_of(gall_id, taxon_id)
    qualifiers = Enum.sort_by(qualifiers_of(inducers), & &1.fact_id)
    context = Map.new(inducers, &{&1.fact_id, &1.gall_context_id})
    ids = Enum.map(inducers ++ qualifiers, & &1.fact_id)

    notes =
      from(n in FactNote, where: n.fact_id in ^ids, order_by: n.id)
      |> Repo.all()
      |> Enum.group_by(& &1.fact_id, &%{text: &1.text, author_name: &1.author_name})

    Enum.map(inducers, fn r ->
      %{fact_id: r.fact_id, qualifier: nil, gall_context_id: r.gall_context_id}
    end)
    |> Enum.concat(
      Enum.map(qualifiers, fn q ->
        %{
          fact_id: q.fact_id,
          qualifier: {q.qualifier, q.value},
          gall_context_id: Map.fetch!(context, q.of_fact_id)
        }
      end)
    )
    |> Enum.map(&Map.put(&1, :notes, Map.get(notes, &1.fact_id, [])))
  end

  @doc """
  Moves back what `move_gall_inducer/4` moved from taxon `to_id` to
  `from_id` on Gall `gall_id` (the undo of a split's answer): for each of
  `facts` (`inducer_fact/0`, the Facts themselves before their
  qualifiers), the attributions of its `source_ids` and its notes move
  from the `from_id` Fact back onto the `to_id` one (made again if it was
  deleted), and nothing else: the `from_id` Fact keeps the statements it
  held before. A `from_id` Fact left with no attribution (nor qualifier
  with one) is deleted. What is no longer there (a replay that did it
  already) is skipped.
  """
  @spec return_gall_inducer(Actor.t(), integer(), integer(), integer(), [inducer_fact()]) ::
          {:ok, :ok}
  def return_gall_inducer(%Actor{} = actor, gall_id, from_id, to_id, facts) do
    Audit.transaction(actor, "catalog.return_gall_inducer", fn ->
      {relationships, qualifiers} = Enum.split_with(facts, &is_nil(&1.qualifier))

      left =
        for fact <- relationships ++ qualifiers,
            id = return_one(actor, gall_id, {from_id, to_id}, fact),
            uniq: true,
            do: id

      {:ok, _} = delete_facts(actor, Enum.filter(left, &unattributed?/1))
      :ok
    end)
  end

  # Moves one Fact's statements back; returns the Fact they left, or nil.
  defp return_one(actor, gall_id, {from_id, to_id}, %{qualifier: nil} = fact) do
    with %RelationshipFact{fact_id: from} <-
           find_detail(RelationshipFact, inducer_key(gall_id, from_id, fact.gall_context_id)) do
      to =
        find_or_create_detail(
          actor,
          RelationshipFact,
          inducer_key(gall_id, to_id, fact.gall_context_id)
        )

      move_back(actor, from, to, fact)
    end
  end

  defp return_one(actor, gall_id, {from_id, to_id}, %{qualifier: {qualifier, value}} = fact) do
    with %RelationshipFact{fact_id: of_from} <-
           find_detail(RelationshipFact, inducer_key(gall_id, from_id, fact.gall_context_id)),
         %QualifierFact{fact_id: from} <-
           find_detail(QualifierFact, %{of_fact_id: of_from, qualifier: qualifier, value: value}) do
      of_to =
        find_or_create_detail(
          actor,
          RelationshipFact,
          inducer_key(gall_id, to_id, fact.gall_context_id)
        )

      to =
        find_or_create_detail(actor, QualifierFact, %{
          of_fact_id: of_to,
          qualifier: qualifier,
          value: value
        })

      move_back(actor, from, to, fact)
    end
  end

  defp move_back(actor, from, to, fact) do
    for source_id <- Map.get(fact, :source_ids, []),
        %{id: id} <- [Facts.get_attribution(from, source_id)] do
      {:ok, _} = Facts.move_attribution(actor, id, to)
    end

    for note <- fact.notes do
      from(n in FactNote,
        where: n.fact_id == ^from and n.text == ^note.text,
        order_by: n.id,
        limit: 1,
        select: n.id
      )
      |> with_author(note.author_name)
      |> Repo.one()
      |> case do
        nil -> :ok
        id -> Repo.update_all(from(n in FactNote, where: n.id == ^id), set: [fact_id: to])
      end
    end

    from
  end

  defp with_author(query, nil), do: where(query, [n], is_nil(n.author_name))
  defp with_author(query, name), do: where(query, [n], n.author_name == ^name)

  defp inducer_key(gall_id, taxon_id, context_id) do
    %{
      type: "inducer_of",
      subject_taxon_id: taxon_id,
      subject_gall_id: nil,
      object_taxon_id: nil,
      object_gall_id: gall_id,
      gall_context_id: context_id
    }
  end

  defp find_detail(module, key) do
    {:ok, detail} = Assert.find(module, key)
    detail
  end

  defp find_or_create_detail(actor, module, key) do
    {:ok, detail} = Assert.find_or_create(module, actor, key)
    detail.fact_id
  end

  # No attribution on the Fact, nor on any of its qualifiers.
  defp unattributed?(fact_id) do
    qualifiers =
      Repo.all(from(q in QualifierFact, where: q.of_fact_id == ^fact_id, select: q.fact_id))

    Facts.source_ids_by_fact([fact_id | qualifiers]) == %{}
  end

  defp swap(id, id, to_id), do: to_id
  defp swap(id, _from_id, _to_id), do: id

  defp move_all(actor, rows, swap) do
    texts = Map.new(rows, &{&1.fact_id, &1})
    ids = Map.keys(texts)
    details = details(ids)

    # Relationships first, so their qualifiers know where they went.
    {relationships, others} = Enum.split_with(details, &match?(%RelationshipFact{}, &1))
    {qualifiers, plain} = Enum.split_with(others, &match?(%QualifierFact{}, &1))

    {rel_moves, mapping} =
      Enum.map_reduce(relationships, %{}, fn detail, acc ->
        key = relationship_key(detail, swap)

        move =
          actor
          |> move_one(detail, key, RelationshipFact, texts)
          |> Map.put(:with_gall, other_gall(detail, key))

        {move, Map.put(acc, detail.fact_id, move.to)}
      end)

    qualifier_moves =
      Enum.map(qualifiers, fn q ->
        key = Map.fetch!(mapping, q.of_fact_id) && qualifier_key(q, mapping)
        move_one(actor, q, key, QualifierFact, texts)
      end)

    plain_moves =
      Enum.map(plain, fn %module{} = detail ->
        move_one(actor, detail, plain_key(detail, swap), module, texts)
      end)

    moves = rel_moves ++ Enum.map(qualifier_moves ++ plain_moves, &Map.put(&1, :with_gall, nil))

    %{
      moves: Enum.map(moves, &Map.delete(&1, :conflicts)),
      conflicts: moves |> Enum.flat_map(& &1.conflicts) |> Enum.uniq()
    }
  end

  defp details(ids) do
    [RelationshipFact, QualifierFact | @gall_kinds]
    |> Enum.flat_map(fn schema -> Repo.all(from(d in schema, where: d.fact_id in ^ids)) end)
    |> Enum.sort_by(& &1.fact_id)
  end

  # The key on the survivor, or nil when the Fact would join the two
  # records (a Gall's relationship to itself).
  @endpoints [
    :subject_taxon_id,
    :subject_gall_id,
    :object_taxon_id,
    :object_gall_id,
    :gall_context_id
  ]

  defp relationship_key(r, swap) do
    key =
      Enum.reduce(@endpoints, %{type: r.type}, fn field, acc ->
        Map.put(acc, field, Map.fetch!(r, field) && swap.(Map.fetch!(r, field)))
      end)

    joins_itself? =
      (key.subject_gall_id != nil and key.subject_gall_id == key.object_gall_id) or
        (key.subject_taxon_id != nil and key.subject_taxon_id == key.object_taxon_id)

    if joins_itself?, do: nil, else: key
  end

  # The other Gall of a Relationship between two Galls, re-pointed by the move.
  defp other_gall(%RelationshipFact{subject_gall_id: s, object_gall_id: o}, %{} = key)
       when is_integer(s) and is_integer(o) do
    cond do
      key.subject_gall_id != s -> o
      key.object_gall_id != o -> s
      true -> nil
    end
  end

  defp other_gall(_relationship, _key), do: nil

  defp qualifier_key(q, mapping),
    do: %{of_fact_id: Map.fetch!(mapping, q.of_fact_id), qualifier: q.qualifier, value: q.value}

  defp plain_key(%TraitFact{} = t, swap) do
    %TraitValue{trait: trait, value: value} = Repo.get!(TraitValue, t.trait_value_id)
    %{gall_id: swap.(t.gall_id), trait: trait, value: value}
  end

  defp plain_key(%AliasFact{} = a, swap),
    do: %{gall_id: swap.(a.gall_id), name: a.name, kind: a.kind}

  defp plain_key(%RangeFact{} = r, swap),
    do: %{gall_id: swap.(r.gall_id), adjustment: r.adjustment, place_id: r.place_id}

  defp plain_key(%OccurrenceFact{} = o, swap),
    do: %{gall_id: swap.(o.gall_id), place_id: o.place_id}

  defp plain_key(%DescriptionFact{} = d, swap), do: %{gall_id: swap.(d.gall_id)}

  defp move_one(actor, detail, nil, _module, texts) do
    from = detail.fact_id

    {sources, conflicts} =
      from
      |> Facts.list_attributions()
      |> Enum.map_reduce([], fn a, acc ->
        {:ok, conflicts} = Facts.remove_attribution(actor, from, a.source_id)
        {%{id: a.source_id, outcome: :dropped}, acc ++ conflicts}
      end)

    %{
      from: from,
      to: nil,
      kind: texts[from].kind,
      text: texts[from].text,
      outcome: :dropped,
      sources: sources,
      conflicts: conflicts
    }
  end

  defp move_one(actor, detail, key, module, texts) do
    from = detail.fact_id
    {:ok, existing} = Assert.find(module, key)
    # An alias the survivor holds keeps its own kind.
    key = if existing && module == AliasFact, do: Map.delete(key, :kind), else: key
    {:ok, target} = Assert.find_or_create(module, actor, key)

    {sources, conflicts} =
      from
      |> Facts.list_attributions()
      |> Enum.map_reduce([], fn a, acc ->
        {:ok, %{moved: moved, conflicts: conflicts}} =
          Facts.move_attribution(actor, a.id, target.fact_id)

        {%{id: a.source_id, outcome: if(moved, do: :moved, else: :already_held)},
         acc ++ conflicts}
      end)

    from(n in FactNote, where: n.fact_id == ^from)
    |> Repo.update_all(set: [fact_id: target.fact_id])

    %{
      from: from,
      to: target.fact_id,
      kind: texts[from].kind,
      text: texts[from].text,
      outcome: if(existing, do: :combined, else: :moved),
      sources: sources,
      conflicts: conflicts
    }
  end

  @typedoc "What the rest of a Gall merge did (`absorb_gall/4`)."
  @type absorbed :: %{alias: String.t() | nil}

  @doc """
  Finishes merging Gall `absorbed_id` into `survivor_id`, once its Facts,
  images and notes have moved: the absorbed Gall's name becomes the
  survivor's alias (a former label, stated by the Gallformers Source,
  unless it is the survivor's name but for case), its legacy citations
  and waiting Trait terms move over (a citation of a Source the survivor
  cites already is dropped), its ID and Gallformers code redirect to the
  survivor (`gall_redirect/1`; the redirects to it are re-pointed), and
  it is deleted (`delete_galls/2`). The survivor keeps its own name, code,
  completeness, abundance and default Source.
  """
  @spec absorb_gall(Actor.t(), integer(), integer()) :: {:ok, absorbed()} | {:error, term()}
  def absorb_gall(%Actor{} = actor, absorbed_id, survivor_id) do
    Audit.transaction(actor, "catalog.absorb_gall", fn ->
      [absorbed, survivor] =
        for id <- [absorbed_id, survivor_id],
            do: Repo.one!(from(g in Gall, where: g.id == ^id, lock: "FOR UPDATE"))

      alias_name = add_former_label(actor, absorbed, survivor)
      move_citations(absorbed_id, survivor_id)

      from(p in PendingTraitTerm, where: p.gall_id == ^absorbed_id)
      |> Repo.update_all(set: [gall_id: survivor_id])

      from(r in GallRedirect, where: r.gall_id == ^absorbed_id)
      |> Repo.update_all(set: [gall_id: survivor_id])

      code = absorbed.gallformers_code
      absorbed |> Ecto.Changeset.change(gallformers_code: nil) |> Repo.update!()

      Repo.insert!(%GallRedirect{
        from_gall_id: absorbed_id,
        from_code: code,
        gall_id: survivor_id
      })

      actor |> delete_galls([absorbed_id]) |> ok_or_rollback()
      :ok = GallIndex.enqueue_refresh([survivor_id])
      %{alias: alias_name}
    end)
  end

  defp add_former_label(actor, absorbed, survivor) do
    name = Gall.display_name(absorbed)

    if String.downcase(name) == String.downcase(Gall.display_name(survivor)) do
      nil
    else
      gallformers = Sources.get_gallformers_source() || Repo.rollback(:no_gallformers_source)

      Assert.assert(
        AliasFact,
        actor,
        %{gall_id: survivor.id, name: name, kind: :former_label},
        %{
          source_id: gallformers.id,
          stance: :confirm,
          stated: Date.to_iso8601(Date.utc_today()),
          statement_text: "The name of a Gall merged into this one (\"#{name}\")."
        }
      )
      |> ok_or_rollback()

      name
    end
  end

  defp move_citations(absorbed_id, survivor_id) do
    cited =
      Repo.all(from(c in LegacyCitation, where: c.gall_id == ^survivor_id, select: c.source_id))

    from(c in LegacyCitation, where: c.gall_id == ^absorbed_id and c.source_id in ^cited)
    |> Repo.delete_all()

    from(c in LegacyCitation, where: c.gall_id == ^absorbed_id)
    |> Repo.update_all(set: [gall_id: survivor_id])
  end

  @doc """
  The Gall a merged-away Gall ID or Gallformers code (ignoring case) now
  is, or nil (`Gallformers.Catalog.GallRedirect`).
  """
  @spec gall_redirect(integer() | String.t()) :: integer() | nil
  def gall_redirect(id) when is_integer(id),
    do: Repo.one(from(r in GallRedirect, where: r.from_gall_id == ^id, select: r.gall_id))

  def gall_redirect(code) when is_binary(code) do
    code = String.trim(code)

    Repo.one(
      from(r in GallRedirect,
        where: fragment("lower(?)", r.from_code) == ^String.downcase(code),
        select: r.gall_id
      )
    )
  end

  @doc """
  Gives the Galls whose name plant `from_id` qualifies plant `to_id`
  instead (`Gallformers.Catalog.update_name_parts/3`, which derives the
  name again). Returns their IDs.
  """
  @spec requalify_galls(Actor.t(), integer(), integer()) :: {:ok, [integer()]} | {:error, term()}
  def requalify_galls(%Actor{} = actor, from_id, to_id) do
    Audit.transaction(actor, "catalog.requalify_galls", fn ->
      from(g in Gall, where: g.host_qualifier_taxon_id == ^from_id, order_by: g.id)
      |> Repo.all()
      |> Enum.map(fn gall ->
        actor
        |> Catalog.update_name_parts(gall, %{host_qualifier_taxon_id: to_id})
        |> ok_or_rollback()

        gall.id
      end)
    end)
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
