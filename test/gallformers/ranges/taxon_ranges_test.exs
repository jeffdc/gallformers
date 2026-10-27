defmodule Gallformers.Ranges.TaxonRangesTest do
  @moduledoc """
  Host ranges by taxon (`a856` Task 8): `host_range` read and written by
  `taxon_id`, a plant made after the data migration having no `species`
  row, and the ID tool's lookup table following a change.

  Not async: loads the vocabularies (see `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Ranges

  setup do
    load_vocab!()
    %{source: source_fixture("Weld", "1959")}
  end

  defp rows(taxon_id) do
    Repo.all(
      from(hr in "host_range",
        join: p in "place",
        on: p.id == hr.place_id,
        where: hr.taxon_id == ^taxon_id,
        order_by: p.code,
        select: {p.code, hr.precision, hr.distribution_type, hr.species_id}
      )
    )
  end

  defp host!(plant, gall, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        confirm(source)
      )

    :ok
  end

  describe "get_places_for_taxon_with_precision/1" do
    test "a plant's rows with code, precision, place and distribution" do
      plant = plant_fixture()
      host_range_fixture(plant, [{"US-CA", "exact"}, {"CA", "country", "introduced"}])

      assert Enum.sort_by(Ranges.get_places_for_taxon_with_precision(plant.id), & &1.code) == [
               %{
                 code: "CA",
                 precision: "country",
                 place_id: place_id("CA"),
                 distribution_type: "introduced"
               },
               %{
                 code: "US-CA",
                 precision: "exact",
                 place_id: place_id("US-CA"),
                 distribution_type: "native"
               }
             ]
    end
  end

  describe "update_taxon_places/3" do
    test "replaces a plant's rows, leaving other plants' as they are" do
      plant = plant_fixture()
      other = plant_fixture()
      host_range_fixture(plant, [{"US-CA", "exact"}])
      host_range_fixture(other, [{"US-CA", "exact"}])

      assert {:ok, 2} =
               Ranges.update_taxon_places(test_actor(), plant.id, [
                 {place_id("MX-JAL"), "exact", "native"},
                 {place_id("CA"), "country", "introduced"}
               ])

      # A migrated plant keeps its species ID on the rows.
      assert rows(plant.id) == [
               {"CA", "country", "introduced", plant.id},
               {"MX-JAL", "exact", "native", plant.id}
             ]

      assert rows(other.id) == [{"US-CA", "exact", "native", other.id}]
    end

    test "a plant made after the data migration (no species row) gets rows by taxon only" do
      plant = plant_fixture()

      assert {:ok, 1} = Ranges.update_taxon_places(test_actor(), plant, [place_id("US-CA")])
      assert rows(plant.id) == [{"US-CA", "exact", "native", nil}]
    end

    test "a place given twice is kept once, native first" do
      plant = plant_fixture()

      assert {:ok, 1} =
               Ranges.update_taxon_places(test_actor(), plant.id, [
                 {place_id("US-CA"), "exact", "introduced"},
                 {place_id("US-CA"), "exact", "native"}
               ])

      assert rows(plant.id) == [{"US-CA", "exact", "native", nil}]
    end

    test "an empty list clears the range" do
      plant = plant_fixture()
      host_range_fixture(plant, [{"US-CA", "exact"}])

      assert {:ok, 0} = Ranges.update_taxon_places(test_actor(), plant.id, [])
      assert rows(plant.id) == []
    end

    test "refreshes the Galls whose Host is the plant, or a genus above it", %{source: source} do
      genus = plant_fixture(rank: :genus, name: "Rangequercus")
      oak = plant_fixture(name: "Rangequercus alba", parent: genus)
      host_range_fixture(oak, [{"US-CA", "exact"}])

      on_oak = gall_fixture()
      on_genus = gall_fixture()
      elsewhere = gall_fixture()
      host!(oak, on_oak, source)
      host!(genus, on_genus, source)
      host!(plant_fixture(), elsewhere, source)
      :ok = Catalog.refresh_gall_index([on_oak.id, on_genus.id, elsewhere.id])

      {:ok, _} = Ranges.update_taxon_places(test_actor(), oak.id, [place_id("MX-JAL")])

      assert Repo.get!(GallIndex, on_oak.id).place_ids == [place_id("MX-JAL")]
      assert Repo.get!(GallIndex, on_genus.id).place_ids == [place_id("MX-JAL")]
      assert Repo.get!(GallIndex, elsewhere.id).everywhere == true
    end
  end
end
