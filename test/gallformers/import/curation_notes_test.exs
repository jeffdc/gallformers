defmodule Gallformers.Import.CurationNotesTest do
  @moduledoc """
  Curators' notes that are data (matter `ec2c`), recorded in the replay log
  by stable keys and replayed: a note on a Fact
  (`Gallformers.Import.record_fact_note/5`) and a "based on" note on a
  plant's editorial edit (`Gallformers.Import.record_taxon_note/5`).

  Not async: the tests load the vocabularies.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Audit
  alias Gallformers.Catalog
  alias Gallformers.Catalog.FactNote
  alias Gallformers.Import
  alias Gallformers.Import.Replay
  alias Gallformers.Taxa
  alias Gallformers.Taxa.TaxonNote

  setup :audit_test_metadata

  setup do
    load_vocab!()
    source = source_fixture("Weld", "1959")
    gall = gall_fixture()
    oak = plant_fixture(name: "Quercus notarum")

    {:ok, %{fact: host}} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: oak.id, object_gall_id: gall.id},
        confirm(source)
      )

    {:ok, %{fact: excluded}} =
      Catalog.assert_range(
        test_actor(),
        %{gall_id: gall.id, adjustment: :exclude, place_id: place_id("US-CA")},
        confirm(source)
      )

    %{gall: gall, oak: oak, host: host, excluded: excluded}
  end

  defp entries(kind), do: for(e <- Import.list_replay_entries(), e.kind == kind, do: e)

  defp wipe!(schema) do
    {:ok, _} = Audit.transaction(test_actor(), "test.wipe", fn -> Repo.delete_all(schema) end)
  end

  describe "record_fact_note/5" do
    test "notes the Fact the key names and logs it by stable keys", ctx do
      assert {:ok, %FactNote{fact_id: fact_id, text: "Only on young trees."}} =
               Import.record_fact_note(
                 test_actor(),
                 ctx.gall.id,
                 {:host, ctx.oak.id},
                 "Only on young trees."
               )

      assert fact_id == ctx.host.id

      assert [entry] = entries(:fact_note)
      assert entry.key["gall"] == %{"id" => ctx.gall.id}

      assert entry.key["fact"] == %{
               "kind" => "host",
               "taxon" => Import.StableRef.taxon(ctx.oak.id)
             }

      assert entry.payload == %{"text" => "Only on young trees.", "author" => "test"}
    end

    test "a range key names its place by code", ctx do
      key = {:range, :exclude, place_id("US-CA")}
      {:ok, _} = Import.record_fact_note(test_actor(), ctx.gall.id, key, "Checked herbaria.")

      assert [
               %{
                 key: %{
                   "fact" => %{"kind" => "range", "adjustment" => "exclude", "place" => "US-CA"}
                 }
               }
             ] =
               entries(:fact_note)
    end

    test "a key that names no Fact is refused and logs nothing", ctx do
      assert {:error, :no_fact} =
               Import.record_fact_note(test_actor(), ctx.gall.id, {:alias, "oak apple"}, "x")

      assert entries(:fact_note) == []
    end

    test "replays onto the Fact found again, once", ctx do
      {:ok, _} =
        Import.record_fact_note(test_actor(), ctx.gall.id, {:host, ctx.oak.id}, "Young trees.")

      logged = entries(:fact_note)
      wipe!(FactNote)

      assert {:ok, 1} = Replay.run(logged, actor: test_actor())
      assert [%FactNote{text: "Young trees.", author_name: "test"}] = Repo.all(FactNote)

      assert {:ok, 1} = Replay.run(logged, actor: test_actor())
      assert [_one] = Repo.all(FactNote)
    end
  end

  describe "record_taxon_note/5" do
    test "notes a plant's edit and replays it once", ctx do
      assert {:ok, %TaxonNote{about: "synonyms", text: "per Flora of North America"}} =
               Import.record_taxon_note(
                 test_actor(),
                 ctx.oak.id,
                 "synonyms",
                 "per Flora of North America"
               )

      assert [%TaxonNote{}] = Taxa.list_taxon_notes(ctx.oak.id)
      assert [entry] = entries(:taxon_note)
      assert entry.key == %{"taxon" => Import.StableRef.taxon(ctx.oak.id), "about" => "synonyms"}

      wipe!(TaxonNote)
      assert {:ok, 1} = Replay.run([entry], actor: test_actor())
      assert {:ok, 1} = Replay.run([entry], actor: test_actor())
      assert [%TaxonNote{author_name: "test"}] = Taxa.list_taxon_notes(ctx.oak.id)
    end
  end
end
