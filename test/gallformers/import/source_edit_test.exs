defmodule Gallformers.Import.SourceEditTest do
  @moduledoc """
  The Source editor's edits (matter a856, Task 10):
  `Gallformers.Import.record_source_edit/2` edits a Source's details,
  retracts it or undoes its retraction through `Gallformers.Sources`,
  recomputes the standings of the Facts it attributes and records the edit
  in the replay log, in one audited transaction; the replay log replays
  them by the Sources' titles.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures

  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.Replay
  alias Gallformers.Sources
  alias Gallformers.Sources.Source

  defp fact_supported_by(source) do
    {:ok, fact} = Facts.create_fact(test_actor(), %{kind: "trait"})
    {:ok, _} = Facts.attribute(test_actor(), confirm(source, %{fact_id: fact.id}))
    fact
  end

  defp standing(fact), do: Facts.get_fact!(fact.id).standing

  defp source_edits do
    for e <- Import.list_replay_entries(), e.kind == :source_edit, do: {e.key, e.payload}
  end

  defp replay_log_changes do
    Repo.all(
      from c in test_audit_changes(), where: c.table_name == "replay_log", preload: :transaction
    )
  end

  describe "record_source_edit/2, {:update_details, source, attrs}" do
    test "edits the Source and records the changed fields under its title before the edit" do
      source = source_fixture("Galls of the Sierra", "1957")

      assert {:ok, %Source{} = updated} =
               Import.record_source_edit(
                 test_actor(),
                 {:update_details, source,
                  %{
                    "title" => "Galls of the Sierra Nevada",
                    "authored" => "1957-06",
                    "doi" => "10.1000/sierra",
                    "citation" => source.citation
                  }}
               )

      assert updated.title == "Galls of the Sierra Nevada"
      assert Source.authored(updated) == "1957-06"

      assert [
               {%{"op" => "update_details", "source" => %{"title" => old_title}},
                %{"attrs" => attrs}}
             ] = source_edits()

      assert old_title == source.title

      assert attrs == %{
               "title" => "Galls of the Sierra Nevada",
               "authored" => "1957-06",
               "doi" => "10.1000/sierra"
             }

      assert [%{op: :insert, transaction: %{meta: %{"actor" => %{"name" => "test"}}}}] =
               replay_log_changes()
    end

    test "an invalid edit writes nothing and logs nothing" do
      source = source_fixture("Kept as it was", "1957")

      assert {:error, %Ecto.Changeset{} = changeset} =
               Import.record_source_edit(test_actor(), {:update_details, source, %{title: ""}})

      assert %{title: ["can't be blank"]} = errors_on(changeset)
      assert Sources.get_source!(source.id).title == source.title
      assert source_edits() == []
    end
  end

  describe "record_source_edit/2, retracting and un-retracting" do
    test "retracting recomputes the standings of the Facts the Source supports" do
      retracted = source_fixture("Fabricated results", "2019")
      notice = source_fixture("Retraction notice", "2021")
      fact = fact_supported_by(retracted)
      assert standing(fact) == :current

      assert {:ok, %Source{retracted_by_id: notice_id}} =
               Import.record_source_edit(
                 test_actor(),
                 {:retract, retracted, notice, ~D[2021-06-01]}
               )

      assert notice_id == notice.id
      assert standing(fact) == :retracted

      assert [
               {%{"op" => "retract", "source" => %{"title" => title}},
                %{"notice" => %{"title" => notice_title}, "on" => "2021-06-01"}}
             ] = source_edits()

      assert {title, notice_title} == {retracted.title, notice.title}
    end

    test "un-retracting restores them" do
      retracted = source_fixture("Retracted by mistake", "2019")
      notice = source_fixture("Mistaken notice", "2021")
      fact = fact_supported_by(retracted)

      {:ok, _} =
        Import.record_source_edit(
          test_actor(),
          {:retract, retracted.id, notice.id, ~D[2021-06-01]}
        )

      assert standing(fact) == :retracted

      assert {:ok, %Source{retracted_by_id: nil, retracted_on: nil}} =
               Import.record_source_edit(test_actor(), {:unretract, retracted.id})

      assert standing(fact) == :current

      assert [_retract, {%{"op" => "unretract", "source" => %{"title" => title}}, %{}}] =
               source_edits()

      assert title == retracted.title
    end

    test "un-retracting a Source that is not retracted is refused and logs nothing" do
      source = source_fixture("Never retracted", "2019")

      assert {:error, changeset} = Import.record_source_edit(test_actor(), {:unretract, source})
      assert %{retracted_by_id: ["is not retracted"]} = errors_on(changeset)
      assert source_edits() == []
    end
  end

  describe "replaying Source edits" do
    defp state(source_ids, fact) do
      sources =
        for id <- source_ids do
          Map.take(Sources.get_source!(id), [
            :title,
            :doi,
            :authored_date,
            :authored_precision,
            :retracted_by_id,
            :retracted_on
          ])
        end

      {sources, standing(fact)}
    end

    test "makes the same edits again, finding the Sources by title" do
      source = source_fixture("Replayed paper", "2019")
      notice = source_fixture("Replayed notice", "2021")
      fact = fact_supported_by(source)
      original = Map.take(source, [:title, :doi, :authored_date, :authored_precision])

      {:ok, _} =
        Import.record_source_edit(
          test_actor(),
          {:update_details, source, %{title: "Replayed paper, revised", doi: "10.1/replayed"}}
        )

      {:ok, _} =
        Import.record_source_edit(test_actor(), {:retract, source.id, notice, ~D[2021-06-01]})

      {:ok, _} = Import.record_source_edit(test_actor(), {:unretract, source.id})

      {:ok, _} =
        Import.record_source_edit(test_actor(), {:retract, source.id, notice, ~D[2022-01-01]})

      after_edits = state([source.id, notice.id], fact)
      entries = Enum.filter(Import.list_replay_entries(), &(&1.kind == :source_edit))
      assert length(entries) == 4

      # A fresh copy: the Source as the data migration would have left it.
      Repo.update_all(from(s in Source, where: s.id == ^source.id),
        set: Map.to_list(Map.merge(original, %{retracted_by_id: nil, retracted_on: nil}))
      )

      {:ok, _} = Facts.recompute_for_source(test_actor(), source.id)
      assert standing(fact) == :current

      assert {:ok, 4} = Replay.run(entries, actor: test_actor())
      assert state([source.id, notice.id], fact) == after_edits
    end

    test "an entry whose Source is gone stops the replay" do
      entry = %{
        kind: :source_edit,
        key: %{"op" => "unretract", "source" => %{"title" => "No such Source"}},
        payload: %{}
      }

      assert {:error, %{index: 0, reason: {:not_found, _}}} =
               Replay.run([entry], actor: test_actor())
    end
  end
end
