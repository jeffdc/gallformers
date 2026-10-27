defmodule Gallformers.Catalog.ReadModels.Current do
  @moduledoc """
  Queries for the current gall Facts (standing `:current`), shared by the
  read models. Withdrawn, superseded, retracted and unsupported Facts never
  count.
  """
  import Ecto.Query

  alias Gallformers.Catalog.Facts.AliasFact
  alias Gallformers.Catalog.Facts.DescriptionFact
  alias Gallformers.Catalog.Facts.OccurrenceFact
  alias Gallformers.Catalog.Facts.QualifierFact
  alias Gallformers.Catalog.Facts.RangeFact
  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Catalog.Facts.TraitFact
  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.Fact

  @doc "Current Relationship Facts of `type`."
  @spec relationships(String.t()) :: Ecto.Query.t()
  def relationships(type) do
    from(r in RelationshipFact,
      join: f in Fact,
      on: f.id == r.fact_id,
      where: r.type == ^type and f.standing == :current
    )
  end

  @doc "Current range adjustments of a Gall, or of the Galls among a list of IDs."
  @spec range_adjustments(integer() | [integer()]) :: Ecto.Query.t()
  def range_adjustments(gall_ids) when is_list(gall_ids) do
    from(r in RangeFact,
      join: f in Fact,
      on: f.id == r.fact_id,
      where: r.gall_id in ^gall_ids and f.standing == :current
    )
  end

  def range_adjustments(gall_id) do
    from(r in RangeFact,
      join: f in Fact,
      on: f.id == r.fact_id,
      where: r.gall_id == ^gall_id and f.standing == :current
    )
  end

  @doc "Current alias Facts (common names, former labels, codes) of every Gall."
  @spec aliases() :: Ecto.Query.t()
  def aliases do
    from(a in AliasFact,
      join: f in Fact,
      on: f.id == a.fact_id,
      where: f.standing == :current
    )
  end

  @doc "Current alias Facts of a Gall, or of the Galls among a list of IDs."
  @spec aliases(integer() | [integer()]) :: Ecto.Query.t()
  def aliases(gall_ids) when is_list(gall_ids),
    do: where(aliases(), [a], a.gall_id in ^gall_ids)

  def aliases(gall_id) do
    from(a in AliasFact,
      join: f in Fact,
      on: f.id == a.fact_id,
      where: a.gall_id == ^gall_id and f.standing == :current
    )
  end

  @doc "Current Trait Facts of a Gall, or of the Galls among a list of IDs."
  @spec traits(integer() | [integer()]) :: Ecto.Query.t()
  def traits(gall_ids) when is_list(gall_ids) do
    from(t in TraitFact,
      join: f in Fact,
      on: f.id == t.fact_id,
      where: t.gall_id in ^gall_ids and f.standing == :current
    )
  end

  def traits(gall_id) do
    from(t in TraitFact,
      join: f in Fact,
      on: f.id == t.fact_id,
      where: t.gall_id == ^gall_id and f.standing == :current
    )
  end

  @doc """
  The IDs of the Galls that current Facts attributed by Source `source_id`
  are about (a query selecting Gall IDs, possibly repeated): every gall Fact
  kind's Gall, each Gall of a Relationship (subject, object, context), and
  the Galls of the Relationship a qualifier qualifies.
  """
  @spec gall_ids_attributed_by(integer()) :: Ecto.Query.t()
  def gall_ids_attributed_by(source_id) do
    attributed =
      from(a in Attribution,
        join: f in Fact,
        on: f.id == a.fact_id,
        where: a.source_id == ^source_id and f.standing == :current,
        select: a.fact_id
      )

    qualified =
      from(q in QualifierFact, where: q.fact_id in subquery(attributed), select: q.of_fact_id)

    relationships =
      from(r in RelationshipFact,
        where: r.fact_id in subquery(attributed) or r.fact_id in subquery(qualified)
      )

    by_gall =
      for schema <- [TraitFact, RangeFact, OccurrenceFact, AliasFact, DescriptionFact] do
        from(t in schema, where: t.fact_id in subquery(attributed), select: t.gall_id)
      end

    [
      select(relationships, [r], r.subject_gall_id),
      select(relationships, [r], r.gall_context_id)
      | by_gall
    ]
    |> Enum.reduce(select(relationships, [r], r.object_gall_id), &union_all(&2, ^&1))
  end

  @doc """
  The IDs of the Sources attributing current Facts about Gall `gall_id` (a
  query selecting Source IDs, each once): the converse of
  `gall_ids_attributed_by/1` — every gall Fact kind of the Gall, each
  Relationship naming it (subject, object, context), and the qualifiers of
  those Relationships.
  """
  @spec source_ids_attributing(integer()) :: Ecto.Query.t()
  def source_ids_attributing(gall_id) do
    relationships =
      from(r in RelationshipFact,
        where:
          r.subject_gall_id == ^gall_id or r.object_gall_id == ^gall_id or
            r.gall_context_id == ^gall_id,
        select: r.fact_id
      )

    qualifiers =
      from(q in QualifierFact, where: q.of_fact_id in subquery(relationships), select: q.fact_id)

    fact_ids =
      for schema <- [TraitFact, RangeFact, OccurrenceFact, AliasFact, DescriptionFact],
          reduce: union_all(relationships, ^qualifiers) do
        query ->
          union_all(query, ^from(t in schema, where: t.gall_id == ^gall_id, select: t.fact_id))
      end

    from(a in Attribution,
      join: f in Fact,
      on: f.id == a.fact_id,
      where: f.standing == :current and a.fact_id in subquery(fact_ids),
      distinct: true,
      select: a.source_id
    )
  end
end
