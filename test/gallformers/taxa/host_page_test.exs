defmodule Gallformers.Taxa.HostPageTest do
  @moduledoc """
  The Host page's taxon read model (`Gallformers.Taxa.host_page/1`).

  Mostly the converted seeds (`priv/repo/test_seeds.sql`, checked by
  `Gallformers.CatalogMigration.TestSeedsTest`): plant 10 Notholithocarpus
  densiflorus, in genus Notholithocarpus and family Fagaceae, with a common
  name and a synonym.
  """
  use Gallformers.DataCase, async: true

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Taxa
  alias Gallformers.Taxa.ReadModels.HostPage

  defp page!(id) do
    assert {:ok, %HostPage{} = page} = Taxa.host_page(id)
    page
  end

  describe "a host plant" do
    setup do
      %{page: page!(10)}
    end

    test "has its accepted name, rank and timestamps", %{page: page} do
      assert page.id == 10
      assert page.name == "Notholithocarpus densiflorus"
      assert page.rank == :species
      assert %DateTime{} = page.inserted_at
      assert %DateTime{} = page.updated_at
    end

    test "has its lineage, root first", %{page: page} do
      assert Enum.map(page.lineage, &{&1.name, &1.rank}) == [
               {"Fagaceae", :family},
               {"Notholithocarpus", :genus},
               {"Notholithocarpus densiflorus", :species}
             ]
    end

    test "has its common names and synonyms", %{page: page} do
      assert page.common_names == ["tanoak"]
      assert page.synonyms == [%{name: "Lithocarpus densiflorus", sensu: nil}]
    end

    test "has its editorial data-complete flag and abundance", %{page: page} do
      assert {page.datacomplete, page.abundance} == {true, "common"}
    end
  end

  test "a plant with neither flag is incomplete with no abundance" do
    page = page!(plant_fixture().id)
    assert {page.datacomplete, page.abundance} == {false, nil}
  end

  test "common names and synonyms are by name" do
    plant = plant_fixture(name: "Quercus hostpagei")
    {:ok, _} = Taxa.add_common_name(test_actor(), plant, "zebra oak")
    {:ok, _} = Taxa.add_common_name(test_actor(), plant, "apple oak")
    {:ok, _} = Taxa.add_synonym(test_actor(), plant, "Quercus zebrina")
    {:ok, _} = Taxa.add_synonym(test_actor(), plant, "Quercus applei", sensu: "auct. non Smith")

    page = page!(plant.id)

    assert page.common_names == ["apple oak", "zebra oak"]

    assert page.synonyms == [
             %{name: "Quercus applei", sensu: "auct. non Smith"},
             %{name: "Quercus zebrina", sensu: nil}
           ]
  end

  test "an infraspecific plant has a host page" do
    plant = plant_fixture(name: "Quercus hostpagei var. minor", rank: :variety)
    assert page!(plant.id).rank == :variety
  end

  test ":not_found for a missing ID, a non-plant taxon, a Gall and a plant above species" do
    assert Taxa.host_page(999_999_999) == :not_found
    assert Taxa.host_page(taxon_fixture().id) == :not_found
    assert Taxa.host_page(300) == :not_found
    assert Taxa.host_page(Taxa.get_by_legacy_id(:taxonomy, 41).id) == :not_found
  end
end
