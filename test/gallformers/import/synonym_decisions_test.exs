defmodule Gallformers.Import.SynonymDecisionsTest do
  @moduledoc """
  Synonymy changed from the review page (matter `d213`, Task 9): on a
  synonym question (the tree holds the Source's name as a synonym of X, and
  the Source treats it as valid), "the Source is right: change the tree"
  makes the name a species of its own again, under its genus, or moves it
  to another species. Both are tree edits for every Source, through the
  taxonomy edit log, so they replay; the Source's statements go on the
  result, and the Facts already on X stay.

  Not async: packages create Sources (unique titles).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    andricus = taxon_fixture(name: "Fixtandricus", rank: :genus, kingdom: "Animalia")
    callirhytis = taxon_fixture(name: "Fixtrhytis", rank: :genus, kingdom: "Animalia")
    held = taxon_fixture(name: "Fixtrhytis clarkei", parent: callirhytis)
    other = taxon_fixture(name: "Fixtandricus dimorphus", parent: andricus)
    {:ok, _} = Taxa.add_synonym(test_actor(), held, "Fixtandricus wisliceni")
    {:ok, _} = Taxa.add_synonym(test_actor(), held, "Zzfixtus wisliceni")
    %{andricus: andricus, held: held, other: other}
  end

  # A taxonomy batch naming `name` as a valid species.
  defp deliver(name) do
    taxonomy =
      taxonomy_batch()
      |> unique_batch_id()
      |> put_in(["taxa", Access.at(0), "name_as_written"], name)

    package(gall: nil, taxonomy: taxonomy) |> with_review() |> deliver!()
  end

  defp item(package) do
    [%QueueItem{statement_ref: "t1"} = item] =
      Import.list_queue_items(package, kind: :taxonomy_disagreement)

    item
  end

  defp statement(package) do
    package
    |> Import.list_batches()
    |> Enum.find(&(&1.file == "taxonomy.json"))
    |> Import.list_statements()
    |> Enum.find(&(&1.kind == :taxon and &1.ref == "t1"))
  end

  defp synonyms(taxon), do: taxon |> Taxa.list_synonyms() |> Enum.map(& &1.name)

  defp last_entry_id, do: Enum.reduce(Import.list_replay_entries(), 0, &max(&1.id, &2))

  defp entry_kinds(since),
    do: for(e <- Import.list_replay_entries(), e.id > since, do: e.kind)

  describe "split: a species of its own again" do
    test "creates the species under its genus, the name moved from the held taxon", ctx do
      package = deliver("FIXTANDRICUS WISLICENI")
      since = last_entry_id()

      assert {:ok, %QueueItem{status: :decided, decision: decision}} =
               Import.decide_queue_item(test_actor(), item(package), %{"split" => true})

      assert %{"split" => true, "taxon_id" => id} = decision
      taxon = Taxa.get_taxon!(id)
      assert Taxa.accepted_name(taxon) == "Fixtandricus wisliceni"
      assert taxon.rank == :species
      assert taxon.parent_id == ctx.andricus.id
      assert taxon.kingdom == "Animalia"
      assert synonyms(ctx.held) == ["Zzfixtus wisliceni"]

      # The Source's statements go on the new species.
      assert %{resolution: :resolved, taxon_id: ^id} = statement(package)
      assert Import.list_queue_items(package, kind: :taxonomy_disagreement) == []
      assert entry_kinds(since) == [:taxonomy_edit, :taxonomy_edit, :queue_decision]
    end

    test "is refused when the tree doesn't hold the genus", ctx do
      package = deliver("Zzfixtus wisliceni")

      assert {:error, changeset} =
               Import.decide_queue_item(test_actor(), item(package), %{"split" => true})

      assert {message, _} = changeset.errors[:decision]
      assert message =~ "Zzfixtus"
      assert "Zzfixtus wisliceni" in synonyms(ctx.held)
    end
  end

  describe "synonym_of: a synonym of another species" do
    test "moves the name to the other species; the statements go on it", ctx do
      package = deliver("Fixtandricus wisliceni")

      assert {:ok, %QueueItem{decision: decision}} =
               Import.decide_queue_item(test_actor(), item(package), %{
                 "synonym_of" => ctx.other.id
               })

      assert decision["taxon_id"] == ctx.other.id
      assert synonyms(ctx.other) == ["Fixtandricus wisliceni"]
      refute "Fixtandricus wisliceni" in synonyms(ctx.held)
      assert %{resolution: :resolved, taxon_id: id} = statement(package)
      assert id == ctx.other.id
    end

    test "must be another taxon", ctx do
      package = deliver("Fixtandricus wisliceni")

      assert {:error, _} =
               Import.decide_queue_item(test_actor(), item(package), %{
                 "synonym_of" => ctx.held.id
               })

      assert {:error, _} =
               Import.decide_queue_item(test_actor(), item(package), %{"synonym_of" => -1})
    end
  end

  describe "replay" do
    test "a split replays to the same tree and resolution", ctx do
      package = deliver("Fixtandricus wisliceni")

      {entries, after_decision} =
        logged_and_undone(fn ->
          {:ok, _} = Import.decide_queue_item(test_actor(), item(package), %{"split" => true})
          snapshot(package, ctx)
        end)

      assert snapshot(package, ctx) != after_decision
      assert {:ok, 3} = Replay.run(entries, actor: test_actor())
      assert_replays_again(entries, test_actor())
      assert snapshot(package, ctx) == after_decision
    end

    test "a move replays to the same tree and resolution", ctx do
      package = deliver("Fixtandricus wisliceni")

      {entries, after_decision} =
        logged_and_undone(fn ->
          {:ok, _} =
            Import.decide_queue_item(test_actor(), item(package), %{
              "synonym_of" => ctx.other.id
            })

          snapshot(package, ctx)
        end)

      assert snapshot(package, ctx) != after_decision
      assert {:ok, 3} = Replay.run(entries, actor: test_actor())
      assert_replays_again(entries, test_actor())
      assert snapshot(package, ctx) == after_decision
    end
  end

  defp snapshot(package, ctx) do
    s = statement(package)
    taxon = s.taxon_id && Taxa.get_taxon!(s.taxon_id)

    %{
      resolution: s.resolution,
      taxon: taxon && {Taxa.accepted_name(taxon), taxon.parent_id},
      held: synonyms(ctx.held),
      other: synonyms(ctx.other)
    }
  end

  defp logged_and_undone(fun) do
    before = MapSet.new(Import.list_replay_entries(), & &1.id)

    {:error, {:undone, entries, result}} =
      Repo.transaction(fn ->
        result = fun.()
        entries = Enum.reject(Import.list_replay_entries(), &MapSet.member?(before, &1.id))
        Repo.rollback({:undone, entries, result})
      end)

    {entries, result}
  end
end
