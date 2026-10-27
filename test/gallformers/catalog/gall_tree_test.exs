defmodule Gallformers.Catalog.GallTreeTest do
  @moduledoc """
  The Gall reads behind the rank pages and the Galls browse tree (`803b`
  Task 6): `Gallformers.Catalog.gall_tree/0`, `undescribed_gall_tree/0`,
  Galls by Inducer and by Host, their counts, and the related genera of
  the genus page's filters.

  Mostly the converted seeds (`priv/repo/test_seeds.sql`): in Cynipidae >
  Cynipinae > Cynipini, Andricus holds Andricus crystallinus (Gall 200),
  Andricus seedii (the generation pair 300/301) and the undescribed Gall
  304 linked at the genus; Cynips quercus (201); Neuroterus seedatorius
  (302/303). Plant 10 hosts 300–304; 304 is also on the genus
  Notholithocarpus. Galls 100–103 have no Inducer.
  """
  use Gallformers.DataCase, async: true

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Taxa

  defp old(id), do: Taxa.get_by_legacy_id(:taxonomy, id)

  defp relate!(type, taxon, gall) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: type, subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source_fixture("Weld", "1959"))
      )

    :ok
  end

  defp family_node(tree, name), do: Enum.find(tree, &(&1.name == name))
  defp genus_node(family, name), do: Enum.find(family.nodes, &(&1.name == name))
  defp leaves(genus), do: Enum.map(genus.nodes, & &1.label)

  describe "gall_tree/0" do
    test "is Inducer family > genus > Galls by name, each Gall once" do
      tree = Catalog.gall_tree()
      cynipidae = family_node(tree, "Cynipidae")

      assert cynipidae.key == "f-#{old(30).id}"
      assert cynipidae.url == "/family/Cynipidae"
      assert Enum.map(cynipidae.nodes, & &1.name) == ["Andricus", "Cynips", "Neuroterus"]

      andricus = genus_node(cynipidae, "Andricus")
      assert andricus.key == "g-#{old(33).id}"
      assert andricus.url == "/genus/Andricus"

      assert leaves(andricus) == [
               "Andricus crystallinus",
               "Andricus n-densiflorus-seed-gall",
               "Andricus seedii (agamic)",
               "Andricus seedii (sexgen)"
             ]

      assert %{key: "s-300", url: "/gall/300", genus_placeholder: false} =
               Enum.find(andricus.nodes, &(&1.label == "Andricus seedii (agamic)"))

      assert leaves(genus_node(cynipidae, "Neuroterus")) == [
               "Neuroterus seedatorius (australis) (agamic)",
               "Neuroterus seedatorius (sexgen)"
             ]
    end

    test "leaves out Galls without an Inducer and plant families" do
      labels = for f <- Catalog.gall_tree(), g <- f.nodes, l <- g.nodes, do: l.label

      refute "Andricus quercuscalifornicus" in labels
      refute Enum.any?(Catalog.gall_tree(), &(&1.name == "Fagaceae"))
    end

    test "a Gall placed above genus sits in an Unknown genus linking to its Inducer's page" do
      cynipini = Taxa.get_taxon!(old(32).id)
      gall = gall_fixture(name: "Unknown (Cynipini) q-tree-fixture")
      relate!("inducer_of", cynipini, gall)

      cynipidae = family_node(Catalog.gall_tree(), "Cynipidae")
      unknown = genus_node(cynipidae, "Unknown (Cynipini)")

      assert unknown.url == "/tribe/Cynipini"
      assert unknown.key == "g-#{cynipini.id}"
      assert leaves(unknown) == ["Unknown (Cynipini) q-tree-fixture"]
    end

    test "a gall-forming plant's Galls sit under its family and genus" do
      family = plant_fixture(name: "Fixtursantalaceae", rank: :family)
      genus = plant_fixture(name: "Fixturphoradendron", rank: :genus, parent: family)
      mistletoe = plant_fixture(name: "Fixturphoradendron leucarpum", parent: genus)
      gall = gall_fixture(name: "Fixturphoradendron leucarpum gall")
      relate!("inducer_of", mistletoe, gall)

      genus_node =
        Catalog.gall_tree()
        |> family_node("Fixtursantalaceae")
        |> genus_node("Fixturphoradendron")

      assert leaves(genus_node) == ["Fixturphoradendron leucarpum gall"]
    end
  end

  test "undescribed_gall_tree/0 holds the Galls whose Inducer is above species" do
    andricus = family_node(Catalog.undescribed_gall_tree(), "Cynipidae") |> genus_node("Andricus")

    assert leaves(andricus) == ["Andricus n-densiflorus-seed-gall"]
    assert genus_node(family_node(Catalog.undescribed_gall_tree(), "Cynipidae"), "Cynips") == nil
  end

  test "count_galls_under/1: Galls whose Inducer is in each subtree" do
    ids = Enum.map([30, 33, 36, 40], &old(&1).id)
    [cynipidae, andricus, neuroterus, fagaceae] = ids

    assert Catalog.count_galls_under(ids) ==
             %{cynipidae => 7, andricus => 4, neuroterus => 2, fagaceae => 0}

    assert Catalog.count_galls_under([]) == %{}
  end

  test "list_galls_for_inducers/1: the Galls of those Inducers, as cards by name" do
    andricus = old(33).id
    ids = Taxa.subtree_ids([andricus])[andricus]

    assert Enum.map(Catalog.list_galls_for_inducers(ids), & &1.id) == [200, 304, 300, 301]

    assert %{id: 300, name: "Andricus seedii (agamic)", datacomplete: true} in Catalog.list_galls_for_inducers(
             ids
           )

    assert Catalog.list_galls_for_inducers([]) == []
  end

  test "add_gall_details/1: each card's first common name and Host count" do
    cards = Catalog.list_galls_for_inducers([old(33).id])

    assert [%{id: 304, common_name: nil, host_count: 2}] = Catalog.add_gall_details(cards)

    [card] =
      Catalog.add_gall_details(Enum.filter(Catalog.list_galls_for_hosts([10]), &(&1.id == 300)))

    assert {card.common_name, card.host_count} == {"seed oak apple", 1}
  end

  test "count_galls_for_hosts/1: Galls with a current Host Fact on each taxon" do
    genus = old(41).id

    assert Catalog.count_galls_for_hosts([10, genus, 1]) == %{10 => 5, genus => 1, 1 => 0}
  end

  test "host_genera_of_galls/1: the genera of the Galls' Hosts, with the Galls on each" do
    genus = old(41)

    assert Catalog.host_genera_of_galls([300, 304]) == [
             %{
               taxon_id: genus.id,
               name: "Notholithocarpus",
               focal_ids: [300, 304],
               association_count: 3
             }
           ]

    assert Catalog.host_genera_of_galls([]) == []
  end

  test "inducer_genera_on_hosts/1: the genera of the Inducers of Galls on the hosts" do
    andricus = old(33)
    neuroterus = old(36)

    assert Catalog.inducer_genera_on_hosts([10]) == [
             %{taxon_id: andricus.id, name: "Andricus", focal_ids: [10], association_count: 3},
             %{taxon_id: neuroterus.id, name: "Neuroterus", focal_ids: [10], association_count: 2}
           ]
  end
end
