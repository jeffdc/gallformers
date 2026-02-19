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
end
