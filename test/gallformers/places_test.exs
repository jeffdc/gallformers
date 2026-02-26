defmodule Gallformers.PlacesTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.Places

  describe "list_continents/0" do
    test "returns all continents ordered alphabetically" do
      continents = Places.list_continents()
      assert length(continents) == 3
      assert Enum.all?(continents, &(&1.type == "continent"))
      names = Enum.map(continents, & &1.name)
      assert names == Enum.sort(names)
    end

    test "includes expected continent codes" do
      codes = Places.list_continents() |> Enum.map(& &1.code) |> MapSet.new()
      assert MapSet.member?(codes, "XN")
      assert MapSet.member?(codes, "XB")
      assert MapSet.member?(codes, "XE")
    end
  end

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
      xn = Places.get_place_by_code("XN")
      assert california.id in ids
      assert us.id in ids
      assert xn.id in ids
    end

    test "ancestor_ids/1 for a continent returns just itself" do
      xn = Places.get_place_by_code("XN")
      assert Places.ancestor_ids(xn.id) == [xn.id]
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

  describe "search_places_grouped/3 with continent scope" do
    test "scoped to North America returns California" do
      results = Places.search_places_grouped("Cal", 10, "XN")
      codes = Enum.map(results, & &1.code)
      assert "US-CA" in codes
    end

    test "scoped to North America excludes European places" do
      results = Places.search_places_grouped("Buch", 10, "XN")
      codes = Enum.map(results, & &1.code)
      refute "RO-B" in codes
    end

    test "scoped to Europe returns Bucharest" do
      results = Places.search_places_grouped("Buch", 10, "XE")
      codes = Enum.map(results, & &1.code)
      assert "RO-B" in codes
    end

    test "nil continent returns all places (no filtering)" do
      results = Places.search_places_grouped("Ca", 10, nil)
      codes = Enum.map(results, & &1.code)
      # Should include both North American and other places
      assert "CA" in codes or "US-CA" in codes
    end

    test "invalid continent code returns all places" do
      results = Places.search_places_grouped("Ca", 10, "INVALID")
      assert length(results) > 0
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
      assert codes == ["XN", "US"]
    end

    test "returns ancestors for a country" do
      us = Places.get_place_by_code!("US")
      ancestors = Places.get_ancestors(us.id)
      codes = Enum.map(ancestors, & &1.code)
      assert codes == ["XN"]
    end

    test "returns empty list for a continent" do
      xn = Places.get_place_by_code!("XN")
      assert Places.get_ancestors(xn.id) == []
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
      xn = Places.get_place_by_code!("XN")
      children = Places.get_children(xn.id)
      codes = Enum.map(children, & &1.code) |> Enum.sort()
      assert codes == ["CA", "MX", "US"]
    end
  end

  describe "get_descendant_codes/1" do
    test "returns codes for all descendants of a country" do
      us = Places.get_place_by_code("US")
      codes = Places.get_descendant_codes(us.id)
      assert "US" in codes
      assert "US-CA" in codes
    end

    test "returns just the place's own code for a leaf" do
      california = Places.get_place_by_code("US-CA")
      assert Places.get_descendant_codes(california.id) == ["US-CA"]
    end

    test "returns full tree for a continent" do
      xn = Places.get_place_by_code("XN")
      codes = Places.get_descendant_codes(xn.id)
      assert "XN" in codes
      assert "US" in codes
      assert "US-CA" in codes
      assert "CA" in codes
      assert "CA-AB" in codes
      assert "MX" in codes
      assert "MX-JAL" in codes
    end
  end

  describe "get_places_tree/0" do
    test "returns a tree with continent roots" do
      tree = Places.get_places_tree()
      # Should have multiple continent roots (XN, XB, XE in test data)
      assert length(tree) >= 3
      keys = Enum.map(tree, & &1.key)
      assert "p-XN" in keys
      assert "p-XB" in keys
      assert "p-XE" in keys
    end

    test "continents contain countries" do
      tree = Places.get_places_tree()
      xn = Enum.find(tree, &(&1.key == "p-XN"))
      country_keys = Enum.map(xn.nodes, & &1.key)
      assert "p-US" in country_keys
      assert "p-CA" in country_keys
    end

    test "countries contain subdivisions" do
      tree = Places.get_places_tree()
      xn = Enum.find(tree, &(&1.key == "p-XN"))
      us = Enum.find(xn.nodes, &(&1.key == "p-US"))
      assert Enum.any?(us.nodes, &(&1.key == "p-US-CA"))
    end

    test "leaf countries have no nodes key" do
      tree = Places.get_places_tree()
      caribbean = Enum.find(tree, &(&1.key == "p-XB"))
      bahamas = Enum.find(caribbean.nodes, &(&1.key == "p-BS"))
      refute Map.has_key?(bahamas, :nodes)
    end
  end
end
