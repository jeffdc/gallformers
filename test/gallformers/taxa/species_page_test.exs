defmodule Gallformers.Taxa.SpeciesPageTest do
  @moduledoc """
  The species page's taxon read model (`Gallformers.Taxa.species_page/1`):
  a non-plant taxon at species rank or below, with its name and authorship,
  lineage, synonyms, common names and the taxa merged into it (lumps).
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures, only: [plant_fixture: 1]
  import Gallformers.TaxaFixtures

  alias Gallformers.Taxa
  alias Gallformers.Taxa.ReadModels.SpeciesPage

  setup do
    n = System.unique_integer([:positive])
    family = taxon_fixture(rank: :family, name: "Speciidae#{n}", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Specia#{n}", parent: family, kingdom: "Animalia")

    species =
      taxon_fixture(
        name: "Specia#{n} alba",
        authorship: "(Weld, 1959)",
        parent: genus,
        kingdom: "Animalia"
      )

    %{n: n, family: family, genus: genus, species: species}
  end

  describe "a non-plant species" do
    test "has its accepted name, authorship, rank, kingdom and timestamps", ctx do
      assert {:ok, %SpeciesPage{} = page} = Taxa.species_page(ctx.species.id)

      assert page.id == ctx.species.id
      assert page.name == "Specia#{ctx.n} alba"
      assert page.authorship == "(Weld, 1959)"
      assert page.rank == :species
      assert page.kingdom == "Animalia"
      assert %DateTime{} = page.inserted_at
      assert %DateTime{} = page.updated_at
    end

    test "has its lineage, root first, ending with itself", ctx do
      {:ok, page} = Taxa.species_page(ctx.species.id)

      assert Enum.map(page.lineage, & &1.taxon_id) == [
               ctx.family.id,
               ctx.genus.id,
               ctx.species.id
             ]
    end

    test "has its synonyms and common names, each with its ID, by name", ctx do
      {:ok, _} = Taxa.add_synonym(test_actor(), ctx.species, "Cynips zeta")
      {:ok, _} = Taxa.add_synonym(test_actor(), ctx.species, "Cynips beta", sensu: "Smith")
      {:ok, _} = Taxa.add_common_name(test_actor(), ctx.species, "white specia")

      {:ok, page} = Taxa.species_page(ctx.species.id)

      assert [
               %{id: beta_id, name: "Cynips beta", sensu: "Smith"},
               %{id: zeta_id, name: "Cynips zeta", sensu: nil}
             ] = page.synonyms

      assert is_integer(beta_id) and is_integer(zeta_id)
      assert [%{id: common_id, name: "white specia"}] = page.common_names
      assert is_integer(common_id)
    end

    test "a subspecies has a page too", ctx do
      sub =
        taxon_fixture(rank: :subspecies, name: "Specia#{ctx.n} alba minor", parent: ctx.species)

      assert {:ok, %SpeciesPage{rank: :subspecies}} = Taxa.species_page(sub.id)
    end

    test "a taxon with no kingdom recorded is not a plant", ctx do
      taxon = taxon_fixture(name: "Specia#{ctx.n} nuda", parent: ctx.genus)
      assert {:ok, %SpeciesPage{}} = Taxa.species_page(taxon.id)
    end
  end

  describe "lumps" do
    test "lists the taxa merged into it, with their accepted names and when", ctx do
      absorbed = taxon_fixture(name: "Specia#{ctx.n} nigra", parent: ctx.genus)
      {:ok, _} = Taxa.merge(test_actor(), absorbed, ctx.species)

      {:ok, page} = Taxa.species_page(ctx.species.id)

      assert [%{taxon_id: id, name: name, at: %DateTime{}}] = page.merged
      assert id == absorbed.id
      assert name == "Specia#{ctx.n} nigra"
    end

    test "a taxon nothing was merged into has none", ctx do
      {:ok, page} = Taxa.species_page(ctx.species.id)
      assert page.merged == []
    end
  end

  describe "what isn't a species page" do
    test "a plant at species rank is a Host page", _ctx do
      plant = plant_fixture(%{})
      assert {:plant, id} = Taxa.species_page(plant.id)
      assert id == plant.id
    end

    test "a taxon above species rank is its rank's", ctx do
      assert {:higher, %{rank: :genus, name: name}} = Taxa.species_page(ctx.genus.id)
      assert name == "Specia#{ctx.n}"
    end

    test "a missing taxon is not found", _ctx do
      assert Taxa.species_page(-1) == :not_found
    end
  end
end
