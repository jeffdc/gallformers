defmodule Gallformers.Taxa.AncestryTest do
  @moduledoc """
  The ancestry read model (`9449` §3): descendants and ancestors from the
  closure table, kept in step when a subtree moves.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.TaxaFixtures

  alias Gallformers.Taxa
  alias Gallformers.Taxa.Ancestry
  alias Gallformers.Taxa.Taxon

  defp ids(taxa), do: Enum.map(taxa, & &1.id)

  # The closure rows of a subtree, as {ancestor, descendant, depth}, sorted.
  defp closure(taxa) do
    taxon_ids = ids(taxa)

    Repo.all(
      from a in Ancestry,
        where: a.descendant_id in ^taxon_ids,
        select: {a.ancestor_id, a.descendant_id, a.depth},
        order_by: [a.descendant_id, a.depth]
    )
  end

  setup do
    order = taxon_fixture(rank: :order, name: "Hymenoptera")
    cynipidae = taxon_fixture(rank: :family, name: "Cynipidae", parent: order)
    other_family = taxon_fixture(rank: :family, name: "Figitidae", parent: order)
    tribe = taxon_fixture(rank: :tribe, name: "Cynipini", parent: cynipidae)
    genus = taxon_fixture(rank: :genus, name: "Andricus", parent: tribe)
    species_a = taxon_fixture(rank: :species, name: "Andricus a", parent: genus)
    species_b = taxon_fixture(rank: :species, name: "Andricus b", parent: genus)
    variety = taxon_fixture(rank: :variety, name: "Andricus a var. c", parent: species_a)

    %{
      order: order,
      cynipidae: cynipidae,
      other_family: other_family,
      tribe: tribe,
      genus: genus,
      species_a: species_a,
      species_b: species_b,
      variety: variety
    }
  end

  test "descendants of a genus, nearest first", ctx do
    assert ids(Taxa.descendants(ctx.genus)) == [
             ctx.species_a.id,
             ctx.species_b.id,
             ctx.variety.id
           ]

    assert Taxa.descendants(ctx.variety) == []
  end

  test "ancestors of a species, nearest first", ctx do
    assert ids(Taxa.ancestors(ctx.variety)) ==
             ids([ctx.species_a, ctx.genus, ctx.tribe, ctx.cynipidae, ctx.order])

    assert Taxa.ancestors(ctx.order) == []
  end

  test "after a move, descendants and ancestors follow the new placement", ctx do
    {:ok, _} = Taxa.place(test_actor(), ctx.genus, ctx.other_family)

    assert ids(Taxa.descendants(ctx.genus)) == [
             ctx.species_a.id,
             ctx.species_b.id,
             ctx.variety.id
           ]

    assert ids(Taxa.descendants(ctx.tribe)) == []

    assert ids(Taxa.descendants(ctx.other_family)) ==
             [ctx.genus.id, ctx.species_a.id, ctx.species_b.id, ctx.variety.id]

    assert ids(Taxa.ancestors(ctx.variety)) ==
             ids([ctx.species_a, ctx.genus, ctx.other_family, ctx.order])

    assert ids(Taxa.descendants(ctx.order)) |> Enum.sort() ==
             Enum.sort(
               ids([
                 ctx.cynipidae,
                 ctx.other_family,
                 ctx.tribe,
                 ctx.genus,
                 ctx.species_a,
                 ctx.species_b,
                 ctx.variety
               ])
             )
  end

  test "after several moves, the closure is exactly what parent_id implies", ctx do
    {:ok, _} = Taxa.place(test_actor(), ctx.genus, ctx.other_family)
    {:ok, _} = Taxa.place(test_actor(), ctx.species_b, nil)
    {:ok, _} = Taxa.place(test_actor(), ctx.genus, ctx.tribe)

    all = ctx |> Map.values() |> Enum.filter(&is_struct(&1, Taxon))
    parents = Map.new(all, &{&1.id, Taxa.get_taxon!(&1.id).parent_id})

    expected =
      all
      |> Enum.flat_map(fn taxon ->
        taxon.id
        |> chain(parents)
        |> Enum.with_index()
        |> Enum.map(fn {ancestor_id, depth} -> {ancestor_id, taxon.id, depth} end)
      end)
      |> Enum.sort_by(fn {_a, d, depth} -> {d, depth} end)

    assert closure(all) == expected
  end

  # The taxon and its ancestors, nearest first.
  defp chain(nil, _parents), do: []
  defp chain(id, parents), do: [id | chain(Map.get(parents, id), parents)]
end
