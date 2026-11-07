defmodule Gallformers.Import.SplitQuestionsTest do
  @moduledoc """
  Split questions (`f923` Task 7, "Splits"): when a split of A comes into
  effect, a Gall the splitting paper's own gall statements cover takes the
  Inducer the paper states for it, credited to the paper; each other Gall
  whose Inducer is A gets one question, "Which taxon induces this Gall
  now?" — a daughter, or not known yet (it stays on A, marked as following
  the name in its old broad sense). Older Sources' statements are moved,
  never rewritten: they keep `name_as_written`. Answers re-point the Gall's
  Inducer and propose its rename; they are audited and replayed.

  Not async: loads the vocabularies and makes the Gallformers Source.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Import.ReplayEntry
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    legacy = Sources.get_legacy_data_source()
    weld = source_fixture("Weld", "1959")
    paper = source_fixture("Splitter", "2001")

    family = taxon_fixture(rank: :family, name: "Splitidae", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Splita", parent: family)
    split = taxon_fixture(name: "Splita alba", parent: genus)
    beta = taxon_fixture(name: "Splita beta", parent: genus)
    gamma = taxon_fixture(name: "Splita gamma", parent: genus)

    for taxon <- [family, genus, split, beta, gamma], do: legacy!(taxon, legacy)

    alba_oak = plant_fixture(name: "Quercus splitalba")
    rubra_oak = plant_fixture(name: "Quercus splitrubra")

    %{
      weld: weld,
      paper: paper,
      split: split,
      beta: beta,
      gamma: gamma,
      alba_oak: alba_oak,
      rubra_oak: rubra_oak
    }
  end

  # The tree's own statements of `taxon`, as the cutover makes them.
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
  end

  # A Gall of `generation` whose Inducer `source` states as `inducer`.
  defp gall!(inducer, source, generation) do
    name = "#{Taxa.accepted_name(inducer)} (#{generation})"
    gall = gall_fixture(name: name, generation: generation)
    induces!(gall, inducer, source)
    gall
  end

  defp induces!(gall, inducer, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: inducer.id, object_gall_id: gall.id},
        confirm(source, %{
          names: [
            %{taxon_id: inducer.id, name_as_written: Taxa.accepted_name(inducer), role: "subject"}
          ]
        })
      )
  end

  defp hosted!(gall, plant, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        confirm(source)
      )
  end

  # The paper splits `ctx.split` into `into`; a curator accepts it.
  defp accept_split!(ctx, into) do
    {:ok, %{attribution: attribution}} =
      Taxa.assert_split(
        test_actor(),
        %{taxon_id: ctx.split.id, into_taxon_ids: Enum.map(into, & &1.id)},
        confirm(ctx.paper)
      )

    assert {:ok, _} =
             Import.TaxonomicDecisions.decide(test_actor(), :accept, attribution.id)

    attribution
  end

  defp inducer_ids(gall) do
    from(r in Current.relationships("inducer_of"),
      where: r.object_gall_id == ^gall.id,
      select: r.subject_taxon_id
    )
    |> Repo.all()
    |> Enum.sort()
  end

  defp questions(gall) do
    Import.list_split_questions(status: :all)
    |> Enum.filter(&(&1.subject["gall_id"] == gall.id))
  end

  defp question!(gall) do
    assert [%QueueItem{kind: :split_inducer, status: :open} = item] = questions(gall)
    item
  end

  defp proposals(gall),
    do: Enum.filter(Import.list_gall_renames(), &(&1.subject["gall_id"] == gall.id))

  # The Fact of `gall`'s Inducer `taxon`, and its attributions.
  defp inducer_attributions(gall, taxon) do
    [fact_id] =
      Repo.all(
        from(r in Current.relationships("inducer_of"),
          where: r.object_gall_id == ^gall.id and r.subject_taxon_id == ^taxon.id,
          select: r.fact_id
        )
      )

    Facts.list_attributions(fact_id)
  end

  describe "an accepted split" do
    test "a Gall the paper covers takes its Inducer, credited to the paper: no question", ctx do
      gall = gall!(ctx.split, ctx.weld, "agamic")
      induces!(gall, ctx.beta, ctx.paper)
      [older] = inducer_attributions(gall, ctx.split)

      accept_split!(ctx, [ctx.split, ctx.beta])

      assert inducer_ids(gall) == [ctx.beta.id]
      assert questions(gall) == []

      attributions = inducer_attributions(gall, ctx.beta)

      assert Enum.sort(Enum.map(attributions, & &1.source_id)) ==
               Enum.sort([ctx.weld.id, ctx.paper.id])

      # The older Source's statement moved, never rewritten.
      moved = Enum.find(attributions, &(&1.source_id == ctx.weld.id))
      assert moved.id == older.id
      assert [%{name_as_written: "Splita alba"}] = moved.names

      assert [%QueueItem{proposal: %{"to" => "Splita beta (agamic)"}}] = proposals(gall)
    end

    test "each other Gall on the split taxon gets one question, its Inducer kept", ctx do
      gall = gall!(ctx.split, ctx.weld, "agamic")
      hosted!(gall, ctx.rubra_oak, ctx.weld)

      accept_split!(ctx, [ctx.split, ctx.beta])

      item = question!(gall)
      assert item.package_id == nil
      assert item.subject["taxon_id"] == ctx.split.id
      assert item.subject["into_taxon_ids"] == Enum.sort([ctx.split.id, ctx.beta.id])
      assert item.subject["source_id"] == ctx.paper.id
      assert item.proposal == %{}
      assert inducer_ids(gall) == [ctx.split.id]
      assert proposals(gall) == []
    end

    test "a daughter the paper's Galls share a Host with is suggested", ctx do
      own = gall_fixture(name: "Splita beta (sexgen)", generation: "sexual")
      induces!(own, ctx.beta, ctx.paper)
      hosted!(own, ctx.alba_oak, ctx.paper)

      gall = gall!(ctx.split, ctx.weld, "agamic")
      hosted!(gall, ctx.alba_oak, ctx.weld)
      other = gall!(ctx.split, ctx.weld, "sexual")
      hosted!(other, ctx.rubra_oak, ctx.weld)

      accept_split!(ctx, [ctx.split, ctx.beta])

      assert %{"taxon_id" => beta, "why" => why} = question!(gall).proposal
      assert beta == ctx.beta.id
      assert why =~ "Quercus splitalba"
      assert question!(other).proposal == %{}
    end

    test "a split into taxa other than the split one asks the same", ctx do
      gall = gall!(ctx.split, ctx.weld, "agamic")
      accept_split!(ctx, [ctx.beta, ctx.gamma])

      assert question!(gall).subject["into_taxon_ids"] ==
               Enum.sort([ctx.beta.id, ctx.gamma.id])
    end

    test "accepting the rest of the paper previews the Galls that would ask, not those it settles",
         ctx do
      _asked = gall!(ctx.split, ctx.weld, "agamic")
      settled = gall!(ctx.split, ctx.weld, "sexual")
      induces!(settled, ctx.beta, ctx.paper)

      {:ok, %{attribution: attribution}} =
        Taxa.assert_split(
          test_actor(),
          %{taxon_id: ctx.split.id, into_taxon_ids: [ctx.split.id, ctx.beta.id]},
          confirm(ctx.paper)
        )

      question = Import.TaxonomyQueue.question(attribution.id, "a split", "a1")
      %QueueItem{} |> QueueItem.create_changeset(question) |> Repo.insert!()

      assert {:ok, %{splits: [%{taxon_id: taxon_id, galls: 1}]}} =
               Import.preview_accept_rest(ctx.paper.id, test_actor())

      assert taxon_id == ctx.split.id
      assert Import.list_split_questions() == []
    end

    test "an unaccepted split asks nothing", ctx do
      gall = gall!(ctx.split, ctx.weld, "agamic")

      {:ok, _} =
        Taxa.assert_split(
          test_actor(),
          %{taxon_id: ctx.split.id, into_taxon_ids: [ctx.beta.id, ctx.gamma.id]},
          confirm(ctx.paper)
        )

      assert questions(gall) == []
    end
  end

  describe "answering" do
    setup ctx do
      gall = gall!(ctx.split, ctx.weld, "agamic")
      accept_split!(ctx, [ctx.split, ctx.beta])
      %{gall: gall, item: question!(gall)}
    end

    test "a daughter re-points the Inducer, keeping the older statements, and proposes the rename",
         ctx do
      [older] = inducer_attributions(ctx.gall, ctx.split)

      assert {:ok, %QueueItem{status: :decided}} =
               Import.decide_queue_item(test_actor(), ctx.item, %{"taxon_id" => ctx.beta.id})

      assert inducer_ids(ctx.gall) == [ctx.beta.id]
      assert [moved] = inducer_attributions(ctx.gall, ctx.beta)
      assert moved.id == older.id
      assert [%{name_as_written: "Splita alba"}] = moved.names
      assert [%QueueItem{proposal: %{"to" => "Splita beta (agamic)"}}] = proposals(ctx.gall)
    end

    test "the split taxon in its narrow sense keeps the Inducer, unmarked", ctx do
      assert {:ok, _} =
               Import.decide_queue_item(test_actor(), ctx.item, %{"taxon_id" => ctx.split.id})

      assert inducer_ids(ctx.gall) == [ctx.split.id]
      assert Catalog.broad_sense_inducers(ctx.gall.id) == %{}
    end

    test "not known yet keeps the Inducer, marked as its broad sense", ctx do
      assert {:ok, _} =
               Import.decide_queue_item(test_actor(), ctx.item, %{"not_known" => true})

      assert inducer_ids(ctx.gall) == [ctx.split.id]
      assert proposals(ctx.gall) == []

      split_id = ctx.split.id
      assert %{^split_id => %{source_id: source_id}} = Catalog.broad_sense_inducers(ctx.gall.id)
      assert source_id == ctx.paper.id

      # The Gall's Facts show the mark on its Inducer.
      [%{facts: %{inducer: [entry]}}] = Import.facts_for_gall(ctx.gall.id)
      assert %{source: source} = entry.value.broad_sense
      assert source == Sources.short_name(ctx.paper)
    end

    test "a taxon outside the split is refused", ctx do
      assert {:error, %Ecto.Changeset{}} =
               Import.decide_queue_item(test_actor(), ctx.item, %{"taxon_id" => ctx.gamma.id})

      assert %QueueItem{status: :open} = Repo.get!(QueueItem, ctx.item.id)
    end

    test "answers are logged and replayed", ctx do
      {:ok, _} = Import.decide_queue_item(test_actor(), ctx.item, %{"taxon_id" => ctx.beta.id})

      entries =
        Repo.all(
          from e in ReplayEntry,
            where: e.kind in [:taxonomic_decision, :queue_decision],
            order_by: e.id
        )

      assert [
               %ReplayEntry{kind: :taxonomic_decision},
               %ReplayEntry{kind: :queue_decision, key: %{"kind" => "split_inducer"}}
             ] = entries

      # As after the cutover: the question open again, the Gall on the split taxon.
      {:ok, _} = Catalog.repoint_inducer(test_actor(), ctx.gall.id, ctx.beta.id, ctx.split.id)

      Repo.update_all(from(q in QueueItem, where: q.id == ^ctx.item.id),
        set: [status: :open, decision: nil, decided_at: nil, decided_by_name: nil]
      )

      assert {:ok, 2} = Replay.run(entries, actor: test_actor())
      Gallformers.ImportFixtures.assert_replays_again(entries, test_actor())

      assert %QueueItem{status: :decided, decision: %{"taxon_id" => beta}} =
               Repo.get!(QueueItem, ctx.item.id)

      assert beta == ctx.beta.id
      assert inducer_ids(ctx.gall) == [ctx.beta.id]
    end
  end
end
