defmodule Gallformers.SpeciesTest do
  @moduledoc """
  Unit tests for the Species context.
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.Repo
  alias Gallformers.Species
  alias Gallformers.Species.GallTraits

  describe "list_species/0" do
    test "returns a list of species" do
      species = Species.list_species()
      assert is_list(species)
    end
  end

  describe "list_galls/0" do
    test "returns galls with expected fields" do
      galls = Species.list_galls()
      assert is_list(galls)

      if length(galls) > 0 do
        gall = hd(galls)
        assert Map.has_key?(gall, :id)
        assert Map.has_key?(gall, :name)
        assert Map.has_key?(gall, :taxoncode)
        assert gall.taxoncode == "gall"
      end
    end

    test "returns galls ordered by name" do
      galls = Species.list_galls()

      if length(galls) > 1 do
        names = Enum.map(galls, & &1.name)
        assert names == Enum.sort(names)
      end
    end
  end

  describe "list_galls_paginated/2" do
    test "returns limited number of galls" do
      galls = Species.list_galls_paginated(5, 0)
      assert length(galls) <= 5
    end

    test "respects offset parameter" do
      all_galls = Species.list_galls()

      if length(all_galls) > 5 do
        first_page = Species.list_galls_paginated(5, 0)
        second_page = Species.list_galls_paginated(5, 5)

        # Ensure no overlap
        first_ids = MapSet.new(Enum.map(first_page, & &1.id))
        second_ids = MapSet.new(Enum.map(second_page, & &1.id))
        assert MapSet.disjoint?(first_ids, second_ids)
      end
    end
  end

  describe "count_galls/0" do
    test "returns a non-negative integer" do
      count = Species.count_galls()
      assert is_integer(count)
      assert count >= 0
    end

    test "count matches length of list_galls" do
      count = Species.count_galls()
      galls = Species.list_galls()
      assert count == length(galls)
    end
  end

  describe "get_species/1" do
    test "returns nil for non-existent ID" do
      assert nil == Species.get_species(999_999_999)
    end

    test "returns species for valid ID" do
      galls = Species.list_galls()

      if length(galls) > 0 do
        species = Species.get_species(hd(galls).id)
        assert species != nil
        assert species.id == hd(galls).id
      end
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
      assert nil == Species.get_gall_by_id(999_999_999)
    end

    test "returns gall with expected fields for valid ID" do
      galls = Species.list_galls()

      if length(galls) > 0 do
        gall = Species.get_gall_by_id(hd(galls).id)
        assert gall != nil
        assert Map.has_key?(gall, :id)
        assert Map.has_key?(gall, :name)
        assert Map.has_key?(gall, :gall_id)
        assert Map.has_key?(gall, :detachable)
        assert Map.has_key?(gall, :undescribed)
      end
    end
  end

  describe "get_gall_by_name/1" do
    test "returns nil for non-existent name" do
      assert nil == Species.get_gall_by_name("Nonexistent species name xyz")
    end

    test "returns gall for valid name" do
      galls = Species.list_galls()

      if length(galls) > 0 do
        gall = Species.get_gall_by_name(hd(galls).name)
        assert gall != nil
        assert gall.name == hd(galls).name
      end
    end
  end

  describe "get_images_for_species/1" do
    test "returns empty list for non-existent species" do
      images = Species.get_images_for_species(999_999_999)
      assert images == []
    end

    test "returns images with expected fields" do
      galls = Species.list_galls()

      if length(galls) > 0 do
        images = Species.get_images_for_species(hd(galls).id)
        assert is_list(images)

        if length(images) > 0 do
          image = hd(images)
          assert Map.has_key?(image, :id)
          assert Map.has_key?(image, :path)
          assert Map.has_key?(image, :default)
        end
      end
    end
  end

  describe "get_aliases_for_species/1" do
    test "returns empty list for non-existent species" do
      aliases = Species.get_aliases_for_species(999_999_999)
      assert aliases == []
    end

    test "returns aliases with expected fields" do
      galls = Species.list_galls()

      # Find a gall with aliases
      gall_with_alias =
        Enum.find(galls, fn g ->
          length(Species.get_aliases_for_species(g.id)) > 0
        end)

      if gall_with_alias do
        aliases = Species.get_aliases_for_species(gall_with_alias.id)
        alias_entry = hd(aliases)
        assert Map.has_key?(alias_entry, :id)
        assert Map.has_key?(alias_entry, :name)
        assert Map.has_key?(alias_entry, :type)
      end
    end
  end

  describe "random_gall/0" do
    test "returns a gall with image or nil" do
      result = Species.random_gall()

      if result != nil do
        assert Map.has_key?(result, :id)
        assert Map.has_key?(result, :name)
        assert Map.has_key?(result, :image_url)
        assert String.contains?(result.image_url, "http")
      end
    end
  end

  describe "get_default_gall_images/0" do
    test "returns a list of image maps" do
      images = Species.get_default_gall_images()
      assert is_list(images)

      if length(images) > 0 do
        image = hd(images)
        assert Map.has_key?(image, :species_id)
        assert Map.has_key?(image, :path)
      end
    end
  end

  describe "list_abundances/0" do
    test "returns a list of abundances" do
      abundances = Species.list_abundances()
      assert is_list(abundances)
    end
  end

  describe "get_abundance/1" do
    test "returns nil for non-existent abundance" do
      assert nil == Species.get_abundance(999_999_999)
    end
  end

  # ============================================
  # FTS5 Full-Text Search Tests
  # ============================================

  describe "search_species_fts/2" do
    test "returns results for valid query" do
      # "Quercus" is a common genus in the database
      results = Species.search_species_fts("quercus", 10)
      assert is_list(results)
      assert length(results) > 0
    end

    test "prefix matching works (partial terms)" do
      # "qu" should match "Quercus" species
      results = Species.search_species_fts("qu", 10)
      assert is_list(results)
      assert length(results) > 0

      # All results should have names or aliases containing "qu"
      Enum.each(results, fn r ->
        name_matches = String.contains?(String.downcase(r.name), "qu")
        assert name_matches
      end)
    end

    test "multi-word queries work" do
      # "q alba" should match "Quercus alba"
      results = Species.search_species_fts("q alba", 10)
      assert is_list(results)

      # Should find Quercus alba or similar
      if length(results) > 0 do
        names = Enum.map(results, & &1.name)
        assert Enum.any?(names, &String.contains?(String.downcase(&1), "alba"))
      end
    end

    test "returns empty list for nonsense query" do
      results = Species.search_species_fts("xyznonexistent123", 10)
      assert results == []
    end

    test "returns empty list for empty query" do
      results = Species.search_species_fts("", 10)
      assert results == []
    end

    test "results have expected fields" do
      results = Species.search_species_fts("quercus", 5)

      if length(results) > 0 do
        result = hd(results)
        assert Map.has_key?(result, :id)
        assert Map.has_key?(result, :name)
        assert Map.has_key?(result, :taxoncode)
        assert Map.has_key?(result, :datacomplete)
        assert Map.has_key?(result, :abundance_name)
      end
    end

    test "respects limit parameter" do
      results = Species.search_species_fts("a", 3)
      assert length(results) <= 3
    end
  end

  describe "search_species/2 (hybrid search)" do
    test "uses FTS5 for prefix matching" do
      # This should use FTS5 (fast path)
      results = Species.search_species("quercus", 10)
      assert is_list(results)
      assert length(results) > 0
    end

    test "falls back to LIKE for mid-word matches" do
      # "ercus" is mid-word in "Quercus" - FTS5 won't match this
      # but LIKE should
      results = Species.search_species("ercus", 10)
      assert is_list(results)

      # Should find Quercus species via LIKE fallback
      if length(results) > 0 do
        names = Enum.map(results, & &1.name)
        assert Enum.any?(names, &String.contains?(String.downcase(&1), "ercus"))
      end
    end
  end

  describe "sanitize_fts_query/1" do
    test "removes special FTS5 characters" do
      assert Species.sanitize_fts_query("test*query") == "test query"
      assert Species.sanitize_fts_query("hello-world") == "hello world"
      assert Species.sanitize_fts_query("\"quoted\"") == "quoted"
      assert Species.sanitize_fts_query("a:b") == "a b"
    end

    test "normalizes whitespace" do
      assert Species.sanitize_fts_query("  hello   world  ") == "hello world"
    end

    test "handles empty string" do
      assert Species.sanitize_fts_query("") == ""
    end

    test "handles string with only special chars" do
      result = Species.sanitize_fts_query("***---\"\"\"")
      assert result == "" or String.trim(result) == ""
    end
  end

  describe "update_species_fts/1 and rebuild_species_fts/0" do
    test "rebuild_species_fts/0 succeeds" do
      # This verifies the FTS index can be rebuilt
      assert :ok == Species.rebuild_species_fts()
    end

    test "species can be found after rebuild" do
      # Rebuild and verify search still works
      Species.rebuild_species_fts()
      results = Species.search_species_fts("quercus", 5)
      assert length(results) > 0
    end
  end

  describe "search_species_by_name/3 with FTS" do
    test "finds species with prefix matching" do
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

    test "falls back to LIKE for mid-word matches" do
      # "ercus" won't match via FTS5, should fall back to LIKE
      results = Species.search_species_by_name("ercus", nil, 10)
      assert is_list(results)
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
