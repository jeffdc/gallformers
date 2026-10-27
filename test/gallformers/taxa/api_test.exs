defmodule Gallformers.Taxa.ApiTest do
  @moduledoc """
  The taxon reads API v2 lists hosts and the taxonomy with
  (`Gallformers.Taxa.ReadModels.Api`, `803b` Task 13).

  Partly the converted seeds (`priv/repo/test_seeds.sql`): Cynipidae >
  Cynipinae > Cynipini > Andricus, Cynips, Neuroterus; Fagaceae >
  Notholithocarpus ("Tanoaks") > plant 10 Notholithocarpus densiflorus
  ("tanoak", synonym Lithocarpus densiflorus). Higher-taxon IDs are new, so
  they are found by name.
  """
  use Gallformers.DataCase, async: true

  # Reading the seeds, converted, is part of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures

  alias Gallformers.Taxa

  defp named(name, rank), do: name |> Taxa.get_by_name(rank) |> hd()

  defp all_plants, do: Taxa.paginate_plants([]).entries
  defp all_genera, do: Taxa.paginate_taxa(:genus, []).entries

  describe "paginate_plants/1" do
    test "plants (Plantae at species rank or below) by name, with completeness, and the total" do
      %{entries: plants, total: total} = Taxa.paginate_plants([])
      names = Enum.map(plants, & &1.name)

      assert names == Enum.sort(names)
      assert total == Taxa.count_plants()
      assert length(plants) == total
      assert %{id: 10, name: "Notholithocarpus densiflorus", datacomplete: true} in plants
      refute Enum.any?(plants, &(&1.name in ["Notholithocarpus", "Andricus seedii"]))
    end

    test "a variety is a plant" do
      variety = plant_fixture(name: "Quercus varietas var. testii", rank: :variety)

      assert variety.id in Enum.map(all_plants(), & &1.id)
    end

    test ":limit and :offset page through the same order; the total is every plant" do
      all = all_plants()

      assert Taxa.paginate_plants(limit: 2) == %{entries: Enum.take(all, 2), total: length(all)}

      assert Taxa.paginate_plants(limit: 2, offset: 2).entries ==
               all |> Enum.drop(2) |> Enum.take(2)
    end

    test ":q finds plants as the search does, with the matching total" do
      assert %{entries: [%{id: 10}], total: 1} = Taxa.paginate_plants(q: "notholithocarpus DENSI")
      assert %{entries: [%{id: 10}]} = Taxa.paginate_plants(q: "lithocarpus densiflorus")

      assert Taxa.paginate_plants(q: "tanoak") == %{
               entries: [%{id: 10, name: "Notholithocarpus densiflorus", datacomplete: true}],
               total: 1
             }

      assert Taxa.paginate_plants(q: "tanoak alba") == %{entries: [], total: 0}
      assert Taxa.paginate_plants(q: "").total == Taxa.count_plants()
    end

    test ":q leaves out taxa that are not plants" do
      assert Taxa.paginate_plants(q: "Notholithocarpus").entries == [
               %{id: 10, name: "Notholithocarpus densiflorus", datacomplete: true}
             ]
    end
  end

  describe "paginate_taxa/2" do
    test "the taxa of a rank by name, with parent and common names as description" do
      %{entries: genera, total: total} = Taxa.paginate_taxa(:genus, [])
      names = Enum.map(genera, & &1.name)

      assert names == Enum.sort(names)
      assert length(genera) == total

      notholithocarpus = named("Notholithocarpus", :genus)
      andricus = named("Andricus", :genus)

      assert %{
               id: notholithocarpus.id,
               name: "Notholithocarpus",
               rank: :genus,
               parent_id: named("Fagaceae", :family).id,
               description: "Tanoaks"
             } in genera

      assert %{parent_id: parent_id, description: nil} =
               Enum.find(genera, &(&1.id == andricus.id))

      assert parent_id == named("Cynipini", :tribe).id
      refute Enum.any?(genera, &(&1.rank != :genus))
    end

    test ":q finds taxa of the rank by name, synonym or common name" do
      genus = plant_fixture(name: "Prefixia", rank: :genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), genus, "Oldprefixia")
      {:ok, _} = Taxa.add_common_name(test_actor(), genus, "Little Prefixes")
      plant_fixture(name: "Prefixia minor", parent_id: genus.id)

      for q <- ["prefixia", "OLDPREF", "little prefixes"] do
        assert %{entries: [%{id: id}], total: 1} = Taxa.paginate_taxa(:genus, q: q)
        assert id == genus.id
      end

      assert Taxa.paginate_taxa(:genus, q: "zzzz") == %{entries: [], total: 0}
    end

    test ":limit and :offset page through the same order" do
      all = all_genera()

      assert Taxa.paginate_taxa(:genus, limit: 2, offset: 1).entries ==
               all |> Enum.drop(1) |> Enum.take(2)
    end
  end

  test "taxon_summary/1: one taxon as paginate_taxa/2 gives it, or nil" do
    cynipinae = named("Cynipinae", :subfamily)

    assert Taxa.taxon_summary(cynipinae.id) == %{
             id: cynipinae.id,
             name: "Cynipinae",
             rank: :subfamily,
             parent_id: named("Cynipidae", :family).id,
             description: nil
           }

    assert Taxa.taxon_summary(999_999_999) == nil
  end

  test "children_by_parent/1: each taxon's direct children by name, batched" do
    cynipini = named("Cynipini", :tribe)
    fagaceae = named("Fagaceae", :family)

    children = Taxa.children_by_parent([cynipini.id, fagaceae.id])

    assert Enum.map(children[cynipini.id], & &1.name) == ["Andricus", "Cynips", "Neuroterus"]

    assert [%{name: "Notholithocarpus", rank: :genus, common_names: ["Tanoaks"]}] =
             children[fagaceae.id]

    assert Taxa.children_by_parent([]) == %{}
    assert Taxa.children_by_parent([10]) == %{10 => []}
  end

  test "list_sections/0: sections with their genus and how many plants they hold" do
    genus = named("Notholithocarpus", :genus)

    section =
      plant_fixture(name: "Notholithocarpus sect. Testia", rank: :section, parent_id: genus.id)

    {:ok, _} = Taxa.add_common_name(test_actor(), section, "Test tanoaks")
    plant_fixture(parent_id: section.id)

    assert %{
             id: section.id,
             name: "Notholithocarpus sect. Testia",
             description: "Test tanoaks",
             genus_id: genus.id,
             genus_name: "Notholithocarpus",
             species_count: 1
           } in Taxa.list_sections()
  end

  test "list_synonyms_by_taxon/1: each taxon's synonyms in the order added, batched" do
    plant = plant_fixture()
    {:ok, first} = Taxa.add_synonym(test_actor(), plant, "Firstia")
    {:ok, second} = Taxa.add_synonym(test_actor(), plant, "Secondia", sensu: "auct.")
    [lithocarpus] = Taxa.list_synonyms(10)

    assert Taxa.list_synonyms_by_taxon([plant.id, 10]) == %{
             plant.id => [
               %{id: first.id, name: "Firstia", sensu: nil},
               %{id: second.id, name: "Secondia", sensu: "auct."}
             ],
             10 => [%{id: lithocarpus.id, name: "Lithocarpus densiflorus", sensu: nil}]
           }

    assert Taxa.list_synonyms_by_taxon([]) == %{}
  end
end
