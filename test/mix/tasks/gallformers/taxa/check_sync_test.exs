defmodule Mix.Tasks.Gallformers.Taxa.CheckSyncTest do
  @moduledoc """
  `mix gallformers.taxa.check_sync` (`f923` Task 5): rebuilds the expected
  tree from the taxonomic Facts and prints the rows that differ.
  """
  use Gallformers.DataCase, async: true

  import ExUnit.CaptureIO
  import Gallformers.TaxaFixtures

  alias Mix.Tasks.Gallformers.Taxa.CheckSync

  test "a tree that follows its Facts" do
    assert CheckSync.format([]) == ["The tree follows the Facts: no differences."]
  end

  test "each difference is a line, with a count" do
    differences = [
      %{taxon_id: 7, name: "Andricus foo", aspect: :placement, expected: 3, actual: 4},
      %{taxon_id: 7, name: "Andricus foo", aspect: :synonym, expected: nil, actual: "Cynips foo"},
      %{taxon_id: 9, name: "Bar", aspect: :name, expected: :none, actual: "Bar"}
    ]

    assert CheckSync.format(differences) == [
             "3 tree rows differ from the Facts:",
             "  7 Andricus foo — placement: the Facts give 3, the tree has 4",
             "  7 Andricus foo — synonym: no Fact backs \"Cynips foo\"",
             "  9 Bar — name: no current Fact, the tree has \"Bar\""
           ]
  end

  test "run prints the differences" do
    bare = taxon_fixture(rank: :family, name: "Checkidae", kingdom: "Animalia")

    output = capture_io(fn -> CheckSync.run([]) end)
    assert output =~ "#{bare.id} Checkidae — placement: no current Fact"
  end
end
