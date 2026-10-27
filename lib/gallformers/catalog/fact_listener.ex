defmodule Gallformers.Catalog.FactListener do
  @moduledoc """
  The Catalog's "Facts changed" listener (`Gallformers.Facts.Events`),
  registered in `config/config.exs` and called by `Gallformers.Facts`
  inside the transaction that changed the Facts' standings.

  Maps the Facts to the Galls whose lookup-table rows
  (`Gallformers.Catalog.ReadModels.GallIndex`) read them — a Gall's
  `inducer_of` and `host_of` Relationships, its Trait Facts and its range
  adjustments — and enqueues a refresh of each. Other Facts (aliases,
  occurrences, descriptions, qualifiers, other Relationships, taxonomic
  acts) are not in the table, so they enqueue nothing.
  """
  @behaviour Gallformers.Facts.Events

  import Ecto.Query, only: [from: 2, union_all: 2]

  alias Gallformers.Catalog.Facts.RangeFact
  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Catalog.Facts.TraitFact
  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Repo

  @indexed_relationships ["inducer_of", "host_of"]

  @impl true
  def facts_changed(fact_ids) when is_list(fact_ids) do
    fact_ids
    |> gall_ids()
    |> GallIndex.enqueue_refresh()
  end

  @doc "The Galls whose lookup-table rows read the Facts among `fact_ids`."
  @spec gall_ids([integer()]) :: [integer()]
  def gall_ids([]), do: []

  def gall_ids(fact_ids) do
    relationships =
      from(r in RelationshipFact,
        where: r.fact_id in ^fact_ids and r.type in @indexed_relationships,
        select: r.object_gall_id
      )

    traits = from(t in TraitFact, where: t.fact_id in ^fact_ids, select: t.gall_id)
    ranges = from(r in RangeFact, where: r.fact_id in ^fact_ids, select: r.gall_id)

    relationships
    |> union_all(^traits)
    |> union_all(^ranges)
    |> Repo.all()
    |> Enum.uniq()
    |> Enum.sort()
  end
end
