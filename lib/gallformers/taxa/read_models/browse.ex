defmodule Gallformers.Taxa.ReadModels.Browse do
  @moduledoc """
  Taxon reads for the rank pages (`/family/:name`, `/genus/:name`,
  `/section/:name`, intermediate ranks) and the Hosts browse tree (`803b`
  Task 6). Batched over the ancestry closure (`Gallformers.Taxa.Ancestry`)
  so a page or tree is a few queries.

  "Plants" are Plantae taxa at species rank or below
  (`Gallformers.Taxa.Rank.species_and_below/0`), the taxa a Host page shows.
  Galls are the Catalog's: Taxa knows nothing about them.
  """
  import Ecto.Query

  alias Gallformers.Repo
  alias Gallformers.Taxa.Ancestry
  alias Gallformers.Taxa.CommonName
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TaxonName
  alias Gallformers.Taxa.TreeBuilder

  @type child :: %{
          taxon_id: integer(),
          name: String.t(),
          rank: Rank.t(),
          common_names: [String.t()]
        }

  @type plant :: %{id: integer(), name: String.t(), rank: Rank.t(), common_name: String.t() | nil}

  @doc "The taxa of `rank` whose accepted name is `name`, by ID."
  @spec get_by_name(String.t(), Rank.t()) :: [Taxon.t()]
  def get_by_name(name, rank) when is_binary(name) and is_atom(rank) do
    Repo.all(
      from(t in Taxon,
        join: n in TaxonName,
        on: n.taxon_id == t.id and n.status == :accepted,
        where: n.name == ^name and t.rank == ^rank,
        order_by: t.id
      )
    )
  end

  @doc "The taxa directly under `taxon_id`, by name, with their ranks and common names."
  @spec children_with_ranks(integer()) :: [child()]
  def children_with_ranks(taxon_id) when is_integer(taxon_id),
    do: [taxon_id] |> children_by_parent() |> Map.fetch!(taxon_id)

  @doc """
  The taxa directly under each of `taxon_ids` (as `children_with_ranks/1`
  gives them), by parent ID; a taxon without children has an empty list.
  """
  @spec children_by_parent([integer()]) :: %{integer() => [child()]}
  def children_by_parent([]), do: %{}

  def children_by_parent(taxon_ids) when is_list(taxon_ids) do
    children =
      Repo.all(
        from(t in Taxon,
          join: n in TaxonName,
          on: n.taxon_id == t.id and n.status == :accepted,
          where: t.parent_id in ^taxon_ids,
          order_by: [n.name, t.id],
          select: {t.parent_id, %{taxon_id: t.id, name: n.name, rank: t.rank}}
        )
      )

    names = children |> Enum.map(&elem(&1, 1).taxon_id) |> common_names()

    by_parent =
      Enum.group_by(children, &elem(&1, 0), fn {_parent, child} ->
        Map.put(child, :common_names, Map.get(names, child.taxon_id, []))
      end)

    Map.new(taxon_ids, &{&1, Map.get(by_parent, &1, [])})
  end

  @doc "How many plants each taxon's subtree holds (itself included), by taxon ID."
  @spec count_plants_under([integer()]) :: %{integer() => non_neg_integer()}
  def count_plants_under([]), do: %{}

  def count_plants_under(taxon_ids) when is_list(taxon_ids) do
    counts =
      Repo.all(
        from(a in Ancestry,
          join: t in Taxon,
          on: t.id == a.descendant_id,
          where:
            a.ancestor_id in ^taxon_ids and t.kingdom == "Plantae" and
              t.rank in ^Rank.species_and_below(),
          group_by: a.ancestor_id,
          select: {a.ancestor_id, count(a.descendant_id)}
        )
      )
      |> Map.new()

    Map.new(taxon_ids, &{&1, Map.get(counts, &1, 0)})
  end

  @doc "The plants in `taxon_id`'s subtree (itself included), by name, each with its first common name."
  @spec list_plants_under(integer()) :: [plant()]
  def list_plants_under(taxon_id) when is_integer(taxon_id) do
    plants =
      Repo.all(
        from(a in Ancestry,
          join: t in Taxon,
          on: t.id == a.descendant_id,
          join: n in TaxonName,
          on: n.taxon_id == t.id and n.status == :accepted,
          where:
            a.ancestor_id == ^taxon_id and t.kingdom == "Plantae" and
              t.rank in ^Rank.species_and_below(),
          order_by: [n.name, t.id],
          select: %{id: t.id, name: n.name, rank: t.rank}
        )
      )

    names = common_names(Enum.map(plants, & &1.id))
    Enum.map(plants, &Map.put(&1, :common_name, names |> Map.get(&1.id, []) |> List.first()))
  end

  @doc "Each taxon's lineage (`Gallformers.Taxa.lineage/1`, root first), by taxon ID."
  @spec lineages([integer()]) :: %{integer() => [Gallformers.Taxa.lineage_entry()]}
  def lineages([]), do: %{}

  def lineages(taxon_ids) when is_list(taxon_ids) do
    from(a in Ancestry,
      join: t in Taxon,
      on: t.id == a.ancestor_id,
      join: n in TaxonName,
      on: n.taxon_id == t.id and n.status == :accepted,
      where: a.descendant_id in ^Enum.uniq(taxon_ids),
      order_by: [a.descendant_id, desc: a.depth],
      select: {a.descendant_id, %{taxon_id: t.id, name: n.name, rank: t.rank}}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "Each taxon's ID and the IDs of the taxa below it, by taxon ID."
  @spec subtree_ids([integer()]) :: %{integer() => [integer()]}
  def subtree_ids([]), do: %{}

  def subtree_ids(taxon_ids) when is_list(taxon_ids) do
    from(a in Ancestry,
      where: a.ancestor_id in ^taxon_ids,
      order_by: [a.ancestor_id, a.depth, a.descendant_id],
      select: {a.ancestor_id, a.descendant_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "Each taxon's common names, in the order added, by taxon ID (taxa without any left out)."
  @spec common_names([integer()]) :: %{integer() => [String.t()]}
  def common_names([]), do: %{}

  def common_names(taxon_ids) when is_list(taxon_ids) do
    from(c in CommonName,
      where: c.taxon_id in ^Enum.uniq(taxon_ids),
      order_by: [c.taxon_id, c.id],
      select: {c.taxon_id, c.name}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc """
  The Hosts browse tree: plant families → genera → plants, each by name
  (`Gallformers.Taxa.TreeBuilder` shape; leaves link to `/host/:id`). A
  plant without a genus and family above it is left out; a family or
  genus is described by its common names.
  """
  @spec plant_tree() :: [map()]
  def plant_tree do
    plants =
      Repo.all(
        from(t in Taxon,
          join: n in TaxonName,
          on: n.taxon_id == t.id and n.status == :accepted,
          where: t.kingdom == "Plantae" and t.rank in ^Rank.species_and_below(),
          select: {t.id, n.name}
        )
      )

    lineages = plants |> Enum.map(&elem(&1, 0)) |> lineages()

    rows =
      for {id, name} <- plants,
          lineage = Map.get(lineages, id, []),
          family = Enum.find(lineage, &(&1.rank == :family)),
          genus = Enum.find(lineage, &(&1.rank == :genus)),
          family != nil and genus != nil do
        %{family: family, genus: genus, leaf_id: id, leaf_name: name}
      end

    described = rows |> Enum.flat_map(&[&1.family.taxon_id, &1.genus.taxon_id]) |> common_names()

    rows
    |> Enum.map(fn row ->
      %{
        family_id: row.family.taxon_id,
        family_name: row.family.name,
        family_description: describe(described, row.family.taxon_id),
        genus_id: row.genus.taxon_id,
        genus_name: row.genus.name,
        genus_description: describe(described, row.genus.taxon_id),
        leaf_id: row.leaf_id,
        leaf_name: row.leaf_name
      }
    end)
    |> Enum.sort_by(&{&1.family_name, &1.family_id, &1.genus_name, &1.genus_id, &1.leaf_name})
    |> TreeBuilder.build_tree("/host/")
  end

  # A taxon's common names as one description ("Elms, Oaks"), or nil.
  defp describe(common_names, taxon_id) do
    case Map.get(common_names, taxon_id, []) do
      [] -> nil
      names -> Enum.join(names, ", ")
    end
  end
end
