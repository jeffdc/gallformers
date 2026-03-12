defmodule Gallformers.TaxonomyTest do
  @moduledoc """
  Unit tests for the Taxonomy context.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Repo
  alias Gallformers.Species.Alias
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.{Family, Genus, Intermediate, Lineage, Section}
  alias Gallformers.Taxonomy.Taxonomy, as: TaxonomySchema
  alias Gallformers.Taxonomy.Tree

  describe "update_taxonomy/2 genus rename" do
    setup do
      # Create a family
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestFamilyRename",
          type: "family",
          description: "Test family for rename tests"
        })

      # Create a genus under the family
      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "Testgenus",
          type: "genus",
          description: "Test genus",
          parent_id: family.id
        })

      # Create a species
      {:ok, species} =
        Repo.insert(%Species{
          name: "Testgenus alba",
          taxoncode: "gall",
          datacomplete: false
        })

      # Link species to genus
      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      {:ok, family: family, genus: genus, species: species}
    end

    test "renames species and creates synonyms when genus is renamed", %{
      genus: genus,
      species: species
    } do
      # Rename the genus
      {:ok, updated_genus} = Taxonomy.update_taxonomy(genus, %{"name" => "Newgenus"})

      assert updated_genus.name == "Newgenus"

      # Verify species name was updated
      updated_species = Repo.get!(Species, species.id)
      assert updated_species.name == "Newgenus alba"

      # Verify synonym was created
      aliases =
        from(a in Alias,
          join: as in "alias_species",
          on: as.alias_id == a.id,
          where: as.species_id == ^species.id,
          select: a
        )
        |> Repo.all()

      assert length(aliases) == 1
      [synonym] = aliases
      assert synonym.name == "Testgenus alba"
      assert synonym.type == "scientific"
      assert synonym.description == "Previous name"
    end

    test "handles multiple species under a genus", %{genus: genus} do
      # Create additional species
      {:ok, species2} =
        Repo.insert(%Species{
          name: "Testgenus rubra",
          taxoncode: "gall",
          datacomplete: false
        })

      {:ok, species3} =
        Repo.insert(%Species{
          name: "Testgenus nigra",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species2.id, genus.id)
      Taxonomy.link_species_to_taxonomy(species3.id, genus.id)

      # Rename the genus
      {:ok, _updated_genus} = Taxonomy.update_taxonomy(genus, %{"name" => "Anothergenus"})

      # All species should be renamed
      s2 = Repo.get!(Species, species2.id)
      s3 = Repo.get!(Species, species3.id)

      assert s2.name == "Anothergenus rubra"
      assert s3.name == "Anothergenus nigra"

      # Both should have synonyms
      for sp <- [species2.id, species3.id] do
        alias_count =
          from(as in "alias_species", where: as.species_id == ^sp, select: count())
          |> Repo.one()

        assert alias_count == 1
      end
    end

    test "does not sync species when updating non-name fields", %{genus: genus, species: species} do
      # Update description only
      {:ok, _updated_genus} = Taxonomy.update_taxonomy(genus, %{"description" => "Updated desc"})

      # Species name should be unchanged
      unchanged_species = Repo.get!(Species, species.id)
      assert unchanged_species.name == "Testgenus alba"

      # No synonyms should be created
      alias_count =
        from(as in "alias_species", where: as.species_id == ^species.id, select: count())
        |> Repo.one()

      assert alias_count == 0
    end

    test "does not sync species when name is unchanged", %{genus: genus, species: species} do
      # Update with same name
      {:ok, _updated_genus} = Taxonomy.update_taxonomy(genus, %{"name" => "Testgenus"})

      # Species name should be unchanged
      unchanged_species = Repo.get!(Species, species.id)
      assert unchanged_species.name == "Testgenus alba"

      # No synonyms should be created
      alias_count =
        from(as in "alias_species", where: as.species_id == ^species.id, select: count())
        |> Repo.one()

      assert alias_count == 0
    end

    test "does not affect family rename", %{family: family} do
      # Rename family should work normally without species sync
      {:ok, updated_family} = Taxonomy.update_taxonomy(family, %{"name" => "NewFamilyName"})
      assert updated_family.name == "NewFamilyName"
    end
  end

  describe "update_taxonomy/2 genus rename collision" do
    setup do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "CollisionTestFamily",
          type: "family",
          description: "Test family for collision tests"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "Collisiongenus",
          type: "genus",
          description: "Genus to be renamed",
          parent_id: family.id
        })

      # Create a species under the genus
      {:ok, species} =
        Repo.insert(%Species{
          name: "Collisiongenus alpha",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      # Create a colliding species that already has the target name
      {:ok, _colliding} =
        Repo.insert(%Species{
          name: "Targetgenus alpha",
          taxoncode: "gall",
          datacomplete: false
        })

      {:ok, family: family, genus: genus, species: species}
    end

    test "returns error when genus rename would cause species name collision", %{
      genus: genus,
      species: species
    } do
      # Renaming "Collisiongenus" → "Targetgenus" would make "Collisiongenus alpha" → "Targetgenus alpha"
      # which already exists
      assert {:error, {:rename_collision, "Collisiongenus alpha", :name_exists}} =
               Taxonomy.update_taxonomy(genus, %{"name" => "Targetgenus"})

      # Genus should be unchanged (transaction rolled back)
      unchanged_genus = Taxonomy.get_taxonomy!(genus.id)
      assert unchanged_genus.name == "Collisiongenus"

      # Species should be unchanged
      unchanged_species = Repo.get!(Species, species.id)
      assert unchanged_species.name == "Collisiongenus alpha"
    end

    test "succeeds when genus rename does not cause collision", %{
      genus: genus
    } do
      assert {:ok, updated_genus} =
               Taxonomy.update_taxonomy(genus, %{"name" => "Safegenusname"})

      assert updated_genus.name == "Safegenusname"
    end
  end

  describe "reclassify_species/2 collision" do
    alias Gallformers.Galls.GallTraits

    setup do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "ReclCollisionFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, genus1} =
        Taxonomy.create_taxonomy(%{
          name: "ReclCollisionGenus1",
          type: "genus",
          parent_id: family.id
        })

      {:ok, genus2} =
        Taxonomy.create_taxonomy(%{
          name: "ReclCollisionGenus2",
          type: "genus",
          parent_id: family.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "ReclCollisionGenus1 testsp",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus1.id)

      {:ok, _gall_traits} =
        Repo.insert(%GallTraits{
          species_id: species.id,
          undescribed: false,
          detachable: "unknown"
        })

      # Create colliding species in target genus
      {:ok, _colliding} =
        Repo.insert(%Species{
          name: "ReclCollisionGenus2 testsp",
          taxoncode: "gall",
          datacomplete: false
        })

      {:ok, genus1: genus1, genus2: genus2, species: species}
    end

    test "reclassify returns error when target name already exists", %{
      species: species,
      genus2: genus2
    } do
      assert {:error, :name_exists} =
               Taxonomy.reassign_species_taxonomy(species.id, genus2.id)

      # Species should be unchanged
      unchanged = Repo.get!(Species, species.id)
      assert unchanged.name == "ReclCollisionGenus1 testsp"
    end

    test "reclassify via reclassify_species returns error for name-only collision", %{
      species: species,
      genus1: genus1
    } do
      # Create a species with the target name
      {:ok, _colliding2} =
        Repo.insert(%Species{
          name: "ReclCollisionGenus1 newepithet",
          taxoncode: "gall",
          datacomplete: false
        })

      params = %{
        genus_id: genus1.id,
        new_name: "ReclCollisionGenus1 newepithet",
        old_name: "ReclCollisionGenus1 testsp",
        genus_changed?: false,
        name_changed?: true,
        add_alias?: true
      }

      assert {:error, :name_exists} = Taxonomy.reclassify_species(species.id, params)

      # Species should be unchanged
      unchanged = Repo.get!(Species, species.id)
      assert unchanged.name == "ReclCollisionGenus1 testsp"
    end
  end

  describe "get_taxonomy_for_species" do
    test "returns taxonomy info for species with genus only" do
      # Create Family → Genus
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestSpeciesTaxFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "TestSpeciesTaxGenus",
          type: "genus",
          parent_id: family.id
        })

      # Create species and link to genus
      {:ok, species} =
        Repo.insert(%Species{
          name: "TestSpeciesTaxGenus species",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      # Get taxonomy info
      result = Taxonomy.get_taxonomy_for_species(species.id)

      assert result.genus.name == "TestSpeciesTaxGenus"
      assert result.genus.id == genus.id
      assert result.family.name == "TestSpeciesTaxFamily"
      assert result.family.id == family.id
      assert result.section == nil
    end

    test "returns taxonomy info for species with genus and section" do
      # Create Family → Genus → Section
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestSectionFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "TestSectionGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "TestSection",
          type: "section",
          parent_id: genus.id
        })

      # Create species
      {:ok, species} =
        Repo.insert(%Species{
          name: "TestSectionGenus alba",
          taxoncode: "plant",
          datacomplete: false
        })

      # Link to both genus and section
      Taxonomy.link_species_to_taxonomy(species.id, genus.id)
      Taxonomy.link_species_to_taxonomy(species.id, section.id)

      # Get taxonomy info
      result = Taxonomy.get_taxonomy_for_species(species.id)

      assert result.genus.name == "TestSectionGenus"
      assert result.genus.id == genus.id
      assert result.section.name == "TestSection"
      assert result.section.id == section.id
      assert result.family.name == "TestSectionFamily"
      assert result.family.id == family.id
    end

    test "genus parent is always a family, not a section" do
      # Hierarchy: Family → Genus → Section (optional).
      # Genus.parent_id always points to a family. Sections are children of genera.
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "DirectFamilyTest",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "DirectFamilyGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "DirectFamilyGenus alba",
          taxoncode: "plant",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      result = Taxonomy.get_taxonomy_for_species(species.id)

      assert result.genus.name == "DirectFamilyGenus"
      assert result.genus.id == genus.id
      # Family comes directly from genus.parent — no intermediate section
      assert result.family.name == "DirectFamilyTest"
      assert result.family.id == family.id
      assert result.section == nil
    end

    test "returns nil for species with no taxonomy" do
      {:ok, species} =
        Repo.insert(%Species{
          name: "Orphan species",
          taxoncode: "gall",
          datacomplete: false
        })

      result = Taxonomy.get_taxonomy_for_species(species.id)
      assert result == nil
    end
  end

  describe "taxonomy path" do
    test "get_taxonomy_path returns path from root to leaf" do
      # Create hierarchy: Family → Genus → Section
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestPathFamily",
          type: "family",
          description: "Test family"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "TestPathGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "TestPathSection",
          type: "section",
          parent_id: genus.id
        })

      # Get path from section (should include all three levels)
      path = Taxonomy.get_taxonomy_path(section.id)

      assert length(path) == 3
      assert Enum.map(path, & &1.name) == ["TestPathFamily", "TestPathGenus", "TestPathSection"]
      assert Enum.map(path, & &1.type) == ["family", "genus", "section"]
    end

    test "get_taxonomy_path returns single item for root taxonomy" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "RootFamily",
          type: "family",
          description: "Root test"
        })

      path = Taxonomy.get_taxonomy_path(family.id)

      assert length(path) == 1
      assert hd(path).name == "RootFamily"
    end

    test "get_taxonomy_path returns empty list for non-existent taxonomy" do
      path = Taxonomy.get_taxonomy_path(99_999)
      assert path == []
    end
  end

  describe "Unknown genus handling" do
    test "creating a family auto-creates an Unknown genus" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestAutoUnknownFamily",
          type: "family",
          description: "Wasp"
        })

      # Verify Unknown genus was auto-created with proper naming
      unknown_genus =
        Repo.one(
          from(t in Taxonomy.Taxonomy,
            where: t.is_placeholder == true and t.type == "genus" and t.parent_id == ^family.id
          )
        )

      assert unknown_genus != nil
      assert unknown_genus.name == "Unknown (TestAutoUnknownFamily)"
      assert unknown_genus.description == "Placeholder genus for undescribed species"
    end

    test "creating a plant family does NOT auto-create an Unknown genus" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestPlantFamily",
          type: "family",
          description: "Plant"
        })

      # Verify Unknown genus was NOT created for plant family
      unknown_genus =
        Repo.one(
          from(t in Taxonomy.Taxonomy,
            where: t.is_placeholder == true and t.type == "genus" and t.parent_id == ^family.id
          )
        )

      assert unknown_genus == nil
    end

    test "find_or_create_unknown_genus reuses existing Unknown genus" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestReuseUnknownFamily",
          type: "family",
          description: "Mite"
        })

      # Family creation already created an Unknown genus
      {:ok, unknown1} = Taxonomy.find_or_create_unknown_genus(family.id)
      {:ok, unknown2} = Taxonomy.find_or_create_unknown_genus(family.id)

      # Should return the same genus, not create a new one
      assert unknown1.id == unknown2.id
    end

    test "link_species_taxonomy with Unknown genus uses find_or_create" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestLinkUnknownFamily",
          type: "family",
          description: "Fly"
        })

      # Get the auto-created Unknown genus
      {:ok, unknown_genus} = Taxonomy.find_or_create_unknown_genus(family.id)

      # Create two species
      {:ok, species1} =
        Repo.insert(%Species{
          name: "Unknown sp. 1",
          taxoncode: "gall",
          datacomplete: false
        })

      {:ok, species2} =
        Repo.insert(%Species{
          name: "Unknown sp. 2",
          taxoncode: "gall",
          datacomplete: false
        })

      # Link both to Unknown genus (simulating undescribed gall creation)
      taxonomy = %Lineage{genus: %Genus{name: "Unknown"}}
      :ok = Taxonomy.link_species_taxonomy(species1.id, taxonomy, true, family.id)
      :ok = Taxonomy.link_species_taxonomy(species2.id, taxonomy, true, family.id)

      # Both should be linked to the same Unknown genus
      links =
        Repo.all(
          from(st in "species_taxonomy",
            where: st.taxonomy_id == ^unknown_genus.id,
            select: st.species_id
          )
        )

      assert species1.id in links
      assert species2.id in links

      # Should not have created a second Unknown genus
      unknown_count =
        Repo.one(
          from(t in Taxonomy.Taxonomy,
            where: t.is_placeholder == true and t.type == "genus" and t.parent_id == ^family.id,
            select: count()
          )
        )

      assert unknown_count == 1
    end

    test "empty_unknown_genus_ids returns IDs of Unknown genera with no species" do
      # Create a family (will auto-create an empty Unknown genus)
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestEmptyUnknownFamily",
          type: "family",
          description: "Midge"
        })

      {:ok, unknown_genus} = Taxonomy.find_or_create_unknown_genus(family.id)

      # The auto-created Unknown genus should be in the empty list
      empty_ids = Taxonomy.empty_unknown_genus_ids()
      assert unknown_genus.id in empty_ids

      # Now link a species to it
      {:ok, species} =
        Repo.insert(%Species{
          name: "Unknown sp. test",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, unknown_genus.id)

      # After linking a species, it should no longer be in the empty list
      empty_ids_after = Taxonomy.empty_unknown_genus_ids()
      refute unknown_genus.id in empty_ids_after
    end

    test "search_genera_and_sections filters empty Unknown genera by default" do
      # Create family with empty Unknown genus
      {:ok, _family} =
        Taxonomy.create_taxonomy(%{
          name: "TestSearchFilterFamily",
          type: "family",
          description: "Scale"
        })

      # Search for "Unknown" - should not find empty Unknown genera
      results = Taxonomy.search_genera_and_sections("Unknown", 100)
      empty_unknown_results = Enum.filter(results, &(&1.name == "Unknown" && &1.type == "genus"))

      # All Unknown genera in results should have species (not empty)
      for result <- empty_unknown_results do
        species_count =
          Repo.one(
            from(st in "species_taxonomy",
              where: st.taxonomy_id == ^result.id,
              select: count()
            )
          )

        assert species_count > 0, "Found empty Unknown genus #{result.id} in search results"
      end

      # With include_empty_unknown: true, should find all Unknown genera
      results_all =
        Taxonomy.search_genera_and_sections("Unknown", 100, include_empty_unknown: true)

      assert length(results_all) >= length(results)
    end

    test "move_genera updates parent_id for selected genera" do
      # Create two families
      {:ok, old_family} =
        Taxonomy.create_taxonomy(%{
          name: "OldFamily",
          type: "family",
          description: "Original family"
        })

      {:ok, new_family} =
        Taxonomy.create_taxonomy(%{
          name: "NewFamily",
          type: "family",
          description: "Target family"
        })

      # Create genera under old family
      {:ok, genus1} =
        Taxonomy.create_taxonomy(%{
          name: "Genus1",
          type: "genus",
          parent_id: old_family.id
        })

      {:ok, genus2} =
        Taxonomy.create_taxonomy(%{
          name: "Genus2",
          type: "genus",
          parent_id: old_family.id
        })

      {:ok, genus3} =
        Taxonomy.create_taxonomy(%{
          name: "Genus3",
          type: "genus",
          parent_id: old_family.id
        })

      # Move two genera to new family
      {:ok, count} = Taxonomy.move_genera([genus1.id, genus2.id], old_family.id, new_family.id)

      assert count == 2

      # Verify genera were moved
      moved_genus1 = Repo.get!(Taxonomy.Taxonomy, genus1.id)
      moved_genus2 = Repo.get!(Taxonomy.Taxonomy, genus2.id)
      unmoved_genus3 = Repo.get!(Taxonomy.Taxonomy, genus3.id)

      assert moved_genus1.parent_id == new_family.id
      assert moved_genus2.parent_id == new_family.id
      assert unmoved_genus3.parent_id == old_family.id
    end

    test "move_genera with empty list returns error" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestFamily",
          type: "family",
          description: "Test"
        })

      assert {:error, :no_genera_selected} = Taxonomy.move_genera([], family.id, family.id)
    end
  end

  describe "reassign_species_taxonomy/2" do
    alias Gallformers.Galls.GallTraits

    setup do
      {:ok, family1} =
        Taxonomy.create_taxonomy(%{
          name: "ReclassifyFamily1",
          type: "family",
          description: "Wasp"
        })

      {:ok, genus1} =
        Taxonomy.create_taxonomy(%{
          name: "ReclassifyGenus1",
          type: "genus",
          parent_id: family1.id
        })

      {:ok, family2} =
        Taxonomy.create_taxonomy(%{
          name: "ReclassifyFamily2",
          type: "family",
          description: "Midge"
        })

      {:ok, genus2} =
        Taxonomy.create_taxonomy(%{
          name: "ReclassifyGenus2",
          type: "genus",
          parent_id: family2.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "ReclassifyGenus1 testsp",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus1.id)

      {:ok, _gall_traits} =
        Repo.insert(%GallTraits{
          species_id: species.id,
          undescribed: false,
          detachable: "unknown"
        })

      {:ok, family1: family1, genus1: genus1, family2: family2, genus2: genus2, species: species}
    end

    test "moves species to a different genus and renames", %{species: species, genus2: genus2} do
      assert {:ok, updated} = Taxonomy.reassign_species_taxonomy(species.id, genus2.id)

      taxonomy = Taxonomy.get_taxonomy_for_species(species.id)
      assert taxonomy.genus.name == "ReclassifyGenus2"
      assert taxonomy.family.name == "ReclassifyFamily2"

      # Species name should reflect the new genus
      assert updated.name == "ReclassifyGenus2 testsp"
    end

    test "forces undescribed=true when moving to Unknown genus", %{
      species: species,
      family2: family2
    } do
      {:ok, unknown_genus} = Taxonomy.find_or_create_unknown_genus(family2.id)

      assert {:ok, updated} = Taxonomy.reassign_species_taxonomy(species.id, unknown_genus.id)

      # Verify genus changed to a placeholder
      taxonomy = Taxonomy.get_taxonomy_for_species(species.id)
      assert Taxonomy.placeholder_genus_name?(taxonomy.genus.name)

      # Species name should reflect the Unknown genus
      assert updated.name == "Unknown (ReclassifyFamily2) testsp"

      # Verify undescribed was forced to true
      gall_traits = Repo.get!(GallTraits, species.id)
      assert gall_traits.undescribed == true
    end

    test "does not force undescribed when moving to a real genus", %{
      species: species,
      genus2: genus2
    } do
      assert {:ok, _updated} = Taxonomy.reassign_species_taxonomy(species.id, genus2.id)

      # undescribed should remain false
      gall_traits = Repo.get!(GallTraits, species.id)
      assert gall_traits.undescribed == false
    end

    test "renames correctly from Unknown genus to real genus", %{
      species: species,
      family2: family2,
      genus2: genus2
    } do
      # First move to Unknown genus
      {:ok, unknown_genus} = Taxonomy.find_or_create_unknown_genus(family2.id)
      assert {:ok, updated} = Taxonomy.reassign_species_taxonomy(species.id, unknown_genus.id)
      assert updated.name == "Unknown (ReclassifyFamily2) testsp"

      # Now reclassify from Unknown to a real genus
      assert {:ok, updated2} = Taxonomy.reassign_species_taxonomy(updated.id, genus2.id)
      assert updated2.name == "ReclassifyGenus2 testsp"
    end

    test "creates scientific alias when moving undescribed species to real genus", %{
      species: species,
      family2: family2,
      genus2: genus2
    } do
      # Move to Unknown genus first (species starts described, so first alias is scientific)
      {:ok, unknown_genus} = Taxonomy.find_or_create_unknown_genus(family2.id)
      assert {:ok, _updated} = Taxonomy.reassign_species_taxonomy(species.id, unknown_genus.id)

      # Verify first move created a scientific alias
      scientific_aliases =
        from(a in Alias,
          join: as in "alias_species",
          on: as.alias_id == a.id,
          where: as.species_id == ^species.id and a.type == "scientific",
          select: a
        )
        |> Repo.all()

      assert length(scientific_aliases) == 1

      # Now move from Unknown to a real genus — always creates scientific alias
      assert {:ok, _updated2} = Taxonomy.reassign_species_taxonomy(species.id, genus2.id)

      all_aliases =
        from(a in Alias,
          join: as in "alias_species",
          on: as.alias_id == a.id,
          where: as.species_id == ^species.id,
          select: a
        )
        |> Repo.all()

      # All aliases should be scientific
      assert Enum.all?(all_aliases, &(&1.type == "scientific"))
      assert length(all_aliases) == 2
    end

    test "creates scientific alias for Known→Known genus change",
         %{
           species: species,
           genus2: genus2
         } do
      # Move from one real genus to another
      assert {:ok, _updated} = Taxonomy.reassign_species_taxonomy(species.id, genus2.id)

      aliases =
        from(a in Alias,
          join: as in "alias_species",
          on: as.alias_id == a.id,
          where: as.species_id == ^species.id,
          select: a
        )
        |> Repo.all()

      assert length(aliases) == 1
      [synonym] = aliases
      assert synonym.type == "scientific"
      assert synonym.name == "ReclassifyGenus1 testsp"
    end

    test "target_epithet overrides the extracted epithet", %{
      species: species,
      genus2: genus2
    } do
      assert {:ok, updated} =
               Taxonomy.reassign_species_taxonomy(species.id, genus2.id,
                 target_epithet: "newepithet"
               )

      assert updated.name == "ReclassifyGenus2 newepithet"
    end

    test "creates exactly one alias for combined genus + epithet change", %{
      species: species,
      genus2: genus2
    } do
      assert {:ok, _updated} =
               Taxonomy.reassign_species_taxonomy(species.id, genus2.id,
                 add_alias?: true,
                 target_epithet: "newepithet"
               )

      aliases = Gallformers.Species.get_aliases_for_species(species.id)
      assert length(aliases) == 1
      [alias_record] = aliases
      # Alias should be for the original name, not an intermediate
      assert alias_record.name == "ReclassifyGenus1 testsp"
    end

    test "target_epithet nil falls back to current epithet", %{
      species: species,
      genus2: genus2
    } do
      assert {:ok, updated} =
               Taxonomy.reassign_species_taxonomy(species.id, genus2.id, target_epithet: nil)

      assert updated.name == "ReclassifyGenus2 testsp"
    end

    test "creates scientific aliases for multiple reclassifications", %{
      species: species,
      family1: family1,
      family2: family2,
      genus1: genus1,
      genus2: genus2
    } do
      # Move to Unknown genus
      {:ok, unknown1} = Taxonomy.find_or_create_unknown_genus(family2.id)
      assert {:ok, _} = Taxonomy.reassign_species_taxonomy(species.id, unknown1.id)

      # Move to real genus (creates scientific alias)
      assert {:ok, _} = Taxonomy.reassign_species_taxonomy(species.id, genus2.id)

      # Move back to Unknown
      {:ok, unknown2} = Taxonomy.find_or_create_unknown_genus(family1.id)
      assert {:ok, _} = Taxonomy.reassign_species_taxonomy(species.id, unknown2.id)

      # Move to real genus again
      assert {:ok, _} = Taxonomy.reassign_species_taxonomy(species.id, genus1.id)

      all_aliases =
        from(a in Alias,
          join: as in "alias_species",
          on: as.alias_id == a.id,
          where: as.species_id == ^species.id,
          select: a
        )
        |> Repo.all()

      # All aliases should be scientific
      assert Enum.all?(all_aliases, &(&1.type == "scientific"))
    end
  end

  describe "reclassify_species/2" do
    alias Gallformers.Galls.GallTraits

    setup do
      {:ok, family1} =
        Taxonomy.create_taxonomy(%{
          name: "ReclSpFamily1",
          type: "family",
          description: "Wasp"
        })

      {:ok, genus1} =
        Taxonomy.create_taxonomy(%{
          name: "ReclSpGenus1",
          type: "genus",
          parent_id: family1.id
        })

      {:ok, family2} =
        Taxonomy.create_taxonomy(%{
          name: "ReclSpFamily2",
          type: "family",
          description: "Midge"
        })

      {:ok, genus2} =
        Taxonomy.create_taxonomy(%{
          name: "ReclSpGenus2",
          type: "genus",
          parent_id: family2.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "ReclSpGenus1 testsp",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus1.id)

      {:ok, _gall_traits} =
        Repo.insert(%GallTraits{
          species_id: species.id,
          undescribed: false,
          detachable: "unknown"
        })

      {:ok, family1: family1, genus1: genus1, family2: family2, genus2: genus2, species: species}
    end

    test "genus change reclassifies taxonomy and renames, creates alias", %{
      species: species,
      genus2: genus2
    } do
      params = %{
        genus_id: genus2.id,
        new_name: "ReclSpGenus2 testsp",
        old_name: "ReclSpGenus1 testsp",
        genus_changed?: true,
        name_changed?: true,
        add_alias?: true
      }

      assert {:ok, updated} = Taxonomy.reclassify_species(species.id, params)
      assert updated.name == "ReclSpGenus2 testsp"

      aliases = Gallformers.Species.get_aliases_for_species(species.id)
      assert length(aliases) == 1
      assert hd(aliases).type == "scientific"
      assert hd(aliases).name == "ReclSpGenus1 testsp"
    end

    test "epithet change only renames and creates alias", %{
      species: species,
      genus1: genus1
    } do
      params = %{
        genus_id: genus1.id,
        new_name: "ReclSpGenus1 newepithet",
        old_name: "ReclSpGenus1 testsp",
        genus_changed?: false,
        name_changed?: true,
        add_alias?: true
      }

      assert {:ok, updated} = Taxonomy.reclassify_species(species.id, params)
      assert updated.name == "ReclSpGenus1 newepithet"

      aliases = Gallformers.Species.get_aliases_for_species(species.id)
      assert length(aliases) == 1
      assert hd(aliases).type == "scientific"
      assert hd(aliases).name == "ReclSpGenus1 testsp"
    end

    test "no changes returns species unchanged, no alias created", %{
      species: species,
      genus1: genus1
    } do
      params = %{
        genus_id: genus1.id,
        new_name: "ReclSpGenus1 testsp",
        old_name: "ReclSpGenus1 testsp",
        genus_changed?: false,
        name_changed?: false,
        add_alias?: true
      }

      assert {:ok, returned} = Taxonomy.reclassify_species(species.id, params)
      assert returned.name == "ReclSpGenus1 testsp"

      aliases = Gallformers.Species.get_aliases_for_species(species.id)
      assert aliases == []
    end

    test "combined genus and epithet change produces final name atomically", %{
      species: species,
      genus2: genus2
    } do
      params = %{
        genus_id: genus2.id,
        new_name: "ReclSpGenus2 newepithet",
        old_name: "ReclSpGenus1 testsp",
        genus_changed?: true,
        name_changed?: true,
        add_alias?: true
      }

      assert {:ok, updated} = Taxonomy.reclassify_species(species.id, params)
      assert updated.name == "ReclSpGenus2 newepithet"

      # Only one alias: for the original name
      aliases = Gallformers.Species.get_aliases_for_species(species.id)
      assert length(aliases) == 1
      assert hd(aliases).name == "ReclSpGenus1 testsp"
    end
  end

  describe "search_genera/1" do
    setup do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "SearchGeneraFamily",
          type: "family",
          description: "Test"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "Searchablegenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, family: family, genus: genus}
    end

    test "finds genera by name prefix", %{genus: genus, family: family} do
      results = Taxonomy.search_genera("Search")
      ids = Enum.map(results, & &1.id)
      assert genus.id in ids

      # Verify result structure
      result = Enum.find(results, &(&1.id == genus.id))
      assert result.name == "Searchablegenus"
      assert result.family_name == "SearchGeneraFamily"
      assert result.family_id == family.id
    end

    test "returns empty list for non-matching query" do
      results = Taxonomy.search_genera("Zzzznotagenus")
      assert results == []
    end

    test "taxoncode filter includes genera with no species", %{genus: genus} do
      # genus has no species linked — it should still appear when filtering by taxoncode
      results = Taxonomy.search_genera("Search", nil, taxoncode: "gall")
      ids = Enum.map(results, & &1.id)
      assert genus.id in ids
    end

    test "taxoncode filter excludes genera belonging to the other taxoncode" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TaxcodeFilterFamily",
          type: "family",
          description: "Test"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "Taxcodefiltergenus",
          type: "genus",
          parent_id: family.id
        })

      # Create a plant species and link it to this genus
      {:ok, plant} =
        Gallformers.Species.create_species(%{
          name: "Taxcodefiltergenus plantsp",
          taxoncode: "plant"
        })

      Taxonomy.link_species_to_taxonomy(plant.id, genus.id)

      # Searching with taxoncode: "gall" should NOT find this genus (it has only plant species)
      results = Taxonomy.search_genera("Taxcodefilter", nil, taxoncode: "gall")
      ids = Enum.map(results, & &1.id)
      refute genus.id in ids

      # Searching with taxoncode: "plant" should find it
      results = Taxonomy.search_genera("Taxcodefilter", nil, taxoncode: "plant")
      ids = Enum.map(results, & &1.id)
      assert genus.id in ids
    end
  end

  describe "resolve_taxonomy_for_species/2" do
    setup do
      # Create plant family + genus
      {:ok, plant_family} =
        Taxonomy.create_taxonomy(%{
          name: "ResolvePlantFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, plant_genus} =
        Taxonomy.create_taxonomy(%{
          name: "Resolveplantgenus",
          type: "genus",
          parent_id: plant_family.id
        })

      # Create gall family + genus
      {:ok, gall_family} =
        Taxonomy.create_taxonomy(%{
          name: "ResolveGallFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, gall_genus} =
        Taxonomy.create_taxonomy(%{
          name: "Resolvegallgenus",
          type: "genus",
          parent_id: gall_family.id
        })

      plant_family_ids = MapSet.new([plant_family.id])
      gall_family_ids = MapSet.new([gall_family.id])

      {:ok,
       plant_family: plant_family,
       plant_genus: plant_genus,
       gall_family: gall_family,
       gall_genus: gall_genus,
       plant_family_ids: plant_family_ids,
       gall_family_ids: gall_family_ids}
    end

    test "returns nil map for nil taxonomy" do
      assert %{
               taxonomy: nil,
               genus_is_new: false,
               family_id: nil,
               section_id: nil,
               possible_families: []
             } =
               Taxonomy.resolve_taxonomy_for_species(nil, MapSet.new())
    end

    test "new genus returns genus_is_new=true", ctx do
      lookup_result = {:new_genus, Lineage.new_genus("Brandnewgenus")}

      %{taxonomy: result, genus_is_new: true, family_id: nil, possible_families: []} =
        Taxonomy.resolve_taxonomy_for_species(lookup_result, ctx.gall_family_ids)

      assert result.genus.name == "Brandnewgenus"
    end

    test "known genus in valid family resolves directly", ctx do
      lineage = %Lineage{
        genus: %Genus{id: ctx.gall_genus.id, name: "Resolvegallgenus"},
        family: %Family{id: ctx.gall_family.id, name: "ResolveGallFamily"}
      }

      %{taxonomy: resolved, genus_is_new: false, family_id: family_id, possible_families: []} =
        Taxonomy.resolve_taxonomy_for_species({:ok, lineage}, ctx.gall_family_ids)

      assert family_id == ctx.gall_family.id
      assert resolved.genus.name == "Resolvegallgenus"
    end

    test "known genus in wrong family treated as new genus", ctx do
      # Plant genus but using gall family IDs
      lineage = %Lineage{
        genus: %Genus{id: ctx.plant_genus.id, name: "Resolveplantgenus"},
        family: %Family{id: ctx.plant_family.id, name: "ResolvePlantFamily"}
      }

      %{taxonomy: result, genus_is_new: true, family_id: nil, possible_families: []} =
        Taxonomy.resolve_taxonomy_for_species({:ok, lineage}, ctx.gall_family_ids)

      assert not Lineage.resolved?(result)
    end

    test "disambiguation filters to valid families", ctx do
      lookup_result =
        {:ambiguous, "Ambiguousgenus",
         [
           %{
             genus_id: 1,
             family: %Family{id: ctx.plant_family.id, name: "ResolvePlantFamily"},
             section: nil
           },
           %{
             genus_id: 2,
             family: %Family{id: ctx.gall_family.id, name: "ResolveGallFamily"},
             section: nil
           }
         ]}

      # Using gall families, should auto-resolve to single gall family
      %{taxonomy: resolved, genus_is_new: false, family_id: family_id, possible_families: []} =
        Taxonomy.resolve_taxonomy_for_species(lookup_result, ctx.gall_family_ids)

      assert family_id == ctx.gall_family.id
      assert resolved.genus.id == 2
    end

    test "disambiguation with no matching families returns new genus", _ctx do
      other_family_ids = MapSet.new([99_999])

      lookup_result =
        {:ambiguous, "Ambiguousgenus",
         [
           %{
             genus_id: 1,
             family: %Family{id: 12, name: "ResolvePlantFamily"},
             section: nil
           }
         ]}

      %{taxonomy: result, genus_is_new: true, family_id: nil, possible_families: []} =
        Taxonomy.resolve_taxonomy_for_species(lookup_result, other_family_ids)

      assert not Lineage.resolved?(result)
    end

    test "returns section_id when taxonomy has a section", ctx do
      {:ok, section_record} =
        Taxonomy.create_taxonomy(%{
          name: "ResolveSection",
          type: "section",
          parent_id: ctx.plant_genus.id
        })

      lineage = %Lineage{
        genus: %Genus{id: ctx.plant_genus.id, name: "Resolveplantgenus"},
        family: %Family{id: ctx.plant_family.id, name: "ResolvePlantFamily"},
        section: %Section{id: section_record.id, name: "ResolveSection"}
      }

      %{
        taxonomy: resolved,
        genus_is_new: false,
        family_id: family_id,
        section_id: section_id,
        possible_families: []
      } =
        Taxonomy.resolve_taxonomy_for_species({:ok, lineage}, ctx.plant_family_ids)

      assert family_id == ctx.plant_family.id
      assert section_id == section_record.id
      assert resolved.section.name == "ResolveSection"
    end

    test "disambiguation with multiple matches returns all for modal", ctx do
      both_family_ids = MapSet.new([ctx.plant_family.id, ctx.gall_family.id])

      lookup_result =
        {:ambiguous, "Ambiguousgenus",
         [
           %{
             genus_id: 1,
             family: %Family{id: ctx.plant_family.id, name: "ResolvePlantFamily"},
             section: nil
           },
           %{
             genus_id: 2,
             family: %Family{id: ctx.gall_family.id, name: "ResolveGallFamily"},
             section: nil
           }
         ]}

      %{taxonomy: _taxonomy, genus_is_new: false, family_id: nil, possible_families: multiple} =
        Taxonomy.resolve_taxonomy_for_species(lookup_result, both_family_ids)

      assert length(multiple) == 2
    end
  end

  describe "get_deletion_impact/1" do
    test "family shows genera, sections, and species counts" do
      # Create Family → Genus1, Genus2, Genus1 → Section
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "ImpactTestFamily",
          type: "family",
          description: "Test family"
        })

      {:ok, genus1} =
        Taxonomy.create_taxonomy(%{
          name: "ImpactGenus1",
          type: "genus",
          parent_id: family.id
        })

      {:ok, genus2} =
        Taxonomy.create_taxonomy(%{
          name: "ImpactGenus2",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "ImpactSection",
          type: "section",
          parent_id: genus1.id
        })

      # Create species under genus1 (2), genus2 (1), and section (1)
      {:ok, species1} =
        Repo.insert(%Species{name: "ImpactGenus1 sp1", taxoncode: "gall", datacomplete: false})

      {:ok, species2} =
        Repo.insert(%Species{name: "ImpactGenus1 sp2", taxoncode: "gall", datacomplete: false})

      {:ok, species3} =
        Repo.insert(%Species{name: "ImpactGenus2 sp1", taxoncode: "gall", datacomplete: false})

      {:ok, species4} =
        Repo.insert(%Species{
          name: "ImpactGenus1 sectioned",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species1.id, genus1.id)
      Taxonomy.link_species_to_taxonomy(species2.id, genus1.id)
      Taxonomy.link_species_to_taxonomy(species3.id, genus2.id)
      Taxonomy.link_species_to_taxonomy(species4.id, section.id)

      impact = Taxonomy.get_deletion_impact(family)

      # 3 genera: ImpactGenus1, ImpactGenus2, and auto-created Unknown
      assert impact.genera_count == 3
      assert impact.sections_count == 1
      assert impact.species_count == 4
      assert impact.has_impact == true
      assert impact.taxonomy.id == family.id
    end

    test "genus shows sections and species counts" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "GenusImpactFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "GenusImpactGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "GenusImpactSection",
          type: "section",
          parent_id: genus.id
        })

      # Create species under genus (1) and section (1)
      {:ok, species1} =
        Repo.insert(%Species{
          name: "GenusImpactGenus sp1",
          taxoncode: "plant",
          datacomplete: false
        })

      {:ok, species2} =
        Repo.insert(%Species{
          name: "GenusImpactGenus sectioned",
          taxoncode: "plant",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species1.id, genus.id)
      Taxonomy.link_species_to_taxonomy(species2.id, section.id)

      impact = Taxonomy.get_deletion_impact(genus)

      assert impact.genera_count == 0
      assert impact.sections_count == 1
      assert impact.species_count == 2
      assert impact.has_impact == true
    end

    test "section has no cascade impact" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "SectionImpactFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "SectionImpactGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "SectionImpactSection",
          type: "section",
          parent_id: genus.id
        })

      impact = Taxonomy.get_deletion_impact(section)

      assert impact.genera_count == 0
      assert impact.sections_count == 0
      assert impact.species_count == 0
      assert impact.has_impact == false
    end

    test "family with no children has has_impact false" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "EmptyImpactFamily",
          type: "family",
          description: "Plant"
        })

      impact = Taxonomy.get_deletion_impact(family)

      # Plant families don't auto-create Unknown genus
      assert impact.genera_count == 0
      assert impact.sections_count == 0
      assert impact.species_count == 0
      assert impact.has_impact == false
    end

    test "genus with no children or species has has_impact false" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "EmptyGenusFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "EmptyGenusGenus",
          type: "genus",
          parent_id: family.id
        })

      impact = Taxonomy.get_deletion_impact(genus)

      assert impact.genera_count == 0
      assert impact.sections_count == 0
      assert impact.species_count == 0
      assert impact.has_impact == false
    end

    test "search_genera_and_sections filters by taxoncode when provided" do
      # Create a family
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestTaxoncodeFamily",
          type: "family",
          description: "Test family"
        })

      # Create two genera
      {:ok, plant_genus} =
        Taxonomy.create_taxonomy(%{
          name: "Plantgenus",
          type: "genus",
          description: "Plant genus",
          parent_id: family.id
        })

      {:ok, gall_genus} =
        Taxonomy.create_taxonomy(%{
          name: "Gallgenus",
          type: "genus",
          description: "Gall genus",
          parent_id: family.id
        })

      # Create plant species linked to plant genus
      {:ok, plant_species} =
        Repo.insert(%Species{
          name: "Plantgenus alba",
          taxoncode: "plant",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(plant_species.id, plant_genus.id)

      # Create gall species linked to gall genus
      {:ok, gall_species} =
        Repo.insert(%Species{
          name: "Gallgenus nigra",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(gall_species.id, gall_genus.id)

      # Search for plant genus with taxoncode: "plant" - should find it
      results_plant = Taxonomy.search_genera_and_sections("plant", 100, taxoncode: "plant")
      plant_names = Enum.map(results_plant, & &1.name)
      assert "Plantgenus" in plant_names

      # Search for plant genus with taxoncode: "gall" - should NOT find it
      results_plant_as_gall =
        Taxonomy.search_genera_and_sections("plant", 100, taxoncode: "gall")

      plant_as_gall_names = Enum.map(results_plant_as_gall, & &1.name)
      refute "Plantgenus" in plant_as_gall_names

      # Search for gall genus with taxoncode: "gall" - should find it
      results_gall = Taxonomy.search_genera_and_sections("gall", 100, taxoncode: "gall")
      gall_names = Enum.map(results_gall, & &1.name)
      assert "Gallgenus" in gall_names

      # Search for gall genus with taxoncode: "plant" - should NOT find it
      results_gall_as_plant = Taxonomy.search_genera_and_sections("gall", 100, taxoncode: "plant")
      gall_as_plant_names = Enum.map(results_gall_as_plant, & &1.name)
      refute "Gallgenus" in gall_as_plant_names
    end

    test "search_genera_and_sections matches common names in description" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestCommonNameFamily",
          type: "family",
          description: "Test family"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "Quercustestgenus",
          type: "genus",
          description: "Oak",
          parent_id: family.id
        })

      # Create a species so the genus isn't filtered as empty
      {:ok, species} =
        Repo.insert(%Species{
          name: "Quercustestgenus alba",
          taxoncode: "plant",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      # Search by common name should find the genus
      results = Taxonomy.search_genera_and_sections("oak", 100)
      names = Enum.map(results, & &1.name)
      assert "Quercustestgenus" in names

      # Search by scientific name still works
      results = Taxonomy.search_genera_and_sections("quercustest", 100)
      names = Enum.map(results, & &1.name)
      assert "Quercustestgenus" in names
    end
  end

  describe "delete_taxonomy_cascade/1" do
    alias Gallformers.GallHosts.GallHost
    alias Gallformers.Galls.GallTraits
    alias Gallformers.Images.Image

    test "deletes family and all descendants in transaction" do
      # Create Family → Genus → Species with various associations
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "CascadeTestFamily",
          type: "family",
          description: "Test family"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "CascadeTestGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "CascadeTestSection",
          type: "section",
          parent_id: genus.id
        })

      # Create species under genus
      {:ok, species1} =
        Repo.insert(%Species{
          name: "CascadeTestGenus sp1",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species1.id, genus.id)

      # Create species under section
      {:ok, species2} =
        Repo.insert(%Species{
          name: "CascadeTestGenus sp2",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species2.id, section.id)

      # Execute cascade delete
      assert {:ok, impact} = Taxonomy.delete_taxonomy_cascade(family)

      # Verify impact struct
      assert impact.taxonomy.id == family.id
      # 2 genera: CascadeTestGenus + auto-created Unknown
      assert impact.genera_count == 2
      assert impact.sections_count == 1
      assert impact.species_count == 2

      # Verify everything is deleted
      refute Repo.get(Taxonomy.Taxonomy, family.id)
      refute Repo.get(Taxonomy.Taxonomy, genus.id)
      refute Repo.get(Taxonomy.Taxonomy, section.id)
      refute Repo.get(Species, species1.id)
      refute Repo.get(Species, species2.id)
    end

    test "deletes genus and all descendants in transaction" do
      # Create Family → Genus → Section → Species
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "GenusDeleteFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "GenusDeleteGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "GenusDeleteSection",
          type: "section",
          parent_id: genus.id
        })

      # Species under genus
      {:ok, species1} =
        Repo.insert(%Species{
          name: "GenusDeleteGenus sp1",
          taxoncode: "plant",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species1.id, genus.id)

      # Species under section
      {:ok, species2} =
        Repo.insert(%Species{
          name: "GenusDeleteGenus sp2",
          taxoncode: "plant",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species2.id, section.id)

      # Delete genus (should delete section and species but NOT family)
      assert {:ok, impact} = Taxonomy.delete_taxonomy_cascade(genus)

      assert impact.taxonomy.id == genus.id
      assert impact.genera_count == 0
      assert impact.sections_count == 1
      assert impact.species_count == 2

      # Genus, section, species deleted
      refute Repo.get(Taxonomy.Taxonomy, genus.id)
      refute Repo.get(Taxonomy.Taxonomy, section.id)
      refute Repo.get(Species, species1.id)
      refute Repo.get(Species, species2.id)

      # Family still exists
      assert Repo.get(Taxonomy.Taxonomy, family.id)
    end

    test "section delete has no cascade (simple delete)" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "SectionDeleteFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "SectionDeleteGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "SectionDeleteSection",
          type: "section",
          parent_id: genus.id
        })

      # Delete section - simple delete, returns {:ok, taxonomy}
      assert {:ok, deleted} = Taxonomy.delete_taxonomy_cascade(section)
      assert deleted.id == section.id

      # Section deleted, family and genus remain
      refute Repo.get(Taxonomy.Taxonomy, section.id)
      assert Repo.get(Taxonomy.Taxonomy, family.id)
      assert Repo.get(Taxonomy.Taxonomy, genus.id)
    end

    test "deletes species with gall_traits" do
      # Create family → genus → species with gall_traits
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "GallTraitsDeleteFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "GallTraitsDeleteGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "GallTraitsDeleteGenus sp1",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      # Add gall_traits
      {:ok, gall_traits} =
        Repo.insert(%GallTraits{
          species_id: species.id,
          undescribed: false
        })

      # Delete genus (cascades to species with gall_traits)
      assert {:ok, _impact} = Taxonomy.delete_taxonomy_cascade(genus)

      refute Repo.get(Species, species.id)
      # GallTraits uses species_id as primary key
      refute Repo.get(GallTraits, gall_traits.species_id)
    end

    test "deletes species with host associations" do
      # Create family → genus → gall species → host association
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "HostAssocDeleteFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "HostAssocDeleteGenus",
          type: "genus",
          parent_id: family.id
        })

      # Create a gall species
      {:ok, gall_species} =
        Repo.insert(%Species{
          name: "HostAssocDeleteGenus gall1",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(gall_species.id, genus.id)

      # Create a host species (under a different family)
      {:ok, plant_family} =
        Taxonomy.create_taxonomy(%{
          name: "HostAssocPlantFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, plant_genus} =
        Taxonomy.create_taxonomy(%{
          name: "HostAssocPlantGenus",
          type: "genus",
          parent_id: plant_family.id
        })

      {:ok, host_species} =
        Repo.insert(%Species{
          name: "HostAssocPlantGenus host1",
          taxoncode: "plant",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(host_species.id, plant_genus.id)

      # Create host association
      {:ok, host_assoc} =
        Repo.insert(%GallHost{
          gall_species_id: gall_species.id,
          host_species_id: host_species.id
        })

      # Delete gall family (cascades to gall species, which cascades to host association)
      assert {:ok, _impact} = Taxonomy.delete_taxonomy_cascade(family)

      # Gall and association deleted
      refute Repo.get(Species, gall_species.id)
      refute Repo.get(GallHost, host_assoc.id)

      # Host plant still exists
      assert Repo.get(Species, host_species.id)
    end

    test "deletes species with images" do
      # Create family → genus → species with image
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "ImageDeleteFamily",
          type: "family",
          description: "Midge"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "ImageDeleteGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "ImageDeleteGenus sp1",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      # Add an image (without actual S3 file - we're testing DB cascade)
      {:ok, image} =
        Repo.insert(%Image{
          species_id: species.id,
          path: "images/original/test-image.jpg",
          sort_order: 1
        })

      # Delete genus
      assert {:ok, _impact} = Taxonomy.delete_taxonomy_cascade(genus)

      refute Repo.get(Species, species.id)
      refute Repo.get(Image, image.id)
    end

    test "deletes species with aliases" do
      # Create family → genus → species with alias
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "AliasDeleteFamily",
          type: "family",
          description: "Fly"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "AliasDeleteGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "AliasDeleteGenus sp1",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      # Add an alias
      {:ok, alias_record} =
        Repo.insert(%Alias{
          name: "Old name",
          type: "scientific",
          description: "Former name"
        })

      Repo.insert_all("alias_species", [%{alias_id: alias_record.id, species_id: species.id}])

      # Delete genus
      assert {:ok, _impact} = Taxonomy.delete_taxonomy_cascade(genus)

      refute Repo.get(Species, species.id)

      # The alias_species join table is cascade deleted (species no longer associated)
      alias_count =
        Repo.one(
          from(als in "alias_species",
            where: als.species_id == ^species.id,
            select: count()
          )
        )

      assert alias_count == 0
    end

    test "empty family with no children deletes successfully" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "EmptyCascadeFamily",
          type: "family",
          description: "Plant"
        })

      # Plant families don't auto-create Unknown genus
      assert {:ok, impact} = Taxonomy.delete_taxonomy_cascade(family)

      assert impact.genera_count == 0
      assert impact.sections_count == 0
      assert impact.species_count == 0

      refute Repo.get(Taxonomy.Taxonomy, family.id)
    end

    test "empty genus with no children deletes successfully" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "EmptyGenusFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "EmptyCascadeGenus",
          type: "genus",
          parent_id: family.id
        })

      assert {:ok, impact} = Taxonomy.delete_taxonomy_cascade(genus)

      assert impact.sections_count == 0
      assert impact.species_count == 0

      refute Repo.get(Taxonomy.Taxonomy, genus.id)
      # Family remains
      assert Repo.get(Taxonomy.Taxonomy, family.id)
    end

    test "returns impact struct on success" do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "ImpactReturnFamily",
          type: "family",
          description: "Test"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "ImpactReturnGenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "ImpactReturnGenus sp1",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      {:ok, impact} = Taxonomy.delete_taxonomy_cascade(family)

      # Verify impact struct has all expected fields
      assert is_map(impact)
      assert Map.has_key?(impact, :taxonomy)
      assert Map.has_key?(impact, :genera)
      assert Map.has_key?(impact, :genera_count)
      assert Map.has_key?(impact, :sections)
      assert Map.has_key?(impact, :sections_count)
      assert Map.has_key?(impact, :species_count)
    end
  end

  describe "intermediate taxonomy changeset" do
    setup do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestFamilyIntermediate",
          type: "family",
          description: "Wasp"
        })

      {:ok, family: family}
    end

    test "valid intermediate changeset with name, type, parent_id, and rank", %{family: family} do
      changeset =
        TaxonomySchema.changeset(%TaxonomySchema{}, %{
          name: "Cynipinae",
          type: "intermediate",
          parent_id: family.id,
          rank: "Subfamily"
        })

      assert changeset.valid?
    end

    test "invalid intermediate changeset missing rank", %{family: family} do
      changeset =
        TaxonomySchema.changeset(%TaxonomySchema{}, %{
          name: "Cynipinae",
          type: "intermediate",
          parent_id: family.id
        })

      refute changeset.valid?
      assert {"is required for intermediate ranks", _} = changeset.errors[:rank]
    end

    test "invalid intermediate changeset missing parent_id" do
      changeset =
        TaxonomySchema.changeset(%TaxonomySchema{}, %{
          name: "Cynipinae",
          type: "intermediate",
          rank: "Subfamily"
        })

      refute changeset.valid?
      assert {"is required", _} = changeset.errors[:parent_id]
    end

    test "existing family changeset still works (rank ignored)" do
      changeset =
        TaxonomySchema.changeset(%TaxonomySchema{}, %{
          name: "Testidae",
          type: "family",
          description: "Plant"
        })

      assert changeset.valid?
    end

    test "existing genus changeset still works (rank ignored)", %{family: family} do
      changeset =
        TaxonomySchema.changeset(%TaxonomySchema{}, %{
          name: "Testgenus",
          type: "genus",
          parent_id: family.id
        })

      assert changeset.valid?
    end

    test "valid_ranks/0 returns all accepted rank values" do
      ranks = TaxonomySchema.valid_ranks()
      assert is_list(ranks)
      assert "Subfamily" in ranks
      assert "Tribe" in ranks
      assert "Subtribe" in ranks
      assert "Infrafamily" in ranks
      assert "Supertribe" in ranks
      assert "Infratribe" in ranks
    end

    test "changeset accepts each valid rank for intermediate type", %{family: family} do
      for rank <- TaxonomySchema.valid_ranks() do
        changeset =
          TaxonomySchema.changeset(%TaxonomySchema{}, %{
            name: "Test#{rank}",
            type: "intermediate",
            parent_id: family.id,
            rank: rank
          })

        assert changeset.valid?, "expected rank #{inspect(rank)} to be valid"
      end
    end

    test "changeset rejects invalid rank for intermediate type", %{family: family} do
      changeset =
        TaxonomySchema.changeset(%TaxonomySchema{}, %{
          name: "Bogusinae",
          type: "intermediate",
          parent_id: family.id,
          rank: "bogus"
        })

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:rank]
    end

    test "changeset allows nil rank for non-intermediate types (family)" do
      changeset =
        TaxonomySchema.changeset(%TaxonomySchema{}, %{
          name: "Testidae",
          type: "family",
          description: "Plant",
          rank: nil
        })

      assert changeset.valid?
    end

    test "taxonomy_types includes intermediate" do
      assert "intermediate" in TaxonomySchema.taxonomy_types()
    end

    test "create_taxonomy persists intermediate with rank", %{family: family} do
      {:ok, intermediate} =
        Taxonomy.create_taxonomy(%{
          name: "Cynipinae",
          type: "intermediate",
          parent_id: family.id,
          rank: "Subfamily"
        })

      assert intermediate.name == "Cynipinae"
      assert intermediate.type == "intermediate"
      assert intermediate.rank == "Subfamily"
      assert intermediate.parent_id == family.id
    end
  end

  describe "Lineage intermediates" do
    test "Lineage struct includes intermediates field defaulting to []" do
      lineage = %Lineage{genus: %Genus{name: "Test"}}
      assert lineage.intermediates == []
    end

    test "from_path with no intermediates returns intermediates: []" do
      path = [
        %TaxonomySchema{id: 1, name: "Cynipidae", type: "family", description: "Wasp", rank: nil},
        %TaxonomySchema{id: 2, name: "Andricus", type: "genus", description: nil, rank: nil}
      ]

      lineage = Lineage.from_path(path)
      assert lineage.family.name == "Cynipidae"
      assert lineage.genus.name == "Andricus"
      assert lineage.intermediates == []
    end

    test "from_path with one intermediate (subfamily)" do
      path = [
        %TaxonomySchema{id: 1, name: "Cynipidae", type: "family", description: "Wasp", rank: nil},
        %TaxonomySchema{
          id: 2,
          name: "Cynipinae",
          type: "intermediate",
          description: nil,
          rank: "Subfamily"
        },
        %TaxonomySchema{id: 3, name: "Andricus", type: "genus", description: nil, rank: nil}
      ]

      lineage = Lineage.from_path(path)
      assert lineage.family.name == "Cynipidae"
      assert length(lineage.intermediates) == 1
      assert [%Intermediate{name: "Cynipinae", rank: "Subfamily"}] = lineage.intermediates
      assert lineage.genus.name == "Andricus"
    end

    test "from_path with two intermediates ordered root-to-leaf" do
      path = [
        %TaxonomySchema{id: 1, name: "Cynipidae", type: "family", description: "Wasp", rank: nil},
        %TaxonomySchema{
          id: 2,
          name: "Cynipinae",
          type: "intermediate",
          description: nil,
          rank: "Subfamily"
        },
        %TaxonomySchema{
          id: 3,
          name: "Cynipini",
          type: "intermediate",
          description: nil,
          rank: "Tribe"
        },
        %TaxonomySchema{id: 4, name: "Andricus", type: "genus", description: nil, rank: nil}
      ]

      lineage = Lineage.from_path(path)
      assert length(lineage.intermediates) == 2

      assert [%Intermediate{rank: "Subfamily"}, %Intermediate{rank: "Tribe"}] =
               lineage.intermediates
    end

    test "from_section inherits intermediates: [] default" do
      section = %TaxonomySchema{
        id: 10,
        name: "sect. Quercus",
        type: "section",
        description: nil,
        rank: nil
      }

      genus = %TaxonomySchema{
        id: 5,
        name: "Quercus",
        type: "genus",
        description: nil,
        rank: nil,
        parent: %TaxonomySchema{
          id: 1,
          name: "Fagaceae",
          type: "family",
          description: "Plant",
          rank: nil
        }
      }

      lineage = Lineage.from_section(section, genus)
      assert lineage.intermediates == []
      assert lineage.section.name == "sect. Quercus"
    end

    test "new_genus has intermediates: []" do
      lineage = Lineage.new_genus("Newgenus")
      assert lineage.intermediates == []
    end

    test "from_query_result has intermediates: []" do
      result = %{genus_id: 1, genus: "Andricus", family_id: 2, family: "Cynipidae"}
      lineage = Lineage.from_query_result(result)
      assert lineage.intermediates == []
    end
  end

  describe "query changes for intermediates" do
    # Test seed data (from test_seeds.sql):
    # Cynipidae (family, id=30) → Cynipinae (subfamily, id=31) →
    #   Cynipini (tribe, id=32) → Andricus (genus, id=33), Cynips (genus, id=34)
    # Species: 200 = Andricus crystallinus → genus 33, 201 = Cynips quercus → genus 34

    test "get_taxonomy_for_species returns intermediates for species under intermediate-parented genus" do
      # Species 200 is under Andricus (genus 33), which is under Cynipini (tribe) → Cynipinae (subfamily) → Cynipidae
      lineage = Taxonomy.get_taxonomy_for_species(200)

      assert lineage.family.name == "Cynipidae"
      assert lineage.genus.name == "Andricus"
      assert length(lineage.intermediates) == 2

      assert [
               %Intermediate{name: "Cynipinae", rank: "Subfamily"},
               %Intermediate{name: "Cynipini", rank: "Tribe"}
             ] =
               lineage.intermediates
    end

    test "get_taxonomy_for_species returns empty intermediates for species without intermediates" do
      # Species 6 is under GenusAlpha (id=10) → FamilyAlpha (id=20), no intermediates
      lineage = Taxonomy.get_taxonomy_for_species(6)

      assert lineage.family.name == "FamilyAlpha"
      assert lineage.genus.name == "GenusAlpha"
      assert lineage.intermediates == []
    end

    test "get_genus_lineage with intermediates in chain" do
      # Genus 33 (Andricus) is under Cynipini → Cynipinae → Cynipidae
      {:ok, lineage} = Taxonomy.get_genus_lineage(33)

      assert lineage.family.name == "Cynipidae"
      assert lineage.genus.name == "Andricus"
      assert length(lineage.intermediates) == 2
    end

    test "get_genus_lineage without intermediates" do
      # Genus 10 (GenusAlpha) is directly under FamilyAlpha
      {:ok, lineage} = Taxonomy.get_genus_lineage(10)

      assert lineage.family.name == "FamilyAlpha"
      assert lineage.genus.name == "GenusAlpha"
      assert lineage.intermediates == []
    end

    test "build_taxonomy_from_genus with intermediates" do
      genus = Repo.get!(TaxonomySchema, 33)
      lineage = Tree.build_taxonomy_from_genus(genus)

      assert lineage.family.name == "Cynipidae"
      assert lineage.genus.name == "Andricus"
      assert length(lineage.intermediates) == 2
    end

    test "get_taxonomy_for_species_batch resolves family correctly through intermediates" do
      result = Taxonomy.get_taxonomy_for_species_batch([200, 201, 6])

      assert result[200].genus == "Andricus"
      assert result[200].family == "Cynipidae"
      assert result[201].genus == "Cynips"
      assert result[201].family == "Cynipidae"
      assert result[6].genus == "GenusAlpha"
      assert result[6].family == "FamilyAlpha"
    end

    test "get_species_ids_for_family finds species through intermediates" do
      # Family 30 (Cynipidae) has genera under intermediates
      species_ids = Taxonomy.get_species_ids_for_family(30)

      assert 200 in species_ids
      assert 201 in species_ids
    end

    test "list_genera_for_select resolves family through intermediates" do
      genera = Taxonomy.list_genera_for_select()

      andricus = Enum.find(genera, &(&1.name == "Andricus"))
      assert andricus, "Andricus should be in genera list"
      assert andricus.family_id == 30
    end

    test "search_genera resolves family_name through intermediates" do
      results = Taxonomy.search_genera("Andri")

      assert [%{name: "Andricus", family_name: "Cynipidae"}] = results
    end
  end

  describe "search integration for intermediates" do
    # Uses seed data: Cynipinae (subfamily, id=31), Cynipini (tribe, id=32)

    test "search_genera_and_sections includes intermediates" do
      results = Taxonomy.search_genera_and_sections("Cynip")

      intermediate_results = Enum.filter(results, &(&1.type == "intermediate"))
      assert length(intermediate_results) >= 1

      cynipinae = Enum.find(intermediate_results, &(&1.name == "Cynipinae"))
      assert cynipinae
      assert cynipinae.rank == "Subfamily"
    end

    test "search_genera_and_sections returns rank field for intermediates" do
      results = Taxonomy.search_genera_and_sections("Cynipini")
      tribe = Enum.find(results, &(&1.name == "Cynipini"))
      assert tribe
      assert tribe.rank == "Tribe"
      assert tribe.type == "intermediate"
    end

    test "search_genera_and_sections rank is nil for genus and section" do
      results = Taxonomy.search_genera_and_sections("GenusAlpha")
      genus = Enum.find(results, &(&1.name == "GenusAlpha"))
      assert genus
      assert genus.rank == nil
      assert genus.type == "genus"
    end
  end

  describe "create_intermediate/1" do
    setup do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "IntermediateTestFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, genus1} =
        Taxonomy.create_taxonomy(%{
          name: "IntermediateTestGenus1",
          type: "genus",
          parent_id: family.id
        })

      {:ok, genus2} =
        Taxonomy.create_taxonomy(%{
          name: "IntermediateTestGenus2",
          type: "genus",
          parent_id: family.id
        })

      {:ok, family: family, genus1: genus1, genus2: genus2}
    end

    test "creates intermediate and re-parents one child", %{family: family, genus1: genus1} do
      {:ok, intermediate} =
        Taxonomy.create_intermediate(%{
          name: "TestSubfamily",
          rank: "Subfamily",
          parent_id: family.id,
          children_ids: [genus1.id]
        })

      assert intermediate.name == "TestSubfamily"
      assert intermediate.rank == "Subfamily"
      assert intermediate.parent_id == family.id

      # Genus should now be under the intermediate
      updated_genus = Repo.get!(TaxonomySchema, genus1.id)
      assert updated_genus.parent_id == intermediate.id
    end

    test "creates intermediate and re-parents multiple children", %{
      family: family,
      genus1: genus1,
      genus2: genus2
    } do
      {:ok, intermediate} =
        Taxonomy.create_intermediate(%{
          name: "TestSubfamily2",
          rank: "Subfamily",
          parent_id: family.id,
          children_ids: [genus1.id, genus2.id]
        })

      updated_g1 = Repo.get!(TaxonomySchema, genus1.id)
      updated_g2 = Repo.get!(TaxonomySchema, genus2.id)
      assert updated_g1.parent_id == intermediate.id
      assert updated_g2.parent_id == intermediate.id
    end

    test "fails with zero children" do
      assert {:error, :no_children_selected} =
               Taxonomy.create_intermediate(%{
                 name: "EmptyIntermediate",
                 rank: "Subfamily",
                 parent_id: 1,
                 children_ids: []
               })
    end

    test "creates nested intermediate under another intermediate", %{
      family: family,
      genus1: genus1,
      genus2: genus2
    } do
      {:ok, subfamily} =
        Taxonomy.create_intermediate(%{
          name: "NestedSubfamily",
          rank: "Subfamily",
          parent_id: family.id,
          children_ids: [genus1.id, genus2.id]
        })

      {:ok, tribe} =
        Taxonomy.create_intermediate(%{
          name: "NestedTribe",
          rank: "Tribe",
          parent_id: subfamily.id,
          children_ids: [genus1.id]
        })

      assert tribe.parent_id == subfamily.id
      updated_g1 = Repo.get!(TaxonomySchema, genus1.id)
      assert updated_g1.parent_id == tribe.id
    end
  end

  describe "delete intermediate (collapse upward)" do
    test "re-parents children to grandparent when intermediate is deleted" do
      # Cynipini (tribe, id=32) has children Andricus (33) and Cynips (34)
      # Its parent is Cynipinae (subfamily, id=31)
      tribe = Taxonomy.get_taxonomy!(32)
      assert tribe.type == "intermediate"

      # Delete the tribe — children should move to its parent (Cynipinae)
      {:ok, _deleted} = Taxonomy.delete_taxonomy_cascade(tribe)

      # Andricus and Cynips should now be under Cynipinae (id=31)
      andricus = Repo.get!(TaxonomySchema, 33)
      cynips = Repo.get!(TaxonomySchema, 34)
      assert andricus.parent_id == 31
      assert cynips.parent_id == 31
    end

    test "get_deletion_impact for intermediate shows children" do
      tribe = Taxonomy.get_taxonomy!(32)
      impact = Taxonomy.get_deletion_impact(tribe)

      assert impact.taxonomy.id == 32
      assert impact.children_count == 2
      assert impact.has_impact == true
    end
  end

  describe "family page — mixed children" do
    test "get_children returns both intermediates and genera for a family" do
      # Cynipidae (id=30) has Cynipinae (intermediate) and Unknown (genus, id=35)
      children = Taxonomy.get_children(30)
      types = children |> Enum.map(& &1.type) |> Enum.uniq() |> Enum.sort()
      assert "genus" in types
      assert "intermediate" in types
    end
  end

  describe "list_children_with_counts/1" do
    test "returns children of an intermediate with species counts" do
      # Cynipini (tribe, id=32) has children Andricus (33) and Cynips (34)
      children = Taxonomy.list_children_with_counts(32)
      assert length(children) == 2

      andricus = Enum.find(children, &(&1.name == "Andricus"))
      assert andricus.type == "genus"
      # Andricus has species 200 (Andricus crystallinus) in test seeds
      assert andricus.species_count == 1

      cynips = Enum.find(children, &(&1.name == "Cynips"))
      assert cynips.type == "genus"
      assert cynips.species_count == 1
    end

    test "returns intermediates and genera as children of a family" do
      # Cynipidae (id=30) has Cynipinae (intermediate) and Unknown (genus) as direct children
      children = Taxonomy.list_children_with_counts(30)
      types = Enum.map(children, & &1.type)
      assert "intermediate" in types || "genus" in types
    end
  end

  describe "admin index queries for intermediates" do
    test "list_taxonomies_with_parent includes rank for intermediates" do
      # Cynipinae (id=31) is a Subfamily intermediate in test seeds
      results = Taxonomy.list_taxonomies_with_parent("intermediate")
      assert length(results) > 0

      subfamily = Enum.find(results, &(&1.name == "Cynipinae"))
      assert subfamily != nil
      assert subfamily.rank == "Subfamily"
      assert subfamily.type == "intermediate"
      assert subfamily.parent_name == "Cynipidae"
    end

    test "list_taxonomies_with_parent_paginated includes rank for intermediates" do
      results = Taxonomy.list_taxonomies_with_parent_paginated("intermediate", 50, 0)
      assert length(results) > 0

      tribe = Enum.find(results, &(&1.name == "Cynipini"))
      assert tribe != nil
      assert tribe.rank == "Tribe"
    end

    test "count_taxonomies counts intermediates" do
      count = Taxonomy.count_taxonomies("intermediate")
      assert count >= 2
    end
  end
end
