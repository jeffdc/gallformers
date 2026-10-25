defmodule Gallformers.Catalog.ReadModels.Current do
  @moduledoc """
  Queries for the current gall Facts (standing `:current`), shared by the
  read models. Withdrawn, superseded, retracted and unsupported Facts never
  count.
  """
  import Ecto.Query

  alias Gallformers.Catalog.Facts.RangeFact
  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Catalog.Facts.TraitFact
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

  @doc "Current range adjustments of a Gall."
  @spec range_adjustments(integer()) :: Ecto.Query.t()
  def range_adjustments(gall_id) do
    from(r in RangeFact,
      join: f in Fact,
      on: f.id == r.fact_id,
      where: r.gall_id == ^gall_id and f.standing == :current
    )
  end

  @doc "Current Trait Facts of a Gall."
  @spec traits(integer()) :: Ecto.Query.t()
  def traits(gall_id) do
    from(t in TraitFact,
      join: f in Fact,
      on: f.id == t.fact_id,
      where: t.gall_id == ^gall_id and f.standing == :current
    )
  end
end
