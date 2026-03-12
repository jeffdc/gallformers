defmodule Gallformers.SpeciesTest do
  @moduledoc """
  Unit tests for the Species context.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Galls
  alias Gallformers.Galls.GallTraits
  alias Gallformers.Repo
  alias Gallformers.Species

  # Test seeds: galls 100-103, 200-201; plants 1-9

  describe "list_species/0" do
    test "returns all seeded species" do
      species = Species.list_species()
      # 9 plants + 6 galls = 15 species
      assert length(species) == 15
    end
  end

  describe "list_galls/0" do
    test "returns only gall species with correct fields" do
      galls = Galls.list_galls()
      assert length(galls) == 6
      assert Enum.all?(galls, &(&1.taxoncode == "gall"))
    end

    test "returns galls ordered by name" do
      galls = Galls.list_galls()
      names = Enum.map(galls, & &1.name)
      assert names == Enum.sort(names)
    end
  end

  describe "list_galls_paginated/2" do
    test "returns limited number of galls" do
      galls = Galls.list_galls_paginated(3, 0)
      assert length(galls) == 3
    end

    test "respects offset parameter" do
      # 6 galls total, page size 3
      first_page = Galls.list_galls_paginated(3, 0)
      second_page = Galls.list_galls_paginated(3, 3)

      assert length(first_page) == 3
      assert length(second_page) == 3

      first_ids = MapSet.new(Enum.map(first_page, & &1.id))
      second_ids = MapSet.new(Enum.map(second_page, & &1.id))
      assert MapSet.disjoint?(first_ids, second_ids)
    end
  end

  describe "count_galls/0" do
    test "returns count matching seeded galls" do
      assert Galls.count_galls() == 6
    end

    test "count matches length of list_galls" do
      assert Galls.count_galls() == length(Galls.list_galls())
    end
  end

  describe "get_species/1" do
    test "returns nil for non-existent ID" do
      assert nil == Species.get_species(999_999_999)
    end

    test "returns species for valid ID" do
      species = Species.get_species(100)
      assert species.id == 100
      assert species.name == "Andricus quercuscalifornicus"
    end
  end

  describe "get_species!/1" do
    test "raises for non-existent ID" do
      assert_raise Ecto.NoResultsError, fn ->
        Species.get_species!(999_999_999)
      end
    end
  end

  describe "get_gall_by_id/1" do
    test "returns nil for non-existent gall" do
      assert nil == Galls.get_gall(999_999_999)
    end

    test "returns gall with traits for valid ID" do
      gall = Galls.get_gall(100)
      assert gall.id == 100
      assert gall.name == "Andricus quercuscalifornicus"
      assert gall.detachable == "integral"
      assert gall.undescribed == false
    end
  end

  describe "get_gall_by_name/1" do
    test "returns nil for non-existent name" do
      assert nil == Galls.get_gall_by_name("Nonexistent species name xyz")
    end

    test "returns gall for valid name" do
      gall = Galls.get_gall_by_name("Amphibolips confluenta")
      assert gall.id == 101
    end
  end

  describe "get_images_for_species/1" do
    test "returns empty list for non-existent species" do
      assert Species.get_images_for_species(999_999_999) == []
    end

    test "returns empty list for species with no images" do
      # No images seeded for any species
      assert Species.get_images_for_species(100) == []
    end
  end

  describe "get_aliases_for_species/1" do
    test "returns empty list for non-existent species" do
      assert Species.get_aliases_for_species(999_999_999) == []
    end

    test "returns aliases for species that has them" do
      # Species 100 (A. quercuscalifornicus) has alias "Oak Apple Gall Wasp"
      aliases = Species.get_aliases_for_species(100)
      assert length(aliases) == 1
      assert hd(aliases).name == "Oak Apple Gall Wasp"
      assert hd(aliases).type == "common"
    end
  end

  describe "random_gall/0" do
    test "returns nil when no galls have images" do
      # No images seeded, so random_gall should return nil
      assert Galls.random_gall() == nil
    end
  end

  describe "get_default_gall_images/0" do
    test "returns empty list when no images are seeded" do
      assert Galls.get_default_gall_images() == []
    end
  end

  describe "list_abundances/0" do
    test "returns all seeded abundances" do
      abundances = Species.list_abundances()
      assert length(abundances) == 3
      names = Enum.map(abundances, & &1.abundance) |> Enum.sort()
      assert names == ["common", "rare", "uncommon"]
    end
  end

  describe "get_abundance/1" do
    test "returns nil for non-existent abundance" do
      assert nil == Species.get_abundance(999_999_999)
    end
  end

  # ============================================
  # Search Tests
  # ============================================

  describe "search_species/2" do
    test "returns results for valid query" do
      results = Species.search_species("quercus", 10)
      assert is_list(results)
      assert length(results) > 0
    end

    test "partial matching works (substring)" do
      # "ercus" is a substring of "Quercus"
      results = Species.search_species("ercus", 10)
      assert length(results) > 0
      assert Enum.all?(results, &String.contains?(String.downcase(&1.name), "ercus"))
    end

    test "multi-word queries work" do
      # "q alba" should match "Quercus alba"
      results = Species.search_species("q alba", 10)
      assert length(results) > 0
      names = Enum.map(results, & &1.name)
      assert Enum.any?(names, &String.contains?(String.downcase(&1), "alba"))
    end

    test "returns empty list for nonsense query" do
      results = Species.search_species("xyznonexistent123", 10)
      assert results == []
    end

    test "returns empty list for empty query" do
      results = Species.search_species("", 10)
      assert results == []
    end

    test "results have expected fields" do
      [result | _] = Species.search_species("quercus", 5)
      assert result.id
      assert String.contains?(String.downcase(result.name), "quercus")
      assert result.taxoncode in ["plant", "gall"]
      assert Map.has_key?(result, :datacomplete)
      assert Map.has_key?(result, :abundance_name)
    end

    test "respects limit parameter" do
      results = Species.search_species("a", 3)
      assert length(results) <= 3
    end
  end

  describe "search_species_by_name/3" do
    test "finds species matching query" do
      results = Species.search_species_by_name("qu", nil, 10)
      assert is_list(results)
      assert length(results) > 0
    end

    test "filters by taxoncode" do
      plant_results = Species.search_species_by_name("qu", "plant", 10)
      gall_results = Species.search_species_by_name("qu", "gall", 10)

      # All plant results should have taxoncode "plant"
      Enum.each(plant_results, fn r ->
        assert r.taxoncode == "plant"
      end)

      # All gall results should have taxoncode "gall"
      Enum.each(gall_results, fn r ->
        assert r.taxoncode == "gall"
      end)
    end

    test "finds mid-word matches" do
      results = Species.search_species_by_name("ercus", nil, 10)
      assert is_list(results)
      assert length(results) > 0
    end
  end

  describe "rename_species/4 collision detection" do
    setup do
      {:ok, species1} =
        Repo.insert(%Gallformers.Species.Species{
          name: "Testgenus alpha",
          taxoncode: "gall",
          datacomplete: false
        })

      {:ok, species2} =
        Repo.insert(%Gallformers.Species.Species{
          name: "Testgenus beta",
          taxoncode: "gall",
          datacomplete: false
        })

      {:ok, species1: species1, species2: species2}
    end

    test "returns {:error, :name_exists} when target name already exists", %{
      species1: species1,
      species2: species2
    } do
      assert {:error, :name_exists} =
               Species.rename_species(species1.id, species2.name, false)

      # Verify species1 was not renamed
      unchanged = Species.get_species!(species1.id)
      assert unchanged.name == "Testgenus alpha"
    end

    test "succeeds when target name does not exist", %{species1: species1} do
      assert {:ok, updated} = Species.rename_species(species1.id, "Testgenus gamma", true)
      assert updated.name == "Testgenus gamma"

      # Verify alias was created
      aliases = Species.get_aliases_for_species(species1.id)
      assert length(aliases) == 1
      assert hd(aliases).name == "Testgenus alpha"
    end

    test "no-ops when new name matches current name", %{species1: species1} do
      assert {:ok, returned} = Species.rename_species(species1.id, "Testgenus alpha", true)
      assert returned.name == "Testgenus alpha"

      # No alias should be created for a no-op
      aliases = Species.get_aliases_for_species(species1.id)
      assert aliases == []
    end

    test "species is searchable after rename", %{species1: species1} do
      assert {:ok, _updated} =
               Species.rename_species(species1.id, "Xyzuniquename testsearch", false)

      # Should be findable via search
      results = Species.search_species("xyzuniquename", 10)
      assert Enum.any?(results, &(&1.id == species1.id))
    end
  end

  describe "rename_for_genus_change/5 collision detection" do
    setup do
      {:ok, species1} =
        Repo.insert(%Gallformers.Species.Species{
          name: "Oldgenus alpha",
          taxoncode: "gall",
          datacomplete: false
        })

      # Create a species that would collide after genus rename
      {:ok, colliding} =
        Repo.insert(%Gallformers.Species.Species{
          name: "Newgenus alpha",
          taxoncode: "gall",
          datacomplete: false
        })

      {:ok, species1: species1, colliding: colliding}
    end

    test "returns {:error, :name_exists} when computed name collides", %{species1: species1} do
      assert {:error, :name_exists} =
               Species.rename_for_genus_change(species1, "Oldgenus", "Newgenus")

      # Verify species1 was not renamed
      unchanged = Species.get_species!(species1.id)
      assert unchanged.name == "Oldgenus alpha"
    end

    test "succeeds when computed name does not collide", %{species1: species1} do
      assert {:ok, updated} =
               Species.rename_for_genus_change(species1, "Oldgenus", "Safenewgenus")

      assert updated.name == "Safenewgenus alpha"
    end
  end

  describe "delete_species/1" do
    test "deletes the species and associated gall_traits record" do
      # Species 100 is "Andricus quercuscalifornicus" with gall traits
      species = Species.get_species!(100)
      assert species != nil

      # Verify gall_traits record exists (1:1 relationship with species)
      import Ecto.Query
      gall_traits = Repo.one(from gt in GallTraits, where: gt.species_id == 100)
      assert gall_traits != nil

      # Delete the species
      assert {:ok, deleted} = Species.delete_species(species)
      assert deleted.id == 100

      # Verify species is gone
      assert nil == Species.get_species(100)

      # Verify gall_traits record is gone (cascade delete)
      assert nil == Repo.one(from gt in GallTraits, where: gt.species_id == 100)
    end

    test "cleans up orphaned aliases after deletion" do
      import Ecto.Query

      # Species 2 is "Quercus rubra" (a host) — not used by other delete tests
      species = Species.get_species!(2)

      # Add an alias to this species
      {:ok, new_alias} =
        Species.create_alias_for_species(species.id, %{name: "Test Alias", type: "common"})

      # Verify the alias and link exist
      assert Repo.one(from a in "alias", where: a.id == ^new_alias.id, select: a.id) != nil

      assert Repo.one(
               from als in "alias_species",
                 where: als.alias_id == ^new_alias.id and als.species_id == ^species.id,
                 select: als.alias_id
             ) != nil

      # Delete the species
      assert {:ok, _} = Species.delete_species(species)

      # The alias_species link should be gone (cascade)
      assert Repo.one(
               from als in "alias_species",
                 where: als.alias_id == ^new_alias.id,
                 select: als.alias_id
             ) == nil

      # The alias record itself should also be gone (orphan cleanup)
      assert Repo.one(from a in "alias", where: a.id == ^new_alias.id, select: a.id) == nil
    end

    test "raises for non-existent species" do
      # Create a struct with a non-existent ID
      species = %Gallformers.Species.Species{id: 999_999_999, name: "Nonexistent"}

      # Ecto raises StaleEntryError when trying to delete a non-existent record
      assert_raise Ecto.StaleEntryError, fn ->
        Species.delete_species(species)
      end
    end
  end
end
