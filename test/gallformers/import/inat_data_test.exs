defmodule Gallformers.Import.InatDataTest do
  @moduledoc """
  The data a taxon brought in from iNaturalist needs (matter `cb28`
  Task 1): the day's iNaturalist Source, made on the day's first import
  and reused after; a taxon's iNaturalist ID (`taxon_inaturalist`, set by
  the `{:set_inat, taxon, id}` edit); a plant's origin `:inaturalist`.
  Each is logged for replay and replays to the same result.

  Not async: wipes the replay log inside its sandbox, and the Source's
  title is unique.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Import
  alias Gallformers.Import.Replay
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    Repo.query!("DELETE FROM replay_log")
    :ok
  end

  describe "the day's iNaturalist Source" do
    test "is made on the day's first import, dated that day, and reused after" do
      day = ~D[2026-11-08]
      assert Sources.inaturalist_title(day) == "iNaturalist, accessed 8 Nov 2026"
      assert Sources.inaturalist_source(day) == nil

      assert {:ok, source} = Import.record_inaturalist_source(test_actor(), day)
      assert source.title == "iNaturalist, accessed 8 Nov 2026"
      assert source.kind == :database
      assert source.authored_date == day
      assert source.authored_precision == :day
      assert source.authors == ["iNaturalist"]
      assert source.link == "https://www.inaturalist.org"

      assert {:ok, again} = Import.record_inaturalist_source(test_actor(), day)
      assert again.id == source.id
      assert Sources.inaturalist_source(day).id == source.id

      # Another day, another Source.
      assert {:ok, next} = Import.record_inaturalist_source(test_actor(), ~D[2026-11-09])
      assert next.id != source.id

      assert [
               %{kind: :source_edit, key: %{"op" => "create_inaturalist"}, payload: first},
               %{kind: :source_edit, payload: %{"on" => "2026-11-09"}}
             ] = Import.list_replay_entries()

      assert first == %{"on" => "2026-11-08"}
    end

    test "replays: made again when missing, left alone when there" do
      day = ~D[2026-11-08]
      {:ok, source} = Import.record_inaturalist_source(test_actor(), day)
      entries = Import.list_replay_entries()

      Repo.delete!(source)
      assert {:ok, 1} = Replay.run(entries, actor: test_actor())
      assert %{authored_date: ^day} = Sources.inaturalist_source(day)

      Gallformers.ImportFixtures.assert_replays_again(entries)
    end
  end

  describe "a taxon's iNaturalist ID" do
    test "{:set_inat} links it, logged by stable key, and replays" do
      genus = plant_fixture(rank: :genus, name: "Inatlinkus")
      assert Taxa.inat_id(genus) == nil

      assert {:ok, _link} = Import.record_taxonomy_edit(test_actor(), {:set_inat, genus, 47_544})
      assert Taxa.inat_id(genus) == 47_544
      assert Taxa.get_by_inat_id(47_544).id == genus.id
      assert Taxa.get_by_inat_id(1) == nil

      assert [%{kind: :taxonomy_edit, key: key, payload: payload}] = Import.list_replay_entries()

      assert key == %{
               "op" => "set_inat",
               "taxon" => %{"name" => "Inatlinkus", "rank" => "genus", "kingdom" => "Plantae"}
             }

      assert payload == %{"inat_id" => 47_544}

      changes = Repo.all(from(c in test_audit_changes(), select: {c.table_name, c.op}))
      assert {"taxon_inaturalist", :insert} in changes

      entries = Import.list_replay_entries()
      Repo.query!("DELETE FROM taxon_inaturalist")
      assert {:ok, 1} = Replay.run(entries, actor: test_actor())
      assert Taxa.inat_id(genus) == 47_544

      Gallformers.ImportFixtures.assert_replays_again(entries)
    end

    test "an iNaturalist taxon links to one of ours" do
      one = plant_fixture(rank: :genus, name: "Inatoneus")
      other = plant_fixture(rank: :genus, name: "Inatotherus")
      {:ok, _} = Import.record_taxonomy_edit(test_actor(), {:set_inat, one, 5})

      assert {:error, _} = Import.record_taxonomy_edit(test_actor(), {:set_inat, other, 5})
      assert Taxa.inat_id(other) == nil
      assert length(Import.list_replay_entries()) == 1
    end

    test "deletes with its taxon" do
      genus = plant_fixture(rank: :genus, name: "Inatdoomedus")
      {:ok, _} = Import.record_taxonomy_edit(test_actor(), {:set_inat, genus, 9})

      assert {:ok, _} = Taxa.delete_taxon(test_actor(), genus)
      assert Taxa.get_by_inat_id(9) == nil
    end
  end

  describe "a plant from iNaturalist" do
    test "keeps origin :inaturalist, logged and replayed" do
      genus = plant_fixture(rank: :genus, name: "Inatplantus")

      assert {:ok, plant} =
               Import.record_plant_added(test_actor(), %{
                 name: "Inatplantus primus",
                 rank: :species,
                 parent_id: genus.id,
                 origin: :inaturalist
               })

      assert plant.origin == :inaturalist
      assert [%{kind: :plant_added, payload: payload}] = Import.list_replay_entries()
      assert payload["origin"] == "inaturalist"

      entries = Import.list_replay_entries()
      {:ok, _} = Taxa.delete_taxon(test_actor(), plant)
      assert {:ok, 1} = Replay.run(entries, actor: test_actor())

      assert {:ok, %{origin: :inaturalist}} =
               Taxa.resolve_name("Inatplantus primus", kingdom: "Plantae")
    end

    test "a plant added otherwise is :powo, logged as before" do
      genus = plant_fixture(rank: :genus, name: "Powoplantus")

      {:ok, plant} =
        Import.record_plant_added(test_actor(), %{
          name: "Powoplantus primus",
          rank: :species,
          parent_id: genus.id
        })

      assert plant.origin == :powo
      assert [%{payload: payload}] = Import.list_replay_entries()
      refute Map.has_key?(payload, "origin")
    end

    test "a higher plant rank created from iNaturalist is :inaturalist too" do
      genus = plant_fixture(rank: :genus, name: "Inatsectus")

      assert {:ok, section} =
               Import.record_taxon_created(
                 test_actor(),
                 %{
                   name: "Primae",
                   rank: :section,
                   parent_id: genus.id,
                   kingdom: "Plantae",
                   origin: :inaturalist
                 },
                 [],
                 []
               )

      assert section.origin == :inaturalist
    end
  end
end
