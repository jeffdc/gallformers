defmodule Gallformers.Import.SourceCorrectionsTest do
  @moduledoc """
  Corrections to a Source's applied Facts (matter `f14c`, "The Source's
  Facts after approval"): a correction never edits a Fact, which can hold
  several Sources' attributions. The curator withdraws the Source's
  attribution where it didn't say it, and states what it did say (another
  Host, another Trait value, another parent or accepted taxon) as that
  Source's statement, its words carried over. Each needs a note of why, is
  audited, recorded (`Gallformers.Import.list_source_corrections/1`),
  logged for replay, and moves the Source's Updated date. A taxonomic
  statement stated anew awaits a curator unless the correcting curator
  accepts it in the same step.

  Not async: the tests load the vocabularies.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Import.SourceCorrection
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    legacy = Sources.get_legacy_data_source()
    paper = source_fixture("InfluentialPoints", "2026")
    gall = gall_fixture()
    rubus = taxon_fixture(rank: :genus, name: "Rubus", kingdom: "Plantae")
    frondosus = plant_fixture(name: "Rubus frondosus", parent: rubus)
    idaeus = plant_fixture(name: "Rubus idaeus", parent: rubus)

    %{
      legacy: legacy,
      paper: paper,
      gall: gall,
      rubus: rubus,
      frondosus: frondosus,
      idaeus: idaeus
    }
  end

  defp host!(gall, plant, attribution) do
    {:ok, %{fact: fact}} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        attribution
      )

    fact
  end

  defp host_fact(gall, plant) do
    {:ok, id} = Catalog.find_gall_fact(gall.id, {:host, plant.id})
    id
  end

  defp trait!(gall, trait, value, attribution) do
    {:ok, %{fact: fact}} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: gall.id, trait: trait, value: value},
        attribution
      )

    fact
  end

  defp entries(kind), do: for(e <- Import.list_replay_entries(), e.kind == kind, do: e)

  defp standing(fact_id), do: Facts.get_fact!(fact_id).standing

  describe "withdrawing a Source's statement" do
    test "the legacy data's genus Host goes; the Fact and other Sources' statements stay", ctx do
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.legacy, %{stated: nil}))
      _ = host!(ctx.gall, ctx.rubus, confirm(ctx.paper))

      assert {:ok, %{correction: correction, withdrawn: [withdrawn], asserted: []}} =
               Import.correct_source_fact(
                 test_actor(),
                 ctx.legacy.id,
                 fact.id,
                 :withdraw,
                 "InfluentialPoints states species and varieties only; the genus was ours."
               )

      assert withdrawn == fact.id
      assert Facts.get_attribution(fact.id, ctx.legacy.id) == nil
      assert %Attribution{} = Facts.get_attribution(fact.id, ctx.paper.id)
      assert standing(fact.id) == :current

      assert %SourceCorrection{kind: :withdraw, author_name: "test"} = correction
      assert correction.source_id == ctx.legacy.id
      assert correction.summary =~ "Host"
      assert correction.summary =~ "Rubus"
      assert correction.note =~ "the genus was ours"

      assert [^correction] = Import.list_source_corrections(ctx.legacy.id)
    end

    test "a Fact no Source states any more is no longer current", ctx do
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.legacy, %{stated: nil}))

      {:ok, _} =
        Import.correct_source_fact(test_actor(), ctx.legacy.id, fact.id, :withdraw, "Not said.")

      assert standing(fact.id) == :unsupported
    end

    test "needs a note, and a statement the Source makes", ctx do
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.legacy, %{stated: nil}))

      assert {:error, :note_required} =
               Import.correct_source_fact(test_actor(), ctx.legacy.id, fact.id, :withdraw, "  ")

      assert {:error, :not_found} =
               Import.correct_source_fact(test_actor(), ctx.paper.id, fact.id, :withdraw, "Why")

      assert %Attribution{} = Facts.get_attribution(fact.id, ctx.legacy.id)
      assert Import.list_source_corrections(ctx.legacy.id) == []
      assert entries(:source_correction) == []
    end

    test "is logged by stable keys and moves the Source's Updated date", ctx do
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.legacy, %{stated: nil}))

      assert %{updated: nil, legacy?: true} = Import.source_dates([ctx.legacy.id])[ctx.legacy.id]

      {:ok, %{correction: correction}} =
        Import.correct_source_fact(test_actor(), ctx.legacy.id, fact.id, :withdraw, "Not said.")

      assert [entry] = entries(:source_correction)
      assert entry.key["source"] == Import.StableRef.source(ctx.legacy.id)
      assert entry.key["gall"] == Import.StableRef.gall(ctx.gall.id)

      assert entry.key["fact"] == %{
               "kind" => "host",
               "taxon" => Import.StableRef.taxon(ctx.rubus.id)
             }

      assert entry.payload["op"] == "withdraw"
      assert entry.payload["note"] == "Not said."

      assert %{updated: updated, legacy?: true} =
               Import.source_dates([ctx.legacy.id])[ctx.legacy.id]

      assert updated == correction.inserted_at
    end
  end

  describe "stating what the Source said instead" do
    test "another Host: the statement moves to that plant with the Source's words", ctx do
      words = %{value_as_written: "Rubus", evidence: [%{quote: "on Rubus villosus frondosus"}]}
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.paper, words))
      _ = host!(ctx.gall, ctx.rubus, confirm(ctx.legacy, %{stated: nil}))

      assert {:ok, %{withdrawn: [withdrawn], asserted: [asserted], correction: correction}} =
               Import.correct_source_fact(
                 test_actor(),
                 ctx.paper.id,
                 fact.id,
                 {:host, ctx.frondosus.id},
                 "Rubus villosus var. frondosus is Rubus frondosus."
               )

      assert withdrawn == fact.id
      assert asserted == host_fact(ctx.gall, ctx.frondosus)
      assert Facts.get_attribution(fact.id, ctx.paper.id) == nil
      assert %Attribution{} = Facts.get_attribution(fact.id, ctx.legacy.id)

      [moved] = for a <- Facts.list_attributions(asserted), a.source_id == ctx.paper.id, do: a
      assert moved.value_as_written == "Rubus"
      assert moved.stated_on == ~D[2026-01-01]
      assert [%{quote: "on Rubus villosus frondosus"}] = moved.evidence
      assert standing(asserted) == :current

      assert correction.kind == :host
      assert correction.change =~ "Rubus frondosus"
    end

    test "a Host the Source already states elsewhere: only the wrong one goes", ctx do
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.paper))
      held = host!(ctx.gall, ctx.idaeus, confirm(ctx.paper, %{value_as_written: "R. idaeus"}))

      assert {:ok, %{withdrawn: [_], asserted: [asserted]}} =
               Import.correct_source_fact(
                 test_actor(),
                 ctx.paper.id,
                 fact.id,
                 {:host, ctx.idaeus.id},
                 "It said idaeus."
               )

      assert asserted == held.id
      assert Facts.get_attribution(held.id, ctx.paper.id).value_as_written == "R. idaeus"
    end

    test "the same Host is no correction", ctx do
      fact = host!(ctx.gall, ctx.rubus, confirm(ctx.paper))

      assert {:error, :unchanged} =
               Import.correct_source_fact(
                 test_actor(),
                 ctx.paper.id,
                 fact.id,
                 {:host, ctx.rubus.id},
                 "Same."
               )
    end

    test "another Trait value, or several: one statement each, the term kept", ctx do
      fact = trait!(ctx.gall, "color", "red", confirm(ctx.paper, %{term: "reddish"}))

      assert {:ok, %{withdrawn: [withdrawn], asserted: asserted}} =
               Import.correct_source_fact(
                 test_actor(),
                 ctx.paper.id,
                 fact.id,
                 {:values, ["brown", "yellow"]},
                 "The plate shows brown and yellow."
               )

      assert withdrawn == fact.id
      assert length(asserted) == 2

      for value <- ["brown", "yellow"] do
        {:ok, id} = Catalog.find_gall_fact(ctx.gall.id, {:trait, "color", value})
        assert id in asserted
        assert Facts.get_attribution(id, ctx.paper.id).term == "reddish"
      end
    end

    test "keeping the Trait's value among the new ones withdraws nothing", ctx do
      fact = trait!(ctx.gall, "color", "red", confirm(ctx.paper))

      assert {:ok, %{withdrawn: [], asserted: [_brown]}} =
               Import.correct_source_fact(
                 test_actor(),
                 ctx.paper.id,
                 fact.id,
                 {:values, ["red", "brown"]},
                 "Red and brown."
               )

      assert %Attribution{} = Facts.get_attribution(fact.id, ctx.paper.id)
    end

    test "a correction that doesn't fit the Fact is refused", ctx do
      fact = trait!(ctx.gall, "color", "red", confirm(ctx.paper))

      assert {:error, :not_correctable} =
               Import.correct_source_fact(
                 test_actor(),
                 ctx.paper.id,
                 fact.id,
                 {:host, ctx.idaeus.id},
                 "?"
               )
    end
  end

  describe "a taxonomic statement" do
    setup ctx do
      family = taxon_fixture(rank: :family, name: "Aphididae", kingdom: "Animalia")
      aphis = taxon_fixture(rank: :genus, name: "Aphis", kingdom: "Animalia", parent: family)

      other =
        taxon_fixture(rank: :genus, name: "Amphorophora", kingdom: "Animalia", parent: family)

      species = taxon_fixture(name: "Aphis rubifolii", kingdom: "Animalia", parent: aphis)

      for taxon <- [family, aphis, other, species] do
        taxon = Taxa.get_taxon!(taxon.id)
        key = %{taxon_id: taxon.id, parent_id: taxon.parent_id}
        {:ok, _} = Taxa.assert_placement(test_actor(), key, confirm(ctx.legacy, %{stated: nil}))
      end

      {:ok, %{fact: fact, attribution: attribution}} =
        Taxa.assert_placement(
          test_actor(),
          %{taxon_id: species.id, parent_id: aphis.id},
          confirm(ctx.paper)
        )

      {:ok, _} = Import.TaxonomicDecisions.decide(test_actor(), :accept, attribution.id)

      %{species: species, aphis: aphis, other: other, placement: fact}
    end

    defp placement(species, parent) do
      {:ok, id} = Taxa.find_act_fact(:placement, %{taxon_id: species.id, parent_id: parent.id})
      id
    end

    defp open_questions(attribution_id) do
      Repo.all(
        from(q in QueueItem,
          where:
            q.kind == :taxonomy_acceptance and q.status == :open and
              fragment("(?->>'attribution_id')::bigint", q.subject) == ^attribution_id
        )
      )
    end

    test "withdrawn, the tree follows what is left", ctx do
      assert {:ok, %{withdrawn: [_]}} =
               Import.correct_source_fact(
                 test_actor(),
                 ctx.paper.id,
                 ctx.placement.id,
                 :withdraw,
                 "Not in this paper."
               )

      assert Facts.get_attribution(ctx.placement.id, ctx.paper.id) == nil
      assert Taxa.get_taxon!(ctx.species.id).parent_id == ctx.aphis.id
    end

    test "another parent, accepted in the same step: the tree follows", ctx do
      assert {:ok, %{asserted: [asserted]}} =
               Import.correct_source_fact(
                 test_actor(),
                 ctx.paper.id,
                 ctx.placement.id,
                 {:parent, ctx.other.id},
                 "The paper moves it to Amphorophora.",
                 accept: true
               )

      assert asserted == placement(ctx.species, ctx.other)
      assert %{accepted_at: %DateTime{}} = Facts.get_attribution(asserted, ctx.paper.id)
      assert Taxa.get_taxon!(ctx.species.id).parent_id == ctx.other.id
      assert :taxonomic_decision in Enum.map(Import.list_replay_entries(), & &1.kind)
    end

    test "another parent, not accepted: it awaits a curator, asked in the queue", ctx do
      assert {:ok, %{asserted: [asserted]}} =
               Import.correct_source_fact(
                 test_actor(),
                 ctx.paper.id,
                 ctx.placement.id,
                 {:parent, ctx.other.id},
                 "The paper moves it to Amphorophora."
               )

      attribution = Facts.get_attribution(asserted, ctx.paper.id)
      assert attribution.accepted_at == nil
      assert Taxa.get_taxon!(ctx.species.id).parent_id == ctx.aphis.id
      assert [_question] = open_questions(attribution.id)
    end

    test "a withdrawn statement's open question goes with it", ctx do
      {:ok, %{asserted: [asserted]}} =
        Import.correct_source_fact(
          test_actor(),
          ctx.paper.id,
          ctx.placement.id,
          {:parent, ctx.other.id},
          "Moved."
        )

      attribution = Facts.get_attribution(asserted, ctx.paper.id)
      assert [_question] = open_questions(attribution.id)

      {:ok, _} =
        Import.correct_source_fact(test_actor(), ctx.paper.id, asserted, :withdraw, "No, wrong.")

      assert open_questions(attribution.id) == []
    end
  end

  describe "replay" do
    test "makes the correction again on the Facts found by stable keys, once", ctx do
      words = confirm(ctx.paper, %{value_as_written: "Rubus"})
      fact = host!(ctx.gall, ctx.rubus, words)

      {:ok, _} =
        Import.correct_source_fact(
          test_actor(),
          ctx.paper.id,
          fact.id,
          {:host, ctx.frondosus.id},
          "It is frondosus."
        )

      logged = entries(:source_correction)

      # The data as the cutover brings it back: the Source states the genus again.
      {:ok, _} =
        Facts.remove_attribution(test_actor(), host_fact(ctx.gall, ctx.frondosus), ctx.paper.id)

      _ = host!(ctx.gall, ctx.rubus, words)

      assert {:ok, 1} = Replay.run(logged, actor: test_actor())
      assert Facts.get_attribution(fact.id, ctx.paper.id) == nil

      assert %Attribution{} =
               Facts.get_attribution(host_fact(ctx.gall, ctx.frondosus), ctx.paper.id)

      [newest | _] = Import.list_source_corrections(ctx.paper.id)
      assert newest.author_name == "test"
      assert newest.note == "It is frondosus."

      count = length(Import.list_source_corrections(ctx.paper.id))
      assert {:ok, 1} = Replay.run(logged, actor: test_actor())
      assert length(Import.list_source_corrections(ctx.paper.id)) == count
    end
  end

  describe "finding a Source's Facts" do
    test "counts the Source's gall Facts, searches its Galls, and shows one Gall's", ctx do
      other_gall = gall_fixture()
      host!(ctx.gall, ctx.rubus, confirm(ctx.paper))
      trait!(ctx.gall, "color", "red", confirm(ctx.paper))
      host!(other_gall, ctx.idaeus, confirm(ctx.paper))
      host!(gall_fixture(), ctx.idaeus, confirm(ctx.legacy, %{stated: nil}))

      assert Import.source_fact_count(ctx.paper.id) == 3

      name = Catalog.get_gall!(ctx.gall.id) |> Gall.display_name()
      assert [%{id: id, name: ^name}] = Import.search_source_galls(ctx.paper.id, name, 10)
      assert id == ctx.gall.id

      assert %{galls: [%{gall_id: gall_id, facts: facts}]} =
               Import.facts_for_source(ctx.paper.id, gall_ids: [ctx.gall.id])

      assert gall_id == ctx.gall.id
      assert [_host] = facts.hosts
      assert [_red] = facts.traits["color"]
    end
  end
end
