defmodule Gallformers.GallsTest do
  @moduledoc """
  Unit tests for the Galls context.
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.Galls
  alias Gallformers.Galls.GallTraits
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy

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
  end
end
