defmodule Gallformers.PlantsTest do
  @moduledoc """
  Unit tests for the Plants context.
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.Plants
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
          original_places: [],
          current_places: [],
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
          original_places: [],
          current_places: [place.code],
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
          original_places: [],
          current_places: [],
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
end
