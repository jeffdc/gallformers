defmodule Gallformers.PlantsTest do
  @moduledoc """
  Unit tests for the Plants context.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Plants
  alias Gallformers.Plants.HostTraits
  alias Gallformers.Ranges
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.{Genus, Lineage}

  describe "create_host_with_associations/1" do
    setup do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestPlantFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "Testplantgenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, family: family, genus: genus}
    end

    test "creates host with taxonomy and aliases", %{genus: genus} do
      params = %{
        species_attrs: %{
          "name" => "Testplantgenus newhost",
          "taxoncode" => "plant",
          "datacomplete" => false
        },
        taxonomy: %Lineage{genus: %Genus{id: genus.id, name: genus.name}},
        genus_is_new: false,
        parent_id: nil,
        aliases: [%{name: "Test common name", type: "common"}]
      }

      assert {:ok, host} = Plants.create_host_with_associations(params)
      assert host.name == "Testplantgenus newhost"
      assert host.taxoncode == "plant"

      # Verify taxonomy was linked
      taxonomy = Taxonomy.get_taxonomy_for_species(host.id)
      assert taxonomy != nil
      assert taxonomy.genus.id == genus.id

      # Verify alias was created
      aliases = Plants.get_aliases_for_host_full(host.id)
      assert length(aliases) == 1
      assert hd(aliases).name == "Test common name"
    end

    test "creates host with section linked when section is selected", %{
      family: family,
      genus: genus
    } do
      {:ok, section} =
        Taxonomy.create_taxonomy(%{
          name: "Testsection",
          type: "section",
          parent_id: genus.id
        })

      # Mirror save_host(:new) in form.ex — selected_section_id is passed separately,
      # and parent_id falls through to family when section is selected
      selected_section_id = section.id

      params = %{
        species_attrs: %{
          "name" => "Testplantgenus sectionhost",
          "taxoncode" => "plant",
          "datacomplete" => false
        },
        taxonomy: %Lineage{
          genus: %Genus{id: genus.id, name: genus.name},
          section: nil
        },
        genus_is_new: false,
        parent_id: selected_section_id || family.id,
        selected_section_id: selected_section_id,
        aliases: []
      }

      assert {:ok, host} = Plants.create_host_with_associations(params)

      taxonomy = Taxonomy.get_taxonomy_for_species(host.id)
      assert taxonomy.genus.id == genus.id
      assert taxonomy.section != nil, "section should be linked but was nil"
      assert taxonomy.section.id == section.id
    end

    test "rolls back on invalid species attrs" do
      params = %{
        species_attrs: %{"taxoncode" => "plant"},
        taxonomy: %Lineage{genus: %Genus{name: "Whatever"}},
        genus_is_new: false,
        parent_id: nil,
        aliases: []
      }

      assert {:error, %Ecto.Changeset{}} = Plants.create_host_with_associations(params)
    end
  end

  describe "host_traits" do
    setup do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestHostTraitsFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "Testhosttraitsgenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, species} =
        Repo.insert(%Species{name: "Testhosttraitsgenus testhost", taxoncode: "plant"})

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      {:ok, species: species}
    end

    test "creates host_traits with WCVP and POWO IDs", %{species: species} do
      {:ok, traits} =
        Repo.insert(%HostTraits{
          species_id: species.id,
          wcvp_id: "12345",
          powo_id: "urn:lsid:ipni.org:names:12345-1"
        })

      assert traits.species_id == species.id
      assert traits.wcvp_id == "12345"
      assert traits.powo_id == "urn:lsid:ipni.org:names:12345-1"
    end

    test "creates host_traits with range_confirmed defaulting to false", %{species: species} do
      {:ok, traits} = Repo.insert(%HostTraits{species_id: species.id})
      assert traits.range_confirmed == false
      assert traits.wcvp_synced_at == nil
    end

    test "updates range_confirmed and wcvp_synced_at", %{species: species} do
      {:ok, traits} = Repo.insert(%HostTraits{species_id: species.id})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, updated} =
        traits
        |> HostTraits.changeset(%{range_confirmed: true, wcvp_synced_at: now})
        |> Repo.update()

      assert updated.range_confirmed == true
      assert updated.wcvp_synced_at == now
    end

    test "species can preload host_traits", %{species: species} do
      {:ok, _} =
        Repo.insert(%HostTraits{
          species_id: species.id,
          wcvp_id: "99999"
        })

      loaded = Repo.get!(Species, species.id) |> Repo.preload(:host_traits)
      assert loaded.host_traits.wcvp_id == "99999"
    end
  end

  describe "host_traits management" do
    setup do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "Testaceae HT Mgmt",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{name: "Testus HT Mgmt", type: "genus", parent_id: family.id})

      {:ok, species} =
        Repo.insert(%Species{name: "Testus htmgmt", taxoncode: "plant"})

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      {:ok, species: species}
    end

    test "upsert_host_traits/2 creates traits for a host", %{species: species} do
      {:ok, traits} =
        Plants.upsert_host_traits(species.id, %{wcvp_id: "12345", powo_id: "powo-12345"})

      assert traits.wcvp_id == "12345"
      assert traits.powo_id == "powo-12345"
    end

    test "upsert_host_traits/2 updates existing traits", %{species: species} do
      {:ok, _} = Plants.upsert_host_traits(species.id, %{wcvp_id: "12345"})
      {:ok, traits} = Plants.upsert_host_traits(species.id, %{wcvp_id: "99999"})

      assert traits.wcvp_id == "99999"
    end

    test "get_host_traits/1 returns traits or nil", %{species: species} do
      assert Plants.get_host_traits(species.id) == nil

      {:ok, _} = Plants.upsert_host_traits(species.id, %{wcvp_id: "12345"})
      traits = Plants.get_host_traits(species.id)

      assert traits.wcvp_id == "12345"
    end
  end

  describe "update_host_with_associations/2" do
    setup do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestUpdatePlantFamily",
          type: "family",
          description: "Plant"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "Testupdateplantgenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "Testupdateplantgenus oldhost",
          taxoncode: "plant",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      {:ok, species: species, family: family, genus: genus}
    end

    test "updates species and handles empty changes", %{species: species, genus: genus} do
      params = %{
        species_attrs: %{"datacomplete" => true},
        alias_changes: {[], []},
        place_changes: %{
          range_entries: %{},
          original_range_entries: %{},
          all_places: []
        },
        section_update: %{
          genus_id: genus.id,
          selected_section_id: nil,
          section_id: nil,
          family_id: nil
        }
      }

      assert {:ok, updated} = Plants.update_host_with_associations(species, params)
      assert updated.datacomplete == true
    end

    test "updates places when changed", %{species: species, genus: genus} do
      all_places = Gallformers.Places.list_places()
      assert all_places != [], "test seeds must include places"
      place = hd(all_places)

      params = %{
        species_attrs: %{},
        alias_changes: {[], []},
        place_changes: %{
          range_entries: %{
            place.code => %{precision: "exact", distribution_type: "native"}
          },
          original_range_entries: %{},
          all_places: all_places
        },
        section_update: %{
          genus_id: genus.id,
          selected_section_id: nil,
          section_id: nil,
          family_id: nil
        }
      }

      assert {:ok, _updated} = Plants.update_host_with_associations(species, params)

      places = Ranges.get_places_for_host(species.id)
      assert place.code in places
    end

    test "rolls back on invalid species update", %{species: species, genus: genus} do
      params = %{
        species_attrs: %{"name" => ""},
        alias_changes: {[], []},
        place_changes: %{
          range_entries: %{},
          original_range_entries: %{},
          all_places: []
        },
        section_update: %{
          genus_id: genus.id,
          selected_section_id: nil,
          section_id: nil,
          family_id: nil
        }
      }

      assert {:error, %Ecto.Changeset{}} =
               Plants.update_host_with_associations(species, params)
    end
  end

  describe "compute_powo_diff/3" do
    test "empty range with POWO data returns add_native and add_introduced" do
      range_entries = %{}
      native_codes = MapSet.new(["US-AL", "US-CA"])
      introduced_codes = MapSet.new(["CA-ON"])

      result = Plants.compute_powo_diff(range_entries, native_codes, introduced_codes)

      assert Enum.sort(result.add_native) == ["US-AL", "US-CA"]
      assert result.add_introduced == ["CA-ON"]
      assert result.remove == []
      assert result.reclassify_to_introduced == []
      assert result.reclassify_to_native == []
      assert result.agree_count == 0
      assert result.has_changes == true
    end

    test "exact match returns agree_count and no changes" do
      range_entries = %{
        "US-AL" => %{precision: "exact", distribution_type: "native"},
        "CA-ON" => %{precision: "exact", distribution_type: "introduced"}
      }

      native_codes = MapSet.new(["US-AL"])
      introduced_codes = MapSet.new(["CA-ON"])

      result = Plants.compute_powo_diff(range_entries, native_codes, introduced_codes)

      assert result.add_native == []
      assert result.add_introduced == []
      assert result.remove == []
      assert result.reclassify_to_introduced == []
      assert result.reclassify_to_native == []
      assert result.agree_count == 2
      assert result.has_changes == false
    end

    test "range has places POWO doesn't lists them in remove" do
      range_entries = %{
        "US-AL" => %{precision: "exact", distribution_type: "native"},
        "US-CA" => %{precision: "exact", distribution_type: "introduced"}
      }

      native_codes = MapSet.new()
      introduced_codes = MapSet.new()

      result = Plants.compute_powo_diff(range_entries, native_codes, introduced_codes)

      assert Enum.sort(result.remove) == ["US-AL", "US-CA"]
      assert result.add_native == []
      assert result.add_introduced == []
      assert result.agree_count == 0
      assert result.has_changes == true
    end

    test "range has native but POWO says introduced → reclassify_to_introduced" do
      range_entries = %{
        "US-AL" => %{precision: "exact", distribution_type: "native"}
      }

      native_codes = MapSet.new()
      introduced_codes = MapSet.new(["US-AL"])

      result = Plants.compute_powo_diff(range_entries, native_codes, introduced_codes)

      assert result.reclassify_to_introduced == ["US-AL"]
      assert result.reclassify_to_native == []
      assert result.remove == []
      assert result.agree_count == 0
      assert result.has_changes == true
    end

    test "range has introduced but POWO says native → reclassify_to_native" do
      range_entries = %{
        "US-AL" => %{precision: "exact", distribution_type: "introduced"}
      }

      native_codes = MapSet.new(["US-AL"])
      introduced_codes = MapSet.new()

      result = Plants.compute_powo_diff(range_entries, native_codes, introduced_codes)

      assert result.reclassify_to_native == ["US-AL"]
      assert result.reclassify_to_introduced == []
      assert result.remove == []
      assert result.agree_count == 0
      assert result.has_changes == true
    end

    test "mixed scenario distributes correctly across all buckets" do
      range_entries = %{
        "US-AL" => %{precision: "exact", distribution_type: "native"},
        "US-CA" => %{precision: "exact", distribution_type: "introduced"},
        "US-TX" => %{precision: "exact", distribution_type: "native"},
        "US-FL" => %{precision: "exact", distribution_type: "introduced"},
        "US-NY" => %{precision: "exact", distribution_type: "native"}
      }

      # US-AL: native in both → agree
      # US-CA: we have introduced, POWO says native → reclassify_to_native
      # US-TX: we have native, POWO says introduced → reclassify_to_introduced
      # US-FL: introduced in both → agree
      # US-NY: we have native, POWO doesn't list → remove
      # CA-ON: POWO says native, we don't have → add_native
      # CA-BC: POWO says introduced, we don't have → add_introduced
      native_codes = MapSet.new(["US-AL", "US-CA", "CA-ON"])
      introduced_codes = MapSet.new(["US-TX", "US-FL", "CA-BC"])

      result = Plants.compute_powo_diff(range_entries, native_codes, introduced_codes)

      assert result.add_native == ["CA-ON"]
      assert result.add_introduced == ["CA-BC"]
      assert result.remove == ["US-NY"]
      assert result.reclassify_to_introduced == ["US-TX"]
      assert result.reclassify_to_native == ["US-CA"]
      assert result.agree_count == 2
      assert result.has_changes == true

      # No place appears in multiple buckets
      all_changed =
        result.add_native ++
          result.add_introduced ++
          result.remove ++ result.reclassify_to_introduced ++ result.reclassify_to_native

      assert length(all_changed) == length(Enum.uniq(all_changed))
    end

    test "POWO data empty puts all current entries in remove" do
      range_entries = %{
        "US-AL" => %{precision: "exact", distribution_type: "native"},
        "US-CA" => %{precision: "exact", distribution_type: "introduced"}
      }

      native_codes = MapSet.new()
      introduced_codes = MapSet.new()

      result = Plants.compute_powo_diff(range_entries, native_codes, introduced_codes)

      assert Enum.sort(result.remove) == ["US-AL", "US-CA"]
      assert result.add_native == []
      assert result.add_introduced == []
      assert result.agree_count == 0
      assert result.has_changes == true
    end

    test "both empty returns no changes" do
      result = Plants.compute_powo_diff(%{}, MapSet.new(), MapSet.new())

      assert result.add_native == []
      assert result.add_introduced == []
      assert result.remove == []
      assert result.reclassify_to_introduced == []
      assert result.reclassify_to_native == []
      assert result.agree_count == 0
      assert result.has_changes == false
    end
  end
end
