defmodule Gallformers.Taxa.SearchTest do
  @moduledoc """
  The ID tool's typeaheads over taxa (`803b` Task 9):
  `Taxa.search_plants/2` (plants by accepted name, synonym or common name,
  ranked as today's `Plants.search_hosts/2`) and
  `Taxa.search_genera_and_sections/3`.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.TaxaFixtures

  alias Gallformers.Taxa

  defp plant(attrs), do: taxon_fixture(Map.merge(%{kingdom: "Plantae", origin: :powo}, attrs))

  describe "search_plants/2" do
    setup do
      genus = plant(%{rank: :genus, name: "Zyxquercus"})
      alba = plant(%{name: "Zyxquercus alba", parent: genus})
      albida = plant(%{name: "Zyxquercus albida", parent: genus})
      rubra = plant(%{name: "Zyxquercus rubra", parent: genus})
      variety = plant(%{rank: :variety, name: "Zyxquercus rubra var. zyxa", parent: rubra})
      {:ok, _} = Taxa.add_synonym(test_actor(), rubra, "Zyxquercus borealis")
      {:ok, _} = Taxa.add_common_name(test_actor(), alba, "zyx white oak")
      _wasp = taxon_fixture(name: "Zyxquercus alba wasp", kingdom: "Animalia")

      %{genus: genus, alba: alba, albida: albida, rubra: rubra, variety: variety}
    end

    defp names(results), do: Enum.map(results, & &1.name)

    test "every word must match a name; plants only, at species rank or below", ctx do
      assert names(Taxa.search_plants("zyxq alb", 10)) == ["Zyxquercus alba", "Zyxquercus albida"]
      refute ctx.genus.id in Enum.map(Taxa.search_plants("zyxquercus", 10), & &1.id)
      assert "Zyxquercus rubra var. zyxa" in names(Taxa.search_plants("zyxquercus", 10))
    end

    test "finds a plant by a synonym or a common name, giving its accepted name", ctx do
      assert [%{id: id, name: "Zyxquercus rubra"}] = Taxa.search_plants("borealis", 10)
      assert id == ctx.rubra.id

      assert [%{id: id, aliases: aliases}] = Taxa.search_plants("zyx white", 10)
      assert id == ctx.alba.id
      assert aliases == ["zyx white oak"]
    end

    test "ranks an exact name first, then names starting with the query, then the rest" do
      plant(%{name: "Zyxa alpha beta"})
      plant(%{name: "Zyxa beta gamma"})
      plant(%{name: "Zyxa beta"})

      assert names(Taxa.search_plants("zyxa beta", 10)) ==
               ["Zyxa beta", "Zyxa beta gamma", "Zyxa alpha beta"]

      assert hd(names(Taxa.search_plants("zyx white oak", 10))) == "Zyxquercus alba"

      # "rubra" is inside the names, never at their start: by name.
      assert names(Taxa.search_plants("rubra zyx", 10)) ==
               ["Zyxquercus rubra", "Zyxquercus rubra var. zyxa"]
    end

    test "gives each plant's rank, data-complete flag, synonyms and common names", ctx do
      assert [result] = Taxa.search_plants("zyxquercus rubra", 1)

      assert result == %{
               id: ctx.rubra.id,
               name: "Zyxquercus rubra",
               rank: :species,
               datacomplete: false,
               aliases: ["Zyxquercus borealis"]
             }
    end

    test "nothing for a blank query" do
      assert Taxa.search_plants("  ", 10) == []
    end
  end

  describe "search_genera_and_sections/3" do
    setup do
      family = plant(%{rank: :family, name: "Zyxaceae"})
      genus = plant(%{rank: :genus, name: "Zyxquercus", parent: family})
      subgenus = plant(%{rank: :subgenus, name: "Zyxquercus subg. Zyxa", parent: genus})
      section = plant(%{rank: :section, name: "Zyxlobatae", parent: genus})
      {:ok, _} = Taxa.add_common_name(test_actor(), genus, "zyx oaks")
      {:ok, _} = Taxa.add_common_name(test_actor(), section, "zyx red oaks")

      animal =
        taxon_fixture(rank: :genus, name: "Zyxandricus", kingdom: "Animalia", origin: :curated)

      %{family: family, genus: genus, subgenus: subgenus, section: section, animal: animal}
    end

    test "matches names by prefix and common names anywhere, genera before sections", ctx do
      results = Taxa.search_genera_and_sections("zyx", 10, kingdom: "Plantae")

      assert Enum.map(results, & &1.id) == [ctx.genus.id, ctx.subgenus.id, ctx.section.id]

      assert hd(results) == %{
               id: ctx.genus.id,
               name: "Zyxquercus",
               rank: :genus,
               description: "zyx oaks"
             }

      assert [%{id: id}] = Taxa.search_genera_and_sections("red oak", 10, kingdom: "Plantae")
      assert id == ctx.section.id
    end

    test "without a kingdom, every kingdom's", ctx do
      ids = Enum.map(Taxa.search_genera_and_sections("zyx", 10), & &1.id)
      assert ctx.animal.id in ids
      refute ctx.family.id in ids
      assert length(Taxa.search_genera_and_sections("zyx", 2)) == 2
    end

    test "a name inside another word does not match", ctx do
      assert Taxa.search_genera_and_sections("quercus", 10, kingdom: "Plantae") == []
      assert [%{id: id}] = Taxa.search_genera_and_sections("zyxlob", 10, kingdom: "Plantae")
      assert id == ctx.section.id
    end
  end

  describe "search/2 (global search, `803b` Task 11)" do
    setup do
      family = plant(%{rank: :family, name: "Zyxsearchaceae"})
      genus = plant(%{rank: :genus, name: "Zyxsearcha", parent: family})
      oak = plant(%{name: "Zyxsearcha alba", parent: genus})
      {:ok, _} = Taxa.add_synonym(test_actor(), oak, "Zyxoldus albus")
      {:ok, _} = Taxa.add_common_name(test_actor(), oak, "zyx ghost oak")
      wasps = taxon_fixture(rank: :genus, name: "Zyxsearcha", kingdom: "Animalia")
      wasp = taxon_fixture(name: "Zyxsearcha wasp", kingdom: "Animalia", parent: wasps)

      %{family: family, genus: genus, oak: oak, wasps: wasps, wasp: wasp}
    end

    defp ids(results), do: results |> Enum.map(& &1.id) |> Enum.sort()

    test "finds a taxon by its accepted name, a synonym or a common name", ctx do
      assert [%{id: id, name: "Zyxsearcha alba"}] = Taxa.search("zyxoldus", [])
      assert id == ctx.oak.id
      assert [%{id: ^id}] = Taxa.search("ghost oak", [])
      assert [%{id: ^id}] = Taxa.search("zyxsearcha alba", [])
    end

    test "every word must match one name of the taxon (or its accepted name)", ctx do
      assert ids(Taxa.search("zyxs alb", [])) == [ctx.oak.id]
      assert Taxa.search("zyxsearcha nothing", []) == []
      assert Taxa.search("  ", []) == []
    end

    test "a name held by two taxa returns both", ctx do
      assert ids(Taxa.search("zyxsearcha", ranks: [:genus])) ==
               Enum.sort([ctx.genus.id, ctx.wasps.id])
    end

    test "narrows by rank and kingdom", ctx do
      assert ids(Taxa.search("zyxsearcha", kingdom: "Plantae")) ==
               Enum.sort([ctx.family.id, ctx.genus.id, ctx.oak.id])

      assert ids(Taxa.search("zyxsearcha", ranks: [:species], kingdom: "Animalia")) ==
               [ctx.wasp.id]

      assert ids(Taxa.search("zyxsearch", ranks: [:family, :genus])) ==
               Enum.sort([ctx.family.id, ctx.genus.id, ctx.wasps.id])
    end

    test "gives each taxon's accepted name, rank, kingdom, parent and aliases, by name", ctx do
      assert [first | _] = Taxa.search("zyxsearch", kingdom: "Plantae")
      assert first.id == ctx.genus.id

      assert [result] = Taxa.search("zyx ghost", [])

      assert result == %{
               id: ctx.oak.id,
               name: "Zyxsearcha alba",
               rank: :species,
               kingdom: "Plantae",
               parent_id: ctx.genus.id,
               datacomplete: false,
               aliases: ["Zyxoldus albus", "zyx ghost oak"]
             }
    end

    test "search_ids/2 gives the IDs search/2 finds", ctx do
      assert Enum.sort(Taxa.search_ids("zyxoldus", ranks: [:species])) == [ctx.oak.id]
      assert Taxa.search_ids("zyxoldus", kingdom: "Animalia") == []
      assert Taxa.search_ids("", []) == []
    end
  end

  describe "list_synonyms_by_taxon/1" do
    test "leaves out taxa without synonyms" do
      taxon = taxon_fixture(name: "Zyxsyn a")
      plain = taxon_fixture(name: "Zyxsyn b")
      {:ok, _} = Taxa.add_synonym(test_actor(), taxon, "Zyxsyn older")
      {:ok, _} = Taxa.add_synonym(test_actor(), taxon, "Zyxsyn oldest")

      synonyms = Taxa.list_synonyms_by_taxon([taxon.id, plain.id])

      assert Map.keys(synonyms) == [taxon.id]
      assert Enum.map(synonyms[taxon.id], & &1.name) == ["Zyxsyn older", "Zyxsyn oldest"]
    end
  end
end
