defmodule Gallformers.Import.QueueTest do
  @moduledoc """
  The admin queue (`9449` §5, Task 13): decisions recorded with who and
  when, decisions honoured when a batch is resolved and applied, the
  approval gate, phase 6 disputes, and generations outside their group.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.Queue
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Import.StableRef

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobata = plant_fixture(name: "Quercus lobata", parent: quercus)
    andricus = taxon_fixture(name: "Andricus", rank: :genus, kingdom: "Animalia")
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    legacy = source_fixture("Legacy", "1990")

    # Two Galls of the wasp that no generation tells apart.
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

    %{lobata: lobata, andricus: andricus, wasp: wasp, galls: galls}
  end

  # The fixture gall batch, its Host in full, its Gall without a generation.
  defp gall_batch do
    batch()
    |> unique_batch_id()
    |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
    |> update_in(["galls", Access.at(0), "identified_by"], &Map.delete(&1, "generation"))
  end

  defp statements(batch),
    do: batch |> Import.list_statements() |> Map.new(&{{&1.kind, &1.ref}, &1})

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  describe "decide_queue_item/3" do
    test "records the decision with who and when, and the statement follows it", ctx do
      package = package(gall: gall_batch()) |> with_review() |> deliver!()

      assert [%QueueItem{kind: :ambiguous_match, statement_ref: "g1"} = item] =
               Import.list_queue_items(package)

      [chosen, _other] = ctx.galls

      assert {:ok, %QueueItem{status: :decided} = decided} =
               Import.decide_queue_item(test_actor(), item, %{"gall_id" => chosen.id})

      assert decided.decision == %{"gall_id" => chosen.id}
      assert decided.decided_by_name == "test"
      assert %DateTime{} = decided.decided_at

      assert %BatchStatement{resolution: :resolved, gall_id: gall_id, method: "decision"} =
               statements(gall_row(package))[{:gall, "g1"}]

      assert gall_id == chosen.id

      # Resolving again keeps the decision.
      {:ok, package} = Import.resolve_package(test_actor(), package)
      assert Import.list_queue_items(package) == []
      assert statements(gall_row(package))[{:gall, "g1"}].gall_id == chosen.id

      {:ok, _} = Import.approve_package(test_actor(), package)
      assert [%{gall_id: ^gall_id}] = [statements(gall_row(package))[{:gall, "g1"}]]
      assert Enum.map(Catalog.gall_summary(chosen.id).hosts, & &1.taxon_id) == [ctx.lobata.id]
    end

    test "a decision must fit its item", ctx do
      package = package(gall: gall_batch()) |> with_review() |> deliver!()
      [item] = Import.list_queue_items(package)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Import.decide_queue_item(test_actor(), item, %{"taxon_id" => ctx.wasp.id})

      assert %{decision: [_]} = errors_on(changeset)

      assert {:error, %Ecto.Changeset{}} =
               Import.decide_queue_item(test_actor(), item, %{"gall_id" => -1})
    end

    test "a decided item cannot be decided again", ctx do
      package = package(gall: gall_batch()) |> with_review() |> deliver!()
      [item] = Import.list_queue_items(package)
      [chosen, _] = ctx.galls
      {:ok, decided} = Import.decide_queue_item(test_actor(), item, %{"gall_id" => chosen.id})

      assert {:error, :already_decided} =
               Import.decide_queue_item(test_actor(), decided, %{"skip" => true})
    end
  end

  describe "approve_package/2" do
    test "waits for open items" do
      package = package(gall: gall_batch()) |> with_review() |> deliver!()

      assert {:error, {:open_items, [%QueueItem{statement_ref: "g1"}]}} =
               Import.approve_package(test_actor(), package)

      assert Import.get_package!(package.id).status == :awaiting_review
    end

    test "skipping a Gall leaves its Facts out", ctx do
      package = package(gall: gall_batch()) |> with_review() |> deliver!()
      [item] = Import.list_queue_items(package)
      {:ok, _} = Import.decide_queue_item(test_actor(), item, %{"skip" => true})

      {:ok, _} = Import.approve_package(test_actor(), package)
      s = statements(gall_row(package))

      assert %BatchStatement{fact_id: nil, delta: nil} = s[{:fact, "f1"}]
      assert s[{:fact, "f1"}].detail["skipped"] =~ "g1"
      for gall <- ctx.galls, do: assert(Catalog.gall_summary(gall.id).hosts == [])
    end
  end

  describe "disputes" do
    test "a phase 6 dispute is queued, and dropping the statement leaves it out", ctx do
      [chosen, _] = ctx.galls

      finding = %{
        "batch" => "gall.json",
        "id" => "f2",
        "problem" => "unsupported",
        "reason" => "the quote does not name the Host",
        "response" => %{"decision" => "disagree", "reason" => "it does"}
      }

      package =
        package(gall: gall_batch())
        |> with_review([finding], responded: true)
        |> deliver!()

      assert [%QueueItem{statement_ref: "f2", subject: subject} = dispute] =
               Import.list_queue_items(package, kind: :dispute)

      assert [%{"reason" => "the quote does not name the Host"}] = subject["findings"]

      [ambiguous] = Import.list_queue_items(package, kind: :ambiguous_match)
      {:ok, _} = Import.decide_queue_item(test_actor(), ambiguous, %{"gall_id" => chosen.id})
      {:ok, _} = Import.decide_queue_item(test_actor(), dispute, %{"skip" => true})

      {:ok, _} = Import.approve_package(test_actor(), package)
      s = statements(gall_row(package))

      assert %BatchStatement{fact_id: nil} = s[{:fact, "f2"}]
      assert is_integer(s[{:fact, "f1"}].fact_id)
      assert Catalog.gall_summary(chosen.id).hosts == []
    end
  end

  describe "one decision per name per package" do
    # A taxonomy batch and a gall batch that both declare "Andricus ignotus",
    # a name the tree does not hold, under different refs.
    defp shared_name_package do
      taxonomy =
        taxonomy_batch()
        |> unique_batch_id()
        |> Map.put("taxa", [
          %{"ref" => "t7", "name_as_written" => "Andricus ignotus", "rank" => "species"}
        ])
        |> put_in(["acts", Access.at(0), "taxon"], "t7")

      gall = put_in(gall_batch(), ["taxa", Access.at(0), "name_as_written"], "Andricus ignotus")

      package(gall: gall, taxonomy: taxonomy) |> with_review() |> deliver!()
    end

    defp taxon_items(package),
      do:
        package
        |> Import.list_queue_items()
        |> Enum.filter(&String.starts_with?(&1.statement_ref, "t"))

    defp batch_row(package, file), do: Enum.find(Import.list_batches(package), &(&1.file == file))

    test "the name is queued once, for both batches" do
      package = shared_name_package()

      assert [%QueueItem{kind: :unresolved_name, statement_ref: "t7", subject: subject} = item] =
               taxon_items(package)

      assert item.batch_id == batch_row(package, "taxonomy.json").id
      assert subject["also"] == [%{"batch" => "gall.json", "ref" => "t1"}]

      # Resolving again keeps it once, and keeps its ID.
      {:ok, package} = Import.resolve_package(test_actor(), package)
      assert [%QueueItem{id: id}] = taxon_items(package)
      assert id == item.id
    end

    test "a name the gall batch uses as a Host is queued as its unresolved Host" do
      taxonomy =
        taxonomy_batch()
        |> unique_batch_id()
        |> Map.put("taxa", [
          %{"ref" => "t4", "name_as_written" => "Quercus ignota", "rank" => "species"}
        ])
        |> put_in(["acts", Access.at(0), "taxon"], "t4")

      gall = put_in(gall_batch(), ["taxa", Access.at(1), "name_as_written"], "Quercus ignota")
      package = package(gall: gall, taxonomy: taxonomy) |> with_review() |> deliver!()

      assert [%QueueItem{kind: :unresolved_host, statement_ref: "t2", subject: subject} = item] =
               taxon_items(package)

      assert item.batch_id == batch_row(package, "gall.json").id
      assert subject["also"] == [%{"batch" => "taxonomy.json", "ref" => "t4"}]
    end

    test "its decision carries to both batches, and the batch's Galls are matched again", ctx do
      package = shared_name_package()
      [item] = taxon_items(package)

      {:ok, _} = Import.decide_queue_item(test_actor(), item, %{"taxon_id" => ctx.wasp.id})

      for {file, ref} <- [{"taxonomy.json", "t7"}, {"gall.json", "t1"}] do
        assert %BatchStatement{resolution: :resolved, method: "decision", taxon_id: taxon_id} =
                 statements(batch_row(package, file))[{:taxon, ref}]

        assert taxon_id == ctx.wasp.id
      end

      # The Gall waited on its Inducer; now it is matched to the wasp's two Galls.
      assert %BatchStatement{resolution: :ambiguous, candidate_ids: candidates} =
               statements(batch_row(package, "gall.json"))[{:gall, "g1"}]

      assert Enum.sort(candidates) == Enum.sort(Enum.map(ctx.galls, & &1.id))
      assert taxon_items(package) == []

      assert [%QueueItem{kind: :ambiguous_match, statement_ref: "g1"}] =
               Import.list_queue_items(package)
    end

    test "a name can be decided new; a Host name can't" do
      package = shared_name_package()
      [%QueueItem{} = item] = taxon_items(package)

      assert {:ok, %QueueItem{status: :decided}} =
               Import.decide_queue_item(test_actor(), item, %{"new" => true})

      assert %BatchStatement{resolution: :new} =
               statements(batch_row(package, "taxonomy.json"))[{:taxon, "t7"}]

      host = %QueueItem{item | kind: :unresolved_host, status: :open}
      changeset = Queue.validate_decision(Ecto.Changeset.change(host), host, %{"new" => true})
      refute changeset.valid?
    end

    test "deciding an item a later resolution removed says it is gone", ctx do
      package = shared_name_package()
      [item] = taxon_items(package)
      Repo.delete!(item)

      assert {:error, :gone} =
               Import.decide_queue_item(test_actor(), item, %{"taxon_id" => ctx.wasp.id})
    end

    test "a logged decision on the other batch's copy replays onto the shared item", ctx do
      package = shared_name_package()
      [item] = taxon_items(package)

      entry = %{
        kind: :queue_decision,
        key: %{
          "package" => package.key,
          "batch_id" => batch_row(package, "gall.json").producer_batch_id,
          "kind" => "unresolved_name",
          "statement_ref" => "t1"
        },
        payload: %{"decision" => StableRef.encode_decision(%{"taxon_id" => ctx.wasp.id})}
      }

      assert {:ok, 1} = Replay.run([entry], actor: test_actor())
      assert %QueueItem{status: :decided} = Repo.reload!(item)
    end
  end

  describe "a name decided new under a chosen parent" do
    # A taxonomy batch naming "Andricus ignotus", which the tree does not
    # hold, with no placement act: decided new, it would be unplaced.
    defp new_name_package do
      taxonomy =
        taxonomy_batch()
        |> unique_batch_id()
        |> Map.put("taxa", [
          %{"ref" => "t7", "name_as_written" => "Andricus ignotus", "rank" => "species"}
        ])
        |> put_in(["acts", Access.at(0), "taxon"], "t7")

      package(gall: nil, taxonomy: taxonomy) |> with_review() |> deliver!()
    end

    defp name_item(package),
      do: Enum.find(Import.list_queue_items(package), &(&1.statement_ref == "t7"))

    defp name_statement(package) do
      package
      |> Import.list_batches()
      |> Enum.find(&(&1.file == "taxonomy.json"))
      |> statements()
      |> Map.fetch!({:taxon, "t7"})
    end

    defp created_taxon(package) do
      %BatchStatement{taxon_id: id} = name_statement(package)
      id && Gallformers.Taxa.get_taxon!(id)
    end

    defp valid_decision?(item, decision),
      do: Queue.validate_decision(Ecto.Changeset.change(item), item, decision).valid?

    test "the new taxon is created under the parent", ctx do
      package = new_name_package()
      decision = %{"new" => true, "parent_id" => ctx.andricus.id}

      assert {:ok, %QueueItem{decision: ^decision}} =
               Import.decide_queue_item(test_actor(), name_item(package), decision)

      {:ok, _} = Import.approve_package(test_actor(), package)

      taxon = created_taxon(package)
      assert Gallformers.Taxa.accepted_name(taxon) == "Andricus ignotus"
      assert taxon.parent_id == ctx.andricus.id

      assert %BatchStatement{flags: flags} = name_statement(package)
      refute "unplaced" in flags
    end

    test "without a parent it is created unplaced, as before" do
      package = new_name_package()
      {:ok, _} = Import.decide_queue_item(test_actor(), name_item(package), %{"new" => true})
      {:ok, _} = Import.approve_package(test_actor(), package)

      assert %{parent_id: nil} = created_taxon(package)
    end

    test "the parent must be a taxon ranked above the new one, and goes only with new", ctx do
      item = name_item(new_name_package())
      family = taxon_fixture(name: "Cynipidae", rank: :family, kingdom: "Animalia")

      assert valid_decision?(item, %{"new" => true, "parent_id" => ctx.andricus.id})
      assert valid_decision?(item, %{"new" => true, "parent_id" => family.id})
      refute valid_decision?(item, %{"new" => true, "parent_id" => ctx.wasp.id})
      refute valid_decision?(item, %{"new" => true, "parent_id" => -1})
      refute valid_decision?(item, %{"new" => true, "parent_id" => "Andricus"})
      refute valid_decision?(item, %{"taxon_id" => ctx.wasp.id, "parent_id" => ctx.andricus.id})
      refute valid_decision?(item, %{"skip" => true, "parent_id" => ctx.andricus.id})
      refute valid_decision?(item, %{"parent_id" => ctx.andricus.id})
    end

    test "the parent replays, by name" do
      package = new_name_package()
      # A genus name the test database holds once (it holds an "Andricus").
      genus = taxon_fixture(name: "Rcxandricus", rank: :genus, kingdom: "Animalia")

      {entries, parent_name} =
        logged_and_undone(fn ->
          {:ok, _} =
            Import.decide_queue_item(test_actor(), name_item(package), %{
              "new" => true,
              "parent_id" => genus.id
            })

          {:ok, _} = Import.approve_package(test_actor(), package)
          created_taxon(package).parent_id |> Gallformers.Taxa.accepted_name()
        end)

      assert parent_name == "Rcxandricus"
      assert created_taxon(package) == nil

      assert [%{"new" => true, "parent" => parent}] =
               for(%{kind: :queue_decision} = e <- entries, do: e.payload["decision"])

      assert parent == StableRef.taxon(genus.id)

      assert {:ok, _} = Replay.run(entries, actor: test_actor())
      assert created_taxon(package).parent_id == genus.id
    end
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

  describe "generations" do
    test "a generation outside its Inducer's groups is queued", ctx do
      seasonal = Enum.find(Catalog.list_generation_groups(), &(&1.name == "seasonal"))

      Repo.insert_all("generation_group_taxa", [
        %{group_id: seasonal.id, taxon_id: ctx.andricus.id}
      ])

      taxon_fixture(name: "Andricus novus", parent: ctx.andricus)

      gall =
        gall_batch()
        |> put_in(["taxa", Access.at(0), "name_as_written"], "Andricus novus")
        |> put_in(["galls", Access.at(0), "identified_by", "generation"], %{
          "value" => "agamic",
          "as_written" => "agamic"
        })
        |> put_in(["galls", Access.at(0), "new"], true)

      package = package(gall: gall) |> with_review() |> deliver!()
      assert Import.list_queue_items(package) == []
      {:ok, _} = Import.approve_package(test_actor(), package)

      assert [%QueueItem{statement_ref: "g1", subject: %{"generation" => "agamic"}}] =
               Import.list_queue_items(package, kind: :generation_outside_group)

      assert %BatchStatement{gall_id: gall_id} = statements(gall_row(package))[{:gall, "g1"}]
      assert Catalog.get_gall!(gall_id).name == "Andricus novus (agamic)"
    end
  end
end
