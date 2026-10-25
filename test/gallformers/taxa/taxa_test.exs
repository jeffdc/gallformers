defmodule Gallformers.TaxaTest do
  @moduledoc """
  Taxa's common names and the legacy crosswalk (`9449` §3).
  """
  use Gallformers.DataCase, async: true

  import Gallformers.TaxaFixtures

  alias Gallformers.Taxa
  alias Gallformers.Taxa.CommonName
  alias Gallformers.Taxa.LegacyId

  describe "rename/3" do
    defp names(taxon) do
      taxon.id |> Taxa.get_taxon!() |> Map.fetch!(:names) |> Enum.map(&{&1.name, &1.status})
    end

    test "keeps the old accepted name as a synonym" do
      taxon = taxon_fixture(name: "Cynips foo")

      assert {:ok, _} = Taxa.rename(test_actor(), taxon, "Andricus foo")

      assert names(taxon) == [{"Andricus foo", :accepted}, {"Cynips foo", :synonym}]
      assert {:ok, %{matched_name: %{status: :synonym}}} = Taxa.resolve_name("Cynips foo")
    end

    test "promotes a synonym that is the new name" do
      taxon = taxon_fixture(name: "Cynips foo")
      {:ok, synonym} = Taxa.add_synonym(test_actor(), taxon, "Andricus foo")

      assert {:ok, _} = Taxa.rename(test_actor(), taxon, "Andricus foo")

      assert names(taxon) == [{"Andricus foo", :accepted}, {"Cynips foo", :synonym}]
      assert Taxa.get_taxon!(taxon.id).names |> hd() |> Map.fetch!(:id) == synonym.id
    end

    test "a change of form only replaces the accepted name, keeping no synonym" do
      taxon = taxon_fixture(name: "quercus alba var latiloba", rank: :variety)

      assert {:ok, _} = Taxa.rename(test_actor(), taxon, "Quercus alba var. latiloba")
      assert names(taxon) == [{"Quercus alba var. latiloba", :accepted}]
    end

    test "a blank name is rejected and nothing changes" do
      taxon = taxon_fixture(name: "Cynips foo")

      assert {:error, changeset} = Taxa.rename(test_actor(), taxon, "  ")
      assert %{name: ["can't be blank"]} = errors_on(changeset)
      assert names(taxon) == [{"Cynips foo", :accepted}]
    end
  end

  describe "create_taxon/2" do
    test "keeps an explicit ID, as a migrated plant keeps its species ID" do
      # Far above anything the shared sequence hands out in a test run.
      id = 8_000_000_000 + System.unique_integer([:positive])

      assert {:ok, taxon} =
               Taxa.create_taxon(test_actor(), %{
                 id: id,
                 rank: :species,
                 origin: :powo,
                 kingdom: "Plantae",
                 name: "Quercus kept"
               })

      assert taxon.id == id
      assert Taxa.ancestors(id) == []
      assert Taxa.accepted_name(id) == "Quercus kept"
    end
  end

  describe "add_common_name/3" do
    test "adds a common name, once per taxon whatever the case" do
      taxon = taxon_fixture(name: "Pemphigus populitransversus")

      assert {:ok, %CommonName{name: "Poplar petiolegall aphid"}} =
               Taxa.add_common_name(test_actor(), taxon, " Poplar petiolegall aphid ")

      assert {:error, changeset} =
               Taxa.add_common_name(test_actor(), taxon, "poplar PETIOLEGALL aphid")

      assert %{name: ["is already a common name of this taxon"]} = errors_on(changeset)

      assert ["Poplar petiolegall aphid"] =
               Enum.map(Taxa.list_common_names(taxon), & &1.name)
    end
  end

  describe "legacy IDs" do
    test "an old taxonomy ID maps to its taxon" do
      family = taxon_fixture(rank: :family, name: "Cynipidae")

      assert {:ok, %LegacyId{kind: :taxonomy, legacy_id: 12}} =
               Taxa.add_legacy_id(test_actor(), family, :taxonomy, 12, "Cynipidae")

      assert Taxa.get_by_legacy_id(:taxonomy, 12).id == family.id
      assert Taxa.get_by_legacy_id(:taxonomy, 13) == nil
    end

    test "the same number in two kinds maps separately" do
      family = taxon_fixture(rank: :family)
      inducer = taxon_fixture(rank: :species)

      {:ok, _} = Taxa.add_legacy_id(test_actor(), family, :taxonomy, 587)
      {:ok, _} = Taxa.add_legacy_id(test_actor(), inducer, :gall_inducer, 587)

      assert Taxa.get_by_legacy_id(:taxonomy, 587).id == family.id
      assert Taxa.get_by_legacy_id(:gall_inducer, 587).id == inducer.id
    end

    test "an agamic/sexgen pair of gall rows maps to one Inducer" do
      inducer = taxon_fixture(name: "Andricus quercuspetiolicola")

      {:ok, _} =
        Taxa.add_legacy_id(
          test_actor(),
          inducer,
          :gall_inducer,
          101,
          "Andricus quercuspetiolicola (agamic)"
        )

      {:ok, _} =
        Taxa.add_legacy_id(
          test_actor(),
          inducer,
          :gall_inducer,
          102,
          "Andricus quercuspetiolicola (sexgen)"
        )

      assert Taxa.get_by_legacy_id(:gall_inducer, 101).id == inducer.id
      assert Taxa.get_by_legacy_id(:gall_inducer, 102).id == inducer.id
    end

    test "a legacy ID maps to one taxon only" do
      {:ok, _} = Taxa.add_legacy_id(test_actor(), taxon_fixture(), :taxonomy, 7)

      assert {:error, changeset} =
               Taxa.add_legacy_id(test_actor(), taxon_fixture(), :taxonomy, 7)

      assert %{kind: ["is already mapped"]} = errors_on(changeset)
    end
  end
end
