defmodule Gallformers.Import.ProposalsTest do
  @moduledoc """
  Proposals (`6611` Task 3): what accepting an item's proposal decides, per
  kind; rejecting a proposal (the item stays open, out of bulk accept) and
  restoring it; and accepting every proposal of a list of items at once,
  skipping rejected items, suggestions to check and items with no proposal.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.Proposals
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobata = plant_fixture(name: "Quercus lobata", parent: quercus)
    douglasii = plant_fixture(name: "Quercus douglasii", parent: quercus)
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

    %{lobata: lobata, douglasii: douglasii, wasp: wasp, gall: gall}
  end

  # Hosts: t2 a spelling variant of Quercus lobata (proposed), t4 of Quercus
  # douglasii (proposed), t5 near a WCVP name (a suggestion only), t6 nothing.
  defp gall_batch do
    hosts = [
      {"t4", "Quercus douglasiii", "f6"},
      {"t5", "Zzyzx wcvponli", "f7"},
      {"t6", "Quercus inexistens", "f8"}
    ]

    batch()
    |> unique_batch_id()
    |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobatus")
    |> Map.update!("taxa", fn taxa ->
      taxa ++
        for {ref, name, _f} <- hosts,
            do: %{"ref" => ref, "name_as_written" => name, "rank" => "species"}
    end)
    |> Map.update!("facts", fn facts ->
      facts ++
        for {ref, _name, id} <- hosts do
          %{
            "id" => id,
            "stance" => "confirm",
            "kind" => "relationship",
            "type" => "host_of",
            "subject" => ref,
            "object" => "g1",
            "evidence" => [%{"item" => "#/texts/2", "quote" => "Common on Q. lobata"}]
          }
        end
    end)
    |> Map.put("unmapped", [
      %{
        "term" => "pale tan",
        "slot" => "other",
        "gall" => "g1",
        "evidence" => [%{"item" => "#/texts/1", "quote" => "pale tan"}]
      }
    ])
  end

  @dispute %{
    "batch" => "gall.json",
    "id" => "f3",
    "problem" => "unsupported",
    "reason" => "no parasitoid is named",
    "response" => %{"decision" => "disagree", "reason" => "Torymus is"}
  }

  defp deliver,
    do: package(gall: gall_batch()) |> with_review([@dispute], responded: true) |> deliver!()

  defp items(package),
    do: Map.new(Import.list_queue_items(package, status: :all), &{&1.statement_ref, &1})

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  defp statement(package, ref),
    do:
      package
      |> gall_row()
      |> Import.list_statements()
      |> Enum.find(&(&1.kind == :taxon and &1.ref == ref))

  defp synonyms(taxon), do: taxon |> Taxa.list_synonyms() |> Enum.map(& &1.name)

  describe "the proposed decision, by kind" do
    defp proposed(kind, ref, proposal, subject \\ %{}),
      do:
        Proposals.proposed(%QueueItem{
          kind: kind,
          statement_ref: ref,
          subject: subject,
          proposal: proposal
        })

    test "a name: its proposed taxon; a suggestion without one is weak" do
      for kind <- [:ambiguous_match, :unresolved_name, :taxonomy_disagreement] do
        assert proposed(kind, "t1", %{"candidate_ids" => [3, 4], "proposed" => 4}) ==
                 {:ok, %{"taxon_id" => 4}}

        assert proposed(kind, "t1", %{"candidate_ids" => [3, 4]}) == {:none, :weak}
        assert proposed(kind, "t1", %{"candidate_ids" => []}) == {:none, :no_proposal}
      end
    end

    test "an unresolved Host: the plant, adding the Source's spelling as its synonym" do
      host = %{"host" => true, "name_as_written" => "Quercus lobatus"}

      assert proposed(:unresolved_host, "t2", %{"candidate_ids" => [5], "proposed" => 5}, host) ==
               {:ok, %{"taxon_id" => 5, "add_synonym" => true}}

      near = %{"source" => "wcvp", "match" => "edit_distance", "wcvp_id" => "500"}

      assert proposed(
               :unresolved_host,
               "t2",
               %{"candidate_ids" => [], "suggestions" => [near]},
               host
             ) ==
               {:none, :weak}

      assert proposed(:unresolved_host, "t2", %{"candidate_ids" => []}, host) ==
               {:none, :no_proposal}

      # A Host name several plants hold already is one of their names.
      assert proposed(:ambiguous_match, "t2", %{"candidate_ids" => [5, 6], "proposed" => 5}, host) ==
               {:ok, %{"taxon_id" => 5}}
    end

    test "a Gall: its proposed Gall, or new" do
      for kind <- [:ambiguous_match, :unresolved_name] do
        assert proposed(kind, "g1", %{"candidate_ids" => [7], "proposed" => 7}) ==
                 {:ok, %{"gall_id" => 7}}

        assert proposed(kind, "g1", %{"candidate_ids" => [7, 8]}) == {:none, :weak}
      end
    end

    test "a Gall proposed new is only a suggestion: bulk accept could create duplicates" do
      # `c8c3` item 6: Gallformers may hold it under another name (an undescribed Gall named
      # by its Host's epithet), so the curator decides each one.
      assert proposed(:unresolved_name, "g1", %{"candidate_ids" => [], "proposed" => "new"}) ==
               {:none, :weak}
    end

    test "a Gall: a best match, an undescribed match or one with a conflict is never firm" do
      # `d213` Task 4: the curator decides.
      assert proposed(:ambiguous_match, "g1", %{"candidate_ids" => [7], "best" => 7}) ==
               {:none, :weak}

      assert proposed(:undescribed_gall, "g1", %{"candidate_ids" => [7], "proposed" => 7}) ==
               {:none, :weak}

      assert proposed(:ambiguous_match, "g1", %{
               "candidate_ids" => [7],
               "proposed" => 7,
               "conflicts" => ["where"]
             }) == {:none, :weak}
    end

    test "what was set aside: keep it" do
      assert proposed(:set_aside_statement, "u:other:tan", %{"keep" => true}) ==
               {:ok, %{"keep" => true}}
    end

    test "a Trait term: the category the readers agree on, else none" do
      assert proposed(:trait_term, "u:color:tan", %{"category" => "tan"}) ==
               {:ok, %{"category" => "tan"}}

      assert proposed(:trait_term, "u:color:tan", %{}) == {:none, :no_proposal}
    end

    test "a rename: accept it, unless another Gall has the name" do
      assert proposed(:gall_rename, nil, %{"collision" => false, "to" => "B"}) ==
               {:ok, %{"accept" => true}}

      assert proposed(:gall_rename, nil, %{"collision" => true, "to" => "B"}) == {:none, :weak}
    end

    test "disputes, the Source and what is only acknowledged have none" do
      assert proposed(:dispute, "f3", %{}) == {:none, :no_proposal}
      assert proposed(:ambiguous_match, "source", %{"candidate_ids" => [1, 2]}) == {:none, :weak}
      assert proposed(:unresolved_name, "retracts", %{}) == {:none, :no_proposal}
      assert proposed(:same_date_conflict, "f3", %{}) == {:none, :no_proposal}
      assert proposed(:generation_outside_group, "g1", %{}) == {:none, :no_proposal}
      assert proposed(:taxonomy_disagreement, "a1", %{}) == {:none, :no_proposal}
    end

    test "a rejected proposal is none" do
      item = %QueueItem{
        kind: :ambiguous_match,
        statement_ref: "t1",
        proposal: %{"candidate_ids" => [3], "proposed" => 3},
        proposal_rejected_at: DateTime.utc_now(:second)
      }

      assert Proposals.proposed(item) == {:none, :rejected}
    end
  end

  describe "the queued items" do
    test "Hosts with a spelling variant are proposed; a WCVP near name is a suggestion", ctx do
      items = items(deliver())

      assert %QueueItem{kind: :unresolved_host, proposal: %{"proposed" => lobata}} = items["t2"]
      assert lobata == ctx.lobata.id
      assert %QueueItem{proposal: %{"proposed" => douglasii}} = items["t4"]
      assert douglasii == ctx.douglasii.id

      assert %QueueItem{proposal: %{"suggestions" => [%{"match" => "edit_distance"}]}} =
               items["t5"]

      refute Map.has_key?(items["t5"].proposal, "proposed")
      assert items["t6"].proposal == %{"candidate_ids" => []}
    end
  end

  describe "reject_proposal/2 and restore_proposal/2" do
    test "the item stays open, its proposal marked rejected, then restored" do
      package = deliver()
      item = items(package)["t4"]

      assert {:ok, %QueueItem{status: :open} = rejected} =
               Import.reject_proposal(test_actor(), item)

      assert %DateTime{} = rejected.proposal_rejected_at
      assert rejected.proposal_rejected_by_name == "test"
      assert Proposals.proposed(rejected) == {:none, :rejected}

      # A fresh resolution keeps the rejection while the proposal is the same.
      {:ok, package} = Import.resolve_package(test_actor(), package)
      assert %DateTime{} = items(package)["t4"].proposal_rejected_at

      assert {:ok, restored} = Import.restore_proposal(test_actor(), rejected)
      assert restored.proposal_rejected_at == nil
      assert restored.proposal_rejected_by_name == nil
      assert {:ok, %{"taxon_id" => _}} = Proposals.proposed(restored)
    end

    test "a new proposal clears the rejection" do
      package = deliver()
      {:ok, item} = Import.reject_proposal(test_actor(), items(package)["t4"])

      Repo.update_all(from(q in QueueItem, where: q.id == ^item.id),
        set: [proposal: %{"candidate_ids" => [], "proposed" => -1}]
      )

      {:ok, package} = Import.resolve_package(test_actor(), package)
      assert items(package)["t4"].proposal_rejected_at == nil
    end

    test "only an open item with a proposal or a suggestion", ctx do
      package = deliver()
      items = items(package)

      assert {:ok, _} = Import.reject_proposal(test_actor(), items["t5"])
      assert {:error, :no_proposal} = Import.reject_proposal(test_actor(), items["t6"])
      assert {:error, :no_proposal} = Import.reject_proposal(test_actor(), items["f3"])

      {:ok, decided} =
        Import.decide_queue_item(test_actor(), items["t2"], %{"taxon_id" => ctx.lobata.id})

      assert {:error, :already_decided} = Import.reject_proposal(test_actor(), decided)
    end
  end

  describe "accept_proposals/2" do
    test "decides each proposal; rejected, weak and proposal-less items stay open", ctx do
      package = deliver()
      {:ok, _} = Import.reject_proposal(test_actor(), items(package)["t4"])

      assert {:ok, %{decided: decided, skipped: skipped}} =
               Import.accept_proposals(test_actor(), Import.list_queue_items(package))

      assert decided |> Enum.map(& &1.statement_ref) |> Enum.sort() == ["t2", "u:other:pale tan"]

      assert Map.new(skipped, fn {item, reason} -> {item.statement_ref, reason} end) == %{
               "t4" => :rejected,
               "t5" => :weak,
               "t6" => :no_proposal,
               "f3" => :no_proposal
             }

      items = items(package)
      assert items["t2"].decision == %{"taxon_id" => ctx.lobata.id, "add_synonym" => true}
      assert items["u:other:pale tan"].decision == %{"keep" => true}
      for ref <- ~w(t4 t5 t6 f3), do: assert(items[ref].status == :open)

      # Honoured: the Host resolves, with the Source's spelling as a synonym.
      assert "Quercus lobatus" in synonyms(ctx.lobata)
      assert %{resolution: :resolved, taxon_id: taxon_id} = statement(package, "t2")
      assert taxon_id == ctx.lobata.id

      # Each decision is logged like any other.
      logged =
        for %{kind: :queue_decision, key: key} <- Import.list_replay_entries(),
            key["package"] == package.key,
            do: key["statement_ref"]

      assert Enum.sort(logged) == ["t2", "u:other:pale tan"]
    end

    test "skips items decided or gone since they were listed", ctx do
      package = deliver()
      items = items(package)

      {:ok, _} =
        Import.decide_queue_item(test_actor(), items["t2"], %{"taxon_id" => ctx.lobata.id})

      Repo.delete!(items["u:other:pale tan"])

      assert {:ok, %{decided: [], skipped: skipped}} =
               Import.accept_proposals(test_actor(), [items["t2"], items["u:other:pale tan"]])

      assert Enum.map(skipped, &elem(&1, 1)) == [:already_decided, :gone]
    end

    test "the decisions replay to the same result", ctx do
      package = deliver()
      {:ok, _} = Import.reject_proposal(test_actor(), items(package)["t4"])
      listed = Import.list_queue_items(package)

      {entries, after_accept} =
        logged_and_undone(fn ->
          {:ok, _} = Import.accept_proposals(test_actor(), listed)
          snapshot(package, ctx)
        end)

      assert after_accept != snapshot(package, ctx)
      assert {:ok, _count} = Replay.run(entries, actor: test_actor())
      assert_replays_again(entries, test_actor())
      assert snapshot(package, ctx) == after_accept
    end
  end

  # Runs `fun`, then undoes it: the replay entries it appended, and what it returned.
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

  defp snapshot(package, ctx) do
    decisions =
      for item <- Import.list_queue_items(package, status: :all),
          do: {item.kind, item.statement_ref, item.status, item.decision}

    {Enum.sort(decisions), Enum.sort(synonyms(ctx.lobata)),
     Map.take(statement(package, "t2"), [:resolution, :taxon_id])}
  end
end
