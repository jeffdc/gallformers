defmodule Gallformers.Import.SetAsideTest do
  @moduledoc """
  What producers set aside as hedged or not a Fact (`unmapped`; `6611`
  Task 2): each term within a package becomes one non-blocking queue item
  covering every Gall it was set aside for, decided keep or state it;
  stated decisions write the Facts on apply. (Trait terms set aside are
  `Gallformers.Import.TraitTerms`'s.)

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.Queue
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Import.SetAside
  alias Gallformers.Import.StableRef
  alias Gallformers.Places
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

    Repo.insert_all("place", [%{name: "Testland", code: "XT", type: "state"}],
      on_conflict: :nothing
    )

    %{lobata: lobata, douglasii: douglasii, wasp: wasp, gall: gall}
  end

  @tan_g1 %{
    "term" => "Pale Tan",
    "slot" => "other",
    "gall" => "g1",
    "note" => "for one Host only",
    "evidence" => [%{"item" => "#/texts/1", "quote" => "pale tan"}]
  }

  @tan_g2 %{
    "term" => "pale  tan",
    "slot" => "other",
    "gall" => "g2",
    "evidence" => [%{"item" => "#/texts/1", "quote" => "pale tan when mature"}]
  }

  @hills %{
    "term" => "throughout the hills",
    "slot" => "place",
    "gall" => "g1",
    "note" => "no place is named",
    "evidence" => [%{"item" => "#/texts/2", "quote" => "throughout the hills"}]
  }

  # The fixture gall batch with a second, new Gall (the wasp's sexual
  # generation) and `unmapped` entries.
  defp gall_batch(unmapped \\ [@tan_g1, @tan_g2, @hills]) do
    batch()
    |> unique_batch_id()
    |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
    |> Map.update!("galls", fn galls ->
      galls ++
        [
          %{
            "ref" => "g2",
            "name_as_written" => "the small bud galls",
            "new" => true,
            "identified_by" => %{
              "inducer" => "t1",
              "generation" => %{"value" => "sexual", "as_written" => "sexual generation"}
            }
          }
        ]
    end)
    |> Map.update!("facts", fn facts ->
      facts ++
        [
          %{
            "id" => "f5",
            "stance" => "confirm",
            "kind" => "relationship",
            "type" => "inducer_of",
            "subject" => "t1",
            "object" => "g2",
            "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
          }
        ]
    end)
    |> Map.put("unmapped", unmapped)
  end

  @brown %{"state" => %{"kind" => "trait", "trait" => "color", "value" => "brown"}}

  defp deliver(batch \\ gall_batch(), findings \\ []),
    do: package(gall: batch) |> with_review(findings, responded: true) |> deliver!()

  defp set_aside(package),
    do:
      Enum.filter(Import.list_queue_items(package, status: :all), &(&1.kind in SetAside.kinds()))

  @tan "u:other:pale tan"
  # The ref is the normalized term: plurals are folded (`TraitTermMapping.normalize/1`).
  @hills_ref "u:place:throughout the hill"

  defp item(package, ref), do: Enum.find(set_aside(package), &(&1.statement_ref == ref))

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  defp statements(package),
    do: package |> gall_row() |> Import.list_statements() |> Map.new(&{{&1.kind, &1.ref}, &1})

  defp gall_id(package, ref), do: statements(package)[{:gall, ref}].gall_id

  defp attribution(fact_id, source_id),
    do: Enum.find(Facts.list_attributions(fact_id), &(&1.source_id == source_id))

  defp approve!(package) do
    {:ok, _} = Import.approve_package(test_actor(), package)
    Import.get_package!(package.id)
  end

  defp decide!(item, decision) do
    {:ok, item} = Import.decide_queue_item(test_actor(), item, decision)
    item
  end

  describe "queueing" do
    test "each term becomes one item of its kind, covering every Gall it was set aside for" do
      package = deliver()

      assert [%QueueItem{} = term, %QueueItem{} = statement] =
               Enum.sort_by(set_aside(package), &(&1.statement_ref != @tan))

      assert term.kind == :set_aside_statement
      assert term.statement_ref == @tan
      assert term.batch_id == gall_row(package).id
      assert term.proposal == %{"keep" => true}
      assert term.subject["slot"] == "other"
      assert term.subject["term"] == "Pale Tan"

      assert [
               %{
                 "gall" => "g1",
                 "name_as_written" => "the large stem galls",
                 "term" => "Pale Tan",
                 "note" => "for one Host only",
                 "evidence" => [%{"item" => "#/texts/1", "quote" => "pale tan"}]
               },
               %{
                 "gall" => "g2",
                 "name_as_written" => "the small bud galls",
                 "term" => "pale  tan"
               }
             ] = term.subject["covers"]

      assert statement.kind == :set_aside_statement
      assert statement.statement_ref == @hills_ref
      assert statement.proposal == %{"keep" => true}
      assert [%{"gall" => "g1", "note" => "no place is named"}] = statement.subject["covers"]
    end

    test "an item carries its topic, from its first entry" do
      entry = fn term, topic ->
        %{"term" => term, "slot" => "other", "evidence" => [], "note" => "hedged"}
        |> then(&if(topic, do: Map.put(&1, "topic", topic), else: &1))
      end

      content = %{
        "unmapped" => [
          entry.("may be found in Arkansas", "range"),
          entry.("presumed Diastrophus", nil)
        ]
      }

      assert [range, none] = SetAside.queue_items(content)
      assert range.subject["topic"] == "range"
      assert none.subject["topic"] == nil
    end

    test "they never hold approval" do
      package = deliver()

      for item <- set_aside(package),
          type <- [:gall, :taxonomy, nil],
          do: refute(Queue.blocking?(item, type))

      assert %{status: :approved} = approve!(package)
      assert length(set_aside(package)) == 2
    end

    test "a taxonomy batch's entries are queued too, covering no Gall" do
      taxonomy =
        taxonomy_batch()
        |> unique_batch_id()
        |> Map.put("unmapped", [
          %{
            "term" => "stat. rev.",
            "slot" => "taxonomic_act",
            "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
          }
        ])

      package =
        package(gall: gall_batch([]), taxonomy: taxonomy)
        |> with_review([], responded: true)
        |> deliver!()

      assert [%QueueItem{kind: :set_aside_statement, statement_ref: "u:taxonomic_act:stat. rev."}] =
               set_aside(package)

      assert [%{"gall" => nil, "name_as_written" => nil}] =
               item(package, "u:taxonomic_act:stat. rev.").subject["covers"]
    end

    test "re-resolving keeps open items' IDs and decided items' decisions" do
      package = deliver()
      term = item(package, @tan)
      statement = decide!(item(package, @hills_ref), %{"keep" => true})

      {:ok, package} = Import.resolve_package(test_actor(), package)

      assert [%QueueItem{id: term_id, status: :open}, %QueueItem{id: statement_id} = decided] =
               Enum.sort_by(set_aside(package), &(&1.statement_ref != @tan))

      assert term_id == term.id
      assert statement_id == statement.id
      assert decided.status == :decided
      assert decided.decision == %{"keep" => true}
    end
  end

  describe "decisions" do
    defp statement_item(covers \\ [%{"gall" => "g1"}]),
      do: %QueueItem{
        kind: :set_aside_statement,
        statement_ref: "u:place:hills",
        subject: %{"slot" => "place", "term" => "hills", "covers" => covers}
      }

    defp valid?(item, decision),
      do: Queue.validate_decision(Ecto.Changeset.change(item), item, decision).valid?

    test "keep" do
      assert valid?(statement_item(), %{"keep" => true, "note" => "hedged"})
      refute valid?(statement_item(), %{"keep" => false})
      refute valid?(statement_item(), %{})
    end

    test "state a Trait, a Host or an occurrence", ctx do
      trait = %{"kind" => "trait", "trait" => "texture", "value" => "bumpy"}
      host = %{"kind" => "host_of", "taxon_id" => ctx.douglasii.id}
      occurrence = %{"kind" => "occurrence", "place" => "XT"}

      for spec <- [trait, host, occurrence],
          do: assert(valid?(statement_item(), %{"state" => spec}))

      for bad <- [
            %{trait | "value" => "brown"},
            %{trait | "trait" => "generation"},
            Map.put(trait, "extra", 1),
            %{host | "taxon_id" => ctx.wasp.id},
            %{host | "taxon_id" => -1},
            %{host | "taxon_id" => "#{ctx.douglasii.id}"},
            %{occurrence | "place" => "nowhere"},
            %{"kind" => "range", "place" => "XT"},
            "Host: Quercus"
          ],
          do: refute(valid?(statement_item(), %{"state" => bad}), inspect(bad))

      refute valid?(statement_item([%{"gall" => nil}]), %{"state" => occurrence})
    end

    test "no Trait value or request for a statement" do
      refute valid?(statement_item(), %{"trait_value" => "brown"})
      refute valid?(statement_item(), %{"request_value" => true})
    end

    test "one choice at a time" do
      refute valid?(statement_item(), %{"keep" => true, "state" => %{}})
    end
  end

  describe "applying" do
    test "a stated Trait is written on every Gall it covers, the quote as evidence", ctx do
      package = deliver()
      decide!(item(package, @tan), @brown)
      package = approve!(package)

      g1 = gall_id(package, "g1")
      g2 = gall_id(package, "g2")
      assert g1 == ctx.gall.id

      for {gall, quote} <- [{g1, "pale tan"}, {g2, "pale tan when mature"}] do
        assert {:ok, fact_id} =
                 Catalog.find_fact(:trait, %{gall_id: gall, trait: "color", value: "brown"})

        assert is_integer(fact_id)
        attribution = attribution(fact_id, package.source_id)
        assert [%{quote: ^quote}] = attribution.evidence
        assert attribution.value_as_written in ["Pale Tan", "pale  tan"]
      end

      s = statements(package)
      assert %BatchStatement{fact_id: id} = s[{:fact, "u:other:pale tan@g1"}]
      assert is_integer(id)
    end

    test "a stated Host and occurrence are written for the Galls covered", ctx do
      package = deliver()

      decide!(item(package, @tan), %{
        "state" => %{"kind" => "host_of", "taxon_id" => ctx.douglasii.id}
      })

      decide!(item(package, @hills_ref), %{
        "state" => %{"kind" => "occurrence", "place" => "XT"}
      })

      package = approve!(package)

      g1 = gall_id(package, "g1")
      g2 = gall_id(package, "g2")

      for gall <- [g1, g2] do
        assert ctx.douglasii.id in Enum.map(Catalog.gall_summary(gall).hosts, & &1.taxon_id)
      end

      place = Places.get_place_by_code("XT")
      assert {:ok, fact_id} = Catalog.find_fact(:occurrence, %{gall_id: g1, place_id: place.id})
      assert is_integer(fact_id)

      assert [%{quote: "throughout the hills"}] =
               attribution(fact_id, package.source_id).evidence

      assert {:ok, nil} = Catalog.find_fact(:occurrence, %{gall_id: g2, place_id: place.id})
    end

    test "keep writes nothing" do
      package = deliver()
      decide!(item(package, @tan), %{"keep" => true})
      decide!(item(package, @hills_ref), %{"keep" => true})
      package = approve!(package)

      refute Enum.any?(Map.keys(statements(package)), fn {_kind, ref} ->
               String.starts_with?(ref, "u:")
             end)

      assert {:ok, nil} =
               Catalog.find_fact(:trait, %{
                 gall_id: gall_id(package, "g1"),
                 trait: "color",
                 value: "brown"
               })
    end

    test "a covered Gall that is not resolved at apply is skipped with a reason" do
      finding = %{
        "batch" => "gall.json",
        "id" => "g2",
        "problem" => "unsupported",
        "reason" => "no such Gall",
        "response" => %{"decision" => "disagree", "reason" => "there is"}
      }

      package = deliver(gall_batch(), [finding])
      [dispute] = Import.list_queue_items(package, kind: :dispute)
      decide!(dispute, %{"skip" => true})
      decide!(item(package, @tan), @brown)
      package = approve!(package)

      s = statements(package)
      assert is_integer(s[{:fact, "u:other:pale tan@g1"}].fact_id)
      assert %BatchStatement{fact_id: nil, detail: detail} = s[{:fact, "u:other:pale tan@g2"}]
      assert detail["skipped"] =~ "g2"
    end
  end

  describe "deciding after the gall batch is applied" do
    test "a stated Trait's Facts are written at once", ctx do
      package = deliver() |> approve!()
      assert gall_row(package).status == :applied

      decide!(item(package, @tan), @brown)

      g1 = gall_id(package, "g1")
      assert g1 == ctx.gall.id

      for {gall, quote} <- [{g1, "pale tan"}, {gall_id(package, "g2"), "pale tan when mature"}] do
        assert {:ok, fact_id} =
                 Catalog.find_fact(:trait, %{gall_id: gall, trait: "color", value: "brown"})

        assert is_integer(fact_id)
        assert [%{quote: ^quote}] = attribution(fact_id, package.source_id).evidence
      end

      assert is_integer(statements(package)[{:fact, "u:other:pale tan@g1"}].fact_id)
    end

    test "a stated Host is written at once, and keep writes nothing", ctx do
      package = deliver() |> approve!()

      decide!(item(package, @hills_ref), %{
        "state" => %{"kind" => "host_of", "taxon_id" => ctx.douglasii.id}
      })

      decide!(item(package, @tan), %{"keep" => true})

      assert ctx.douglasii.id in Enum.map(Catalog.gall_summary(ctx.gall.id).hosts, & &1.taxon_id)
      refute Map.has_key?(statements(package), {:fact, "u:other:pale tan@g1"})
    end

    test "writing again changes nothing", ctx do
      package = deliver() |> approve!()
      item = decide!(item(package, @tan), @brown)

      assert {:ok, :written} = Import.apply_set_aside_decision(test_actor(), item)

      assert {:ok, fact_id} =
               Catalog.find_fact(:trait, %{gall_id: ctx.gall.id, trait: "color", value: "brown"})

      assert [_] =
               Enum.filter(Facts.list_attributions(fact_id), &(&1.source_id == package.source_id))
    end

    test "before the batch is applied it waits for the batch" do
      package = deliver()
      item = decide!(item(package, @tan), @brown)
      assert {:ok, :not_applied} = Import.apply_set_aside_decision(test_actor(), item)
      refute Map.has_key?(statements(package), {:fact, "u:other:pale tan@g1"})
    end

    test "replays to the same Facts", ctx do
      package = deliver() |> approve!()
      before = MapSet.new(Import.list_replay_entries(), & &1.id)

      {:error, {:undone, entries}} =
        Repo.transaction(fn ->
          decide!(item(package, @tan), @brown)

          Repo.rollback(
            {:undone, Enum.reject(Import.list_replay_entries(), &MapSet.member?(before, &1.id))}
          )
        end)

      assert {:ok, nil} =
               Catalog.find_fact(:trait, %{gall_id: ctx.gall.id, trait: "color", value: "brown"})

      assert {:ok, 1} = Replay.run(entries, actor: test_actor())
      assert_replays_again(entries, test_actor())

      assert {:ok, fact_id} =
               Catalog.find_fact(:trait, %{gall_id: ctx.gall.id, trait: "color", value: "brown"})

      assert is_integer(fact_id)
    end
  end

  describe "replay" do
    test "a decision is logged with stable references and replays", ctx do
      package = deliver()
      item = item(package, @hills_ref)
      decision = %{"state" => %{"kind" => "host_of", "taxon_id" => ctx.douglasii.id}}

      encoded = StableRef.encode_decision(decision)

      assert %{"state" => %{"kind" => "host_of", "taxon" => %{"name" => "Quercus douglasii"}}} =
               encoded

      assert StableRef.decode_decision(encoded) == {:ok, decision}

      entry = %{
        kind: :queue_decision,
        key: %{
          "package" => package.key,
          "batch_id" => gall_row(package).producer_batch_id,
          "kind" => "set_aside_statement",
          "statement_ref" => item.statement_ref
        },
        payload: %{"decision" => encoded}
      }

      assert {:ok, 1} = Replay.run([entry], actor: test_actor())
      assert_replays_again([entry], test_actor())
      assert %QueueItem{status: :decided, decision: ^decision} = Repo.reload!(item)

      assert %{key: key, payload: %{"decision" => ^encoded}} =
               List.last(Import.list_replay_entries())

      assert key["statement_ref"] == item.statement_ref
    end
  end
end
