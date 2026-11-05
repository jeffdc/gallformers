defmodule Gallformers.Import.QueueItemNotesTest do
  @moduledoc """
  Notes on queue items (matter `d213`, Task 7): saved on their own,
  decided or not, for the next curator. A note is not part of a decision
  and is not replayed; it stays with its item through deciding, rejecting
  and restoring the proposal, and resolving the package again. A decision
  that carries a `"note"` (older rows) still shows it as a note.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Ecto.Query
  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Audit
  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.QueueItemNote
  alias Gallformers.Import.ReplayLog

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    plant_fixture(name: "Quercus lobata", parent: quercus)
    andricus = taxon_fixture(name: "Andricus", rank: :genus, kingdom: "Animalia")
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    legacy = source_fixture("Legacy", "1990")

    # Two Galls of the wasp that no generation tells apart: g1 is ambiguous.
    galls =
      for name <- [
            "Andricus quercuscalifornicus stem gall",
            "Andricus quercuscalifornicus bud gall"
          ] do
        gall = gall_fixture(name: name)

        {:ok, _} =
          Catalog.assert_relationship(
            test_actor(),
            %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
            confirm(legacy)
          )

        gall
      end

    package =
      batch()
      |> unique_batch_id()
      |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
      |> update_in(["galls", Access.at(0), "identified_by"], &Map.delete(&1, "generation"))
      |> then(&package(gall: &1))
      |> with_review()
      |> deliver!()

    [item] = Import.list_queue_items(package)
    %{galls: galls, package: package, item: item}
  end

  describe "add_note/3" do
    test "saves a note on an open item, with who wrote it", %{item: item} do
      assert {:ok, %QueueItemNote{} = note} =
               Import.add_note(test_actor(), item, "  Check the plate in Kinsey.  ")

      assert note.text == "Check the plate in Kinsey."
      assert note.author_name == "test"
      assert %DateTime{} = note.inserted_at
      assert note.queue_item_id == item.id

      assert [%QueueItemNote{text: "Check the plate in Kinsey."}] = Import.list_notes(item)
      # The item is still open, and undecided.
      assert %QueueItem{status: :open, decision: nil} = Import.get_queue_item!(item.id)
    end

    test "refuses a blank note", %{item: item} do
      assert {:error, %Ecto.Changeset{} = changeset} = Import.add_note(test_actor(), item, "   ")
      assert %{text: [_]} = errors_on(changeset)
      assert Import.list_notes(item) == []
    end

    test "is not replayed", %{item: item} do
      before = length(ReplayLog.list())
      {:ok, _} = Import.add_note(test_actor(), item, "A note.")
      assert length(ReplayLog.list()) == before
    end
  end

  describe "list_notes/1" do
    test "lists an item's notes oldest first", %{item: item} do
      {:ok, first} = Import.add_note(test_actor(), item, "First.")
      {:ok, second} = Import.add_note(test_actor(), item, "Second.")

      # The same second: the order they were saved in.
      assert Enum.map(Import.list_notes(item), & &1.id) == [first.id, second.id]

      # An earlier note comes first whatever its ID.
      backdate(second, ~U[2020-01-01 00:00:00Z])
      assert Enum.map(Import.list_notes(item), & &1.id) == [second.id, first.id]
    end
  end

  describe "notes stay with the item" do
    test "through deciding it, and a decided item takes notes too", ctx do
      [chosen, _other] = ctx.galls
      {:ok, _} = Import.add_note(test_actor(), ctx.item, "Before deciding.")

      {:ok, decided} = Import.decide_queue_item(test_actor(), ctx.item, %{"gall_id" => chosen.id})
      assert decided.decision == %{"gall_id" => chosen.id}
      assert Enum.map(Import.list_notes(decided), & &1.text) == ["Before deciding."]

      {:ok, _} = Import.add_note(test_actor(), decided, "After deciding.")

      assert Enum.map(Import.list_notes(decided), & &1.text) ==
               ["Before deciding.", "After deciding."]
    end

    test "through rejecting the proposal and undoing it", %{item: item} do
      {:ok, _} = Import.add_note(test_actor(), item, "Kept.")
      {:ok, rejected} = Import.reject_proposal(test_actor(), item)
      assert Enum.map(Import.list_notes(rejected), & &1.text) == ["Kept."]
      {:ok, restored} = Import.restore_proposal(test_actor(), rejected)
      assert Enum.map(Import.list_notes(restored), & &1.text) == ["Kept."]
    end

    test "through resolving the package again", %{package: package, item: item} do
      {:ok, _} = Import.add_note(test_actor(), item, "Kept.")
      {:ok, package} = Import.resolve_package(test_actor(), package)

      assert [%QueueItem{id: id}] = Import.list_queue_items(package)
      assert id == item.id
      assert Enum.map(Import.list_notes(item), & &1.text) == ["Kept."]
    end

    test "when resolving again replaces the open item with another about its statement",
         %{package: package, item: item} do
      # An earlier resolution queued g1 as something else: resolving again
      # replaces that item with the ambiguous match.
      queued_as(item, :unresolved_name)
      {:ok, _} = Import.add_note(test_actor(), item, "Moved along.")

      {:ok, package} = Import.resolve_package(test_actor(), package)

      assert [%QueueItem{kind: :ambiguous_match, statement_ref: "g1"} = replacing] =
               Import.list_queue_items(package)

      assert replacing.id != item.id
      assert Enum.map(Import.list_notes(replacing), & &1.text) == ["Moved along."]
    end

    test "go with an item no resolution calls for any more", %{package: package, item: item} do
      queued_as(item, :unresolved_name, "g9")
      {:ok, _} = Import.add_note(test_actor(), item, "Gone with it.")

      {:ok, _package} = Import.resolve_package(test_actor(), package)

      assert Repo.get(QueueItem, item.id) == nil
      assert Repo.all(from(n in QueueItemNote, where: n.queue_item_id == ^item.id)) == []
    end
  end

  describe "notes_for/1" do
    test "shows a decision's note (older decisions) as a note", ctx do
      [chosen, _other] = ctx.galls
      {:ok, _} = Import.add_note(test_actor(), ctx.item, "Saved on its own.")

      {:ok, decided} =
        Import.decide_queue_item(test_actor(), ctx.item, %{
          "gall_id" => chosen.id,
          "note" => "The stem gall, from the plate."
        })

      backdate_notes(decided, ~U[2020-01-01 00:00:00Z])

      assert [stored, legacy] = Import.notes_for(decided)
      assert stored.text == "Saved on its own."
      assert %QueueItemNote{id: nil, text: "The stem gall, from the plate."} = legacy
      assert legacy.author_name == "test"
      assert legacy.inserted_at == decided.decided_at
      assert legacy.queue_item_id == decided.id

      assert Import.notes_by_item([decided]) == %{decided.id => [stored, legacy]}
    end

    test "is the stored notes for an item with no decision note", %{item: item} do
      {:ok, note} = Import.add_note(test_actor(), item, "Only this.")
      assert Import.notes_for(item) == [note]
      assert Import.notes_by_item([item]) == %{item.id => [note]}
    end
  end

  defp backdate(%QueueItemNote{id: id}, at) do
    {:ok, _} =
      Audit.transaction(test_actor(), "test.backdate_note", fn ->
        Repo.update_all(from(n in QueueItemNote, where: n.id == ^id), set: [inserted_at: at])
      end)
  end

  defp backdate_notes(%QueueItem{id: id}, at) do
    {:ok, _} =
      Audit.transaction(test_actor(), "test.backdate_notes", fn ->
        Repo.update_all(from(n in QueueItemNote, where: n.queue_item_id == ^id),
          set: [inserted_at: at]
        )
      end)
  end

  defp queued_as(%QueueItem{id: id}, kind, ref \\ "g1") do
    {:ok, _} =
      Audit.transaction(test_actor(), "test.queued_as", fn ->
        Repo.update_all(from(q in QueueItem, where: q.id == ^id),
          set: [kind: kind, statement_ref: ref]
        )
      end)
  end
end
