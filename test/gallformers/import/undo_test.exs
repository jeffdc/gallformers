defmodule Gallformers.Import.UndoTest do
  @moduledoc """
  Undo of a decided question on a package's review steps (matter `f14c`,
  "Undo rule"): allowed only while nothing depends on the decision — the
  Source isn't approved yet, and nothing the decision changed (a synonym
  added, a plant created, a name split) has been edited since, per the
  audit log. Undo reverses what the decision changed in the tree, reopens
  the item and resolves the package again; it is audited and logged for
  replay, so a replay ends in the same state.

  A test runs in one database transaction, so the decision's audit
  transaction holds everything the test did; a later edit by another
  curator is written into the audit trail directly, as Carbonite would
  have.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Import.ReplayEntry
  alias Gallformers.Ranges.Wcvp
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobata = plant_fixture(name: "Quercus lobata", parent: quercus)
    andricus = Taxa.get_by_legacy_id(:taxonomy, 33)
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    legacy = source_fixture("Legacy", "1990")
    gall = gall_fixture(name: "Andricus quercuscalifornicus (agamic)", generation: "agamic")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
        confirm(legacy)
      )

    %{quercus: quercus, lobata: lobata, wasp: wasp, gall: gall}
  end

  defp deliver(host_name) do
    gall =
      batch() |> unique_batch_id() |> put_in(["taxa", Access.at(1), "name_as_written"], host_name)

    package(gall: gall) |> with_review() |> deliver!()
  end

  defp host_item(package),
    do: Enum.find(Import.list_queue_items(package, status: :all), &(&1.statement_ref == "t2"))

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  defp host_statement(package),
    do:
      package
      |> gall_row()
      |> Import.list_statements()
      |> Enum.find(&(&1.kind == :taxon and &1.ref == "t2"))

  defp synonyms(taxon), do: taxon |> Taxa.list_synonyms() |> Enum.map(& &1.name)

  defp decide!(item, decision) do
    {:ok, item} = Import.decide_queue_item(test_actor(), item, decision)
    item
  end

  defp entries_since(since), do: for(e <- Import.list_replay_entries(), e.id > since, do: e)
  defp last_entry_id, do: Enum.reduce(Import.list_replay_entries(), 0, &max(&1.id, &2))

  # Another curator's later change to a row, in the audit trail as Carbonite
  # records it (its table's primary key included).
  defp edited_later!(who, table, pk, data, op \\ "update") do
    id = System.unique_integer([:positive, :monotonic]) + 3_000_000_000_000

    at =
      NaiveDateTime.utc_now() |> NaiveDateTime.add(60) |> NaiveDateTime.truncate(:second)

    Repo.query!(
      "INSERT INTO carbonite_default.transactions (id, xact_id, meta, inserted_at) VALUES ($1, $2::xid8, $3, $4)",
      [id, id, %{actor: %{type: "user", id: 99, name: who}, operation: "test.edit"}, at]
    )

    Repo.query!(
      """
      INSERT INTO carbonite_default.changes
        (transaction_id, transaction_xact_id, op, table_prefix, table_name, table_pk, data, changed)
      VALUES ($1, $2::xid8, $3::text::carbonite_default.change_op, 'public', $4, $5, $6, '{}')
      """,
      [id, id, op, table, Enum.map(List.wrap(pk), &to_string/1), data]
    )

    at
  end

  # Runs `fun`, returning the replay entries it logged and its result, then
  # rolls it all back, so the entries can be replayed onto the state before.
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

  defp snapshot(package) do
    statement = host_statement(package)
    taxon = statement.taxon_id && Taxa.get_taxon!(statement.taxon_id)

    {statement.resolution, taxon && Taxa.accepted_name(taxon), gall_row(package).status,
     Enum.map(Import.list_queue_items(package, status: :all), &{&1.statement_ref, &1.status})}
  end

  describe "a decision with no change outside the package" do
    test "reopens the item and resolves the package again", ctx do
      package = deliver("Quercus lobatus")
      before = snapshot(package)
      item = decide!(host_item(package), %{"taxon_id" => ctx.lobata.id})
      assert %{resolution: :resolved} = host_statement(package)
      since = last_entry_id()

      assert {:ok, %QueueItem{status: :open, decision: nil, decided_at: nil} = undone} =
               Import.undo_decision(test_actor(), item)

      assert undone.id == item.id
      assert snapshot(package) == before
      assert gall_row(package).status == :blocked

      assert [%ReplayEntry{kind: :queue_decision_undone, key: key}] = entries_since(since)
      assert key["package"] == package.key
      assert key["statement_ref"] == "t2"
    end

    test "is refused for an open item, and for one gone", ctx do
      package = deliver("Quercus lobatus")
      item = host_item(package)

      assert {:error, :not_decided} = Import.undo_decision(test_actor(), item)

      decided = decide!(item, %{"taxon_id" => ctx.lobata.id})
      Repo.delete!(decided)
      assert {:error, :gone} = Import.undo_decision(test_actor(), decided)
    end

    test "is refused once the Source is approved", ctx do
      package = deliver("Quercus lobatus")
      item = decide!(host_item(package), %{"taxon_id" => ctx.lobata.id})

      {:ok, %{status: :approved}} =
        Import.approve_package(test_actor(), Import.get_package!(package.id))

      assert {:error, :source_approved} = Import.undo_decision(test_actor(), item)
      assert Import.undo_refusal(:source_approved).text =~ "approved"
    end

    test "replays: the decision and its undo end where the item was", ctx do
      package = deliver("Quercus lobatus")
      before = snapshot(package)

      {entries, after_undo} =
        logged_and_undone(fn ->
          item = decide!(host_item(package), %{"taxon_id" => ctx.lobata.id})
          {:ok, _} = Import.undo_decision(test_actor(), item)
          snapshot(package)
        end)

      assert after_undo == before
      assert Enum.map(entries, & &1.kind) == [:queue_decision, :queue_decision_undone]
      assert {:ok, 2} = Replay.run(entries, actor: test_actor())
      assert snapshot(package) == before
    end
  end

  describe "a decision that added a synonym" do
    test "removes the synonym it added", ctx do
      package = deliver("Quercus lobatus")
      item = decide!(host_item(package), %{"taxon_id" => ctx.lobata.id, "add_synonym" => true})
      assert "Quercus lobatus" in synonyms(ctx.lobata)

      assert {:ok, %QueueItem{status: :open}} = Import.undo_decision(test_actor(), item)

      assert synonyms(ctx.lobata) == []
      assert %{resolution: :unresolved, taxon_id: nil} = host_statement(package)
      assert gall_row(package).status == :blocked
    end

    test "keeps a synonym the plant held before", ctx do
      {:ok, _} = Import.record_synonym_added(test_actor(), ctx.lobata.id, "Quercus lobatus")
      package = deliver("Quercus lobatusa")

      item =
        decide!(host_item(package), %{"taxon_id" => ctx.lobata.id, "add_synonym" => true})

      assert Enum.sort(synonyms(ctx.lobata)) == ["Quercus lobatus", "Quercus lobatusa"]

      {:ok, _} = Import.undo_decision(test_actor(), item)
      assert synonyms(ctx.lobata) == ["Quercus lobatus"]
    end

    test "is refused once the synonym was edited since, saying by whom", ctx do
      package = deliver("Quercus lobatus")
      item = decide!(host_item(package), %{"taxon_id" => ctx.lobata.id, "add_synonym" => true})
      [synonym] = Taxa.list_synonyms(ctx.lobata)

      edited_later!("Bea Curator", "taxon_names", synonym.id, %{
        "id" => synonym.id,
        "taxon_id" => ctx.lobata.id,
        "name" => "Quercus lobatus"
      })

      assert {:error, {:edited, edit}} = Import.undo_decision(test_actor(), item)
      assert edit.by == "Bea Curator"
      assert edit.link == {:taxon, ctx.lobata.id}
      assert Import.undo_refusal({:edited, edit}).text =~ "was edited by Bea Curator"

      # Nothing changed.
      assert %QueueItem{status: :decided} = Repo.get!(QueueItem, item.id)
      assert synonyms(ctx.lobata) == ["Quercus lobatus"]
    end

    test "a later change to something the decision didn't change doesn't block", ctx do
      package = deliver("Quercus lobatus")
      item = decide!(host_item(package), %{"taxon_id" => ctx.lobata.id, "add_synonym" => true})
      edited_later!("Bea Curator", "taxon_names", 987_654_321, %{"id" => 987_654_321})

      assert {:ok, %QueueItem{status: :open}} = Import.undo_decision(test_actor(), item)
    end

    test "replays to the same state", ctx do
      package = deliver("Quercus lobatus")
      before = snapshot(package)

      {entries, _} =
        logged_and_undone(fn ->
          item =
            decide!(host_item(package), %{"taxon_id" => ctx.lobata.id, "add_synonym" => true})

          {:ok, _} = Import.undo_decision(test_actor(), item)
        end)

      assert {:ok, _} = Replay.run(entries, actor: test_actor())
      assert synonyms(ctx.lobata) == []
      assert snapshot(package) == before
    end
  end

  describe "a decision that added a plant from WCVP" do
    test "deletes the plant, and the genus and family it was added under" do
      package = deliver("Zzyzx wcvponli")
      item = decide!(host_item(package), %{"wcvp_id" => "500"})
      plant_id = item.decision["taxon_id"]
      lineage = plant_id |> Taxa.get_taxon!() |> Taxa.lineage() |> Enum.map(& &1.taxon_id)

      assert {:ok, %QueueItem{status: :open}} = Import.undo_decision(test_actor(), item)

      assert Wcvp.linked_taxon_ids("500") == []
      for id <- Enum.take(lineage, -3), do: assert(Taxa.get_taxon(id) == nil)
      assert %{resolution: :unresolved, taxon_id: nil} = host_statement(package)
    end

    test "is refused once something was added to the plant since" do
      package = deliver("Zzyzx wcvponli")
      item = decide!(host_item(package), %{"wcvp_id" => "500"})
      plant_id = item.decision["taxon_id"]

      edited_later!(
        "Bea Curator",
        "taxon_names",
        876_543_210,
        %{"id" => 876_543_210, "taxon_id" => plant_id, "name" => "Zzyzx otheri"},
        "insert"
      )

      assert {:error, {:edited, %{by: "Bea Curator", link: {:taxon, ^plant_id}}}} =
               Import.undo_decision(test_actor(), item)

      assert %Taxa.Taxon{} = Taxa.get_taxon(plant_id)
    end

    test "replays to the same state" do
      package = deliver("Zzyzx wcvponli")
      before = snapshot(package)

      {entries, _} =
        logged_and_undone(fn ->
          item = decide!(host_item(package), %{"wcvp_id" => "500"})
          {:ok, _} = Import.undo_decision(test_actor(), item)
        end)

      assert {:ok, _} = Replay.run(entries, actor: test_actor())
      assert Wcvp.linked_taxon_ids("500") == []
      assert snapshot(package) == before
    end
  end

  describe "a decision that split a name off the tree's synonym" do
    setup do
      andricus = taxon_fixture(name: "Fixtandricus", rank: :genus, kingdom: "Animalia")
      callirhytis = taxon_fixture(name: "Fixtrhytis", rank: :genus, kingdom: "Animalia")
      held = taxon_fixture(name: "Fixtrhytis clarkei", parent: callirhytis)
      other = taxon_fixture(name: "Fixtandricus dimorphus", parent: andricus)
      {:ok, _} = Taxa.add_synonym(test_actor(), held, "Fixtandricus wisliceni")
      %{held: held, other: other}
    end

    defp synonym_package(name) do
      taxonomy =
        taxonomy_batch()
        |> unique_batch_id()
        |> put_in(["taxa", Access.at(0), "name_as_written"], name)

      package(gall: nil, taxonomy: taxonomy) |> with_review() |> deliver!()
    end

    defp synonym_item(package) do
      Enum.find(
        Import.list_queue_items(package, kind: :taxonomy_disagreement, status: :all),
        &(&1.statement_ref == "t1")
      )
    end

    test "split: deletes the new species and gives the name back to the taxon", ctx do
      package = synonym_package("Fixtandricus wisliceni")
      item = decide!(synonym_item(package), %{"split" => true})
      species_id = item.decision["taxon_id"]

      assert {:ok, %QueueItem{status: :open}} = Import.undo_decision(test_actor(), item)

      assert Taxa.get_taxon(species_id) == nil
      assert synonyms(ctx.held) == ["Fixtandricus wisliceni"]
      assert %QueueItem{status: :open} = synonym_item(package)
    end

    test "synonym_of: moves the name back", ctx do
      package = synonym_package("Fixtandricus wisliceni")
      item = decide!(synonym_item(package), %{"synonym_of" => ctx.other.id})

      {:ok, _} = Import.undo_decision(test_actor(), item)

      assert synonyms(ctx.other) == []
      assert synonyms(ctx.held) == ["Fixtandricus wisliceni"]
    end

    test "an undone split is not carried over at cutover", _ctx do
      package = synonym_package("Fixtandricus wisliceni")
      item = decide!(synonym_item(package), %{"split" => true})
      {:ok, _} = Import.undo_decision(test_actor(), item)

      assert {:ok, %{decisions: 0}} =
               Import.carry_over_taxonomy_decisions(test_actor(), Import.list_replay_entries())
    end

    test "split replays to the same state", ctx do
      package = synonym_package("Fixtandricus wisliceni")

      {entries, _} =
        logged_and_undone(fn ->
          item = decide!(synonym_item(package), %{"split" => true})
          {:ok, _} = Import.undo_decision(test_actor(), item)
        end)

      assert {:ok, _} = Replay.run(entries, actor: test_actor())
      assert synonyms(ctx.held) == ["Fixtandricus wisliceni"]

      assert {:ok, %{matched_name: %{status: :synonym}}} =
               Taxa.resolve_name("Fixtandricus wisliceni")

      assert %QueueItem{status: :open} = synonym_item(package)
    end
  end

  describe "a group of disputes decided together" do
    setup do
      ids = for n <- 10..12, do: "f#{n}"

      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
        |> Map.update!("facts", fn facts ->
          facts ++
            for id <- ids do
              %{
                "id" => id,
                "stance" => "confirm",
                "kind" => "relationship",
                "type" => "host_of",
                "subject" => "t2",
                "object" => "g1",
                "evidence" => [%{"item" => "#/texts/2", "quote" => "Common on Q. lobata"}]
              }
            end
        end)

      findings =
        for id <- ids do
          %{
            "batch" => "gall.json",
            "id" => id,
            "problem" => "unsupported",
            "reason" => "the quote does not say so",
            "response" => %{"decision" => "disagree", "reason" => "it does"}
          }
        end

      package = package(gall: gall) |> with_review(findings, responded: true) |> deliver!()
      %{package: package}
    end

    test "are undone all together, or not at all", %{package: package} do
      disputes = fn -> Import.list_queue_items(package, kind: :dispute, status: :all) end
      {:ok, decided} = Import.decide_group(test_actor(), disputes.(), %{"skip" => true})

      assert {:ok, undone} = Import.undo_decisions(test_actor(), decided)
      assert length(undone) == 3
      assert disputes.() |> Enum.map(& &1.status) |> Enum.uniq() == [:open]

      # The last is gone: the first two, undone, are rolled back with it.
      {:ok, decided} = Import.decide_group(test_actor(), disputes.(), %{"keep" => true})
      Repo.delete!(List.last(decided))

      assert {:error, :gone} = Import.undo_decisions(test_actor(), decided)
      assert disputes.() |> Enum.map(& &1.status) |> Enum.uniq() == [:decided]
    end
  end

  describe "a question the decision raised" do
    test "decided since, blocks the undo", ctx do
      package = deliver("Quercus lobatus")
      item = decide!(host_item(package), %{"taxon_id" => ctx.lobata.id})

      # A question the decision's resolution raised, decided by another curator later.
      raised =
        Repo.insert!(%QueueItem{
          package_id: package.id,
          kind: :undescribed_gall,
          statement_ref: "g9",
          subject: %{}
        })

      edited_later!("Bea Curator", "queue_items", raised.id, %{
        "id" => raised.id,
        "status" => "decided"
      })

      assert {:error, {:edited, %{by: "Bea Curator"} = edit}} =
               Import.undo_decision(test_actor(), item)

      assert Import.undo_refusal({:edited, edit}).text =~ "question"
    end
  end
end
