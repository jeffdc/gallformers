defmodule Gallformers.Catalog.SourceGallsTest do
  @moduledoc """
  The Galls a Source speaks of (`Gallformers.Catalog.list_galls_for_source/1`),
  for the Source page: its legacy citations, its attributions of current
  Facts, and for the Gallformers Source its notes.

  The converted seeds (`priv/repo/test_seeds.sql`) have Source 59 cited on
  Gall 300 and Gallformers notes (Source 58) on Galls 300 and 301.

  Not async: some tests use the Gallformers Source (see
  `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  # Reading the seeds, converted, is part of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Sources

  defp host!(plant, gall, attribution) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        attribution
      )

    :ok
  end

  defp ids(cards), do: Enum.map(cards, & &1.id)

  test "a Source's legacy citations" do
    assert Catalog.list_galls_for_source(59) == [
             %{id: 300, name: "Andricus seedii (agamic)", datacomplete: true}
           ]
  end

  test "the Gallformers Source lists the Galls with its notes" do
    assert ids(Catalog.list_galls_for_source(58)) == [300, 301]
  end

  test "a Source attributing Facts only, each Gall once, by the name shown" do
    source = source_fixture("Facts only", "1990")
    plant = plant_fixture()
    zebra = gall_fixture(name: "Zebra gall")
    apple = gall_fixture(name: "Derived", name_override: "Apple gall")

    host!(plant, zebra, confirm(source))
    host!(plant_fixture(), zebra, confirm(source))

    {:ok, _} =
      Catalog.assert_alias(test_actor(), %{gall_id: apple.id, name: "apple"}, confirm(source))

    assert Enum.map(Catalog.list_galls_for_source(source.id), & &1.name) == [
             "Apple gall",
             "Zebra gall"
           ]
  end

  test "a qualifier lists the Gall of the Relationship it qualifies" do
    source = source_fixture("Qualifiers only", "1990")
    gall = gall_fixture()

    {:ok, %{fact: relationship}} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "parasitoid_in", subject_taxon_id: taxon_fixture().id, object_gall_id: gall.id},
        confirm(source_fixture("Other", "1980"))
      )

    {:ok, _} =
      Catalog.assert_qualifier(
        test_actor(),
        %{of_fact_id: relationship.id, qualifier: "parasitism_mode", value: "koinobiont"},
        confirm(source)
      )

    assert ids(Catalog.list_galls_for_source(source.id)) == [gall.id]
  end

  test "a Fact that is no longer current does not count" do
    source = source_fixture("Superseded", "1950")
    gall = gall_fixture()
    plant = plant_fixture()

    host!(plant, gall, confirm(source))
    host!(plant, gall, deny(source_fixture("Revision", "1990")))

    assert Catalog.list_galls_for_source(source.id) == []
  end

  test "citations, Facts and notes together, each Gall once" do
    gallformers = gallformers_source()
    cited = gall_fixture()
    noted = gall_fixture()

    {:ok, 1} =
      Catalog.insert_legacy_citations(test_actor(), [
        %{gall_id: cited.id, source_id: gallformers.id, description: "C.", useasdefault: false}
      ])

    {:ok, _} = Sources.store_note(test_actor(), gallformers, noted.id, "A note.")
    {:ok, _} = Sources.store_note(test_actor(), gallformers, cited.id, "Another note.")

    assert Enum.sort(ids(Catalog.list_galls_for_source(gallformers.id))) ==
             Enum.sort([cited.id, noted.id])
  end

  test "a Source with no Galls, or no such Source, lists none" do
    assert Catalog.list_galls_for_source(source_fixture("Nothing", "2000").id) == []
    assert Catalog.list_galls_for_source(999_999_999) == []
  end
end
