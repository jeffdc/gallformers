defmodule Gallformers.Catalog.ApiTest do
  @moduledoc """
  The Catalog reads API v2 lists and shows Galls with
  (`Gallformers.Catalog.ReadModels.Api`, `803b` Task 13).

  Partly the converted seeds (`priv/repo/test_seeds.sql`): Gall 300 is
  Andricus seedii (agamic), with the common name "seed oak apple", a
  detachable Trait and its Inducer's synonym "Callirhytis seedii"; Gall 304
  an undescribed Andricus gall with a former label and a code; Gall 100 a
  Gall with no Inducer.

  Not async: Trait tests load the vocabularies (`Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  # Reading the seeds, converted, is part of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Sources
  alias Gallformers.Taxa

  defp inducer!(taxon, gall) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source_fixture("Weld", "1959"))
      )

    :ok
  end

  defp species_inducer!(gall) do
    inducer!(taxon_fixture(name: "Inducer #{System.unique_integer([:positive])}"), gall)
  end

  defp all_galls, do: Catalog.paginate_galls([]).entries

  describe "paginate_galls/1" do
    test "every Gall by the name shown, with its editorial fields and aliases, and the total" do
      %{entries: galls, total: total} = Catalog.paginate_galls([])
      names = Enum.map(galls, & &1.name)

      assert names == Enum.sort(names)
      assert total == Catalog.count_galls()
      assert length(galls) == total

      assert %{
               id: 300,
               name: "Andricus seedii (agamic)",
               datacomplete: true,
               abundance_id: 1,
               abundance: "common",
               detachable: "detachable",
               undescribed: false
             } = seedii = Enum.find(galls, &(&1.id == 300))

      assert [
               %{name: "seed oak apple", type: "common", description: nil, id: common_id},
               %{name: "Callirhytis seedii", type: "scientific", description: nil, id: syn_id}
             ] = seedii.aliases

      assert is_integer(common_id)
      assert is_integer(syn_id)
    end

    test "an undescribed Gall's former labels and codes are aliases of their kind" do
      gall = Enum.find(all_galls(), &(&1.id == 304))

      assert gall.undescribed == true
      assert gall.detachable == "integral"

      assert Enum.map(gall.aliases, &{&1.name, &1.type}) == [
               {"Andricus q-seed-old-label", "former_label"},
               {"q-seed-code", "code"}
             ]
    end

    test "a Gall with no Inducer is undescribed" do
      assert %{undescribed: true} = Enum.find(all_galls(), &(&1.id == 100))
    end

    test ":limit and :offset page through the same order; the total is every Gall" do
      all = all_galls()
      total = length(all)

      assert Catalog.paginate_galls(limit: 3) == %{entries: Enum.take(all, 3), total: total}

      assert Catalog.paginate_galls(limit: 3, offset: 3) ==
               %{entries: all |> Enum.drop(3) |> Enum.take(3), total: total}

      assert Catalog.paginate_galls(offset: 2).entries == Enum.drop(all, 2)
    end

    test ":q finds Galls as the search does, paged, with the matching total" do
      gall = gall_fixture(name: "Zzyzx bulletus (agamic)", name_override: "Zzyzx shown gall")
      other = gall_fixture(name: "Zzyzx other gall")

      {:ok, _} =
        Catalog.assert_alias(
          test_actor(),
          %{gall_id: gall.id, name: "Mojave quux gall", kind: :common_name},
          confirm(source_fixture("Weld", "1959"))
        )

      assert %{entries: [%{id: id, name: "Zzyzx shown gall"}], total: 1} =
               Catalog.paginate_galls(q: "quux mojave")

      assert id == gall.id

      assert %{entries: [%{id: other_id}], total: 2} =
               Catalog.paginate_galls(q: "zzyzx", limit: 1, offset: 0)

      assert other_id == other.id
      assert Catalog.paginate_galls(q: "zzyzx mojave") == %{entries: [], total: 0}
    end

    test "a blank :q lists every Gall" do
      assert Catalog.paginate_galls(q: "  ").total == Catalog.count_galls()
    end
  end

  describe "gall_details/1" do
    test "a Gall's row with its Hosts and its Traits with their IDs" do
      assert {:ok, details} = Catalog.gall_details(300)

      assert %{id: 300, name: "Andricus seedii (agamic)", undescribed: false} = details
      assert details.hosts == [%{id: 10, name: "Notholithocarpus densiflorus"}]
      assert %{"detachable" => [%{id: value_id, value: "detachable"}]} = details.traits
      assert is_integer(value_id)
    end

    test "Traits carry their values' definitions" do
      load_vocab!()
      gall = gall_fixture()

      {:ok, _} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: gall.id, trait: "color", value: "red"},
          confirm(source_fixture("Weld", "1959"))
        )

      red = Catalog.get_trait_value("color", "red")

      assert {:ok, %{traits: %{"color" => [color]}}} = Catalog.gall_details(gall.id)
      assert color == %{id: red.id, value: "red", definition: red.definition}
    end

    test ":not_found for a missing ID and for an ID that is not a Gall" do
      assert Catalog.gall_details(999_999_999) == :not_found
      assert Catalog.gall_details(10) == :not_found
    end
  end

  describe "list_gall_sources/1" do
    test "the Gall page's Sources: the default citation, then the note" do
      {:ok, page} = Catalog.gall_page(300)

      assert {:ok, sources} = Catalog.list_gall_sources(300)
      assert sources == page.sources
      assert [%{id: 59, note?: false}, %{id: 58, note?: true}] = sources
    end

    test ":not_found for a missing ID" do
      assert Catalog.list_gall_sources(999_999_999) == :not_found
    end
  end

  test "add_undescribed/1 adds whether each card's Gall has no species-rank Inducer" do
    described = gall_fixture()
    species_inducer!(described)
    at_genus = gall_fixture()
    inducer!(taxon_fixture(rank: :genus), at_genus)
    without = gall_fixture()

    cards = Enum.map([described, at_genus, without], &%{id: &1.id})

    assert Enum.map(Catalog.add_undescribed(cards), & &1.undescribed) == [false, true, true]
    assert Catalog.add_undescribed([]) == []
  end

  describe "add_citations/2" do
    test "adds each card's legacy citation of the Source, or its newest note's text" do
      gallformers = gallformers_source()
      noted = gall_fixture()
      {:ok, _} = Sources.store_note(test_actor(), gallformers, noted.id, "Old.", ~D[2020-01-01])
      {:ok, _} = Sources.store_note(test_actor(), gallformers, noted.id, "New.", ~D[2024-01-01])

      assert [%{description: "New.", externallink: nil}] =
               Catalog.add_citations([%{id: noted.id}], gallformers.id)

      assert [%{id: 300, description: description, externallink: link}] =
               Catalog.add_citations([%{id: 300}], 59)

      assert description =~ "seed citation"
      assert link == "https://example.com/seed-slope#p12"
    end

    test "a card the Source neither cites nor notes has neither" do
      assert Catalog.add_citations([%{id: 301}], 59) == [
               %{id: 301, description: nil, externallink: nil}
             ]

      assert Catalog.add_citations([], 59) == []
    end
  end

  test "the Inducer's synonyms are aliases of every Gall it induces" do
    seedii = Taxa.get_by_name("Andricus seedii", :species) |> hd()
    gall = gall_fixture()
    inducer!(seedii, gall)

    assert [%{name: "Callirhytis seedii", type: "scientific"}] =
             Enum.find(all_galls(), &(&1.id == gall.id)).aliases
  end
end
