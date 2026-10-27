defmodule Gallformers.Taxa.TreePagesTest do
  @moduledoc """
  The taxon reads behind the rank pages and the Hosts browse tree
  (`803b` Task 6): taxa by name and rank, children, plants under a taxon,
  batched lineages and subtrees, and `Gallformers.Taxa.plant_tree/0`.

  Mostly the converted seeds (`priv/repo/test_seeds.sql`): Cynipidae >
  Cynipinae > Cynipini > Andricus, Cynips, Neuroterus; Fagaceae >
  Notholithocarpus > plant 10 Notholithocarpus densiflorus ("tanoak").
  Higher-taxon IDs are new, so they are found through the crosswalk.
  """
  use Gallformers.DataCase, async: true

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon

  defp old(id), do: Taxa.get_by_legacy_id(:taxonomy, id)

  describe "get_by_name/2" do
    test "finds the taxa of a rank by accepted name" do
      assert [%Taxon{id: id}] = Taxa.get_by_name("Cynipidae", :family)
      assert id == old(30).id
    end

    test "the rank must match, and an unknown name finds nothing" do
      assert Taxa.get_by_name("Cynipinae", :tribe) == []
      assert Taxa.get_by_name("Nonexistentia", :genus) == []
    end

    test "a name used in two kingdoms finds both, by ID" do
      animal = taxon_fixture(name: "Homonymia", rank: :genus, kingdom: "Animalia")
      plant = plant_fixture(name: "Homonymia", rank: :genus)

      assert Enum.map(Taxa.get_by_name("Homonymia", :genus), & &1.id) == [animal.id, plant.id]
    end

    test "a synonym is not a page name" do
      plant = plant_fixture(rank: :genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), plant, "Synonymia")

      assert Taxa.get_by_name("Synonymia", :genus) == []
    end
  end

  test "children_with_ranks/1: the direct children by name, with their ranks and common names" do
    neuroterus = old(36)
    {:ok, _} = Taxa.add_common_name(test_actor(), neuroterus, "jumping gall wasps")

    assert Taxa.children_with_ranks(old(32).id) == [
             %{taxon_id: old(33).id, name: "Andricus", rank: :genus, common_names: []},
             %{taxon_id: old(34).id, name: "Cynips", rank: :genus, common_names: []},
             %{
               taxon_id: neuroterus.id,
               name: "Neuroterus",
               rank: :genus,
               common_names: ["jumping gall wasps"]
             }
           ]

    assert Taxa.children_with_ranks(10) == []
  end

  test "count_plants_under/1: plants at species rank or below in each subtree" do
    variety = plant_fixture(name: "Notholithocarpus densiflorus var. echinoides", rank: :variety)
    {:ok, _} = Taxa.place(test_actor(), variety, 10)

    fagaceae = old(40).id
    genus = old(41).id
    cynipidae = old(30).id

    assert Taxa.count_plants_under([fagaceae, genus, cynipidae, 10]) ==
             %{fagaceae => 2, genus => 2, cynipidae => 0, 10 => 2}

    assert Taxa.count_plants_under([]) == %{}
  end

  test "list_plants_under/1: the plants in a subtree by name, with a common name" do
    assert Taxa.list_plants_under(old(41).id) == [
             %{
               id: 10,
               name: "Notholithocarpus densiflorus",
               rank: :species,
               common_name: "tanoak"
             }
           ]

    assert Taxa.list_plants_under(old(33).id) == []
  end

  test "lineages/1: each taxon's lineage, root first" do
    lineages = Taxa.lineages([10, old(33).id])

    assert Enum.map(lineages[10], & &1.name) ==
             ["Fagaceae", "Notholithocarpus", "Notholithocarpus densiflorus"]

    assert Enum.map(lineages[old(33).id], &{&1.name, &1.rank}) == [
             {"Cynipidae", :family},
             {"Cynipinae", :subfamily},
             {"Cynipini", :tribe},
             {"Andricus", :genus}
           ]

    assert Taxa.lineages([]) == %{}
  end

  test "subtree_ids/1: each taxon and the taxa below it" do
    genus = old(41).id
    subtrees = Taxa.subtree_ids([genus, 10])

    assert Enum.sort(subtrees[genus]) == [10, genus]
    assert subtrees[10] == [10]
  end

  describe "plant_tree/0" do
    test "is family > genus > plant, with today's node shape" do
      fagaceae = old(40)
      genus = old(41)

      family = Enum.find(Taxa.plant_tree(), &(&1.name == "Fagaceae"))

      assert %{
               key: key,
               label: "Fagaceae",
               rank: "family",
               description: nil,
               url: "/family/Fagaceae",
               nodes: [genus_node]
             } = family

      assert key == "f-#{fagaceae.id}"

      assert genus_node.key == "g-#{genus.id}"
      assert genus_node.url == "/genus/Notholithocarpus"
      assert genus_node.rank == "genus"

      assert genus_node.nodes == [
               %{
                 key: "s-10",
                 label: "Notholithocarpus densiflorus",
                 url: "/host/10",
                 genus_placeholder: false
               }
             ]
    end

    test "families, genera and plants are by name; a genus's common names describe it" do
      family = plant_fixture(name: "Zfixturaceae", rank: :family)
      genus = plant_fixture(name: "Zfixturus", rank: :genus, parent: family)
      {:ok, _} = Taxa.add_common_name(test_actor(), genus, "Elms")
      plant_fixture(name: "Zfixturus beta", parent: genus)
      plant_fixture(name: "Zfixturus alpha", parent: genus)

      tree = Taxa.plant_tree()
      names = Enum.map(tree, & &1.name)
      assert names == Enum.sort(names)

      assert %{nodes: [genus_node]} = Enum.find(tree, &(&1.name == "Zfixturaceae"))
      assert {genus_node.label, genus_node.description} == {"Zfixturus (Elms)", "Elms"}
      assert Enum.map(genus_node.nodes, & &1.label) == ["Zfixturus alpha", "Zfixturus beta"]
    end

    test "leaves out plants without a genus and taxa of other kingdoms" do
      labels =
        for family <- Taxa.plant_tree(),
            genus <- family.nodes,
            leaf <- genus.nodes,
            do: leaf.label

      refute "Quercus alba" in labels
      refute Enum.any?(Taxa.plant_tree(), &(&1.name == "Cynipidae"))
    end
  end
end
