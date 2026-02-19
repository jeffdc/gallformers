defmodule Gallformers.PlacesTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.Places

  describe "hierarchy traversal" do
    test "descendant_ids/1 returns the place and all children recursively" do
      us = Places.get_place_by_code("US")
      ids = Places.descendant_ids(us.id)
      california = Places.get_place_by_code("US-CA")
      assert us.id in ids
      assert california.id in ids
    end

    test "descendant_ids/1 for a leaf place returns just itself" do
      california = Places.get_place_by_code("US-CA")
      assert Places.descendant_ids(california.id) == [california.id]
    end

    test "ancestor_ids/1 returns the place and all parents recursively" do
      california = Places.get_place_by_code("US-CA")
      ids = Places.ancestor_ids(california.id)
      us = Places.get_place_by_code("US")
      na = Places.get_place_by_code("NA")
      wh = Places.get_place_by_code("WH")
      assert california.id in ids
      assert us.id in ids
      assert na.id in ids
      assert wh.id in ids
    end

    test "ancestor_ids/1 for the root returns just itself" do
      wh = Places.get_place_by_code("WH")
      assert Places.ancestor_ids(wh.id) == [wh.id]
    end

    test "leaf_descendant_ids/1 returns only leaf nodes" do
      us = Places.get_place_by_code("US")
      ids = Places.leaf_descendant_ids(us.id)
      california = Places.get_place_by_code("US-CA")
      # California is a leaf, US is not
      assert california.id in ids
      refute us.id in ids
    end

    test "leaf_descendant_ids/1 for a leaf country returns itself" do
      bahamas = Places.get_place_by_code("BS")
      assert Places.leaf_descendant_ids(bahamas.id) == [bahamas.id]
    end
  end

  describe "search_places_grouped/2" do
    test "returns countries and subdivisions, not continents or regions" do
      results = Places.search_places_grouped("a", 50)
      types = Enum.map(results, & &1.type)
      refute "continent" in types
      refute "region" in types
    end

    test "includes group field for typeahead grouping" do
      results = Places.search_places_grouped("ca", 10)
      assert Enum.all?(results, &Map.has_key?(&1, :group))
      groups = Enum.map(results, & &1.group) |> Enum.uniq()
      assert Enum.all?(groups, &(&1 in ["Countries", "States & Provinces"]))
    end

    test "includes parent_name for context display" do
      results = Places.search_places_grouped("california", 10)
      california = Enum.find(results, &(&1.code == "US-CA"))
      assert california.parent_name == "United States"
    end

    test "countries sort before subdivisions" do
      results = Places.search_places_grouped("ca", 10)
      groups = Enum.map(results, & &1.group)
      country_indices = groups |> Enum.with_index() |> Enum.filter(fn {g, _} -> g == "Countries" end) |> Enum.map(&elem(&1, 1))
      subdiv_indices = groups |> Enum.with_index() |> Enum.filter(fn {g, _} -> g == "States & Provinces" end) |> Enum.map(&elem(&1, 1))

      if country_indices != [] and subdiv_indices != [] do
        assert Enum.max(country_indices) < Enum.min(subdiv_indices)
      end
    end

    test "leaf countries appear in Countries group" do
      results = Places.search_places_grouped("bahamas", 10)
      bahamas = Enum.find(results, &(&1.code == "BS"))
      assert bahamas.group == "Countries"
    end
  end
end
