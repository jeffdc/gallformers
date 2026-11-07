defmodule Gallformers.Import.UndoQuestionsTest do
  @moduledoc """
  Undo of the cross-Source questions (matter `f14c`, "Undo rule"): a
  taxonomic statement accepted or declined is reopened (the tree goes back,
  the same question is open again); a split question's answer, a rename
  proposal's decision and a merge's same-date question are reopened, what
  they changed put back. Each is refused once something since depends on
  it, and replays to the same state.

  Not async: loads the vocabularies and makes Sources.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Facts.AliasFact
  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    %{legacy: Sources.get_legacy_data_source()}
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

  defp edited_later!(who, table, pk, data) do
    id = System.unique_integer([:positive, :monotonic]) + 3_000_000_000_000
    at = NaiveDateTime.utc_now() |> NaiveDateTime.add(60) |> NaiveDateTime.truncate(:second)

    Repo.query!(
      "INSERT INTO carbonite_default.transactions (id, xact_id, meta, inserted_at) VALUES ($1, $2::xid8, $3, $4)",
      [id, id, %{actor: %{type: "user", id: 99, name: who}, operation: "test.edit"}, at]
    )

    Repo.query!(
      """
      INSERT INTO carbonite_default.changes
        (transaction_id, transaction_xact_id, op, table_prefix, table_name, table_pk, data, changed)
      VALUES ($1, $2::xid8, 'update', 'public', $3, $4, $5, '{}')
      """,
      [id, id, table, [to_string(pk)], data]
    )
  end

  defp decide!(item, decision) do
    {:ok, item} = Import.decide_queue_item(test_actor(), item, decision)
    item
  end

  describe "a taxonomic statement" do
    setup ctx do
      n = System.unique_integer([:positive])
      family = taxon_fixture(rank: :family, name: "Undoidae#{n}", kingdom: "Animalia")
      other = taxon_fixture(rank: :family, name: "Otherundoidae#{n}", kingdom: "Animalia")
      genus = taxon_fixture(rank: :genus, name: "Undoa#{n}", parent: family)
      for taxon <- [family, other, genus], do: legacy!(taxon, ctx.legacy)
      %{family: family, other: other, genus: genus}
    end

    # An approved paper placing the genus under `to`: one question.
    defp moves!(ctx, to) do
      u = System.unique_integer([:positive])

      taxa =
        for {ref, taxon} <- [{"t1", ctx.genus}, {"t2", to}] do
          %{
            "ref" => ref,
            "name_as_written" => Taxa.accepted_name(taxon),
            "rank" => Atom.to_string(taxon.rank)
          }
        end

      batch =
        taxonomy_batch()
        |> unique_batch_id()
        |> put_in(["source", "title"], "Revision #{u}")
        |> put_in(["source", "citation"], "Revision #{u}. 2001.")
        |> put_in(["source", "authored"], %{"date" => "2001", "as_written" => "2001"})
        |> Map.put("taxa", taxa)
        |> Map.put("acts", [
          %{
            "id" => "a1",
            "stance" => "confirm",
            "kind" => "placement",
            "taxon" => "t1",
            "parent" => "t2",
            "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
          }
        ])

      package = package(gall: nil, taxonomy: batch) |> with_review() |> deliver!()
      {:ok, %{status: :approved}} = Import.approve_package(test_actor(), package)
      [item] = Import.list_queue_items(package, kind: :taxonomy_acceptance)
      item
    end

    defp parent_id(taxon), do: Taxa.get_taxon!(taxon.id).parent_id

    test "an acceptance is reopened: the tree goes back, the same question is open", ctx do
      item = decide!(moves!(ctx, ctx.other), %{"accept" => true})
      assert parent_id(ctx.genus) == ctx.other.id

      assert {:ok, %QueueItem{status: :open, decision: nil} = undone} =
               Import.undo_decision(test_actor(), item)

      assert undone.id == item.id
      assert parent_id(ctx.genus) == ctx.family.id

      assert %{accepted_at: nil, declined_at: nil} =
               Facts.get_attribution(item.subject["attribution_id"])

      assert [%QueueItem{id: id, status: :open}] =
               Import.list_taxonomy_questions(source_id: item.subject["source_id"])

      assert id == item.id
    end

    test "a decline is reopened too", ctx do
      item = decide!(moves!(ctx, ctx.other), %{"decline" => true, "reason" => "Unsure."})

      assert {:ok, %QueueItem{status: :open}} = Import.undo_decision(test_actor(), item)
      assert %{declined_at: nil} = Facts.get_attribution(item.subject["attribution_id"])
    end

    test "is refused once the tree it changed was edited since", ctx do
      item = decide!(moves!(ctx, ctx.other), %{"accept" => true})

      edited_later!("Bea Curator", "taxa", ctx.genus.id, %{
        "id" => ctx.genus.id,
        "parent_id" => ctx.family.id
      })

      assert {:error, {:edited, %{by: "Bea Curator", link: {:taxon, id}}}} =
               Import.undo_decision(test_actor(), item)

      assert id == ctx.genus.id
      assert parent_id(ctx.genus) == ctx.other.id
    end

    test "replays to the same state", ctx do
      item = moves!(ctx, ctx.other)

      {entries, _} =
        logged_and_undone(fn ->
          item = decide!(item, %{"accept" => true})
          {:ok, _} = Import.undo_decision(test_actor(), item)
        end)

      assert {:ok, 2} = Replay.run(entries, actor: test_actor())
      assert parent_id(ctx.genus) == ctx.family.id
      assert %QueueItem{status: :open} = Repo.get!(QueueItem, item.id)
    end
  end

  describe "a split question's answer" do
    setup ctx do
      weld = source_fixture("Weld", "1959")
      paper = source_fixture("Splitter", "2001")
      family = taxon_fixture(rank: :family, name: "Undosplitidae", kingdom: "Animalia")
      genus = taxon_fixture(rank: :genus, name: "Undosplita", parent: family)
      split = taxon_fixture(name: "Undosplita alba", parent: genus)
      beta = taxon_fixture(name: "Undosplita beta", parent: genus)
      for taxon <- [family, genus, split, beta], do: legacy!(taxon, ctx.legacy)

      gall = gall_fixture(name: "Undosplita alba (agamic)", generation: "agamic")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: split.id, object_gall_id: gall.id},
          confirm(weld)
        )

      {:ok, %{attribution: attribution}} =
        Taxa.assert_split(
          test_actor(),
          %{taxon_id: split.id, into_taxon_ids: [split.id, beta.id]},
          confirm(paper)
        )

      {:ok, _} = Import.TaxonomicDecisions.decide(test_actor(), :accept, attribution.id)

      [item] =
        Enum.filter(Import.list_split_questions(), &(&1.subject["gall_id"] == gall.id))

      %{split: split, beta: beta, gall: gall, item: item, weld: weld}
    end

    # The Sources stating each of the Gall's Inducers, by Inducer.
    defp inducer_sources(gall) do
      from(r in Gallformers.Catalog.Facts.RelationshipFact,
        where: r.type == "inducer_of" and r.object_gall_id == ^gall.id
      )
      |> Repo.all()
      |> Map.new(fn r ->
        {r.subject_taxon_id,
         r.fact_id |> Facts.list_attributions() |> Enum.map(& &1.source_id) |> Enum.sort()}
      end)
    end

    defp state_inducer!(gall, taxon, source) do
      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: taxon.id, object_gall_id: gall.id},
          confirm(source)
        )
    end

    defp inducer_ids(gall) do
      from(r in Current.relationships("inducer_of"),
        where: r.object_gall_id == ^gall.id,
        select: r.subject_taxon_id
      )
      |> Repo.all()
      |> Enum.sort()
    end

    test "a daughter answer puts the Inducer back and withdraws the rename", ctx do
      decided = decide!(ctx.item, %{"taxon_id" => ctx.beta.id})
      assert inducer_ids(ctx.gall) == [ctx.beta.id]

      assert {:ok, %QueueItem{status: :open}} = Import.undo_decision(test_actor(), decided)

      assert inducer_ids(ctx.gall) == [ctx.split.id]

      assert Enum.filter(Import.list_gall_renames(), &(&1.subject["gall_id"] == ctx.gall.id)) ==
               []
    end

    test "a daughter answer moves back only what it moved, not the daughter's own statements",
         ctx do
      other = source_fixture("Otherinducer", "1990")
      state_inducer!(ctx.gall, ctx.beta, other)

      decided = decide!(ctx.item, %{"taxon_id" => ctx.beta.id})
      assert inducer_sources(ctx.gall) == %{ctx.beta.id => Enum.sort([other.id, ctx.weld.id])}

      assert {:ok, %QueueItem{status: :open}} = Import.undo_decision(test_actor(), decided)

      assert inducer_sources(ctx.gall) == %{
               ctx.split.id => [ctx.weld.id],
               ctx.beta.id => [other.id]
             }
    end

    test "a daughter answer that moved a note moves it back", ctx do
      [fact_id] =
        from(r in Gallformers.Catalog.Facts.RelationshipFact,
          where: r.type == "inducer_of" and r.object_gall_id == ^ctx.gall.id,
          select: r.fact_id
        )
        |> Repo.all()

      {:ok, _} = Catalog.add_fact_note(test_actor(), fact_id, "Weld's type series.")
      decided = decide!(ctx.item, %{"taxon_id" => ctx.beta.id})

      {:ok, _} = Import.undo_decision(test_actor(), decided)

      [back] =
        from(r in Gallformers.Catalog.Facts.RelationshipFact,
          where: r.type == "inducer_of" and r.object_gall_id == ^ctx.gall.id,
          select: r.fact_id
        )
        |> Repo.all()

      assert [%{text: "Weld's type series."}] =
               Repo.all(from(n in Gallformers.Catalog.FactNote, where: n.fact_id == ^back))
    end

    test "a daughter answer that joined a Source's two statements is not undone", ctx do
      state_inducer!(ctx.gall, ctx.beta, ctx.weld)
      decided = decide!(ctx.item, %{"taxon_id" => ctx.beta.id})

      assert {:error, {:cannot_undo, :joined} = reason} =
               Import.undo_decision(test_actor(), decided)

      assert Import.undo_refusal(reason).text =~ "Gall's page"
      assert inducer_sources(ctx.gall) == %{ctx.beta.id => [ctx.weld.id]}
    end

    test "not known yet: the broad-sense mark goes", ctx do
      decided = decide!(ctx.item, %{"not_known" => true})
      assert Catalog.broad_sense_inducers(ctx.gall.id) != %{}

      assert {:ok, %QueueItem{status: :open}} = Import.undo_decision(test_actor(), decided)
      assert Catalog.broad_sense_inducers(ctx.gall.id) == %{}
    end

    test "the accepted split itself is not undone by reopening it", ctx do
      gamma = taxon_fixture(name: "Undosplita gamma", parent: Taxa.get_taxon!(ctx.beta.parent_id))
      paper = source_fixture("Resplitter", "2010")

      {:ok, %{attribution: attribution}} =
        Taxa.assert_split(
          test_actor(),
          %{taxon_id: ctx.beta.id, into_taxon_ids: [ctx.beta.id, gamma.id]},
          confirm(paper)
        )

      question = Import.TaxonomyQueue.question(attribution.id, "a split", "a1")
      item = %QueueItem{} |> QueueItem.create_changeset(question) |> Repo.insert!()
      decided = decide!(item, %{"accept" => true})

      assert {:error, {:cannot_undo, :split} = reason} =
               Import.undo_decision(test_actor(), decided)

      assert Import.undo_refusal(reason).text =~ "split"
    end

    test "replays to the same state", ctx do
      {entries, _} =
        logged_and_undone(fn ->
          decided = decide!(ctx.item, %{"taxon_id" => ctx.beta.id})
          {:ok, _} = Import.undo_decision(test_actor(), decided)
        end)

      assert {:ok, 2} = Replay.run(entries, actor: test_actor())
      assert inducer_ids(ctx.gall) == [ctx.split.id]
      assert %QueueItem{status: :open} = Repo.get!(QueueItem, ctx.item.id)
    end

    test "replays to the same state on a Gall already naming the daughter", ctx do
      other = source_fixture("Otherinducer", "1990")
      state_inducer!(ctx.gall, ctx.beta, other)

      {entries, _} =
        logged_and_undone(fn ->
          decided = decide!(ctx.item, %{"taxon_id" => ctx.beta.id})
          {:ok, _} = Import.undo_decision(test_actor(), decided)
        end)

      assert {:ok, 2} = Replay.run(entries, actor: test_actor())

      assert inducer_sources(ctx.gall) == %{
               ctx.split.id => [ctx.weld.id],
               ctx.beta.id => [other.id]
             }

      assert %QueueItem{status: :open} = Repo.get!(QueueItem, ctx.item.id)
    end
  end

  describe "a rename proposal's decision" do
    setup do
      source = source_fixture("Weld", "1959")
      family = taxon_fixture(rank: :family, name: "Undorenamidae", kingdom: "Animalia")
      genus = taxon_fixture(rank: :genus, name: "Undorena", parent: family)
      species = taxon_fixture(name: "Undorena alba", parent: genus)
      gall = gall_fixture(name: "Undorena alba (agamic)", generation: "agamic")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: species.id, object_gall_id: gall.id},
          confirm(source)
        )

      {:ok, _} = Taxa.rename(test_actor(), species, "Undorena nigra")
      [item] = Enum.filter(Import.list_gall_renames(), &(&1.subject["gall_id"] == gall.id))
      %{gall: gall, item: item}
    end

    defp former_labels(gall) do
      Repo.all(
        from(a in AliasFact,
          where: a.gall_id == ^gall.id and a.kind == :former_label,
          select: a.name
        )
      )
    end

    test "accepted: the Gall's name goes back, and its former-label alias", ctx do
      decided = decide!(ctx.item, %{"accept" => true})
      assert Catalog.get_gall!(ctx.gall.id).name == "Undorena nigra (agamic)"
      assert former_labels(ctx.gall) == ["Undorena alba (agamic)"]

      assert {:ok, %QueueItem{status: :open}} = Import.undo_decision(test_actor(), decided)

      assert Catalog.get_gall!(ctx.gall.id).name == "Undorena alba (agamic)"
      assert former_labels(ctx.gall) == []
    end

    test "rejected: the name override goes", ctx do
      decided = decide!(ctx.item, %{"reject" => true})
      assert Catalog.get_gall!(ctx.gall.id).name_override == "Undorena alba (agamic)"

      assert {:ok, %QueueItem{status: :open}} = Import.undo_decision(test_actor(), decided)

      gall = Catalog.get_gall!(ctx.gall.id)
      assert gall.name_override == nil
      assert Gall.display_name(gall) == "Undorena alba (agamic)"
    end

    test "replays to the same state", ctx do
      {entries, _} =
        logged_and_undone(fn ->
          decided = decide!(ctx.item, %{"accept" => true})
          {:ok, _} = Import.undo_decision(test_actor(), decided)
        end)

      assert {:ok, 2} = Replay.run(entries, actor: test_actor())
      assert Catalog.get_gall!(ctx.gall.id).name == "Undorena alba (agamic)"
      assert %QueueItem{status: :open} = Repo.get!(QueueItem, ctx.item.id)
    end
  end

  describe "a merge's same-date question" do
    test "is reopened, and replays", _ctx do
      gall = gall_fixture(name: "Undomerged gall")

      item =
        Repo.insert!(%QueueItem{
          kind: :same_date_conflict,
          statement_ref: "merge:undo",
          subject: %{"gall_id" => gall.id, "fact_ids" => [], "merge" => "test"}
        })

      {entries, _} =
        logged_and_undone(fn ->
          decided = decide!(item, %{})
          assert {:ok, %QueueItem{status: :open}} = Import.undo_decision(test_actor(), decided)
        end)

      assert {:ok, 2} = Replay.run(entries, actor: test_actor())
      assert %QueueItem{status: :open} = Repo.get!(QueueItem, item.id)
    end
  end
end
