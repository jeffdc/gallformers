defmodule Gallformers.Import.TaxonomyCarryOverTest do
  @moduledoc """
  Phase 1 decisions carry over (matter `f923` Task 9, "Phase 1 decisions
  carry over"): at cutover, a phase 1 "change the tree" decision on a
  synonym question (`Gallformers.Import.SynonymDecisions`: a split, or a
  move to another taxon) becomes the acceptance of the Source's matching
  taxonomic statements, those the same package recorded about the name
  that the tree now holds; and an act a curator followed (its question in
  the review, the tree since changed to what it says) is accepted too. The
  tree is unchanged and follows the Facts. What the Source's statements
  can't carry is reported for a curator. Running it again changes nothing.

  Not async: packages create Sources (unique titles).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.TaxonomyCarryOver
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.ActFacts.SynonymyFact
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Sync

  setup :audit_test_metadata

  @evidence [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]

  setup do
    legacy = Sources.get_legacy_data_source()
    family = taxon_fixture(name: "Carryidae", rank: :family, kingdom: "Animalia")
    andricus = taxon_fixture(name: "Carryandricus", rank: :genus, parent: family)
    callirhytis = taxon_fixture(name: "Carryrhytis", rank: :genus, parent: family)
    held = taxon_fixture(name: "Carryrhytis clarkei", parent: callirhytis)
    other = taxon_fixture(name: "Carryandricus dimorphus", parent: andricus)
    {:ok, _} = Taxa.add_synonym(test_actor(), held, "Carryandricus wisliceni")

    # The tree as the cutover's legacy statements give it.
    for taxon <- [family, andricus, callirhytis, held, other], do: legacy!(taxon, legacy)

    %{
      legacy: legacy,
      family: family,
      andricus: andricus,
      callirhytis: callirhytis,
      held: held,
      other: other
    }
  end

  defp legacy!(taxon, legacy) do
    taxon = Taxa.get_taxon!(taxon.id)
    attribution = %{source_id: legacy.id, stance: :confirm, stated: nil}

    {:ok, _} =
      Taxa.assert_placement(
        test_actor(),
        %{taxon_id: taxon.id, parent_id: taxon.parent_id},
        attribution
      )

    {:ok, _} =
      Taxa.assert_name(
        test_actor(),
        %{taxon_id: taxon.id, name: Taxa.accepted_name(taxon), rank: taxon.rank},
        attribution
      )

    for %{status: :synonym, name: name} <- taxon.names do
      {:ok, _} =
        Taxa.assert_synonymy(
          test_actor(),
          %{name: name, accepted_taxon_id: taxon.id},
          attribution
        )
    end
  end

  defp act(id, attrs), do: Map.merge(%{"id" => id, "evidence" => @evidence}, attrs)

  # A taxonomy batch treating "Carryandricus wisliceni" (held as a synonym
  # of C. clarkei) as a valid species of Carryandricus, with `acts`.
  defp revalidation(acts) do
    taxonomy_batch()
    |> unique_batch_id()
    |> Map.put("taxa", [
      %{"ref" => "t1", "name_as_written" => "Carryandricus wisliceni", "rank" => "species"},
      %{"ref" => "t2", "name_as_written" => "Carryandricus", "rank" => "genus"},
      %{"ref" => "t3", "name_as_written" => "Carryrhytis clarkei", "rank" => "species"}
    ])
    |> Map.put("acts", acts)
  end

  defp name_act, do: act("a1", %{"stance" => "confirm", "kind" => "name", "taxon" => "t1"})

  defp placement_act,
    do:
      act("a2", %{"stance" => "confirm", "kind" => "placement", "taxon" => "t1", "parent" => "t2"})

  defp not_synonym_act do
    act("a3", %{
      "stance" => "deny",
      "kind" => "synonymy",
      "name" => "t1",
      "accepted" => "t3",
      "status_as_written" => "erroneously synonymized"
    })
  end

  defp deliver(taxonomy),
    do: package(gall: nil, taxonomy: taxonomy) |> with_review() |> deliver!()

  defp synonym_item(package) do
    [%QueueItem{statement_ref: "t1"} = item] =
      Import.list_queue_items(package, kind: :taxonomy_disagreement)

    item
  end

  # The phase 1 decision, then approval: the Source's acts are recorded,
  # awaiting a curator.
  defp decided_and_approved(package, decision) do
    {:ok, %QueueItem{decision: decided}} =
      Import.decide_queue_item(test_actor(), synonym_item(package), decision)

    {:ok, _} = Import.approve_package(test_actor(), package)
    Map.fetch!(decided, "taxon_id")
  end

  defp differences(taxa) do
    ids = MapSet.new(taxa, & &1.id)
    Enum.filter(Sync.check(), &MapSet.member?(ids, &1.taxon_id))
  end

  defp attributions(package) do
    source_id = Import.get_package!(package.id).source_id
    source_id |> Facts.list_source_attributions("taxon_") |> Map.values()
  end

  defp legacy_synonymies(taxon, name) do
    key = NameNormalizer.normalize(name)

    Repo.all(
      from s in SynonymyFact,
        where: s.accepted_taxon_id == ^taxon.id and s.normalized_name == ^key,
        preload: :fact
    )
  end

  defp tree(taxa) do
    for t <- taxa do
      t = Taxa.get_taxon!(t.id)
      {Taxa.accepted_name(t), t.parent_id, t.names |> Enum.map(& &1.name) |> Enum.sort()}
    end
  end

  describe "a split (a species of its own again)" do
    test "becomes the acceptance of the Source's statements; the tree follows the Facts", ctx do
      package = deliver(revalidation([name_act(), placement_act(), not_synonym_act()]))
      taxon_id = decided_and_approved(package, %{"split" => true})
      split = Taxa.get_taxon!(taxon_id)
      before = tree([split, ctx.held])

      # Before: the tree holds the split, but no Fact it counts does.
      assert differences([split, ctx.held]) != []
      assert Enum.map(attributions(package), & &1.accepted_at) == [nil, nil, nil]
      since = Enum.reduce(Import.list_replay_entries(), 0, &max(&1.id, &2))

      assert {:ok, report} = TaxonomyCarryOver.run(test_actor(), Import.list_replay_entries())

      assert report.decisions == 1
      assert report.accepted == 3
      assert report.unmatched == []
      assert Enum.filter(attributions(package), &is_nil(&1.accepted_at)) == []
      assert tree([split, ctx.held]) == before
      assert differences([split, ctx.held]) == []

      # Each acceptance is in the replay log.
      assert [:taxonomic_decision, :taxonomic_decision, :taxonomic_decision] =
               for(e <- Import.list_replay_entries(), e.id > since, do: e.kind)

      # Running it again changes nothing.
      assert {:ok, again} = TaxonomyCarryOver.run(test_actor(), Import.list_replay_entries())
      assert again.accepted == 0
      assert again.already == 3
      assert again.unmatched == []
    end

    test "a revalidation stating only the name and placement is carried", ctx do
      # No statement that the name is not C. clarkei's synonym: the dated
      # name statement outranks the older (legacy) synonymy of it.
      package = deliver(revalidation([name_act(), placement_act()]))
      taxon_id = decided_and_approved(package, %{"split" => true})
      split = Taxa.get_taxon!(taxon_id)
      before = tree([split, ctx.held])

      assert {:ok, report} = TaxonomyCarryOver.run(test_actor(), Import.list_replay_entries())

      assert report.accepted == 2
      assert report.unmatched == []
      assert tree([split, ctx.held]) == before
      assert differences([split, ctx.held]) == []

      assert [%{fact: %{standing: :superseded}}] =
               legacy_synonymies(ctx.held, "Carryandricus wisliceni")
    end

    test "what the Source's statements don't carry is reported for a curator", ctx do
      # Only a placement: nothing names the split taxon, so the legacy
      # synonymy of its name into C. clarkei still counts.
      package = deliver(revalidation([placement_act()]))
      taxon_id = decided_and_approved(package, %{"split" => true})

      assert {:ok, report} = TaxonomyCarryOver.run(test_actor(), Import.list_replay_entries())

      assert report.accepted == 1
      assert [unmatched] = report.unmatched
      assert unmatched.name == "Carryandricus wisliceni"
      assert unmatched.decision =~ "split"
      assert unmatched.source =~ "T"
      assert [_] = Enum.filter(unmatched.differences, &(&1 =~ "Carryrhytis clarkei — synonym"))
      assert [_] = Enum.filter(unmatched.differences, &(&1 =~ "Carryandricus wisliceni — name"))
      assert differences([Taxa.get_taxon!(taxon_id)]) != []

      assert [%{fact: %{standing: :current}}] =
               legacy_synonymies(ctx.held, "Carryandricus wisliceni")

      assert TaxonomyCarryOver.format(report) =~ "Carryandricus wisliceni"
    end

    test "a decision found only in the exported replay log carries over too", ctx do
      package = deliver(revalidation([name_act(), placement_act(), not_synonym_act()]))
      taxon_id = decided_and_approved(package, %{"split" => true})
      {:ok, %{key: key}} = Import.export_replay_log()
      # As when replay found the name resolved without its question.
      Repo.delete_all(QueueItem)

      assert {:ok, %{decisions: 1, accepted: 3, unmatched: []}} =
               Import.carry_over_exported(test_actor(), key)

      assert differences([Taxa.get_taxon!(taxon_id), ctx.held]) == []
    end
  end

  describe "a move (a synonym of another taxon)" do
    test "accepts what the tree holds; a name act it didn't follow stays awaiting", ctx do
      moved =
        act("a4", %{
          "stance" => "confirm",
          "kind" => "synonymy",
          "name" => "t1",
          "accepted" => "t4"
        })

      taxonomy =
        revalidation([name_act(), not_synonym_act(), moved])
        |> Map.update!(
          "taxa",
          &(&1 ++
              [
                %{
                  "ref" => "t4",
                  "name_as_written" => "Carryandricus dimorphus",
                  "rank" => "species"
                }
              ])
        )

      package = deliver(taxonomy)
      decided_and_approved(package, %{"synonym_of" => ctx.other.id})

      assert {:ok, report} = TaxonomyCarryOver.run(test_actor(), Import.list_replay_entries())

      # The synonymy into C. dimorphus and the denial into C. clarkei are
      # accepted; the name act (on C. dimorphus, now its synonym) is not.
      assert report.accepted == 2
      assert report.unmatched == []
      assert differences([ctx.other, ctx.held]) == []
      assert Taxa.accepted_name(ctx.other.id) == "Carryandricus dimorphus"

      awaiting = for a <- attributions(package), is_nil(a.accepted_at), do: a
      assert [_name_act] = awaiting
    end
  end

  describe "an act a curator followed" do
    test "is accepted once the tree holds what it says", ctx do
      move =
        taxonomy_batch()
        |> unique_batch_id()
        |> Map.put("taxa", [
          %{"ref" => "t1", "name_as_written" => "Carryandricus", "rank" => "genus"},
          %{"ref" => "t2", "name_as_written" => "Otherfamilyidae", "rank" => "family"}
        ])
        |> Map.put("acts", [
          act("a1", %{
            "stance" => "confirm",
            "kind" => "placement",
            "taxon" => "t1",
            "parent" => "t2"
          })
        ])

      target = taxon_fixture(name: "Otherfamilyidae", rank: :family, kingdom: "Animalia")
      legacy!(target, ctx.legacy)
      package = deliver(move)
      {:ok, _} = Import.approve_package(test_actor(), package)

      assert [%QueueItem{statement_ref: "a1"}] =
               Import.list_queue_items(package, kind: :taxonomy_acceptance)

      # Not followed yet: nothing is accepted.
      assert {:ok, %{accepted: 0}} = TaxonomyCarryOver.run(test_actor(), [])

      # The curator moved it editorially, as phase 1 did.
      {:ok, _} = Taxa.place(test_actor(), ctx.andricus.id, target.id)
      assert differences([ctx.andricus]) != []

      assert {:ok, %{accepted: 1, followed: 1}} = TaxonomyCarryOver.run(test_actor(), [])
      assert differences([ctx.andricus]) == []

      # Its question is closed with the acceptance.
      assert [%QueueItem{status: :decided}] =
               Import.list_queue_items(package, kind: :taxonomy_acceptance, status: :decided)

      assert Taxa.get_taxon!(ctx.andricus.id).parent_id == target.id
    end
  end
end
