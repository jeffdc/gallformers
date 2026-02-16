defmodule Gallformers.ProdData.WriteOperationsTest do
  use Gallformers.ProdDataCase

  @moduletag :prod_data

  alias Gallformers.Galls.GallTraits
  alias Gallformers.Species.{Alias, Species}
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.Taxonomy, as: TaxonomySchema

  # =====================================================================
  # Helpers
  # =====================================================================

  defp count_species_taxonomy_links(species_id) do
    Repo.one(
      from(st in "species_taxonomy",
        where: st.species_id == ^species_id,
        select: count()
      )
    )
  end

  defp count_genus_links(species_id) do
    Repo.one(
      from(st in "species_taxonomy",
        join: t in TaxonomySchema,
        on: t.id == st.taxonomy_id,
        where: st.species_id == ^species_id and t.type == "genus",
        select: count()
      )
    )
  end

  defp count_section_links(species_id) do
    Repo.one(
      from(st in "species_taxonomy",
        join: t in TaxonomySchema,
        on: t.id == st.taxonomy_id,
        where: st.species_id == ^species_id and t.type == "section",
        select: count()
      )
    )
  end

  defp get_alias_names(species_id) do
    Repo.all(
      from(a in Alias,
        join: als in "alias_species",
        on: als.alias_id == a.id,
        where: als.species_id == ^species_id,
        select: %{name: a.name, type: a.type}
      )
    )
  end

  defp get_genus_id_for_species(species_id) do
    Repo.one(
      from(st in "species_taxonomy",
        join: t in TaxonomySchema,
        on: t.id == st.taxonomy_id,
        where: st.species_id == ^species_id and t.type == "genus",
        select: t.id
      )
    )
  end

  # =====================================================================
  # Reclassify species
  # =====================================================================

  describe "reclassify_species" do
    setup do
      # Find a gall species linked to a non-Unknown, non-placeholder genus
      species =
        Repo.one(
          from(s in Species,
            join: st in "species_taxonomy",
            on: st.species_id == s.id,
            join: t in TaxonomySchema,
            on: t.id == st.taxonomy_id,
            where:
              s.taxoncode == "gall" and t.type == "genus" and
                t.is_placeholder == false and
                not like(t.name, "Unknown%"),
            limit: 1,
            select: s
          )
        )

      if is_nil(species) do
        raise ExUnit.DocTest.Error, "No suitable gall species found for reclassify tests"
      end

      lineage = Taxonomy.get_taxonomy_for_species(species.id)
      original_aliases = get_alias_names(species.id)

      %{species: species, lineage: lineage, original_aliases: original_aliases}
    end

    test "reclassify gall to different existing genus in same family", ctx do
      %{species: species, lineage: lineage} = ctx

      # Find a different genus in the same family
      different_genus =
        Repo.one(
          from(t in TaxonomySchema,
            where:
              t.type == "genus" and t.parent_id == ^lineage.family.id and
                t.id != ^lineage.genus.id and
                t.is_placeholder == false,
            limit: 1
          )
        )

      if is_nil(different_genus) do
        IO.puts(
          "SKIP: No second genus in family #{lineage.family.name} — only one non-placeholder genus"
        )
      else
        old_name = species.name
        new_name = "#{different_genus.name} #{Taxonomy.extract_epithet(old_name)}"

        {:ok, updated} =
          Taxonomy.reclassify_species(species.id, %{
            genus_id: different_genus.id,
            new_name: new_name,
            old_name: old_name,
            genus_changed?: true,
            name_changed?: true,
            add_alias?: true
          })

        # Species name updated
        assert updated.name == new_name

        # Old name exists as alias
        aliases = get_alias_names(species.id)
        old_name_aliases = Enum.filter(aliases, &(&1.name == old_name))
        assert length(old_name_aliases) > 0, "Expected alias with old name #{old_name}"

        # species_taxonomy points to new genus
        assert get_genus_id_for_species(species.id) == different_genus.id

        # gall_traits still exists
        assert Repo.get(GallTraits, species.id) != nil
      end
    end

    test "reclassify gall to genus in different family", ctx do
      %{species: species, lineage: lineage} = ctx

      # Find a genus in a completely different family
      different_family_genus =
        Repo.one(
          from(t in TaxonomySchema,
            where:
              t.type == "genus" and t.parent_id != ^lineage.family.id and
                t.is_placeholder == false,
            limit: 1
          )
        )

      if is_nil(different_family_genus) do
        IO.puts("SKIP: No genus in a different family found")
      else
        old_name = species.name
        new_name = "#{different_family_genus.name} #{Taxonomy.extract_epithet(old_name)}"

        {:ok, updated} =
          Taxonomy.reclassify_species(species.id, %{
            genus_id: different_family_genus.id,
            new_name: new_name,
            old_name: old_name,
            genus_changed?: true,
            name_changed?: true,
            add_alias?: true
          })

        assert updated.name == new_name

        aliases = get_alias_names(species.id)
        assert Enum.any?(aliases, &(&1.name == old_name))

        assert get_genus_id_for_species(species.id) == different_family_genus.id
        assert Repo.get(GallTraits, species.id) != nil
      end
    end

    test "reclassify species that has a section link removes section" do
      # Find a species linked to both a genus and a section
      species_with_section =
        Repo.one(
          from(s in Species,
            join: st1 in "species_taxonomy",
            on: st1.species_id == s.id,
            join: g in TaxonomySchema,
            on: g.id == st1.taxonomy_id and g.type == "genus",
            join: st2 in "species_taxonomy",
            on: st2.species_id == s.id,
            join: sec in TaxonomySchema,
            on: sec.id == st2.taxonomy_id and sec.type == "section",
            where: g.is_placeholder == false,
            limit: 1,
            select: s
          )
        )

      if is_nil(species_with_section) do
        IO.puts("SKIP: No species with both genus and section link found")
      else
        assert count_section_links(species_with_section.id) >= 1

        # Find a different genus to move to
        current_genus_id = get_genus_id_for_species(species_with_section.id)

        different_genus =
          Repo.one(
            from(t in TaxonomySchema,
              where:
                t.type == "genus" and t.id != ^current_genus_id and
                  t.is_placeholder == false,
              limit: 1
            )
          )

        old_name = species_with_section.name
        new_name = "#{different_genus.name} #{Taxonomy.extract_epithet(old_name)}"

        {:ok, _updated} =
          Taxonomy.reclassify_species(species_with_section.id, %{
            genus_id: different_genus.id,
            new_name: new_name,
            old_name: old_name,
            genus_changed?: true,
            name_changed?: true,
            add_alias?: true
          })

        # Old section link should be removed
        assert count_section_links(species_with_section.id) == 0,
               "Section links should be removed when reclassifying to a different genus"

        # Should have exactly one genus link (the new one)
        assert count_genus_links(species_with_section.id) == 1
      end
    end

    test "name-only reclassify (epithet change, same genus)", ctx do
      %{species: species, lineage: lineage, original_aliases: original_aliases} = ctx

      old_name = species.name
      unique = System.unique_integer([:positive])
      new_name = "#{lineage.genus.name} testreclassify#{unique}"

      {:ok, updated} =
        Taxonomy.reclassify_species(species.id, %{
          genus_id: lineage.genus.id,
          new_name: new_name,
          old_name: old_name,
          genus_changed?: false,
          name_changed?: true,
          add_alias?: true
        })

      assert updated.name == new_name

      # Alias created for old name
      aliases = get_alias_names(species.id)
      assert Enum.any?(aliases, &(&1.name == old_name))

      # Genus link unchanged
      assert get_genus_id_for_species(species.id) == lineage.genus.id

      # More aliases than before
      assert length(aliases) > length(original_aliases)
    end

    test "no-op reclassify (nothing changed)", ctx do
      %{species: species, lineage: lineage, original_aliases: original_aliases} = ctx

      {:ok, returned} =
        Taxonomy.reclassify_species(species.id, %{
          genus_id: lineage.genus.id,
          new_name: species.name,
          old_name: species.name,
          genus_changed?: false,
          name_changed?: false,
          add_alias?: false
        })

      # Same species returned
      assert returned.id == species.id
      assert returned.name == species.name

      # No new aliases
      aliases = get_alias_names(species.id)
      assert length(aliases) == length(original_aliases)

      # Genus link unchanged
      assert get_genus_id_for_species(species.id) == lineage.genus.id
    end

    test "reclassify undescribed gall from Unknown genus to real genus" do
      # Find an undescribed gall under an Unknown/placeholder genus
      undescribed_gall =
        Repo.one(
          from(s in Species,
            join: gt in GallTraits,
            on: gt.species_id == s.id,
            join: st in "species_taxonomy",
            on: st.species_id == s.id,
            join: t in TaxonomySchema,
            on: t.id == st.taxonomy_id,
            where:
              s.taxoncode == "gall" and gt.undescribed == true and
                t.type == "genus" and t.is_placeholder == true,
            limit: 1,
            select: s
          )
        )

      if is_nil(undescribed_gall) do
        IO.puts("SKIP: No undescribed gall under an Unknown genus found")
      else
        old_name = undescribed_gall.name

        # Find a real (non-placeholder) genus
        real_genus =
          Repo.one(
            from(t in TaxonomySchema,
              where: t.type == "genus" and t.is_placeholder == false,
              limit: 1
            )
          )

        new_name = "#{real_genus.name} #{Taxonomy.extract_epithet(old_name)}"

        {:ok, updated} =
          Taxonomy.reclassify_species(undescribed_gall.id, %{
            genus_id: real_genus.id,
            new_name: new_name,
            old_name: old_name,
            genus_changed?: true,
            name_changed?: true,
            add_alias?: true
          })

        # Name updated to use real genus
        assert updated.name == new_name
        refute String.starts_with?(updated.name, "Unknown")

        # Alias created with old unknown name
        aliases = get_alias_names(undescribed_gall.id)
        assert Enum.any?(aliases, &(&1.name == old_name))

        # Genus link updated
        assert get_genus_id_for_species(undescribed_gall.id) == real_genus.id
      end
    end

    test "reclassify described gall TO Unknown genus" do
      # Find a described gall (not undescribed) under a real genus
      described_gall =
        Repo.one(
          from(s in Species,
            join: gt in GallTraits,
            on: gt.species_id == s.id,
            join: st in "species_taxonomy",
            on: st.species_id == s.id,
            join: t in TaxonomySchema,
            on: t.id == st.taxonomy_id,
            where:
              s.taxoncode == "gall" and gt.undescribed == false and
                t.type == "genus" and t.is_placeholder == false,
            limit: 1,
            select: s
          )
        )

      if is_nil(described_gall) do
        IO.puts("SKIP: No described gall under a real genus found")
      else
        old_name = described_gall.name

        # Find an Unknown/placeholder genus
        placeholder_genus =
          Repo.one(
            from(t in TaxonomySchema,
              where: t.type == "genus" and t.is_placeholder == true,
              limit: 1
            )
          )
          |> Repo.preload(:parent)

        family_name = placeholder_genus.parent.name
        new_name = "Unknown (#{family_name}) #{Taxonomy.extract_epithet(old_name)}"

        {:ok, updated} =
          Taxonomy.reclassify_species(described_gall.id, %{
            genus_id: placeholder_genus.id,
            new_name: new_name,
            old_name: old_name,
            genus_changed?: true,
            name_changed?: true,
            add_alias?: true
          })

        # Name should reflect the Unknown genus
        assert String.starts_with?(updated.name, "Unknown (")

        # undescribed should be forced to true
        gall_traits = Repo.get(GallTraits, described_gall.id)

        assert gall_traits.undescribed == true,
               "Expected undescribed to be forced true when moving to Unknown genus"

        # Genus link updated to placeholder
        assert get_genus_id_for_species(described_gall.id) == placeholder_genus.id
      end
    end
  end

  # =====================================================================
  # Genus rename cascade
  # =====================================================================

  describe "genus rename cascade" do
    setup do
      # Find a non-placeholder genus with 2+ species
      genus_with_species =
        Repo.one(
          from(t in TaxonomySchema,
            join: st in "species_taxonomy",
            on: st.taxonomy_id == t.id,
            where: t.type == "genus" and t.is_placeholder == false,
            group_by: t.id,
            having: count(st.species_id) >= 2,
            limit: 1,
            select: t
          )
        )

      if is_nil(genus_with_species) do
        raise "No genus with 2+ species found for rename cascade test"
      end

      species_ids = Taxonomy.get_species_ids_for_genus(genus_with_species.id)

      old_species_names =
        Repo.all(from(s in Species, where: s.id in ^species_ids, select: {s.id, s.name}))

      %{
        genus: genus_with_species,
        species_ids: species_ids,
        old_species_names: Map.new(old_species_names)
      }
    end

    test "rename a genus with species cascades to all species", ctx do
      %{genus: genus, species_ids: species_ids, old_species_names: old_names} = ctx
      old_genus_name = genus.name
      new_genus_name = "Testgenus#{System.unique_integer([:positive])}"

      {:ok, updated_genus} = Taxonomy.update_taxonomy(genus, %{name: new_genus_name})
      assert updated_genus.name == new_genus_name

      # All species under this genus should have updated names
      updated_species = Repo.all(from(s in Species, where: s.id in ^species_ids))

      for sp <- updated_species do
        assert String.starts_with?(sp.name, new_genus_name),
               "Species #{sp.id} name '#{sp.name}' should start with '#{new_genus_name}'"

        refute String.starts_with?(sp.name, old_genus_name),
               "Species #{sp.id} name '#{sp.name}' should NOT start with old genus '#{old_genus_name}'"
      end

      # Each species should have an alias with the old name
      for sp <- updated_species do
        aliases = get_alias_names(sp.id)
        old_name = old_names[sp.id]

        assert Enum.any?(aliases, &(&1.name == old_name)),
               "Species #{sp.id} should have alias with old name '#{old_name}'"
      end
    end

    test "genus rename alias type is scientific", ctx do
      %{genus: genus, species_ids: species_ids, old_species_names: old_names} = ctx
      new_genus_name = "Testgenus#{System.unique_integer([:positive])}"

      {:ok, _} = Taxonomy.update_taxonomy(genus, %{name: new_genus_name})

      # Check that new aliases are of type "scientific"
      for id <- species_ids do
        aliases = get_alias_names(id)
        old_name = old_names[id]

        # The alias matching the old name should be scientific
        matching = Enum.filter(aliases, &(&1.name == old_name))

        assert Enum.any?(matching, &(&1.type == "scientific")),
               "Expected a 'scientific' alias for old name '#{old_name}' on species #{id}, got: #{inspect(matching)}"
      end
    end
  end

  # =====================================================================
  # update_species_genus — isolated
  # =====================================================================

  describe "update_species_genus" do
    test "species with genus-only link" do
      # Find a species with exactly one species_taxonomy link (genus only)
      species =
        Repo.one(
          from(s in Species,
            join: st in "species_taxonomy",
            on: st.species_id == s.id,
            join: t in TaxonomySchema,
            on: t.id == st.taxonomy_id,
            where: t.type == "genus" and t.is_placeholder == false,
            group_by: s.id,
            having: count(st.species_id) == 1,
            limit: 1,
            select: s
          )
        )

      if is_nil(species) do
        IO.puts("SKIP: No species with exactly one genus link found")
      else
        old_genus_id = get_genus_id_for_species(species.id)

        # Find a different genus
        new_genus =
          Repo.one(
            from(t in TaxonomySchema,
              where:
                t.type == "genus" and t.id != ^old_genus_id and
                  t.is_placeholder == false,
              limit: 1
            )
          )

        :ok = Taxonomy.update_species_genus(species.id, new_genus.id)

        assert get_genus_id_for_species(species.id) == new_genus.id
        assert count_genus_links(species.id) == 1
        assert count_species_taxonomy_links(species.id) == 1
      end
    end

    test "species with genus AND section links removes both old links" do
      # Find a species linked to both a genus and a section
      species_with_both =
        Repo.one(
          from(s in Species,
            join: st1 in "species_taxonomy",
            on: st1.species_id == s.id,
            join: g in TaxonomySchema,
            on: g.id == st1.taxonomy_id and g.type == "genus",
            join: st2 in "species_taxonomy",
            on: st2.species_id == s.id,
            join: sec in TaxonomySchema,
            on: sec.id == st2.taxonomy_id and sec.type == "section",
            limit: 1,
            select: s
          )
        )

      if is_nil(species_with_both) do
        IO.puts("SKIP: No species with both genus and section links found")
      else
        links_before = count_species_taxonomy_links(species_with_both.id)
        assert links_before >= 2

        old_genus_id = get_genus_id_for_species(species_with_both.id)

        new_genus =
          Repo.one(
            from(t in TaxonomySchema,
              where:
                t.type == "genus" and t.id != ^old_genus_id and
                  t.is_placeholder == false,
              limit: 1
            )
          )

        :ok = Taxonomy.update_species_genus(species_with_both.id, new_genus.id)

        # Only the new genus link remains — section links removed
        assert count_genus_links(species_with_both.id) == 1
        assert count_section_links(species_with_both.id) == 0
        assert count_species_taxonomy_links(species_with_both.id) == 1
      end
    end
  end

  # =====================================================================
  # Cascade delete
  # =====================================================================

  describe "delete_taxonomy_cascade" do
    test "delete a genus with species removes everything" do
      # Find a small genus (few species) to minimize test scope
      genus =
        Repo.one(
          from(t in TaxonomySchema,
            join: st in "species_taxonomy",
            on: st.taxonomy_id == t.id,
            where: t.type == "genus" and t.is_placeholder == false,
            group_by: t.id,
            having: count(st.species_id) >= 1 and count(st.species_id) <= 5,
            order_by: [asc: count(st.species_id)],
            limit: 1,
            select: t
          )
        )

      if is_nil(genus) do
        IO.puts("SKIP: No genus with 1-5 species found")
      else
        # Record what exists before deletion
        species_ids = Taxonomy.get_species_ids_for_genus(genus.id)
        assert length(species_ids) > 0

        alias_ids_before =
          Repo.all(
            from(als in "alias_species",
              where: als.species_id in ^species_ids,
              select: als.alias_id
            )
          )

        {:ok, impact} = Taxonomy.delete_taxonomy_cascade(genus)

        # Genus gone
        assert Repo.get(TaxonomySchema, genus.id) == nil

        # All species gone
        remaining_species =
          Repo.all(from(s in Species, where: s.id in ^species_ids))

        assert remaining_species == [],
               "Expected all species to be deleted, found: #{inspect(Enum.map(remaining_species, & &1.id))}"

        # All gall_traits gone
        remaining_traits =
          Repo.aggregate(
            from(gt in GallTraits, where: gt.species_id in ^species_ids),
            :count
          )

        assert remaining_traits == 0

        # All species_taxonomy rows gone
        remaining_st =
          Repo.one(
            from(st in "species_taxonomy",
              where: st.species_id in ^species_ids,
              select: count()
            )
          )

        assert remaining_st == 0

        # All alias_species rows gone
        if alias_ids_before != [] do
          remaining_alias_links =
            Repo.one(
              from(als in "alias_species",
                where: als.species_id in ^species_ids,
                select: count()
              )
            )

          assert remaining_alias_links == 0
        end

        # Impact map has correct species count
        assert impact.species_count == length(species_ids)
      end
    end

    test "get_deletion_impact matches actual deletions" do
      # Find a small genus with species
      genus =
        Repo.one(
          from(t in TaxonomySchema,
            join: st in "species_taxonomy",
            on: st.taxonomy_id == t.id,
            where: t.type == "genus" and t.is_placeholder == false,
            group_by: t.id,
            having: count(st.species_id) >= 1 and count(st.species_id) <= 5,
            order_by: [asc: count(st.species_id)],
            limit: 1,
            select: t
          )
        )

      if is_nil(genus) do
        IO.puts("SKIP: No genus with 1-5 species found")
      else
        # Get predicted impact
        impact = Taxonomy.get_deletion_impact(genus)
        species_ids = Taxonomy.get_species_ids_for_genus(genus.id)

        # Actually delete
        {:ok, actual} = Taxonomy.delete_taxonomy_cascade(genus)

        assert Repo.all(from(s in Species, where: s.id in ^species_ids)) == []

        assert impact.species_count == actual.species_count,
               "Impact predicted #{impact.species_count} species but deleted #{actual.species_count}"

        assert impact.sections_count == actual.sections_count,
               "Impact predicted #{impact.sections_count} sections but deleted #{actual.sections_count}"
      end
    end
  end

  # =====================================================================
  # Transaction rollback safety
  # =====================================================================

  describe "transaction rollback safety" do
    test "reclassify with invalid species_id raises or returns error" do
      # Find a real genus to use as target
      genus =
        Repo.one(
          from(t in TaxonomySchema,
            where: t.type == "genus" and t.is_placeholder == false,
            limit: 1
          )
        )

      # NOTE: reclassify_species with an invalid species_id raises an
      # Exqlite.Error (FK constraint) rather than returning {:error, _}.
      # The transaction does not catch the raised error. This documents
      # that callers must ensure the species_id is valid before calling.
      assert_raise Exqlite.Error, ~r/FOREIGN KEY/i, fn ->
        Taxonomy.reclassify_species(-1, %{
          genus_id: genus.id,
          new_name: "Fake testspecies",
          old_name: "Nonexistent species",
          genus_changed?: true,
          name_changed?: true,
          add_alias?: true
        })
      end
    end

    test "reclassify where target name collides returns error" do
      # Find two gall species in the same genus
      pair =
        Repo.all(
          from(s in Species,
            join: st in "species_taxonomy",
            on: st.species_id == s.id,
            join: t in TaxonomySchema,
            on: t.id == st.taxonomy_id,
            where: s.taxoncode == "gall" and t.type == "genus" and t.is_placeholder == false,
            select: %{species_id: s.id, species_name: s.name, genus_id: t.id, genus_name: t.name},
            limit: 100
          )
        )
        |> Enum.group_by(& &1.genus_id)
        |> Enum.find(fn {_genus_id, species} -> length(species) >= 2 end)

      if is_nil(pair) do
        IO.puts("SKIP: No genus with 2+ gall species found")
      else
        {_genus_id, [sp1, sp2 | _]} = pair

        # Try to reclassify sp1 to have sp2's exact name (same genus, just name change)
        result =
          Taxonomy.reclassify_species(sp1.species_id, %{
            genus_id: sp1.genus_id,
            new_name: sp2.species_name,
            old_name: sp1.species_name,
            genus_changed?: false,
            name_changed?: true,
            add_alias?: true
          })

        assert {:error, :name_exists} = result

        # Verify original species name unchanged
        species = Repo.get!(Species, sp1.species_id)
        assert species.name == sp1.species_name
      end
    end
  end

  # =====================================================================
  # Rename collision detection
  # =====================================================================

  describe "rename collision detection" do
    test "reclassify species returns {:error, :name_exists} when target name is taken" do
      # Find a gall species with a genus
      species =
        Repo.one(
          from(s in Species,
            join: st in "species_taxonomy",
            on: st.species_id == s.id,
            join: t in TaxonomySchema,
            on: t.id == st.taxonomy_id,
            where:
              s.taxoncode == "gall" and t.type == "genus" and
                t.is_placeholder == false and
                not like(t.name, "Unknown%"),
            limit: 1,
            select: s
          )
        )

      assert species, "Need a gall species with taxonomy"

      lineage = Taxonomy.get_taxonomy_for_species(species.id)

      # Find a different genus to reclassify to
      different_genus =
        Repo.one(
          from(t in TaxonomySchema,
            where:
              t.type == "genus" and t.id != ^lineage.genus.id and
                t.is_placeholder == false,
            limit: 1
          )
        )

      assert different_genus, "Need a different genus"

      # Create a species with the name that reclassification would produce
      colliding_name = "#{different_genus.name} #{Taxonomy.extract_epithet(species.name)}"

      {:ok, _blocker} =
        Repo.insert(%Species{
          name: colliding_name,
          taxoncode: "gall",
          datacomplete: false
        })

      # Attempt reclassification — should fail with :name_exists
      result =
        Taxonomy.reassign_species_taxonomy(species.id, different_genus.id,
          add_alias?: true,
          target_epithet: Taxonomy.extract_epithet(species.name)
        )

      assert {:error, :name_exists} = result

      # Verify original species name unchanged
      unchanged = Repo.get!(Species, species.id)
      assert unchanged.name == species.name
    end

    test "genus rename returns error when a resulting species name would collide" do
      # Find a genus with at least one species
      genus =
        Repo.one(
          from(t in TaxonomySchema,
            join: st in "species_taxonomy",
            on: st.taxonomy_id == t.id,
            where: t.type == "genus" and t.is_placeholder == false,
            group_by: t.id,
            having: count(st.species_id) >= 1,
            limit: 1,
            select: t
          )
        )

      assert genus, "Need a genus with species"

      species_ids = Taxonomy.get_species_ids_for_genus(genus.id)
      [first_species | _] = Repo.all(from(s in Species, where: s.id in ^species_ids))

      new_genus_name = "Collisiontest#{System.unique_integer([:positive])}"

      # Create a species whose name matches what the rename would produce
      colliding_name =
        "#{new_genus_name} #{Taxonomy.extract_epithet(first_species.name)}"

      {:ok, _blocker} =
        Repo.insert(%Species{
          name: colliding_name,
          taxoncode: first_species.taxoncode,
          datacomplete: false
        })

      # Attempt genus rename — should fail with rename_collision
      result = Taxonomy.update_taxonomy(genus, %{name: new_genus_name})
      assert {:error, {:rename_collision, _, :name_exists}} = result

      # Verify genus name unchanged
      unchanged_genus = Repo.get!(TaxonomySchema, genus.id)
      assert unchanged_genus.name == genus.name

      # Verify species name unchanged
      unchanged_species = Repo.get!(Species, first_species.id)
      assert unchanged_species.name == first_species.name
    end

    test "no partial state on genus rename collision with multiple species" do
      # Find a genus with 2+ species
      genus =
        Repo.one(
          from(t in TaxonomySchema,
            join: st in "species_taxonomy",
            on: st.taxonomy_id == t.id,
            where: t.type == "genus" and t.is_placeholder == false,
            group_by: t.id,
            having: count(st.species_id) >= 2,
            limit: 1,
            select: t
          )
        )

      assert genus, "Need a genus with 2+ species"

      species_ids = Taxonomy.get_species_ids_for_genus(genus.id)

      all_species =
        Repo.all(from(s in Species, where: s.id in ^species_ids, order_by: s.name))

      old_names = Map.new(all_species, &{&1.id, &1.name})
      new_genus_name = "Collisiontest#{System.unique_integer([:positive])}"

      # Pick the LAST species to collide with — earlier species would rename first,
      # so partial state means some renamed and some didn't
      last_species = List.last(all_species)

      colliding_name =
        "#{new_genus_name} #{Taxonomy.extract_epithet(last_species.name)}"

      {:ok, _blocker} =
        Repo.insert(%Species{
          name: colliding_name,
          taxoncode: last_species.taxoncode,
          datacomplete: false
        })

      # Attempt genus rename — should fail
      result = Taxonomy.update_taxonomy(genus, %{name: new_genus_name})
      assert {:error, {:rename_collision, _, :name_exists}} = result

      # Verify ALL species retain original names (transaction rolled back completely)
      for sp <- all_species do
        current = Repo.get!(Species, sp.id)

        assert current.name == old_names[sp.id],
               "Species #{sp.id} should retain name '#{old_names[sp.id]}' but has '#{current.name}'"
      end

      # Verify genus name also unchanged
      unchanged_genus = Repo.get!(TaxonomySchema, genus.id)
      assert unchanged_genus.name == genus.name
    end
  end
end
