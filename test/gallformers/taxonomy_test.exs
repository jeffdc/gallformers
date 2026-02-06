defmodule Gallformers.TaxonomyTest do
  @moduledoc """
  Unit tests for the Taxonomy context.
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.Repo
  alias Gallformers.Species.Alias
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy

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

      assert result.genus == "TestSpeciesTaxGenus"
      assert result.genus_id == genus.id
      assert result.family == "TestSpeciesTaxFamily"
      assert result.family_id == family.id
      assert result.section == nil
      assert result.section_id == nil
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

      assert result.genus == "TestSectionGenus"
      assert result.genus_id == genus.id
      assert result.section == "TestSection"
      assert result.section_id == section.id
      assert result.family == "TestSectionFamily"
      assert result.family_id == family.id
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

      # Verify Unknown genus was auto-created
      unknown_genus =
        Repo.one(
          from(t in Taxonomy.Taxonomy,
            where: t.name == "Unknown" and t.type == "genus" and t.parent_id == ^family.id
          )
        )

      assert unknown_genus != nil
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
            where: t.name == "Unknown" and t.type == "genus" and t.parent_id == ^family.id
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
      taxonomy = %{genus: "Unknown", genus_id: nil}
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
            where: t.name == "Unknown" and t.type == "genus" and t.parent_id == ^family.id,
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
end
