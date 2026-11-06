defmodule GallformersWeb.BrowseHelpersTest do
  use ExUnit.Case, async: true

  alias GallformersWeb.BrowseHelpers

  describe "toggle_set/2" do
    test "adds key when absent" do
      set = MapSet.new(["a", "b"])
      assert BrowseHelpers.toggle_set(set, "c") == MapSet.new(["a", "b", "c"])
    end

    test "removes key when present" do
      set = MapSet.new(["a", "b", "c"])
      assert BrowseHelpers.toggle_set(set, "b") == MapSet.new(["a", "c"])
    end

    test "works with empty set" do
      set = MapSet.new()
      assert BrowseHelpers.toggle_set(set, "x") == MapSet.new(["x"])
    end
  end

  # A browse tree in `Gallformers.Taxa.TreeBuilder`'s shape.
  defp tree do
    [
      %{
        key: "f-1",
        name: "Cynipidae",
        label: "Cynipidae (Gall wasps)",
        description: "Gall wasps",
        url: "/family/Cynipidae",
        nodes: [
          %{
            key: "g-10",
            name: "Cynips",
            label: "Cynips",
            description: nil,
            url: "/genus/Cynips",
            nodes: [%{key: "s-100", label: "Cynips quercusfolii", url: "/gall/100"}]
          },
          %{
            key: "g-11",
            name: "Andricus",
            label: "Andricus",
            description: nil,
            url: "/genus/Andricus",
            nodes: [
              %{key: "s-101", label: "Andricus seedii (agamic)", url: "/gall/101"},
              %{key: "s-102", label: "Andricus kingi", url: "/gall/102"}
            ]
          }
        ]
      },
      %{
        key: "f-2",
        name: "Cecidomyiidae",
        label: "Cecidomyiidae",
        description: nil,
        url: "/family/Cecidomyiidae",
        nodes: [
          %{
            key: "g-20",
            name: "Rabdophaga",
            label: "Rabdophaga",
            description: nil,
            url: "/genus/Rabdophaga",
            nodes: [%{key: "s-200", label: "Rabdophaga strobilina", url: "/gall/200"}]
          }
        ]
      }
    ]
  end

  describe "family_cards/2" do
    test "counted by leaves: genera most first, photo from the first Gall that has one" do
      [cynipidae, cecidomyiidae] =
        BrowseHelpers.family_cards(tree(), {:leaves, %{102 => "/k.jpg"}})

      assert %{key: "f-1", name: "Cynipidae", description: "Gall wasps", count: 3} = cynipidae
      assert cynipidae.image_url == "/k.jpg"

      assert [%{name: "Andricus", count: 2, key: "g-11"}, %{name: "Cynips", count: 1}] =
               cynipidae.genera

      assert [%{label: "Andricus seedii (agamic)", url: "/gall/101"} | _] =
               hd(cynipidae.genera).leaves

      assert %{count: 1, image_url: nil} = cecidomyiidae
    end

    test "counted by taxon: families and genera most galled first, then by name" do
      counts = %{2 => %{count: 9, image_url: "/r.jpg"}, 20 => %{count: 9, image_url: "/r.jpg"}}

      assert [%{name: "Cecidomyiidae", count: 9, image_url: "/r.jpg"}, cynipidae] =
               BrowseHelpers.family_cards(tree(), {:taxa, counts})

      assert %{count: 0, image_url: nil} = cynipidae
      assert [%{name: "Andricus", count: 0}, %{name: "Cynips", count: 0}] = cynipidae.genera
    end
  end

  describe "filter_tree/2" do
    test "a family or genus whose own name matches keeps everything under it" do
      assert [%{key: "f-1", nodes: [_, _]}] = BrowseHelpers.filter_tree(tree(), "cynipidae")

      assert [%{nodes: [%{key: "g-11", nodes: [_, _]}]}] =
               BrowseHelpers.filter_tree(tree(), "andricus")
    end

    test "otherwise the matches and their ancestors" do
      assert [%{nodes: [%{nodes: [%{key: "s-102"}]}]}] =
               BrowseHelpers.filter_tree(tree(), "kingi")

      assert BrowseHelpers.filter_tree(tree(), "") == tree()
      assert BrowseHelpers.filter_tree(tree(), "xyzzy") == []
    end
  end
end
