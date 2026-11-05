defmodule Gallformers.Import.TraitTermsTest do
  @moduledoc """
  Placing a Source's Trait terms on import (matter `d213`, Task C): a
  placed term's Fact goes on its category; an ambiguous term's use, when
  the readers agree for its Gall; a new term is placed for every Source
  when the readers agree; a term that fits no category stays text. The
  rest are questions (`:trait_term`, one per term per package, holding
  nothing), decided by placing the term for every Source, using a
  category for these Galls only, marking it as fitting no category, or
  keeping it as text.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.DoclingFixtures
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.Queue
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Import.TraitTerms
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    plant_fixture(name: "Quercus lobata", parent: quercus)
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

    %{gall: gall}
  end

  @words "The galls are ovoid and globular, round, each with a single insect, pale tan, " <>
           "rough, lumpy and bumpy, " <>
           "a swelling on the leaf, woody, lignified, green-yellow, tan-white, " <>
           "protruding from both sides."

  # The fixture document with one more text item holding the terms.
  defp doc do
    doc = DoclingFixtures.document()

    words = %{
      "self_ref" => "#/texts/5",
      "label" => "text",
      "content_layer" => "body",
      "text" => @words,
      "prov" => [%{"page_no" => 2, "bbox" => %{}, "charspan" => [0, 0]}],
      "children" => []
    }

    doc
    |> Map.update!("texts", &(&1 ++ [words]))
    |> update_in(["body", "children"], &(&1 ++ [%{"$ref" => "#/texts/5"}]))
  end

  # A format 4 trait Fact: the Source's term, the producer's category.
  defp trait(id, gall, trait, term, category, extra \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "stance" => "confirm",
        "kind" => "trait",
        "gall" => gall,
        "trait" => trait,
        "term" => term,
        "category" => category && %{"value" => category},
        "evidence" => [%{"item" => "#/texts/5", "quote" => term}]
      },
      extra
    )
  end

  # A format 3 trait Fact: the value and the Source's words.
  defp trait3(id, gall, trait, value, as_written),
    do: %{
      "id" => id,
      "stance" => "confirm",
      "kind" => "trait",
      "gall" => gall,
      "trait" => trait,
      "value" => %{"value" => value, "as_written" => as_written},
      "evidence" => [%{"item" => "#/texts/5", "quote" => as_written}]
    }

  # g1 (held) and g2 (new), with `traits`.
  defp gall_batch(traits, opts \\ []) do
    batch()
    |> unique_batch_id()
    |> Map.put("format_version", Keyword.get(opts, :version, 4))
    |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
    |> then(fn b ->
      case opts[:title] do
        nil ->
          b

        title ->
          b
          |> put_in(["source", "title"], title)
          |> put_in(["source", "citation"], "A. 2024. #{title}.")
      end
    end)
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
        ] ++ traits
    end)
    |> then(&if opts[:unmapped], do: Map.put(&1, "unmapped", opts[:unmapped]), else: &1)
  end

  # Delivers `batch`; `review` options as `with_review/3` takes them.
  defp deliver(batch, review \\ []) do
    package(gall: batch, doc: doc())
    |> with_review(Keyword.get(review, :findings, []), Keyword.put(review, :responded, true))
    |> deliver!()
  end

  defp placement(id, category, extra \\ %{}),
    do: Map.merge(%{"id" => id, "category" => category && %{"value" => category}}, extra)

  defp questions(package), do: Import.list_queue_items(package, kind: :trait_term, status: :all)

  defp question(package), do: package |> questions() |> hd()

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  defp statements(package),
    do: package |> gall_row() |> Import.list_statements() |> Map.new(&{{&1.kind, &1.ref}, &1})

  defp gall_id(package, ref), do: statements(package)[{:gall, ref}].gall_id

  defp approve!(package) do
    {:ok, _} = Import.approve_package(test_actor(), package)
    Import.get_package!(package.id)
  end

  defp decide!(item, decision) do
    {:ok, item} = Import.decide_queue_item(test_actor(), item, decision)
    item
  end

  defp traits(gall_id, trait), do: Catalog.gall_summary(gall_id).traits[trait] || []

  defp attribution(gall_id, trait, value, source_id) do
    {:ok, fact_id} = Catalog.find_fact(:trait, %{gall_id: gall_id, trait: trait, value: value})
    assert is_integer(fact_id), "no #{trait} #{value} Fact"
    Enum.find(Facts.list_attributions(fact_id), &(&1.source_id == source_id))
  end

  defp pending(gall_id), do: Catalog.list_pending_terms(gall_id, include_settled: true)

  describe "a placed term" do
    test "goes on its category, the Source's term on the attribution", ctx do
      package = deliver(gall_batch([trait("f6", "g1", "shape", "ovoid", "globular")]))
      assert questions(package) == []

      package = approve!(package)
      assert traits(ctx.gall.id, "shape") == ["globular"]
      assert attribution(ctx.gall.id, "shape", "globular", package.source_id).term == "ovoid"
      assert statements(package)[{:fact, "f6"}].flags == []
    end

    test "a term that is the name of a value is placed under it", ctx do
      package = deliver(gall_batch([trait("f6", "g1", "shape", "globular", "globular")]))
      assert questions(package) == []
      approve!(package)
      assert traits(ctx.gall.id, "shape") == ["globular"]
    end

    test "the producer suggesting another category is noted for a spot check", ctx do
      package = deliver(gall_batch([trait("f6", "g1", "texture", "rough", "bumpy")]))
      assert questions(package) == []
      package = approve!(package)

      assert traits(ctx.gall.id, "texture") == ["mealy"]
      row = statements(package)[{:fact, "f6"}]
      assert "suggested_other_category" in row.flags

      assert %{"term" => "rough", "category" => "mealy", "suggested" => ["bumpy"]} =
               row.detail["spot_check"]

      assert [%{trait: "texture", term: "rough", category: "mealy", suggested: ["bumpy"]}] =
               Import.list_term_spot_checks()
    end

    test "on the leaf, with no side stated, is one leaf Fact", ctx do
      package = deliver(gall_batch([trait("f6", "g1", "plant_part", "on the leaf", "leaf")]))

      assert questions(package) == []
      approve!(package)
      assert traits(ctx.gall.id, "plant_part") == ["leaf"]
    end
  end

  describe "a term naming several values" do
    # g1's Facts using `term`, one per category the producer suggests (the
    # checker placing each alike).
    defp several(trait, term, categories) do
      categories
      |> Enum.with_index(6)
      |> Enum.map(fn {c, i} -> trait("f#{i}", "g1", trait, term, c) end)
      |> gall_batch()
    end

    test "agreement on its values places a new term under each, writing a Fact for each", ctx do
      for {trait, term, categories} <- [
            {"color", "green-yellow", ["green", "yellow"]},
            {"plant_part", "protruding from both sides", ["upper leaf", "lower leaf"]}
          ] do
        package = trait |> several(term, categories) |> deliver()
        assert questions(package) == []
        package = approve!(package)

        assert %{status: :placed, categories: ^categories, placed_by: :agreement} =
                 Catalog.get_term(trait, term)

        assert Enum.sort(traits(ctx.gall.id, trait)) == Enum.sort(categories)

        for c <- categories,
            do: assert(attribution(ctx.gall.id, trait, c, package.source_id).term == term)

        assert [%{payload: %{"categories" => ^categories, "placed_by" => "agreement"}}] =
                 Enum.filter(
                   Import.list_replay_entries(),
                   &(&1.kind == :trait_term_edit and &1.key["term"] == term)
                 )
      end
    end

    test "a placed term naming two values writes both for a later Source's use", ctx do
      {:ok, _} =
        Catalog.place_term(test_actor(), "color", "green-yellow", ["green", "yellow"], :curator)

      package =
        deliver(
          gall_batch([
            trait("f6", "g1", "color", "Green-yellow", "green", %{
              "evidence" => [%{"item" => "#/texts/5", "quote" => "green-yellow"}]
            })
          ])
        )

      assert questions(package) == []
      package = approve!(package)

      assert Enum.sort(traits(ctx.gall.id, "color")) == ["green", "yellow"]

      for c <- ["green", "yellow"],
          do:
            assert(attribution(ctx.gall.id, "color", c, package.source_id).term == "Green-yellow")
    end

    test "readers agreeing on different sets is a question" do
      package =
        deliver(several("color", "green-yellow", ["green", "yellow"]),
          placements: [placement("f6", "green"), placement("f7", "green")]
        )

      assert [%QueueItem{status: :open}] = questions(package)
      assert Catalog.get_term("color", "green-yellow") == nil
    end

    test "a single-category term is unchanged: one Fact", ctx do
      package = deliver(gall_batch([trait("f6", "g1", "color", "pale tan", "tan")]))
      approve!(package)
      assert %{categories: ["tan"]} = Catalog.get_term("color", "pale tan")
      assert traits(ctx.gall.id, "color") == ["tan"]
    end
  end

  describe "an ambiguous term" do
    test "is written when the producer and the checker agree for this Gall", ctx do
      package =
        deliver(
          gall_batch([
            trait("f6", "g1", "form", "swelling", "abrupt swelling", %{"depends_on_gall" => true})
          ])
        )

      assert questions(package) == []
      approve!(package)
      assert traits(ctx.gall.id, "form") == ["abrupt swelling"]
      assert Catalog.get_term("form", "swelling").status == :ambiguous
    end

    test "is a question when they disagree, or one finds no category" do
      for other <- ["stem club", nil] do
        package =
          deliver(
            gall_batch([trait("f6", "g1", "form", "swelling", "abrupt swelling")]),
            placements: [placement("f6", other, %{"depends_on_gall" => true})]
          )

        assert [%QueueItem{kind: :trait_term, status: :open} = q] = questions(package)
        assert q.subject["status"] == "ambiguous"

        assert Enum.sort(q.subject["candidates"]) ==
                 ["abrupt swelling", "stem club", "tapered swelling"]

        assert q.proposal == %{}
      end
    end
  end

  describe "a term that fits no category" do
    test "writes no Fact and stays as text on the Gall", ctx do
      {:ok, _} = Catalog.mark_term_no_fit(test_actor(), "texture", "bumpy", :superadmin)
      package = deliver(gall_batch([trait("f6", "g1", "texture", "bumpy", nil)]))
      assert questions(package) == []

      package = approve!(package)
      assert traits(ctx.gall.id, "texture") == []

      assert [%{term: "bumpy", settled_categories: [], settled_at: %DateTime{}} = text] =
               pending(ctx.gall.id)

      assert text.source_id == package.source_id
      assert %BatchStatement{fact_id: nil} = statements(package)[{:fact, "f6"}]

      assert [%{trait: "texture", term: "bumpy", uses: 1}] = Catalog.list_no_fit_terms()
    end
  end

  describe "a new term" do
    test "is placed for every Source by agreement when the batch is applied", ctx do
      package = deliver(gall_batch([trait("f6", "g1", "color", "pale tan", "tan")]))
      assert questions(package) == []
      # Resolving changes nothing.
      assert Catalog.get_term("color", "pale tan") == nil

      package = approve!(package)

      assert %{status: :placed, categories: ["tan"], placed_by: :agreement} =
               Catalog.get_term("color", "pale tan")

      assert traits(ctx.gall.id, "color") == ["tan"]
      assert attribution(ctx.gall.id, "color", "tan", package.source_id).term == "pale tan"

      assert [%{payload: %{"category" => "tan", "placed_by" => "agreement"}}] =
               Enum.filter(
                 Import.list_replay_entries(),
                 &(&1.kind == :trait_term_edit and &1.key["op"] == "place" and
                     &1.key["term"] == "pale tan")
               )
    end

    test "agreeing on no category marks it as fitting none, kept as text", ctx do
      package = deliver(gall_batch([trait("f6", "g1", "texture", "lumpy", nil)]))
      assert questions(package) == []
      approve!(package)

      assert %{status: :no_fit, placed_by: :agreement} = Catalog.get_term("texture", "lumpy")
      assert [%{term: "lumpy", settled_categories: []}] = pending(ctx.gall.id)
    end

    test "agreeing on a category that depends on the Gall is a question, proposing it" do
      package =
        deliver(
          gall_batch([
            trait("f6", "g1", "texture", "lumpy", "bumpy", %{"depends_on_gall" => true})
          ])
        )

      assert [q] = questions(package)
      assert q.proposal == %{"category" => "bumpy"}
      assert Import.proposed_decision(q) == {:ok, %{"category" => "bumpy"}}
      assert Catalog.get_term("texture", "lumpy") == nil
    end

    test "is one question per package when the readers disagree, covering each Gall", ctx do
      package =
        deliver(
          gall_batch([
            trait("f6", "g1", "color", "pale tan", "tan"),
            trait("f7", "g2", "color", "Pale  tan", "tan", %{
              "evidence" => [%{"item" => "#/texts/5", "quote" => "pale tan, rough"}]
            })
          ]),
          placements: [placement("f6", "tan"), placement("f7", "white", %{"reason" => "pale"})]
        )

      assert [%QueueItem{} = q] = questions(package)
      assert q.statement_ref == "u:color:pale tan"
      assert q.batch_id == gall_row(package).id
      assert q.proposal == %{}
      assert %{"trait" => "color", "term" => "pale tan", "status" => "new"} = q.subject

      assert [
               %{
                 "gall" => "g1",
                 "name_as_written" => "the large stem galls",
                 "facts" => ["f6"],
                 "suggestions" => ["tan"],
                 "placements" => [%{"category" => "tan"}],
                 "evidence" => [%{"quote" => "pale tan"}]
               },
               %{
                 "gall" => "g2",
                 "term" => "Pale  tan",
                 "placements" => [%{"category" => "white", "reason" => "pale"}]
               }
             ] = q.subject["covers"]

      for type <- [:gall, :taxonomy, nil], do: refute(Queue.blocking?(q, type))
      assert Import.proposed_decision(q) == {:none, :no_proposal}

      # It holds nothing: the Galls show the term, waiting.
      package = approve!(package)
      assert gall_row(package).status == :applied
      assert traits(ctx.gall.id, "color") == []
      assert Catalog.get_term("color", "pale tan") == nil

      for ref <- ["g1", "g2"] do
        assert [%{term: _, settled_at: nil, queue_item_id: id, statement_ref: _}] =
                 pending(gall_id(package, ref))

        assert id == q.id
      end

      assert %BatchStatement{fact_id: nil, detail: %{"skipped" => skipped}} =
               statements(package)[{:fact, "f6"}]

      assert skipped =~ "question"
    end

    test "the producer suggesting nothing gives way to checkers placing it alike", ctx do
      # "round" in Osten Sacken: the producer no category, both checkers globular.
      package =
        deliver(
          gall_batch([
            trait("f6", "g1", "shape", "round", nil)
          ]),
          placements: [
            placement("f6", "globular", %{"reviewer" => "c1"}),
            placement("f6", "globular", %{"reviewer" => "c2"})
          ]
        )

      assert questions(package) == []
      package = approve!(package)

      assert %{status: :placed, categories: ["globular"], placed_by: :agreement} =
               Catalog.get_term("shape", "round")

      assert traits(ctx.gall.id, "shape") == ["globular"]
      assert attribution(ctx.gall.id, "shape", "globular", package.source_id).term == "round"
    end

    test "the producer and both checkers suggesting nothing is fitting none, by agreement" do
      package =
        deliver(gall_batch([trait("f6", "g1", "texture", "lumpy", nil)]),
          placements: [
            placement("f6", nil, %{"reviewer" => "c1"}),
            placement("f6", nil, %{"reviewer" => "c2"})
          ]
        )

      assert questions(package) == []
      approve!(package)
      assert %{status: :no_fit, placed_by: :agreement} = Catalog.get_term("texture", "lumpy")
    end

    test "a checker naming another value than the producer and the other checker is a question" do
      package =
        deliver(
          gall_batch([
            trait("f6", "g1", "cells", "each with a single insect", "monothalamous")
          ]),
          placements: [
            placement("f6", "monothalamous", %{"reviewer" => "c1"}),
            placement("f6", "polythalamous", %{"reviewer" => "c2"})
          ]
        )

      assert [%QueueItem{kind: :trait_term, status: :open} = q] = questions(package)
      assert q.proposal == %{}
      assert Catalog.get_term("cells", "each with a single insect") == nil
    end

    test "a Fact with no checker placement is a question" do
      package =
        deliver(gall_batch([trait("f6", "g1", "color", "pale tan", "tan")]), placements: [])

      assert [%QueueItem{statement_ref: "u:color:pale tan"}] = questions(package)
    end
  end

  describe "agreement/1" do
    # A use's Fact: the producer's suggestion, each checker's placement.
    defp fact(suggestion, placements, depends? \\ false) do
      %{
        suggestion: suggestion,
        depends_on_gall: false,
        placements:
          Enum.map(placements, fn {reviewer, category} ->
            %{"reviewer" => to_string(reviewer), "category" => category}
            |> then(&if depends?, do: Map.put(&1, "depends_on_gall", true), else: &1)
          end)
      }
    end

    defp agreement(facts), do: TraitTerms.agreement(%{facts: facts})

    test "a silent producer agrees with checkers placing it alike" do
      assert agreement([fact(nil, c1: "globular", c2: "globular")]) ==
               {:agree, ["globular"], false}
    end

    test "a silent producer and a single checker naming a value is no agreement" do
      assert agreement([fact(nil, c1: "globular")]) == :disagree
    end

    test "a silent producer and a single checker naming none agree on none" do
      assert agreement([fact(nil, c1: nil)]) == {:agree, [nil], false}
    end

    test "a silent producer, the checkers apart, is a disagreement" do
      for other <- ["conical", nil] do
        assert agreement([fact(nil, c1: "globular", c2: other)]) == :disagree
      end
    end

    test "a silent producer agrees with checkers placing a leaf-rule pair alike" do
      assert {:agree, categories, false} =
               agreement([
                 fact(nil, c1: "upper leaf", c2: "lower leaf"),
                 fact(nil, c1: "lower leaf", c2: "upper leaf")
               ])

      assert Enum.sort(categories) == ["lower leaf", "upper leaf"]
    end

    test "a producer suggesting for one Fact of a use is not silent" do
      assert agreement([
               fact("upper leaf", c1: "upper leaf", c2: "upper leaf"),
               fact(nil, c1: "lower leaf", c2: "lower leaf")
             ]) == :disagree
    end

    test "a silent producer with a Fact lacking checker placements is none" do
      assert agreement([fact(nil, c1: "globular"), fact(nil, [])]) == :none
    end

    test "a silent producer, the checkers saying it depends on the Gall" do
      assert agreement([fact(nil, [c1: "globular", c2: "globular"], true)]) ==
               {:agree, ["globular"], true}
    end
  end

  describe "a format 3 package" do
    test "maps placed terms, and queues new ones", ctx do
      package =
        deliver(
          gall_batch(
            [
              trait3("f6", "g1", "shape", "globular", "ovoid"),
              trait3("f7", "g1", "color", "tan", "pale tan")
            ],
            version: 3
          )
        )

      assert [%QueueItem{statement_ref: "u:color:pale tan"} = q] = questions(package)
      assert [%{"suggestions" => ["tan"], "placements" => []}] = q.subject["covers"]

      package = approve!(package)
      assert traits(ctx.gall.id, "shape") == ["globular"]
      assert attribution(ctx.gall.id, "shape", "globular", package.source_id).term == "ovoid"
      assert traits(ctx.gall.id, "color") == []
    end

    test "a Trait term set aside is a question with no suggestion" do
      unmapped = [
        %{
          "term" => "lumpy",
          "slot" => "texture",
          "gall" => "g1",
          "note" => "no texture value fits",
          "evidence" => [%{"item" => "#/texts/5", "quote" => "lumpy"}]
        }
      ]

      package = deliver(gall_batch([], version: 3, unmapped: unmapped))
      assert Import.list_queue_items(package, kind: :set_aside_term) == []
      assert [q] = questions(package)
      assert q.statement_ref == "u:texture:lumpy"

      assert [%{"gall" => "g1", "suggestions" => [nil], "note" => "no texture value fits"}] =
               q.subject["covers"]
    end

    test "a checker's finding on a Trait Fact is a disagreement on its term, not a dispute" do
      finding = %{
        "batch" => "gall.json",
        "id" => "f7",
        "problem" => "wrong_value",
        "reason" => "pale tan is white",
        "suggestion" => "color white",
        "reviewer" => "checker",
        "response" => %{"decision" => "disagree", "reason" => "it is tan"}
      }

      package =
        deliver(gall_batch([trait3("f7", "g1", "color", "tan", "pale tan")], version: 3),
          findings: [finding]
        )

      assert Import.list_queue_items(package, kind: :dispute) == []
      assert [q] = questions(package)
      assert [%{"findings" => [%{"reason" => "pale tan is white"}]}] = q.subject["covers"]
    end
  end

  describe "decisions" do
    # g1 and g2 with the color term `term`, the readers disagreeing.
    defp disagreeing(opts \\ []) do
      term = Keyword.get(opts, :term, "pale tan")

      gall_batch(
        [trait("f6", "g1", "color", term, "tan"), trait("f7", "g2", "color", term, "tan")],
        opts
      )
      |> deliver(placements: [placement("f6", "white"), placement("f7", "white")])
    end

    defp valid?(item, decision),
      do: Queue.validate_decision(Ecto.Changeset.change(item), item, decision).valid?

    test "what each takes" do
      package = disagreeing()
      q = question(package)

      assert valid?(q, %{"place" => "tan"})
      assert valid?(q, %{"category" => "white", "note" => "pale"})
      assert valid?(q, %{"no_fit" => true})
      assert valid?(q, %{"keep" => true})
      refute valid?(q, %{"place" => "no such value"})
      refute valid?(q, %{"category" => "globular"})
      refute valid?(q, %{"no_fit" => false})
      refute valid?(q, %{"keep" => true, "place" => "tan"})
      refute valid?(q, %{"trait_value" => "tan"})

      # An ambiguous term is decided per use: it isn't placed for every Source.
      {:ok, _} =
        Catalog.mark_term_ambiguous(test_actor(), "color", "pale tan", ["tan", "white"], :curator)

      refute valid?(q, %{"place" => "tan"})
      refute valid?(q, %{"no_fit" => true})
      assert valid?(q, %{"category" => "tan"})
    end

    test "place takes the values a term names: one, or several" do
      q = question(disagreeing())

      assert valid?(q, %{"place" => ["tan", "white"]})
      assert valid?(q, %{"place" => ["tan"]})
      refute valid?(q, %{"place" => []})
      refute valid?(q, %{"place" => ["tan", "no such value"]})
      refute valid?(q, %{"place" => ["tan", "tan"]})
      refute valid?(q, %{"place" => [nil]})
    end

    test "place under several: the term goes under each; every use gets a Fact for each", ctx do
      first = disagreeing(term: "tan-white") |> approve!()
      other = disagreeing(term: "tan-white", title: "Other galls")
      decide!(question(first), %{"place" => ["tan", "white"]})

      assert %{status: :placed, categories: ["tan", "white"], placed_by: :curator} =
               Catalog.get_term("color", "tan-white")

      # Waiting, in an applied batch: settled under both, written now.
      assert Enum.sort(traits(ctx.gall.id, "color")) == ["tan", "white"]
      assert Enum.sort(traits(gall_id(first, "g2"), "color")) == ["tan", "white"]

      assert pending(ctx.gall.id) |> Enum.map(& &1.settled_categories) |> Enum.uniq() ==
               [["tan", "white"]]

      # Not yet applied: its question settled alike, applying writes both.
      assert %QueueItem{status: :decided, decision: %{"place" => ["tan", "white"]}} =
               question(other)

      other = approve!(other)

      for c <- ["tan", "white"],
          do: assert(attribution(ctx.gall.id, "color", c, other.source_id).term == "tan-white")
    end

    test "place: the term goes under the category for every Source; applying writes the Facts",
         ctx do
      package = disagreeing()
      decide!(question(package), %{"place" => "tan"})

      assert %{status: :placed, categories: ["tan"], placed_by: :curator} =
               Catalog.get_term("color", "pale tan")

      package = approve!(package)
      assert traits(ctx.gall.id, "color") == ["tan"]
      assert traits(gall_id(package, "g2"), "color") == ["tan"]
      assert pending(ctx.gall.id) == []
    end

    test "place, after applying, settles every Source's waiting use of the term", ctx do
      first = disagreeing() |> approve!()
      other = disagreeing(title: "Other galls") |> approve!()
      assert other.source_id != first.source_id

      decide!(question(first), %{"place" => "tan"})

      for package <- [first, other] do
        assert attribution(ctx.gall.id, "color", "tan", package.source_id).term == "pale tan"
        assert is_integer(statements(package)[{:fact, "f6"}].fact_id)
        assert traits(gall_id(package, "g2"), "color") == ["tan"]
      end

      assert pending(ctx.gall.id) |> Enum.map(& &1.settled_categories) |> Enum.uniq() == [["tan"]]

      # The other Source's question is settled with it.
      assert %QueueItem{status: :decided, decision: %{"place" => "tan"}} = question(other)
    end

    test "place, before the other package is applied, closes its question", ctx do
      first = disagreeing()
      other = disagreeing(title: "Other galls")
      decide!(question(first), %{"place" => "tan"})

      assert %QueueItem{status: :decided, decision: %{"place" => "tan"}} = question(other)
      other = approve!(other)
      assert attribution(ctx.gall.id, "color", "tan", other.source_id).term == "pale tan"
    end

    test "category: these Galls only; the term becomes ambiguous", ctx do
      package = disagreeing()
      decide!(question(package), %{"category" => "white"})

      term = Catalog.get_term("color", "pale tan")
      assert term.status == :ambiguous
      assert "white" in term.candidates

      package = approve!(package)
      assert traits(ctx.gall.id, "color") == ["white"]
      assert traits(gall_id(package, "g2"), "color") == ["white"]

      # Another Source's use is decided on its own.
      other = disagreeing(title: "Other galls")
      assert [%QueueItem{status: :open}] = questions(other)
    end

    test "category, after applying, writes the Facts at once", ctx do
      package = disagreeing() |> approve!()
      decide!(question(package), %{"category" => "white"})

      assert attribution(ctx.gall.id, "color", "white", package.source_id).term == "pale tan"
      assert traits(gall_id(package, "g2"), "color") == ["white"]
      assert [%{settled_categories: ["white"]}] = pending(ctx.gall.id)
      assert is_integer(statements(package)[{:fact, "f7"}].fact_id)
    end

    test "categories: per Gall, each covered Gall's category or text" do
      q = question(disagreeing())

      assert valid?(q, %{"categories" => %{"g1" => "white", "g2" => nil}})
      assert valid?(q, %{"categories" => %{"g1" => "tan", "g2" => "white"}, "note" => "x"})
      # Every covered Gall, and only those.
      refute valid?(q, %{"categories" => %{"g1" => "white"}})
      refute valid?(q, %{"categories" => %{"g1" => "white", "g2" => nil, "g3" => "tan"}})
      refute valid?(q, %{"categories" => %{"g1" => "globular", "g2" => nil}})
      refute valid?(q, %{"categories" => ["white"]})

      # An ambiguous term is still decided per Gall; a term fitting none isn't.
      {:ok, _} =
        Catalog.mark_term_ambiguous(test_actor(), "color", "pale tan", ["tan", "white"], :curator)

      assert valid?(q, %{"categories" => %{"g1" => "white", "g2" => "tan"}})
      {:ok, _} = Catalog.mark_term_no_fit(test_actor(), "color", "pale tan", :superadmin)
      refute valid?(q, %{"categories" => %{"g1" => "white", "g2" => "tan"}})
    end

    test "categories: applying writes each Gall's category; text stays text", ctx do
      package = disagreeing()
      decide!(question(package), %{"categories" => %{"g1" => "white", "g2" => nil}})

      term = Catalog.get_term("color", "pale tan")
      assert term.status == :ambiguous
      assert "white" in term.candidates

      package = approve!(package)
      assert traits(ctx.gall.id, "color") == ["white"]
      g2 = gall_id(package, "g2")
      assert traits(g2, "color") == []
      assert [%{settled_categories: [], settled_at: %DateTime{}}] = pending(g2)
      assert attribution(ctx.gall.id, "color", "white", package.source_id).term == "pale tan"
    end

    test "categories, after applying, writes each Gall's Facts at once", ctx do
      package = disagreeing() |> approve!()
      decide!(question(package), %{"categories" => %{"g1" => "white", "g2" => "tan"}})

      assert traits(ctx.gall.id, "color") == ["white"]
      assert traits(gall_id(package, "g2"), "color") == ["tan"]
      assert [%{settled_categories: ["white"]}] = pending(ctx.gall.id)
      assert [%{settled_categories: ["tan"]}] = pending(gall_id(package, "g2"))

      assert Enum.sort(Catalog.get_term("color", "pale tan").candidates) == ["tan", "white"]
    end

    test "no_fit: the term fits no category; its uses stay as text", ctx do
      package = disagreeing() |> approve!()
      decide!(question(package), %{"no_fit" => true})

      assert %{status: :no_fit, placed_by: :curator} = Catalog.get_term("color", "pale tan")
      assert traits(ctx.gall.id, "color") == []
      assert [%{settled_categories: [], settled_at: %DateTime{}}] = pending(ctx.gall.id)
    end

    test "keep: the uses stay as text and the term is left alone", ctx do
      package = disagreeing() |> approve!()
      decide!(question(package), %{"keep" => true})

      assert Catalog.get_term("color", "pale tan") == nil
      assert [%{settled_categories: [], settled_at: %DateTime{}}] = pending(ctx.gall.id)
      assert traits(ctx.gall.id, "color") == []
    end

    test "a decided question stays decided when the package is resolved again" do
      package = disagreeing()
      q = decide!(question(package), %{"keep" => true})
      {:ok, package} = Import.resolve_package(test_actor(), package)
      assert [%QueueItem{id: id, status: :decided}] = questions(package)
      assert id == q.id
    end
  end

  describe "a superadmin placing a term for every Source" do
    # A Source whose Gall keeps the no-fit term "lumpy" as text.
    defp kept_as_text do
      {:ok, _} = Catalog.mark_term_no_fit(test_actor(), "texture", "lumpy", :superadmin)
      package = deliver(gall_batch([trait("f6", "g1", "texture", "lumpy", nil)])) |> approve!()

      assert [%{settled_categories: [], settled_at: %DateTime{}}] =
               pending(gall_id(package, "g1"))

      package
    end

    test "settles the term's text uses into Facts", ctx do
      package = kept_as_text()

      assert {:ok, %{status: :placed, categories: ["bumpy"], placed_by: :superadmin}} =
               Import.place_term(test_actor(), "texture", "lumpy", "bumpy")

      assert traits(ctx.gall.id, "texture") == ["bumpy"]
      assert attribution(ctx.gall.id, "texture", "bumpy", package.source_id).term == "lumpy"
      assert [%{settled_categories: ["bumpy"]}] = pending(ctx.gall.id)
      assert Catalog.list_no_fit_terms() == []
    end

    test "closes the open questions about the term in every package" do
      package = disagreeing(term: "lumpy")
      assert [%QueueItem{status: :open}] = questions(package)

      {:ok, _} = Import.place_term(test_actor(), "color", "lumpy", "tan")
      assert [%QueueItem{status: :decided, decision: %{"place" => "tan"}}] = questions(package)
    end

    test "a use a curator chose to keep as text stays text", ctx do
      package = disagreeing(term: "lumpy") |> approve!()
      decide!(question(package), %{"keep" => true})

      {:ok, _} = Import.place_term(test_actor(), "color", "lumpy", "tan")

      assert traits(ctx.gall.id, "color") == []
      assert [%{settled_categories: [], settled_at: %DateTime{}}] = pending(ctx.gall.id)
    end

    test "replays, settling the uses again", ctx do
      kept_as_text()

      entries =
        undone(fn -> {:ok, _} = Import.place_term(test_actor(), "texture", "lumpy", "bumpy") end)

      assert traits(ctx.gall.id, "texture") == []
      assert [%{kind: :trait_term_edit}] = entries
      assert {:ok, 1} = Replay.run(entries, actor: test_actor())
      assert traits(ctx.gall.id, "texture") == ["bumpy"]
    end
  end

  describe "replay" do
    # Makes `fun`'s decisions, then undoes them, returning the log entries
    # they appended.
    defp undone(fun) do
      before = MapSet.new(Import.list_replay_entries(), & &1.id)

      {:error, {:undone, entries}} =
        Repo.transaction(fn ->
          fun.()

          Repo.rollback(
            {:undone, Enum.reject(Import.list_replay_entries(), &MapSet.member?(before, &1.id))}
          )
        end)

      entries
    end

    test "each decision replays to the same Facts and terms" do
      for {term, decision, color, status} <- [
            {"pale tan", %{"place" => "tan"}, ["tan"], :placed},
            {"tan-white", %{"place" => ["tan", "white"]}, ["tan", "white"], :placed},
            {"lumpy", %{"category" => "white"}, ["white"], :ambiguous},
            {"woody", %{"categories" => %{"g1" => nil, "g2" => "white"}}, ["white"], :ambiguous},
            {"bumpy", %{"no_fit" => true}, [], :no_fit},
            {"lignified", %{"keep" => true}, [], nil}
          ] do
        package =
          disagreeing(term: term, title: "Galls #{System.unique_integer([:positive])}")
          |> approve!()

        entries = undone(fn -> decide!(question(package), decision) end)

        assert Catalog.get_term("color", term) == nil
        assert [%{kind: :queue_decision}] = entries
        assert {:ok, 1} = Replay.run(entries, actor: test_actor())

        assert %QueueItem{status: :decided, decision: ^decision} = question(package)
        written = statements(package)[{:fact, "f7"}]
        assert is_integer(written.fact_id) == (color != [])

        for c <- color,
            do:
              assert(
                attribution(gall_id(package, "g2"), "color", c, package.source_id).term == term
              )

        case status do
          nil -> assert Catalog.get_term("color", term) == nil
          status -> assert %{status: ^status} = Catalog.get_term("color", term)
        end
      end
    end

    test "a placement by agreement replays before its batch" do
      package = deliver(gall_batch([trait("f6", "g1", "color", "pale tan", "tan")]))
      entries = undone(fn -> approve!(package) end)

      assert [:trait_term_edit, :batch_applied] =
               entries
               |> Enum.map(& &1.kind)
               |> Enum.filter(&(&1 in [:trait_term_edit, :batch_applied]))

      assert {:ok, _} = Replay.run(entries, actor: test_actor())
      assert %{status: :placed, placed_by: :agreement} = Catalog.get_term("color", "pale tan")
    end
  end
end
