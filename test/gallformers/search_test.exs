defmodule Gallformers.SearchTest do
  @moduledoc """
  The global search (`803b` Task 11): Galls from `Gallformers.Catalog`,
  plants and higher taxa from `Gallformers.Taxa`; glossary, Sources and
  places as before. Seed names are the converted test seeds
  (`priv/repo/test_seeds.sql` through the catalog migration).
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Search
  alias Gallformers.Taxa

  defp names(results), do: Enum.map(results, & &1.name)

  defp inducer!(taxon, gall, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source)
      )

    :ok
  end

  describe "global_search/2 multi-term matching" do
    test "multi-word query matches species with each term independently" do
      # "q alba" should match "Quercus alba" — "q" in "Quercus", "alba" in "alba"
      results = Search.global_search("q alba")
      assert "Quercus alba" in names(results.hosts)
    end

    test "multi-word query matches galls with each term independently" do
      # "And crystal" should match "Andricus crystallinus"
      results = Search.global_search("And crystal")
      assert "Andricus crystallinus" in names(results.galls)
    end

    test "multi-word query does not match when a term is absent" do
      # "quercus zzz" should not match anything — "zzz" isn't in any name
      results = Search.global_search("quercus zzz")
      assert results.hosts == []
      assert results.galls == []
    end

    test "a blank query finds nothing" do
      assert Search.global_search("   ") == Search.empty_results()
    end
  end

  describe "global_search/2 result shapes" do
    test "a Gall: its ID, display name, type, undescribed flag, aliases and score" do
      results = Search.global_search("Andricus quercuscalifornicus")
      gall = Enum.find(results.galls, &(&1.name == "Andricus quercuscalifornicus"))

      assert %{id: 100, type: "gall", undescribed: true, match_score: -1} = gall
      assert "Oak Apple Gall Wasp" in gall.aliases
    end

    test "a host: its taxon ID, accepted name, type, synonyms and common names" do
      results = Search.global_search("Notholithocarpus")
      host = Enum.find(results.hosts, &(&1.id == 10))

      assert %{
               name: "Notholithocarpus densiflorus",
               type: "host",
               genus_placeholder: false,
               aliases: ["Lithocarpus densiflorus", "tanoak"]
             } = host
    end

    test "a higher taxon: its type, rank, common names and parent" do
      results = Search.global_search("Notholithocarpus")
      genus = Enum.find(results.taxonomy, &(&1.name == "Notholithocarpus"))

      assert %{
               type: "genus",
               rank: nil,
               description: "Tanoaks",
               parent_name: "Fagaceae",
               parent_type: "family",
               parent_rank: nil
             } = genus

      tribe = Enum.find(Search.global_search("Cynipini").taxonomy, &(&1.name == "Cynipini"))

      assert %{type: "intermediate", rank: "Tribe", parent_name: "Cynipinae"} = tribe
      assert %{parent_type: "intermediate", parent_rank: "Subfamily"} = tribe
    end

    test "a family has no parent shown above the family pages' ranks" do
      order = taxon_fixture(rank: :order, name: "Qxorderales", kingdom: "Animalia")
      taxon_fixture(rank: :family, name: "Qxfamilidae", kingdom: "Animalia", parent: order)

      assert [family] = Search.global_search("Qxfamilidae").taxonomy
      assert %{type: "family", parent_name: nil, parent_type: nil} = family
      assert Search.global_search("Qxorderales").taxonomy == []
    end
  end

  describe "global_search/2 over names" do
    test "a synonym finds its taxon" do
      results = Search.global_search("Lithocarpus densiflorus")
      assert "Notholithocarpus densiflorus" in names(results.hosts)

      genus = taxon_fixture(rank: :genus, name: "Qxnewgenus", kingdom: "Animalia")
      {:ok, _} = Taxa.add_synonym(test_actor(), genus, "Qxoldgenus")

      assert ["Qxnewgenus"] = names(Search.global_search("Qxoldgenus").taxonomy)
    end

    test "a common name finds its taxon" do
      assert "Quercus alba" in names(Search.global_search("white oak").hosts)
    end

    test "a gall alias or former label finds the Gall" do
      source = source_fixture("Weld", "1959")
      gall = gall_fixture(name: "Unknown qx-stem-swelling")

      {:ok, _} =
        Catalog.assert_alias(
          test_actor(),
          %{gall_id: gall.id, name: "Qxandricus q-old-stem-label", kind: :former_label},
          confirm(source)
        )

      {:ok, _} =
        Catalog.assert_alias(
          test_actor(),
          %{gall_id: gall.id, name: "qxwoolly stem gall", kind: :common_name},
          confirm(source)
        )

      for query <- ["q-old-stem", "qxwoolly stem"] do
        assert [%{id: id}] = Search.global_search(query).galls
        assert id == gall.id
      end
    end

    test "an Inducer synonym finds its Galls" do
      source = source_fixture("Weld", "1959")
      wasp = taxon_fixture(name: "Qxandricus seedii", kingdom: "Animalia")
      {:ok, _} = Taxa.add_synonym(test_actor(), wasp, "Qxcallirhytis seedii")
      agamic = gall_fixture(name: "Qxandricus seedii (agamic)")
      sexgen = gall_fixture(name: "Qxandricus seedii (sexgen)")
      inducer!(wasp, agamic, source)
      inducer!(wasp, sexgen, source)

      galls = Search.global_search("Qxcallirhytis").galls

      assert Enum.sort(Enum.map(galls, & &1.id)) == Enum.sort([agamic.id, sexgen.id])
      assert Enum.map(galls, & &1.aliases) == [["Qxcallirhytis seedii"], ["Qxcallirhytis seedii"]]
    end

    test "a name held by two taxa returns both" do
      plant = plant_fixture(rank: :genus, name: "Qxtwinus")
      animal = taxon_fixture(rank: :genus, name: "Qxtwinus", kingdom: "Animalia")

      ids = Search.global_search("Qxtwinus").taxonomy |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([plant.id, animal.id])
    end

    test "results are ranked by match quality" do
      plant_fixture(name: "Qxrank alba")
      plant_fixture(name: "Qxrankus albatus")
      plant_fixture(name: "Zz qxrank alba")

      assert names(Search.global_search("qxrank alba").hosts) ==
               ["Qxrank alba", "Qxrankus albatus", "Zz qxrank alba"]
    end
  end

  describe "global_search/2 with continent scoping" do
    test "galls with NA hosts appear in XN search" do
      results = Search.global_search("Andricus", "XN")
      assert "Andricus quercuscalifornicus" in names(results.galls)
    end

    test "galls with only NA hosts excluded from XE search" do
      results = Search.global_search("Andricus", "XE")
      refute "Andricus quercuscalifornicus" in names(results.galls)
    end

    test "European gall appears in XE search" do
      results = Search.global_search("Cynips", "XE")
      assert "Cynips quercusfolii" in names(results.galls)
    end

    test "European gall excluded from XN search" do
      results = Search.global_search("Cynips", "XN")
      refute "Cynips quercusfolii" in names(results.galls)
    end

    test "hosts with NA ranges appear in XN search" do
      results = Search.global_search("Thymus", "XN")
      assert "Thymus alpinus" in names(results.hosts)
    end

    test "hosts with only NA ranges excluded from XE search" do
      results = Search.global_search("Thymus", "XE")
      refute "Thymus alpinus" in names(results.hosts)
    end

    test "European host appears in XE search" do
      results = Search.global_search("Quercus robur", "XE")
      assert "Quercus robur" in names(results.hosts)
    end

    test "glossary/taxonomy/source results unaffected by continent" do
      # These should be identical regardless of continent
      all_results = Search.global_search("test", nil)
      na_results = Search.global_search("test", "XN")

      assert all_results.glossary == na_results.glossary
      assert all_results.sources == na_results.sources
      assert all_results.taxonomy == na_results.taxonomy
    end

    test "everywhere Galls appear in every continent search" do
      # A Gall whose Hosts have no range data is everywhere (`gall_index`).
      source = source_fixture("Weld", "1959")
      gall = gall_fixture(name: "Norangia mysterius")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "host_of", subject_taxon_id: plant_fixture().id, object_gall_id: gall.id},
          confirm(source)
        )

      for continent <- ["XN", "XE"] do
        assert "Norangia mysterius" in names(Search.global_search("Norangia", continent).galls)
      end

      # Seed gall 102 (Callirhytis quercuspunctata) is everywhere too.
      assert "Callirhytis quercuspunctata" in names(
               Search.global_search("Callirhytis", "XE").galls
             )
    end

    test "an unknown continent code filters nothing" do
      results = Search.global_search("Andricus", "XZ")
      assert "Andricus quercuscalifornicus" in names(results.galls)
    end

    test "nil continent returns all results" do
      all_results = Search.global_search("Andricus", nil)
      assert "Andricus quercuscalifornicus" in names(all_results.galls)
    end
  end
end
