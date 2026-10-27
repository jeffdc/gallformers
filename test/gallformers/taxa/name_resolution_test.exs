defmodule Gallformers.Taxa.NameResolutionTest do
  @moduledoc """
  Resolving a name as a Source writes it to a taxon (`9449` §3; producer
  guide background, *What Gallformers does on import* step 2): accepted names
  and synonyms, through the normalized-name index, filtered by rank and
  kingdom. Names are not globally unique.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.TaxaFixtures

  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Taxon

  describe "NameNormalizer.normalize/1" do
    test "ignores case and collapses whitespace" do
      assert NameNormalizer.normalize("  ANDRICUS   Rileyi ") == "andricus rileyi"
    end

    test "treats var and var. alike" do
      assert NameNormalizer.normalize("Quercus alba var latiloba") ==
               NameNormalizer.normalize("Quercus alba var. latiloba")
    end

    test "drops a subgenus between genus and epithet" do
      assert NameNormalizer.normalize("Andricus (Callirhytis) quercuspunctata") ==
               "andricus quercuspunctata"
    end

    test "keeps the subgenus of a subgenus name" do
      assert NameNormalizer.normalize("Andricus (Callirhytis)") == "andricus (callirhytis)"
    end

    test "drops the hybrid sign" do
      expected = "quercus bebbiana"
      assert NameNormalizer.normalize("Quercus × bebbiana") == expected
      assert NameNormalizer.normalize("Quercus ×bebbiana") == expected
      assert NameNormalizer.normalize("Quercus x bebbiana") == expected
      assert NameNormalizer.normalize("×Chitalpa tashkentensis") == "chitalpa tashkentensis"
    end

    test "folds ligatures" do
      assert NameNormalizer.normalize("Cynips ﬂocossa") == "cynips flocossa"
    end
  end

  describe "resolve_name/2" do
    test "resolves an accepted name, whatever the case and spacing" do
      taxon = taxon_fixture(name: "Andricus quercuslanigera")

      assert {:ok, %Taxon{id: id} = resolved} =
               Taxa.resolve_name("ANDRICUS  quercuslanigera")

      assert id == taxon.id
      assert resolved.matched_name.status == :accepted
    end

    test "resolves a synonym to its taxon, saying it matched a synonym" do
      taxon = taxon_fixture(name: "Druon quercuslanigerum")
      {:ok, _} = Taxa.add_synonym(test_actor(), taxon, "Andricus quercuslanigera")

      assert {:ok, %Taxon{id: id} = resolved} = Taxa.resolve_name("Andricus quercuslanigera")
      assert id == taxon.id
      assert resolved.matched_name.status == :synonym
      assert resolved.matched_name.name == "Andricus quercuslanigera"
    end

    test "resolves through a subgenus, var. and the hybrid sign" do
      wasp = taxon_fixture(name: "Andricus quercuspunctata")
      oak = taxon_fixture(name: "Quercus alba var. latiloba", rank: :variety)
      hybrid = taxon_fixture(name: "Quercus × bebbiana")

      assert {:ok, %{id: id}} = Taxa.resolve_name("Andricus (Callirhytis) quercuspunctata")
      assert id == wasp.id
      assert {:ok, %{id: id}} = Taxa.resolve_name("Quercus alba var latiloba")
      assert id == oak.id
      assert {:ok, %{id: id}} = Taxa.resolve_name("Quercus x bebbiana")
      assert id == hybrid.id
    end

    test "an unknown name is :none" do
      assert Taxa.resolve_name("Nonesuch imaginaria #{System.unique_integer([:positive])}") ==
               :none
    end

    test "filters by rank" do
      genus = taxon_fixture(name: "Callirhytis", rank: :genus)
      subgenus = taxon_fixture(name: "Callirhytis", rank: :subgenus)

      assert {:ambiguous, [_, _]} = Taxa.resolve_name("Callirhytis")
      assert {:ok, %{id: id}} = Taxa.resolve_name("Callirhytis", rank: :genus)
      assert id == genus.id
      assert {:ok, %{id: id}} = Taxa.resolve_name("Callirhytis", rank: "subgenus")
      assert id == subgenus.id
    end

    test "homonyms in two kingdoms resolve separately with a kingdom filter and ambiguously without" do
      plant = taxon_fixture(name: "Morus", rank: :genus, kingdom: "Plantae", origin: :powo)
      bird = taxon_fixture(name: "Morus", rank: :genus, kingdom: "Animalia")

      assert {:ok, %{id: id}} = Taxa.resolve_name("Morus", kingdom: "Plantae")
      assert id == plant.id
      assert {:ok, %{id: id}} = Taxa.resolve_name("Morus", kingdom: "Animalia")
      assert id == bird.id

      assert {:ambiguous, taxa} = Taxa.resolve_name("Morus")
      assert taxa |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([plant.id, bird.id])
    end

    test "a taxon holds a normalized name once" do
      taxon = taxon_fixture(name: "Andricus foo")

      assert {:error, changeset} =
               Taxa.add_synonym(test_actor(), taxon, "Andricus (Callirhytis) foo")

      assert %{name: ["is already a name of this taxon"]} = errors_on(changeset)
    end

    test "a misapplied name (sensu) resolves only when the same sensu is asked for" do
      real = taxon_fixture(name: "Cynips strobilana")
      misidentified = taxon_fixture(name: "Cynips other")

      {:ok, _} =
        Taxa.add_synonym(test_actor(), misidentified, "Cynips strobilana",
          sensu: "O. S. non Harris"
        )

      assert {:ok, %{id: id}} = Taxa.resolve_name("Cynips strobilana")
      assert id == real.id

      assert {:ok, %{id: id}} = Taxa.resolve_name("Cynips strobilana", sensu: "o. s. non harris")
      assert id == misidentified.id
    end
  end

  describe "resolve_epithet/2" do
    test "finds a species by its epithet in any genus, accepted or synonym" do
      wasp = taxon_fixture(name: "Andricus quercusspongifica")
      other = taxon_fixture(name: "Disholcaspis quercusvirens")
      {:ok, _} = Taxa.add_synonym(test_actor(), other, "Cynips quercusvirens")

      assert {:ok, %Taxon{id: id} = found} = Taxa.resolve_epithet("QuercusSpongifica")
      assert id == wasp.id
      assert found.matched_name.name == "Andricus quercusspongifica"

      assert {:ok, %Taxon{id: id}} = Taxa.resolve_epithet("quercusvirens")
      assert id == other.id
    end

    test "is ambiguous across genera, and filters by rank and kingdom" do
      a = taxon_fixture(name: "Andricus quercusambigua", kingdom: "Animalia")
      b = taxon_fixture(name: "Callirhytis quercusambigua", kingdom: "Animalia")
      plant = taxon_fixture(name: "Quercus quercusambigua", kingdom: "Plantae", origin: :powo)

      assert {:ambiguous, taxa} = Taxa.resolve_epithet("quercusambigua")
      assert taxa |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([a.id, b.id, plant.id])

      assert {:ambiguous, [_, _]} = Taxa.resolve_epithet("quercusambigua", kingdom: "Animalia")
      assert {:ok, %{id: id}} = Taxa.resolve_epithet("quercusambigua", kingdom: "Plantae")
      assert id == plant.id
      assert Taxa.resolve_epithet("quercusambigua", rank: :genus) == :none
    end

    test "matches only the second word of a binomial" do
      taxon_fixture(name: "Quercus alba var. quercustest")
      assert Taxa.resolve_epithet("quercustest") == :none
    end
  end

  describe "genus_names/1" do
    test "keeps the names that are genera in the tree, as given" do
      taxon_fixture(name: "Quercus", rank: :genus, kingdom: "Plantae", origin: :powo)
      genus = taxon_fixture(name: "Disholcaspis", rank: :genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), genus, "Holcaspis")
      # A species' first word is no genus name (the converted seeds have a
      # genus Andricus, so this uses a genus the tree does not have)
      taxon_fixture(name: "Nogenusia foo")

      assert Enum.sort(Taxa.genus_names(["Quercus", "QUERCUS", "Holcaspis", "Nogenusia", "The"])) ==
               ["Holcaspis", "QUERCUS", "Quercus"]

      assert Taxa.genus_names([]) == []
    end
  end
end
