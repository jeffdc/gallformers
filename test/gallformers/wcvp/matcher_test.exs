defmodule Gallformers.Wcvp.MatcherTest do
  use ExUnit.Case, async: true

  alias Gallformers.Wcvp.Matcher
  alias Gallformers.Wcvp.Reader.Name

  # Simulated WCVP accepted names index (canonical name -> Name struct)
  @accepted_by_name %{
    "Quercus alba" => %Name{
      plant_name_id: "1",
      taxon_name: "Quercus alba",
      family: "Fagaceae",
      genus: "Quercus",
      species: "alba",
      taxon_status: "Accepted"
    },
    "Quercus rubra" => %Name{
      plant_name_id: "3",
      taxon_name: "Quercus rubra",
      family: "Fagaceae",
      genus: "Quercus",
      species: "rubra",
      taxon_status: "Accepted"
    },
    "Rosa canina" => %Name{
      plant_name_id: "10",
      taxon_name: "Rosa canina",
      family: "Rosaceae",
      genus: "Rosa",
      species: "canina",
      taxon_status: "Accepted"
    }
  }

  # Simulated synonym index (synonym canonical -> accepted plant_name_id)
  @synonym_index %{
    "Quercus stellata" => "3"
  }

  # Accepted names by ID (for synonym resolution)
  @accepted_by_id %{
    "1" => @accepted_by_name["Quercus alba"],
    "3" => @accepted_by_name["Quercus rubra"],
    "10" => @accepted_by_name["Rosa canina"]
  }

  describe "match_name/4 — Pass 1 exact" do
    test "exact match returns {:exact, wcvp_name}" do
      assert {:exact, name} =
               Matcher.match_name(
                 "Quercus alba",
                 @accepted_by_name,
                 @synonym_index,
                 @accepted_by_id
               )

      assert name.taxon_name == "Quercus alba"
    end
  end

  describe "match_name/4 — Pass 2 fuzzy" do
    test "no match for unrelated name returns :no_match" do
      assert {:no_match, _} =
               Matcher.match_name(
                 "Quercus bogusii",
                 @accepted_by_name,
                 @synonym_index,
                 @accepted_by_id
               )
    end
  end

  describe "match_name/4 — Pass 3 synonym" do
    test "synonym match returns {:synonym, accepted_name}" do
      assert {:synonym, accepted} =
               Matcher.match_name(
                 "Quercus stellata",
                 @accepted_by_name,
                 @synonym_index,
                 @accepted_by_id
               )

      assert accepted.taxon_name == "Quercus rubra"
    end
  end

  describe "match_name/4 — no match" do
    test "returns :no_match for unknown species" do
      assert {:no_match, closest} =
               Matcher.match_name(
                 "Fictus plantus",
                 @accepted_by_name,
                 @synonym_index,
                 @accepted_by_id
               )

      # closest may be nil or a near miss
      assert is_nil(closest) or is_struct(closest, Name)
    end
  end

  describe "normalize_epithet/1" do
    test "normalizes common Latin endings" do
      assert Matcher.normalize_epithet("wallichii") == Matcher.normalize_epithet("wallichianus")
      assert Matcher.normalize_epithet("canadensis") == Matcher.normalize_epithet("canadense")
    end
  end
end
