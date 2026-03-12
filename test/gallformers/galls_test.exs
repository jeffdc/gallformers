defmodule Gallformers.GallsTest do
  @moduledoc """
  Unit tests for the Galls context.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Galls
  alias Gallformers.Galls.GallTraits
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.{Genus, Lineage}

  describe "update_gall_properties/2 unknown genus floor" do
    setup do
      # Create a family with Unknown genus
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestUnknownFloorFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, unknown_genus} = Taxonomy.find_or_create_unknown_genus(family.id)

      # Create a gall species linked to the Unknown genus
      {:ok, species} =
        Repo.insert(%Species{
          name: "Unknown sp. floor test",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, unknown_genus.id)

      # Create gall_traits
      {:ok, _gall_traits} =
        Repo.insert(%GallTraits{
          species_id: species.id,
          undescribed: true,
          detachable: "unknown"
        })

      {:ok, species: species, family: family, unknown_genus: unknown_genus}
    end

    test "silently corrects undescribed=false to true for Unknown genus", %{species: species} do
      # Try to set undescribed to false on a species with Unknown genus
      {:ok, result} = Galls.update_gall_properties(species.id, %{undescribed: false})

      # Should be silently corrected to true
      assert result.undescribed == true
    end

    test "allows undescribed=true for Unknown genus", %{species: species} do
      {:ok, result} = Galls.update_gall_properties(species.id, %{undescribed: true})
      assert result.undescribed == true
    end

    test "allows undescribed=false for real genus" do
      # Create a family and real genus
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestRealGenusFamily",
          type: "family",
          description: "Midge"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "Realgenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "Realgenus species1",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      {:ok, _gall_traits} =
        Repo.insert(%GallTraits{
          species_id: species.id,
          undescribed: true,
          detachable: "unknown"
        })

      # Should allow setting undescribed to false for real genus
      {:ok, result} = Galls.update_gall_properties(species.id, %{undescribed: false})
      assert result.undescribed == false
    end

    test "works with string keys in attrs", %{species: species} do
      {:ok, result} = Galls.update_gall_properties(species.id, %{"undescribed" => false})
      assert result.undescribed == true
    end

    test "rejects duplicate gallformers_code" do
      {:ok, species1} =
        Repo.insert(%Species{name: "Dupecode sp1", taxoncode: "gall", datacomplete: false})

      {:ok, species2} =
        Repo.insert(%Species{name: "Dupecode sp2", taxoncode: "gall", datacomplete: false})

      {:ok, _} = Galls.create_gall_traits(species1.id)
      {:ok, _} = Galls.create_gall_traits(species2.id)

      {:ok, _} = Galls.update_gall_properties(species1.id, %{gallformers_code: "dupe-code"})

      {:error, changeset} =
        Galls.update_gall_properties(species2.id, %{gallformers_code: "dupe-code"})

      assert errors_on(changeset).gallformers_code
    end
  end

  describe "create_gall_with_associations/1" do
    setup do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestCreateFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "Testcreategenus",
          type: "genus",
          parent_id: family.id
        })

      # Create a host species to link to
      {:ok, host} =
        Repo.insert(%Species{
          name: "Quercus testhost",
          taxoncode: "plant",
          datacomplete: false
        })

      {:ok, family: family, genus: genus, host: host}
    end

    test "creates gall with all associations", %{genus: genus, host: host} do
      params = %{
        species_attrs: %{
          "name" => "Testcreategenus newgall leaf gall",
          "taxoncode" => "gall",
          "datacomplete" => false
        },
        taxonomy: %Lineage{genus: %Genus{id: genus.id, name: genus.name}},
        genus_is_new: false,
        parent_id: nil,
        hosts: [%{host_species_id: host.id}],
        aliases: [%{name: "Test alias", type: "common"}],
        filter_values: %{
          colors: [],
          shapes: [],
          textures: [],
          alignments: [],
          walls: [],
          cells: [],
          plant_parts: [],
          forms: [],
          seasons: []
        },
        detachable: "detachable",
        undescribed: false
      }

      assert {:ok, species} = Galls.create_gall_with_associations(params)
      assert species.name == "Testcreategenus newgall leaf gall"
      assert species.taxoncode == "gall"

      # Verify gall_traits was created
      gall = Galls.get_gall(species.id)
      assert gall != nil
      assert gall.detachable == "detachable"

      # Verify host was linked
      hosts = Gallformers.GallHosts.get_hosts_for_gall(species.id)
      assert length(hosts) == 1

      # Verify alias was created
      aliases = Gallformers.Species.get_aliases_for_species(species.id)
      assert length(aliases) == 1
      assert hd(aliases).name == "Test alias"

      # Verify taxonomy was linked
      taxonomy = Taxonomy.get_taxonomy_for_species(species.id)
      assert taxonomy != nil
      assert taxonomy.genus.id == genus.id
    end

    test "rolls back on invalid species attrs" do
      params = %{
        species_attrs: %{"taxoncode" => "gall"},
        taxonomy: %Lineage{genus: %Genus{name: "Whatever"}},
        genus_is_new: false,
        parent_id: nil,
        hosts: [],
        aliases: [],
        filter_values: %{
          colors: [],
          shapes: [],
          textures: [],
          alignments: [],
          walls: [],
          cells: [],
          plant_parts: [],
          forms: [],
          seasons: []
        },
        detachable: "unknown",
        undescribed: false
      }

      assert {:error, %Ecto.Changeset{}} = Galls.create_gall_with_associations(params)
    end
  end

  describe "update_gall_with_associations/2" do
    setup do
      {:ok, family} =
        Taxonomy.create_taxonomy(%{
          name: "TestUpdateFamily",
          type: "family",
          description: "Wasp"
        })

      {:ok, genus} =
        Taxonomy.create_taxonomy(%{
          name: "Testupdategenus",
          type: "genus",
          parent_id: family.id
        })

      {:ok, species} =
        Repo.insert(%Species{
          name: "Testupdategenus oldname gall",
          taxoncode: "gall",
          datacomplete: false
        })

      Taxonomy.link_species_to_taxonomy(species.id, genus.id)

      {:ok, _gall_traits} =
        Repo.insert(%GallTraits{
          species_id: species.id,
          undescribed: true,
          detachable: "unknown"
        })

      {:ok, species: species, family: family, genus: genus}
    end

    test "updates species and gall properties", %{species: species} do
      params = %{
        species_attrs: %{"datacomplete" => true},
        alias_changes: {[], []},
        host_changes: {[], []},
        original_filter_values: %{
          colors: [],
          shapes: [],
          textures: [],
          alignments: [],
          walls: [],
          cells: [],
          plant_parts: [],
          forms: [],
          seasons: []
        },
        filter_values: %{
          colors: [],
          shapes: [],
          textures: [],
          alignments: [],
          walls: [],
          cells: [],
          plant_parts: [],
          forms: [],
          seasons: []
        },
        detachable: "integral",
        undescribed: false
      }

      assert {:ok, updated} = Galls.update_gall_with_associations(species, params)
      assert updated.datacomplete == true

      gall = Galls.get_gall(species.id)
      assert gall.detachable == "integral"
    end

    test "rolls back on invalid species update", %{species: species} do
      params = %{
        species_attrs: %{"name" => ""},
        alias_changes: {[], []},
        host_changes: {[], []},
        original_filter_values: %{
          colors: [],
          shapes: [],
          textures: [],
          alignments: [],
          walls: [],
          cells: [],
          plant_parts: [],
          forms: [],
          seasons: []
        },
        filter_values: %{
          colors: [],
          shapes: [],
          textures: [],
          alignments: [],
          walls: [],
          cells: [],
          plant_parts: [],
          forms: [],
          seasons: []
        },
        detachable: "unknown",
        undescribed: false
      }

      assert {:error, %Ecto.Changeset{}} = Galls.update_gall_with_associations(species, params)
    end
  end

  describe "sync_filter_values/3" do
    setup do
      {:ok, species} =
        Repo.insert(%Species{
          name: "Filtertest gall",
          taxoncode: "gall",
          datacomplete: false
        })

      {:ok, _gall_traits} =
        Repo.insert(%GallTraits{
          species_id: species.id,
          undescribed: false,
          detachable: "unknown"
        })

      {:ok, species: species}
    end

    test "adds new filter values from empty", %{species: species} do
      # Insert a color for testing
      {:ok, color} =
        Repo.insert(%Gallformers.FilterFields.Color{color: "test-red"})

      empty = %{
        colors: [],
        shapes: [],
        textures: [],
        alignments: [],
        walls: [],
        cells: [],
        plant_parts: [],
        forms: [],
        seasons: []
      }

      current = %{empty | colors: [%{id: color.id, field: color.color}]}

      assert :ok = Galls.sync_filter_values(species.id, empty, current)

      filter_values = Galls.get_gall_filter_values(species.id)
      assert length(filter_values.colors) == 1
      assert hd(filter_values.colors).id == color.id
    end
  end

  describe "compute_undescribed_lock/2" do
    test "locked when genus is placeholder" do
      taxonomy = %Lineage{genus: %Genus{name: "Unknown (TestFamily)"}}
      {true, reason} = Galls.compute_undescribed_lock(taxonomy)
      assert reason =~ "unknown genus"
    end

    test "locked when genus is bare Unknown" do
      taxonomy = %Lineage{genus: %Genus{name: "Unknown"}}
      {true, reason} = Galls.compute_undescribed_lock(taxonomy)
      assert reason =~ "unknown genus"
    end

    test "unlocked for real genus with no species_id" do
      taxonomy = %Lineage{genus: %Genus{name: "Andricus"}}
      assert {false, nil} = Galls.compute_undescribed_lock(taxonomy)
    end

    test "unlocked when species has no sources but real genus" do
      {:ok, species} =
        Repo.insert(%Species{
          name: "Locktest sp",
          taxoncode: "gall",
          datacomplete: false
        })

      taxonomy = %Lineage{genus: %Genus{name: "Locktest"}}
      assert {false, nil} = Galls.compute_undescribed_lock(taxonomy, species.id)
    end

    test "unlocked when species has sources" do
      {:ok, species} =
        Repo.insert(%Species{
          name: "Sourced sp",
          taxoncode: "gall",
          datacomplete: false
        })

      # Add a source
      {:ok, source} =
        Gallformers.Sources.create_source(%{
          title: "Test Source",
          author: "Author",
          pubyear: "2020",
          link: "http://example.com",
          citation: "Test citation",
          license: "CC BY"
        })

      Gallformers.Sources.create_species_source(%{
        species_id: species.id,
        source_id: source.id
      })

      taxonomy = %Lineage{genus: %Genus{name: "Sourced"}}
      assert {false, nil} = Galls.compute_undescribed_lock(taxonomy, species.id)
    end

    test "returns unlocked for nil taxonomy" do
      assert {false, nil} = Galls.compute_undescribed_lock(nil)
    end
  end

  describe "compute_datacomplete_lock/1" do
    test "locked when species has no sources" do
      {:ok, species} =
        Repo.insert(%Species{
          name: "Nolock sp",
          taxoncode: "gall",
          datacomplete: false
        })

      {true, reason} = Galls.compute_datacomplete_lock(species.id)
      assert reason =~ "source is required"
    end

    test "locked when species is undescribed" do
      {:ok, species} =
        Repo.insert(%Species{
          name: "Undesc sp",
          taxoncode: "gall",
          datacomplete: false
        })

      {:ok, _} = Galls.create_gall_traits(species.id)
      Galls.update_gall_properties(species.id, %{undescribed: true})

      # Add a source so we isolate the undescribed check
      {:ok, source} =
        Gallformers.Sources.create_source(%{
          title: "Test Source",
          author: "Author",
          pubyear: "2020",
          link: "http://example.com",
          citation: "Test citation",
          license: "CC BY"
        })

      Gallformers.Sources.create_species_source(%{
        species_id: species.id,
        source_id: source.id
      })

      {true, reason} = Galls.compute_datacomplete_lock(species.id)
      assert reason =~ "undescribed"
    end

    test "unlocked when species has sources and is described" do
      {:ok, species} =
        Repo.insert(%Species{
          name: "Haslock sp",
          taxoncode: "gall",
          datacomplete: false
        })

      {:ok, source} =
        Gallformers.Sources.create_source(%{
          title: "Test Source",
          author: "Author",
          pubyear: "2020",
          link: "http://example.com",
          citation: "Test citation",
          license: "CC BY"
        })

      Gallformers.Sources.create_species_source(%{
        species_id: species.id,
        source_id: source.id
      })

      assert {false, nil} = Galls.compute_datacomplete_lock(species.id)
    end

    test "unlocked for nil species_id" do
      assert {false, nil} = Galls.compute_datacomplete_lock(nil)
    end
  end

  describe "get_gall_traits/1" do
    test "returns gall_traits for a valid species" do
      # Gall 100 exists in test seeds
      traits = Galls.get_gall_traits(100)
      assert %GallTraits{} = traits
      assert traits.species_id == 100
    end

    test "returns nil for non-existent species" do
      assert Galls.get_gall_traits(999_999) == nil
    end
  end

  describe "confirm_gall_range/1" do
    test "sets range_confirmed and range_computed_at" do
      # Gall 100 starts with range_confirmed = false
      traits_before = Galls.get_gall_traits(100)
      refute traits_before.range_confirmed

      Galls.confirm_gall_range(100)

      traits_after = Galls.get_gall_traits(100)
      assert traits_after.range_confirmed == true
      assert traits_after.range_computed_at != nil
    end
  end

  describe "list_galls_for_range_review/1" do
    test "returns unconfirmed galls by default" do
      results = Galls.list_galls_for_range_review()

      # All seed galls start unconfirmed
      assert length(results) > 0
      assert Enum.all?(results, fn g -> g.range_confirmed == false end)
    end

    test "includes host_count and range_count" do
      results = Galls.list_galls_for_range_review()
      gall = Enum.find(results, &(&1.id == 100))

      assert is_integer(gall.host_count)
      assert is_integer(gall.range_count)
    end

    test "excludes confirmed galls when unconfirmed_only is true" do
      Galls.confirm_gall_range(100)

      results = Galls.list_galls_for_range_review(unconfirmed_only: true)
      refute Enum.any?(results, &(&1.id == 100))
    end

    test "includes confirmed galls when unconfirmed_only is false" do
      Galls.confirm_gall_range(100)

      results = Galls.list_galls_for_range_review(unconfirmed_only: false)
      gall = Enum.find(results, &(&1.id == 100))

      assert gall != nil
      assert gall.range_confirmed == true
    end
  end

  describe "bulk_confirm_gall_ranges/1" do
    test "confirms multiple galls at once" do
      {count, _} = Galls.bulk_confirm_gall_ranges([100, 101])
      assert count == 2

      assert Galls.get_gall_traits(100).range_confirmed == true
      assert Galls.get_gall_traits(101).range_confirmed == true
    end

    test "returns zero for empty list" do
      assert {0, nil} = Galls.bulk_confirm_gall_ranges([])
    end

    test "sets range_computed_at" do
      Galls.bulk_confirm_gall_ranges([100])
      traits = Galls.get_gall_traits(100)
      assert traits.range_computed_at != nil
    end
  end
end
