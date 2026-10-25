defmodule Gallformers.Import.ReplayExportTest do
  @moduledoc """
  Carrying the replay log from preview to production (`9449` Task 17;
  `b5bd` M6): exported to a file in the private bucket, then replayed from
  that file after the cutover data migration.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Audit
  alias Gallformers.Import
  alias Gallformers.Storage.Private
  alias Gallformers.Taxa

  defp genus! do
    {:ok, taxon} =
      Taxa.create_taxon(test_actor(), %{
        rank: :genus,
        origin: :curated,
        name: "Fixturexportia",
        kingdom: "Animalia"
      })

    taxon
  end

  test "an exported replay log replays on a database without it" do
    genus = genus!()
    {:ok, _} = Import.record_synonym_added(test_actor(), genus.id, "Fixturexportoides")

    assert {:ok, %{key: "replay/" <> _ = key, count: 1}} = Import.export_replay_log()
    assert {:ok, _json} = Private.get(key)

    # Production after the cutover data migration: the taxon is there; the
    # log and what it records are not.
    {:ok, _} =
      Audit.transaction(test_actor(), "test.cutover", fn ->
        Repo.delete_all(from(n in "taxon_names", where: n.name == "Fixturexportoides"))
        Repo.delete_all("replay_log")
      end)

    assert Taxa.resolve_name("Fixturexportoides") == :none

    assert {:ok, 1} = Import.replay_exported(test_actor(), key)

    assert {:ok, %{id: id, matched_name: %{status: :synonym}}} =
             Taxa.resolve_name("Fixturexportoides")

    assert id == genus.id
    assert [%{kind: :synonym_added}] = Import.list_replay_entries()
  end

  test "the export keeps the log's order, kinds, keys and payloads" do
    genus = genus!()
    {:ok, _} = Import.record_synonym_added(test_actor(), genus.id, "Fixturexportoides")

    {:ok, _} =
      Import.record_taxonomy_edit(test_actor(), {:add_common_name, genus.id, "export galls"})

    expected = for e <- Import.list_replay_entries(), do: {e.kind, e.key, e.payload}

    {:ok, %{key: key}} = Import.export_replay_log()
    assert {:ok, entries} = Import.read_replay_export(key)
    assert for(e <- entries, do: {e.kind, e.key, e.payload}) == expected
  end

  test "a file that is not a replay-log export is an error" do
    :ok = Private.put("replay/not-a-log.json", ~s({"entries": "nope"}))

    assert {:error, {:not_a_replay_export, "replay/not-a-log.json"}} =
             Import.replay_exported(test_actor(), "replay/not-a-log.json")

    assert {:error, :not_found} = Import.replay_exported(test_actor(), "replay/missing.json")
  end
end
