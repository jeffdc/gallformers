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

      country_indices =
        groups
        |> Enum.with_index()
        |> Enum.filter(fn {g, _} -> g == "Countries" end)
        |> Enum.map(&elem(&1, 1))

      subdiv_indices =
        groups
        |> Enum.with_index()
        |> Enum.filter(fn {g, _} -> g == "States & Provinces" end)
        |> Enum.map(&elem(&1, 1))

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

  describe "get_place_by_code!/1" do
    test "returns place for valid code" do
      place = Places.get_place_by_code!("US-CA")
      assert place.name == "California"
      assert place.code == "US-CA"
    end

    test "raises for invalid code" do
      assert_raise Ecto.NoResultsError, fn ->
        Places.get_place_by_code!("XX-ZZ")
      end
    end
  end

  describe "get_ancestors/1" do
    test "returns ancestors from root to parent for a subdivision" do
      california = Places.get_place_by_code!("US-CA")
      ancestors = Places.get_ancestors(california.id)
      codes = Enum.map(ancestors, & &1.code)
      assert codes == ["WH", "NA", "US"]
    end

    test "returns ancestors for a country" do
      us = Places.get_place_by_code!("US")
      ancestors = Places.get_ancestors(us.id)
      codes = Enum.map(ancestors, & &1.code)
      assert codes == ["WH", "NA"]
    end

    test "returns empty list for the root" do
      wh = Places.get_place_by_code!("WH")
      assert Places.get_ancestors(wh.id) == []
    end
  end

  describe "get_children/1" do
    test "returns direct children of a country ordered by name" do
      us = Places.get_place_by_code!("US")
      children = Places.get_children(us.id)
      assert length(children) == 1
      assert hd(children).code == "US-CA"
    end

    test "returns empty list for leaf places" do
      california = Places.get_place_by_code!("US-CA")
      assert Places.get_children(california.id) == []
    end

    test "returns children of a continent" do
      na = Places.get_place_by_code!("NA")
      children = Places.get_children(na.id)
      codes = Enum.map(children, & &1.code) |> Enum.sort()
      assert codes == ["CA", "MX", "US"]
    end
  end

  describe "get_descendant_codes/1" do
    test "returns codes for all descendants of a country" do
      us = Places.get_place_by_code!("US")
      codes = Places.get_descendant_codes(us.id)
      assert "US" in codes
      assert "US-CA" in codes
    end

    test "returns just the place's own code for a leaf" do
      california = Places.get_place_by_code!("US-CA")
      assert Places.get_descendant_codes(california.id) == ["US-CA"]
    end

    test "returns full tree for a continent" do
      na = Places.get_place_by_code!("NA")
      codes = Places.get_descendant_codes(na.id)
      assert "NA" in codes
      assert "US" in codes
      assert "US-CA" in codes
      assert "CA" in codes
      assert "CA-AB" in codes
      assert "MX" in codes
      assert "MX-JAL" in codes
    end
  end

  describe "get_places_tree/0" do
    test "returns a nested tree rooted at Western Hemisphere" do
      tree = Places.get_places_tree()
      assert length(tree) == 1
      root = hd(tree)
      assert root.key == "p-WH"
      assert root.name == "Western Hemisphere"
      assert root.url == "/place/WH"
      assert is_list(root.nodes)
    end

    test "tree has correct continent children" do
      [root] = Places.get_places_tree()
      continent_keys = Enum.map(root.nodes, & &1.key) |> Enum.sort()
      assert "p-NA" in continent_keys
      assert "p-XB" in continent_keys
    end

    test "countries contain subdivisions" do
      [root] = Places.get_places_tree()
      na = Enum.find(root.nodes, &(&1.key == "p-NA"))
      us = Enum.find(na.nodes, &(&1.key == "p-US"))
      assert Enum.any?(us.nodes, &(&1.key == "p-US-CA"))
    end

    test "leaf countries have no nodes key" do
      [root] = Places.get_places_tree()
      caribbean = Enum.find(root.nodes, &(&1.key == "p-XB"))
      bahamas = Enum.find(caribbean.nodes, &(&1.key == "p-BS"))
      refute Map.has_key?(bahamas, :nodes)
    end
  end
end
