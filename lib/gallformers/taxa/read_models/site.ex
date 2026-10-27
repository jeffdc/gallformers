defmodule Gallformers.Taxa.ReadModels.Site do
  @moduledoc """
  Site-wide taxon reads (`803b` Task 12): the plant counts of the home and
  about pages, and the plant IDs and rank pages the sitemap lists.

  "Plants" are Plantae taxa at species rank or below, as in
  `Gallformers.Taxa.ReadModels.Browse`.
  """
  import Ecto.Query

  alias Gallformers.Repo
  alias Gallformers.Taxa.Ancestry
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TaxonName

  # The ranks with a page of their own (`Gallformers.Taxa.TreeBuilder.rank_path/2`).
  @page_ranks [:family, :subfamily, :tribe, :subtribe, :genus, :section]

  @type plant_counts :: %{
          plants: non_neg_integer(),
          families: non_neg_integer(),
          genera: non_neg_integer()
        }

  @type rank_page :: %{rank: Rank.t(), name: String.t()}

  @doc "How many plants there are."
  @spec count_plants() :: non_neg_integer()
  def count_plants, do: Repo.aggregate(plants(), :count)

  @doc "How many plants, and how many plant families and genera hold at least one."
  @spec plant_counts() :: plant_counts()
  def plant_counts do
    groups =
      Repo.all(
        from(a in Ancestry,
          join: p in subquery(plants()),
          on: p.id == a.descendant_id,
          join: g in Taxon,
          on: g.id == a.ancestor_id,
          where: g.rank in [:family, :genus],
          group_by: g.rank,
          select: {g.rank, count(g.id, :distinct)}
        )
      )
      |> Map.new()

    %{
      plants: count_plants(),
      families: Map.get(groups, :family, 0),
      genera: Map.get(groups, :genus, 0)
    }
  end

  @doc "Every plant's ID, ascending."
  @spec list_plant_ids() :: [integer()]
  def list_plant_ids, do: Repo.all(from(t in plants(), order_by: t.id, select: t.id))

  @doc """
  The taxa at ranks with a page (family, subfamily, tribe, subtribe, genus,
  section) as `%{rank, name}` (accepted name), by rank and name, each once:
  taxa sharing a name and rank share a page.
  """
  @spec list_rank_pages() :: [rank_page()]
  def list_rank_pages do
    from(t in Taxon,
      join: n in TaxonName,
      on: n.taxon_id == t.id and n.status == :accepted,
      where: t.rank in ^@page_ranks,
      distinct: true,
      order_by: [t.rank, n.name],
      select: %{rank: t.rank, name: n.name}
    )
    |> Repo.all()
  end

  defp plants do
    from(t in Taxon, where: t.kingdom == "Plantae" and t.rank in ^Rank.species_and_below())
  end
end
