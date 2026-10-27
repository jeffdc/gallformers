defmodule Gallformers.Import.TaxonomyAdminTest do
  @moduledoc """
  The taxonomy admin's writes of several edits as one (`a856` Task 9,
  `Gallformers.Import.TaxonomyAdmin`): each edit in the replay log, and
  all of a write's edits or none.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Import
  alias Gallformers.Ranges
  alias Gallformers.Ranges.Wcvp
  alias Gallformers.Taxa

  setup :audit_test_metadata

  defp uniq, do: System.unique_integer([:positive])
  defp log_size, do: length(Import.list_replay_entries())

  describe "record_taxon_created/4" do
    test "creates the taxon and moves the children under it" do
      family = taxon_fixture(rank: :family, name: "Adminidae#{uniq()}", kingdom: "Animalia")
      child = taxon_fixture(rank: :genus, name: "Admingenus#{uniq()}", parent: family)
      before = log_size()

      assert {:ok, tribe} =
               Import.record_taxon_created(
                 test_actor(),
                 %{name: "Admini#{uniq()}", rank: :tribe, parent_id: family.id, kingdom: nil},
                 [child.id],
                 []
               )

      assert tribe.origin == :curated
      assert Taxa.get_taxon!(child.id).parent_id == tribe.id
      assert log_size() == before + 2
    end

    test "a child that can't move leaves nothing behind" do
      family = taxon_fixture(rank: :family, name: "Rollidae#{uniq()}", kingdom: "Animalia")
      name = "Rollini#{uniq()}"
      before = log_size()

      # A family can't go under a tribe.
      assert {:error, _} =
               Import.record_taxon_created(
                 test_actor(),
                 %{name: name, rank: :tribe, parent_id: family.id, kingdom: nil},
                 [family.id],
                 []
               )

      assert Taxa.resolve_name(name) == :none
      assert log_size() == before
    end

    test "a plant is added as the Host-name step adds one, with its range" do
      genus = plant_fixture(rank: :genus, name: "Adminplant#{uniq()}")
      name = "#{Taxa.accepted_name(genus)} alba"

      assert {:ok, plant} =
               Import.record_taxon_created(
                 test_actor(),
                 %{name: name, rank: :species, parent_id: genus.id, kingdom: "Plantae"},
                 [],
                 [{place_id("US-CA"), "exact", "native"}]
               )

      assert plant.origin == :powo
      assert [%{code: "US-CA"}] = Ranges.get_places_for_taxon_with_precision(plant.id)
      assert :plant_added in Enum.map(Import.list_replay_entries(), & &1.kind)
    end
  end

  describe "record_plant_added_from_wcvp/4" do
    test "makes the WCVP family and genus, the plant, its range and its link" do
      record = %{
        taxon_name: "Adminwcvp#{uniq()} alba",
        taxon_authors: "",
        family: "Adminwcvpaceae#{uniq()}",
        genus: nil,
        plant_name_id: "admin-#{uniq()}",
        powo_id: "powo-x"
      }

      entries = [{place_id("US-CA"), "exact", "native"}]

      assert {:ok, plant} =
               Import.record_plant_added_from_wcvp(test_actor(), record, :species, entries)

      assert [%{rank: :family, name: family}, %{rank: :genus, name: genus} | _] =
               Taxa.lineage(plant)

      assert family == record.family
      assert genus == record.taxon_name |> String.split() |> hd()
      assert Wcvp.get_link(plant.id).wcvp_id == record.plant_name_id
      assert [%{code: "US-CA"}] = Ranges.get_places_for_taxon_with_precision(plant.id)
    end
  end

  describe "record_host_range_saved/4" do
    test "an invalid link leaves the range as it was" do
      plant = plant_fixture()
      host_range_fixture(plant, [{"US-CA", "exact"}])

      assert {:error, _changeset} =
               Import.record_host_range_saved(
                 test_actor(),
                 plant.id,
                 [{place_id("MX-JAL"), "exact", "native"}],
                 %{wcvp_match_status: "maybe"}
               )

      assert [%{code: "US-CA"}] = Ranges.get_places_for_taxon_with_precision(plant.id)
    end
  end

  describe "record_taxa_moved/3" do
    test "moves them all, or none when one can't move" do
      from = taxon_fixture(rank: :family, name: "Fromidae#{uniq()}", kingdom: "Animalia")
      to = taxon_fixture(rank: :family, name: "Toidae#{uniq()}", kingdom: "Animalia")
      a = taxon_fixture(rank: :genus, name: "Movea#{uniq()}", parent: from)
      b = taxon_fixture(rank: :genus, name: "Moveb#{uniq()}", parent: from)

      assert {:error, _} = Import.record_taxa_moved(test_actor(), [a.id, to.id], from.id)
      assert Taxa.get_taxon!(a.id).parent_id == from.id

      assert {:ok, 2} = Import.record_taxa_moved(test_actor(), [a.id, b.id], to.id)
      assert Taxa.get_taxon!(b.id).parent_id == to.id
    end
  end
end
