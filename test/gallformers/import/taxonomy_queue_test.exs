defmodule Gallformers.Import.TaxonomyQueueTest do
  @moduledoc """
  The taxonomy queue (`f923` Task 6): a Source's taxonomic statement that
  differs from the tree and is newer than the latest accepted statement in
  its slot raises one `:taxonomy_acceptance` question, across Sources; it
  never holds the Source's approval. Accepting makes the tree follow it and
  closes the open questions of older papers on the same slot as history;
  declining needs a reason. "Accept the rest of this paper" is previewed in
  a rolled-back transaction, then accepts the paper's open questions (its
  declined ones stay declined). Decisions go through
  `Gallformers.Import.TaxonomicDecisions`, so they are replayed.

  Not async: packages create Sources and the vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
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
    n = System.unique_integer([:positive])

    family = taxon_fixture(rank: :family, name: "Queuidae#{n}", kingdom: "Animalia")
    other = taxon_fixture(rank: :family, name: "Otherqueuidae#{n}", kingdom: "Animalia")
    third = taxon_fixture(rank: :family, name: "Thirdqueuidae#{n}", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Queuea#{n}", parent: family)
    species = taxon_fixture(name: "Queuea#{n} alba", parent: genus)
    lumped = taxon_fixture(name: "Queuea#{n} nigra", parent: genus)

    for taxon <- [family, other, third, genus, species, lumped], do: legacy!(taxon, legacy)

    %{
      n: n,
      legacy: legacy,
      family: family,
      other: other,
      third: third,
      genus: genus,
      species: species,
      lumped: lumped
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

    accepted = Enum.find(taxon.names, &(&1.status == :accepted))

    {:ok, _} =
      Taxa.assert_name(
        test_actor(),
        %{
          taxon_id: taxon.id,
          name: accepted.name,
          rank: taxon.rank,
          authorship: accepted.authorship
        },
        attribution
      )
  end

  # A taxonomy batch of a paper of `date` declaring `taxa` (`{ref, taxon}`
  # pairs, or declared maps) and stating `acts`.
  defp paper(title, date, taxa, acts) do
    u = System.unique_integer([:positive])

    taxonomy_batch()
    |> unique_batch_id()
    |> put_in(["source", "title"], "#{title} #{u}")
    |> put_in(["source", "citation"], "#{title} #{u}. #{date}.")
    |> put_in(["source", "authored"], %{"date" => date, "as_written" => date})
    |> Map.put("taxa", Enum.map(taxa, &declared/1))
    |> Map.put("acts", acts)
  end

  defp declared({ref, %Taxa.Taxon{} = taxon}) do
    taxon = Taxa.get_taxon!(taxon.id)

    %{
      "ref" => ref,
      "name_as_written" => Taxa.accepted_name(taxon),
      "rank" => Atom.to_string(taxon.rank)
    }
  end

  defp declared(%{} = taxon), do: taxon

  defp act(id, kind, fields) do
    Map.merge(
      %{
        "id" => id,
        "stance" => "confirm",
        "kind" => kind,
        "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
      },
      fields
    )
  end

  defp placement(id, taxon, parent),
    do: act(id, "placement", %{"taxon" => taxon, "parent" => parent})

  defp import!(batch) do
    package = package(gall: nil, taxonomy: batch) |> with_review() |> deliver!()
    {:ok, approved} = Import.approve_package(test_actor(), package)
    assert approved.status == :approved
    Import.get_package!(package.id)
  end

  defp moves(ctx, date, to) do
    paper("Revision", date, [{"t1", ctx.genus}, {"t2", to}], [placement("a1", "t1", "t2")])
    |> import!()
  end

  defp questions(package, status \\ :open),
    do: Import.list_queue_items(package, kind: :taxonomy_acceptance, status: status)

  defp question!(package) do
    assert [%QueueItem{} = item] = questions(package)
    item
  end

  defp parent_id(taxon), do: Taxa.get_taxon!(taxon.id).parent_id

  describe "raising questions" do
    test "a newer paper that differs from the tree raises one question, holding nothing", ctx do
      package = moves(ctx, "2001", ctx.other)

      item = question!(package)
      assert item.statement_ref == "a1"
      assert %{"fact_id" => fact_id, "attribution_id" => attribution_id} = item.subject

      assert %Attribution{fact_id: ^fact_id, accepted_at: nil} =
               Facts.get_attribution(attribution_id)

      assert Import.blocking?(item, :taxonomy) == false

      # Approved and applied with the question open; the tree waits for it.
      assert package |> Import.list_batches() |> Enum.map(& &1.status) |> Enum.uniq() == [
               :applied
             ]

      assert parent_id(ctx.genus) == ctx.family.id
      assert Import.list_queue_items(package, kind: :taxonomy_disagreement) == []
    end

    test "a statement that agrees with the tree raises none", ctx do
      package = moves(ctx, "2001", ctx.family)
      assert questions(package) == []
    end

    test "an older paper than the accepted one is history: no question", ctx do
      newer = moves(ctx, "2010", ctx.other)
      {:ok, _} = Import.decide_queue_item(test_actor(), question!(newer), %{"accept" => true})
      assert parent_id(ctx.genus) == ctx.other.id

      older = moves(ctx, "2000", ctx.third)
      assert questions(older) == []

      newest = moves(ctx, "2020", ctx.third)
      assert [_] = questions(newest)
    end

    test "a paper that only adds authorship to the name raises none", ctx do
      batch =
        paper("Authorship", "2001", [{"t1", ctx.species}], [
          act("a1", "name", %{"taxon" => "t1", "authorship" => %{"as_written" => "Weld, 1952"}})
        ])

      assert questions(import!(batch)) == []
    end

    test "a different authorship is a question", ctx do
      authored =
        taxon_fixture(name: "Queuea#{ctx.n} rubra", parent: ctx.genus, authorship: "Weld, 1952")

      legacy!(authored, ctx.legacy)

      batch =
        paper("Authorship", "2001", [{"t1", authored}], [
          act("a1", "name", %{"taxon" => "t1", "authorship" => %{"as_written" => "(Weld, 1952)"}})
        ])

      assert [_] = questions(import!(batch))
    end

    test "a plant's act stays an acknowledged disagreement", ctx do
      quercus = plant_fixture(name: "Quercus#{ctx.n}", rank: :genus)
      fagaceae = plant_fixture(name: "Fagaceae#{ctx.n}", rank: :family)

      package =
        paper("Plants", "2001", [{"t1", quercus}, {"t2", fagaceae}], [placement("a1", "t1", "t2")])
        |> import!()

      assert questions(package) == []
      assert [_] = Import.list_queue_items(package, kind: :taxonomy_disagreement)
    end

    test "a new taxon's own name and placement are accepted with it", ctx do
      batch =
        paper(
          "New species",
          "2001",
          [
            %{
              "ref" => "t1",
              "name_as_written" => "Queuea#{ctx.n} nova",
              "rank" => "species",
              "new" => %{"status" => "sp. nov."}
            },
            {"t2", ctx.genus}
          ],
          [act("a1", "name", %{"taxon" => "t1"}), placement("a2", "t1", "t2")]
        )

      package = import!(batch)
      assert questions(package) == []

      {:ok, nova} = Taxa.resolve_name("Queuea#{ctx.n} nova", rank: :species)
      assert nova.parent_id == ctx.genus.id

      for fact <- Taxa.list_placement_facts(nova) do
        assert fact.fact.standing == :current
      end

      assert [] = for(d <- Taxa.Sync.check(), d.taxon_id == nova.id, do: d)
    end
  end

  describe "deciding a question" do
    test "accepting moves the tree and closes older papers' questions as history", ctx do
      older = moves(ctx, "2001", ctx.third)
      newer = moves(ctx, "2010", ctx.other)
      old_item = question!(older)

      assert {:ok, %QueueItem{status: :decided, decision: %{"accept" => true}}} =
               Import.decide_queue_item(test_actor(), question!(newer), %{"accept" => true})

      assert parent_id(ctx.genus) == ctx.other.id

      assert %QueueItem{status: :decided, decision: %{"history" => true}} =
               Repo.get!(QueueItem, old_item.id)
    end

    test "declining needs a reason and keeps the tree", ctx do
      item = question!(moves(ctx, "2001", ctx.other))

      assert {:error, %Ecto.Changeset{}} =
               Import.decide_queue_item(test_actor(), item, %{"decline" => true, "reason" => " "})

      assert {:ok, %QueueItem{status: :decided}} =
               Import.decide_queue_item(test_actor(), item, %{
                 "decline" => true,
                 "reason" => "Not followed by later work."
               })

      assert parent_id(ctx.genus) == ctx.family.id

      assert %Attribution{declined_at: %DateTime{}, decline_reason: "Not followed by later work."} =
               Facts.get_attribution(item.subject["attribution_id"])
    end

    test "a refusal from the tree comes back with its reason", ctx do
      # The family under its own genus: a cycle.
      package =
        paper("Cycle", "2001", [{"t1", ctx.family}, {"t2", ctx.genus}], [
          placement("a1", "t1", "t2")
        ])
        |> import!()

      item = question!(package)

      assert {:error, reason} = Import.decide_queue_item(test_actor(), item, %{"accept" => true})
      assert Import.taxonomy_refusal(reason) =~ "Queuidae"
      assert %QueueItem{status: :open} = Repo.get!(QueueItem, item.id)
      assert parent_id(ctx.family) == nil
    end

    test "accepting a lump merges the taxon; its own question doesn't block it", ctx do
      package =
        paper("Lump", "2001", [{"t1", ctx.lumped}, {"t2", ctx.species}], [
          act("a1", "synonymy", %{"name" => "t1", "accepted" => "t2"})
        ])
        |> import!()

      item = question!(package)
      name = Taxa.accepted_name(ctx.lumped)
      assert {:ok, _} = Import.decide_queue_item(test_actor(), item, %{"accept" => true})

      assert Taxa.get_taxon(ctx.lumped.id) == nil
      assert {:ok, %{id: id}} = Taxa.resolve_name(name)
      assert id == ctx.species.id
    end

    test "a lump closes the questions of the statements it declines", ctx do
      # A newer paper places the taxon to be lumped elsewhere: an open question.
      placed =
        paper("Placement", "2005", [{"t1", ctx.lumped}, {"t2", ctx.other}], [
          placement("a1", "t1", "t2")
        ])
        |> import!()

      open = question!(placed)

      package =
        paper("Lump", "2010", [{"t1", ctx.lumped}, {"t2", ctx.species}], [
          act("a1", "synonymy", %{"name" => "t1", "accepted" => "t2"})
        ])
        |> import!()

      assert {:ok, _} =
               Import.decide_queue_item(test_actor(), question!(package), %{"accept" => true})

      assert Taxa.get_taxon(ctx.lumped.id) == nil

      assert %QueueItem{status: :decided, decision: %{"decline" => true, "reason" => reason}} =
               Repo.get!(QueueItem, open.id)

      assert reason =~ "was merged into"
    end

    test "decisions are logged as taxonomic decisions; replaying them closes the questions",
         ctx do
      item = question!(moves(ctx, "2001", ctx.other))
      {:ok, _} = Import.decide_queue_item(test_actor(), item, %{"accept" => true})

      entries =
        Repo.all(from e in ReplayEntry, where: e.kind in [:taxonomic_decision, :queue_decision])

      assert [%ReplayEntry{kind: :taxonomic_decision, key: %{"op" => "accept"}}] = entries

      # As after the cutover: the statement awaiting, its question open.
      {:ok, _} = Facts.reopen(test_actor(), item.subject["attribution_id"])

      Repo.update_all(from(q in QueueItem, where: q.id == ^item.id),
        set: [status: :open, decision: nil, decided_at: nil, decided_by_name: nil]
      )

      assert {:ok, 1} = Replay.run(entries, actor: test_actor())

      assert %QueueItem{status: :decided, decision: %{"accept" => true}} =
               Repo.get!(QueueItem, item.id)

      assert parent_id(ctx.genus) == ctx.other.id
    end

    test "reopening a statement asks again", ctx do
      item = question!(moves(ctx, "2001", ctx.other))

      {:ok, _} =
        Import.decide_queue_item(test_actor(), item, %{"decline" => true, "reason" => "Unsure."})

      {:ok, _} = Import.reopen_taxonomic_statement(test_actor(), item.subject["attribution_id"])

      assert [%QueueItem{status: :open} = again] =
               Import.list_taxonomy_questions(source_id: item.subject["source_id"])

      assert again.subject["attribution_id"] == item.subject["attribution_id"]
    end
  end

  describe "the queue across Sources" do
    test "lists the open questions of every Source, and counts a Source's", ctx do
      one = question!(moves(ctx, "2001", ctx.other))
      two = question!(moves(ctx, "2002", ctx.third))

      assert Enum.map(Import.list_taxonomy_questions(), & &1.id) == [one.id, two.id]
      assert Import.count_taxonomy_questions(one.subject["source_id"]) == 1
      assert Import.count_taxonomy_questions() == 2

      {:ok, _} = Import.decide_queue_item(test_actor(), one, %{"accept" => true})
      assert Enum.map(Import.list_taxonomy_questions(), & &1.id) == [two.id]
      assert length(Import.list_taxonomy_questions(status: :all)) == 2
    end
  end

  describe "accepting the rest of a paper" do
    setup ctx do
      # The paper treats the tree's synonym as the valid name: a rename.
      {:ok, _} = Taxa.add_synonym(test_actor(), ctx.species, "Queuea#{ctx.n} candida")

      batch =
        paper("Treatment", "2005", [{"t1", ctx.genus}, {"t2", ctx.other}, {"t3", ctx.species}], [
          placement("a1", "t1", "t2"),
          act("a2", "name", %{"taxon" => "t3"}),
          act("a3", "common_name", %{"taxon" => "t3", "common_name" => "queue gall wasp"})
        ])
        |> put_in(["taxa", Access.at(2), "name_as_written"], "Queuea#{ctx.n} candida")

      package = import!(batch)
      [a1, a2, a3] = questions(package)
      %{package: package, a1: a1, a2: a2, a3: a3, source_id: a1.subject["source_id"]}
    end

    test "the preview shows the tree's moves and renames and changes nothing", ctx do
      {:ok, _} =
        Import.decide_queue_item(test_actor(), ctx.a3, %{"decline" => true, "reason" => "No."})

      assert {:ok, preview} = Import.preview_accept_rest(ctx.source_id, test_actor())
      assert Enum.map(preview.items, & &1.id) == [ctx.a1.id, ctx.a2.id]

      assert [%{taxon_id: genus_id, to: to}] = preview.moves
      assert genus_id == ctx.genus.id
      assert to == Taxa.accepted_name(ctx.other)

      assert [%{taxon_id: species_id, to: "Queuea" <> _}] = preview.renames
      assert species_id == ctx.species.id

      assert parent_id(ctx.genus) == ctx.family.id
      assert length(questions(ctx.package)) == 2
    end

    test "accepting takes every open question; the declined one stays declined", ctx do
      {:ok, _} =
        Import.decide_queue_item(test_actor(), ctx.a3, %{"decline" => true, "reason" => "No."})

      assert {:ok, %{accepted: accepted}} = Import.accept_rest(test_actor(), ctx.source_id)
      assert Enum.map(accepted, & &1.id) == [ctx.a1.id, ctx.a2.id]

      assert parent_id(ctx.genus) == ctx.other.id
      assert Taxa.accepted_name(ctx.species.id) == "Queuea#{ctx.n} candida"
      assert questions(ctx.package) == []

      assert %Attribution{declined_at: %DateTime{}} =
               Facts.get_attribution(ctx.a3.subject["attribution_id"])

      assert Taxa.list_common_names(ctx.species.id) == []
    end

    test "a refusal stops it, with the reason, and accepts nothing", ctx do
      cycle =
        paper("Cycle", "2006", [{"t1", ctx.family}, {"t2", ctx.genus}], [
          placement("a1", "t1", "t2")
        ])
        |> import!()

      item = question!(cycle)
      source_id = item.subject["source_id"]

      assert {:error, {item_id, reason}} =
               Import.preview_accept_rest(source_id, test_actor()) |> refused()

      assert item_id == item.id
      assert Import.taxonomy_refusal(reason) =~ "Queuidae"

      assert {:error, _} = Import.accept_rest(test_actor(), source_id)
      assert [%QueueItem{status: :open}] = questions(cycle)
    end
  end

  defp refused({:ok, %{refused: {id, reason}}}), do: {:error, {id, reason}}
  defp refused(other), do: other
end
