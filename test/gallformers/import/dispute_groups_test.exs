defmodule Gallformers.Import.DisputeGroupsTest do
  @moduledoc """
  Grouped disputes and Trait disputes (matter `d213`, Task 10): disputes
  about the same statement are decided together (`Import.decide_group/3`),
  and a dispute about a Trait term no longer holds approval; left open, its
  Fact waits, and deciding it after the batch is applied writes the Fact
  (keep) or keeps the words as text (drop).

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.DoclingFixtures
  alias Gallformers.Import
  alias Gallformers.Import.Queue
  alias Gallformers.Import.Replay
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    plant_fixture(name: "Quercus lobata", parent: quercus)
    douglasii = plant_fixture(name: "Quercus douglasii", parent: quercus)
    andricus = Taxa.get_by_legacy_id(:taxonomy, 33)
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    torymus = taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    legacy = source_fixture("Legacy", "1990")
    gall = gall_fixture(name: "Andricus quercuscalifornicus (agamic)", generation: "agamic")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
        confirm(legacy)
      )

    %{gall: gall, douglasii: douglasii, quercus: quercus, torymus: torymus}
  end

  defp finding(id),
    do: %{
      "batch" => "gall.json",
      "id" => id,
      "problem" => "unsupported",
      "reason" => "the quote does not say so",
      "response" => %{"decision" => "disagree", "reason" => "it does"}
    }

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  defp statements(package),
    do: package |> gall_row() |> Import.list_statements() |> Map.new(&{{&1.kind, &1.ref}, &1})

  defp disputes(package), do: Import.list_queue_items(package, kind: :dispute, status: :all)

  describe "decide_group/3" do
    setup do
      ids = for n <- 10..19, do: "f#{n}"

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

      package =
        package(gall: gall)
        |> with_review(Enum.map(ids, &finding/1), responded: true)
        |> deliver!()

      %{package: package, ids: ids}
    end

    test "ten disputes about the same statement form one group", %{package: package} do
      items = disputes(package)
      assert length(items) == 10
      assert items |> Enum.map(& &1.subject["group"]) |> Enum.uniq() == ["host_of:quercus lobata"]
    end

    test "keep with two exceptions decides each: eight kept, two dropped", %{package: package} do
      [a, b | _] = items = disputes(package)

      assert {:ok, decided} =
               Import.decide_group(test_actor(), items, %{
                 "keep" => true,
                 "except" => [a.id, b.id]
               })

      assert length(decided) == 10
      assert disputes(package) |> Enum.map(& &1.status) |> Enum.uniq() == [:decided]

      by_decision = Enum.frequencies_by(disputes(package), & &1.decision)
      assert by_decision == %{%{"keep" => true} => 8, %{"skip" => true} => 2}

      {:ok, _} = Import.approve_package(test_actor(), package)
      s = statements(package)
      assert s[{:fact, a.statement_ref}].fact_id == nil
      assert s[{:fact, b.statement_ref}].fact_id == nil
    end

    test "drop all", %{package: package} do
      {:ok, decided} = Import.decide_group(test_actor(), disputes(package), %{"skip" => true})
      assert Enum.map(decided, & &1.decision) == List.duplicate(%{"skip" => true}, 10)
    end

    test "only disputes of one group, open, in one package", %{package: package} do
      [a | _] = items = disputes(package)

      assert {:error, :not_one_group} =
               Import.decide_group(test_actor(), items, %{"keep" => true, "except" => [-1]})

      other = %{a | subject: Map.put(a.subject, "group", "host_of:other")}

      assert {:error, :not_one_group} =
               Import.decide_group(test_actor(), [other | tl(items)], %{"keep" => true})

      {:ok, _} = Import.decide_queue_item(test_actor(), a, %{"keep" => true})

      assert {:error, :already_decided} =
               Import.decide_group(test_actor(), items, %{"keep" => true})
    end

    test "the group's decisions replay", %{package: package} do
      [a | _] = items = disputes(package)

      {entries, after_decisions} =
        logged_and_undone(fn ->
          {:ok, _} =
            Import.decide_group(test_actor(), items, %{"keep" => true, "except" => [a.id]})

          Enum.map(disputes(package), &{&1.statement_ref, &1.decision})
        end)

      assert {:ok, 10} = Replay.run(entries, actor: test_actor())
      assert Enum.map(disputes(package), &{&1.statement_ref, &1.decision}) == after_decisions
    end
  end

  describe "a Host dispute kept, its Host read as another plant" do
    setup do
      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
        |> Map.update!("facts", fn facts ->
          facts ++
            for id <- ["f10", "f11"] do
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

      package =
        package(gall: gall)
        |> with_review(Enum.map(["f2", "f10", "f11", "f3"], &finding/1), responded: true)
        |> deliver!()

      by_ref = Map.new(disputes(package), &{&1.statement_ref, &1})
      %{package: package, host: by_ref["f2"], parasitoid: by_ref["f3"]}
    end

    defp reading(ctx, name \\ "Quercus lobata"),
      do: %{"name" => name, "taxon_id" => ctx.douglasii.id}

    defp valid?(item, decision),
      do: Queue.validate_decision(Ecto.Changeset.change(item), item, decision).valid?

    test "the statement stands, on the plant meant; the name is read so in the package", ctx do
      decision = %{"keep" => true, "host_reading" => reading(ctx)}

      assert {:ok, %{decision: stored}} =
               Import.decide_queue_item(test_actor(), ctx.host, decision)

      assert stored["host_reading"]["sensu"] == "A 2024"
      assert statements(ctx.package)[{:taxon, "t2"}].taxon_id == ctx.douglasii.id

      assert [%{name: "Quercus lobata", sensu: "A 2024"}] =
               Taxa.list_synonyms(ctx.douglasii.id)

      for item <- disputes(ctx.package),
          item.status == :open,
          do: {:ok, _} = Import.decide_queue_item(test_actor(), item, %{"keep" => true})

      {:ok, _} = Import.approve_package(test_actor(), ctx.package)

      s = statements(ctx.package)
      assert is_integer(s[{:fact, "f2"}].fact_id)
      hosts = Catalog.gall_summary(s[{:gall, "g1"}].gall_id).hosts
      assert Enum.map(hosts, & &1.taxon_id) == [ctx.douglasii.id]
    end

    test "only a Host dispute, kept, reading its own Host as a plant", ctx do
      assert valid?(ctx.host, %{"keep" => true, "host_reading" => reading(ctx)})
      refute valid?(ctx.host, %{"skip" => true, "host_reading" => reading(ctx)})
      refute valid?(ctx.host, %{"keep" => true, "host_reading" => reading(ctx, "Torymus")})

      refute valid?(ctx.host, %{
               "keep" => true,
               "host_reading" => %{"name" => "Quercus lobata", "taxon_id" => -1}
             })

      refute valid?(ctx.parasitoid, %{"keep" => true, "host_reading" => reading(ctx, "Torymus")})
    end

    test "a group kept reads the Host for every Gall kept", ctx do
      items =
        Enum.filter(disputes(ctx.package), &(&1.subject["group"] == ctx.host.subject["group"]))

      assert length(items) == 3
      [a | _] = items

      assert {:ok, decided} =
               Import.decide_group(test_actor(), items, %{
                 "keep" => true,
                 "host_reading" => reading(ctx),
                 "except" => [a.id]
               })

      by_id = Map.new(decided, &{&1.id, &1.decision})
      assert by_id[a.id] == %{"skip" => true}

      assert for(i <- tl(items), do: by_id[i.id]["host_reading"]["taxon_id"]) ==
               [ctx.douglasii.id, ctx.douglasii.id]

      assert statements(ctx.package)[{:taxon, "t2"}].taxon_id == ctx.douglasii.id

      assert {:error, :invalid_decision} =
               Import.decide_group(test_actor(), items, %{
                 "skip" => true,
                 "host_reading" => reading(ctx)
               })
    end

    test "the reading replays", ctx do
      {entries, after_decision} =
        logged_and_undone(fn ->
          {:ok, _} =
            Import.decide_queue_item(test_actor(), ctx.host, %{
              "keep" => true,
              "host_reading" => reading(ctx)
            })

          {statements(ctx.package)[{:taxon, "t2"}].taxon_id,
           for(n <- Taxa.list_synonyms(ctx.douglasii.id), do: {n.name, n.sensu})}
        end)

      assert statements(ctx.package)[{:taxon, "t2"}].taxon_id != ctx.douglasii.id
      assert {:ok, _} = Replay.run(entries, actor: test_actor())

      assert {statements(ctx.package)[{:taxon, "t2"}].taxon_id,
              for(n <- Taxa.list_synonyms(ctx.douglasii.id), do: {n.name, n.sensu})} ==
               after_decision
    end
  end

  describe "a genus Host dispute kept on the plant chosen for its Galls" do
    # Ashmead's "an unknown oak" Galls, stated as host_of Quercus: the Host
    # chosen for these statements only, no reading of "Quercus".
    setup %{quercus: quercus} do
      lobatae = plant_fixture(name: "Lobatae", rank: :section, parent: quercus)

      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["taxa", Access.at(1)], %{
          "ref" => "t2",
          "name_as_written" => "Quercus",
          "rank" => "genus"
        })
        |> Map.update!("facts", fn facts ->
          facts ++
            for id <- ["f10", "f11", "f12"] do
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

      # f11 is not disputed: another of the Source's "Quercus" statements.
      package =
        package(gall: gall)
        |> with_review(Enum.map(["f2", "f10", "f12", "f3"], &finding/1), responded: true)
        |> deliver!()

      by_ref = Map.new(disputes(package), &{&1.statement_ref, &1})

      %{
        package: package,
        lobatae: lobatae,
        host: by_ref["f2"],
        group: Enum.map(["f2", "f10", "f12"], &by_ref[&1]),
        parasitoid: by_ref["f3"]
      }
    end

    defp chosen(ctx), do: %{"keep" => true, "host_taxon_id" => ctx.lobatae.id}

    defp keep_open(package) do
      for item <- disputes(package),
          item.status == :open,
          do: {:ok, _} = Import.decide_queue_item(test_actor(), item, %{"keep" => true})
    end

    test "the statement goes in on the plant chosen; the Source's other Quercus stay", ctx do
      assert ctx.host.subject["group"] == "host_of:quercus"

      assert {:ok, %{decision: stored}} =
               Import.decide_queue_item(test_actor(), ctx.host, chosen(ctx))

      assert stored == chosen(ctx)

      # No reading: "Quercus" still means the genus, and the tree records no synonym.
      assert statements(ctx.package)[{:taxon, "t2"}].taxon_id == ctx.quercus.id
      assert Taxa.list_synonyms(ctx.lobatae.id) == []

      keep_open(ctx.package)
      {:ok, _} = Import.approve_package(test_actor(), ctx.package)

      s = statements(ctx.package)
      assert is_integer(s[{:fact, "f2"}].fact_id)
      assert s[{:fact, "f2"}].detail["chosen_host_taxon_id"] == ctx.lobatae.id
      assert is_integer(s[{:fact, "f11"}].fact_id)
      assert s[{:fact, "f2"}].fact_id != s[{:fact, "f11"}].fact_id
      refute Map.has_key?(s[{:fact, "f11"}].detail || %{}, "chosen_host_taxon_id")

      hosts = Catalog.gall_summary(s[{:gall, "g1"}].gall_id).hosts

      assert hosts |> Enum.map(& &1.taxon_id) |> Enum.sort() ==
               Enum.sort([ctx.quercus.id, ctx.lobatae.id])
    end

    test "only a Host dispute, kept, on a plant", ctx do
      assert valid?(ctx.host, chosen(ctx))
      refute valid?(ctx.host, %{"skip" => true, "host_taxon_id" => ctx.lobatae.id})
      refute valid?(ctx.host, %{"keep" => true, "host_taxon_id" => -1})

      refute valid?(ctx.host, %{"keep" => true, "host_taxon_id" => ctx.torymus.id})
      refute valid?(ctx.parasitoid, chosen(ctx))

      refute valid?(ctx.host, Map.put(chosen(ctx), "host_reading", genus_reading(ctx)))
    end

    test "a reading of a genus Host is refused: it would change every Gall", ctx do
      decision = %{"keep" => true, "host_reading" => genus_reading(ctx)}
      refute valid?(ctx.host, decision)

      assert {:error, changeset} = Import.decide_queue_item(test_actor(), ctx.host, decision)

      assert {"this Host is a genus: choose a plant for these Galls instead", _} =
               changeset.errors[:decision]
    end

    test "a group kept on the plant chosen: each kept so, the exception dropped", ctx do
      [a | rest] = ctx.group

      assert {:ok, decided} =
               Import.decide_group(
                 test_actor(),
                 ctx.group,
                 Map.put(chosen(ctx), "except", [a.id])
               )

      by_id = Map.new(decided, &{&1.id, &1.decision})
      assert by_id[a.id] == %{"skip" => true}
      for item <- rest, do: assert(by_id[item.id] == chosen(ctx))

      assert statements(ctx.package)[{:taxon, "t2"}].taxon_id == ctx.quercus.id

      assert {:error, :invalid_decision} =
               Import.decide_group(test_actor(), ctx.group, %{
                 "skip" => true,
                 "host_taxon_id" => ctx.lobatae.id
               })

      keep_open(ctx.package)
      {:ok, _} = Import.approve_package(test_actor(), ctx.package)

      s = statements(ctx.package)
      assert s[{:fact, a.statement_ref}].fact_id == nil

      for item <- rest,
          do:
            assert(
              s[{:fact, item.statement_ref}].detail["chosen_host_taxon_id"] == ctx.lobatae.id
            )
    end

    test "the Host chosen replays, by a stable reference", ctx do
      {entries, after_decision} =
        logged_and_undone(fn ->
          {:ok, item} = Import.decide_queue_item(test_actor(), ctx.host, chosen(ctx))
          item.decision
        end)

      assert [%{"keep" => true, "host_taxon" => %{"name" => "Lobatae", "rank" => "section"}}] =
               for(%{kind: :queue_decision} = e <- entries, do: e.payload["decision"])

      assert {:ok, _} = Replay.run(entries, actor: test_actor())
      assert Import.get_queue_item!(ctx.host.id).decision == after_decision
    end

    defp genus_reading(ctx), do: %{"name" => "Quercus", "taxon_id" => ctx.lobatae.id}
  end

  describe "a dispute about a Trait term" do
    @words "The galls are ovoid and globular, attached by a small point."

    defp doc do
      words = %{
        "self_ref" => "#/texts/5",
        "label" => "text",
        "content_layer" => "body",
        "text" => @words,
        "prov" => [%{"page_no" => 2, "bbox" => %{}, "charspan" => [0, 0]}],
        "children" => []
      }

      DoclingFixtures.document()
      |> Map.update!("texts", &(&1 ++ [words]))
      |> update_in(["body", "children"], &(&1 ++ [%{"$ref" => "#/texts/5"}]))
    end

    setup do
      shape = %{
        "id" => "f6",
        "stance" => "confirm",
        "kind" => "trait",
        "gall" => "g1",
        "trait" => "shape",
        "term" => "globular",
        "category" => %{"value" => "globular"},
        "evidence" => [%{"item" => "#/texts/5", "quote" => "globular"}]
      }

      gall =
        batch()
        |> unique_batch_id()
        |> Map.put("format_version", 4)
        |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
        |> Map.update!("facts", &(&1 ++ [shape]))

      package =
        package(gall: gall, doc: doc())
        |> with_review([finding("f6")], responded: true)
        |> deliver!()

      [dispute] = disputes(package)
      %{package: package, dispute: dispute}
    end

    test "doesn't hold approval; left open, its Fact waits, the Gall showing its words", ctx do
      assert ctx.dispute.subject["trait"] == "shape"
      refute Queue.blocking?(ctx.dispute, :gall)

      assert {:ok, _} = Import.approve_package(test_actor(), ctx.package)
      assert gall_row(ctx.package).status == :applied
      refute match?(%{fact_id: id} when is_integer(id), statements(ctx.package)[{:fact, "f6"}])
      assert Catalog.gall_summary(ctx.gall.id).traits["shape"] in [nil, []]

      # Stored as a term waiting on the dispute: the Gall's page shows the words.
      dispute_id = ctx.dispute.id

      assert [%{statement_ref: "f6", queue_item_id: ^dispute_id, term: "globular"}] =
               Catalog.list_pending_terms(ctx.gall.id)

      assert {:ok, %{text_terms: %{"shape" => ["globular"]}}} = Catalog.gall_page(ctx.gall.id)
    end

    test "kept after the batch is applied, its Fact is written and the term settled", ctx do
      {:ok, _} = Import.approve_package(test_actor(), ctx.package)
      {:ok, _} = Import.decide_queue_item(test_actor(), ctx.dispute, %{"keep" => true})

      assert Catalog.gall_summary(ctx.gall.id).traits["shape"] == ["globular"]
      assert is_integer(statements(ctx.package)[{:fact, "f6"}].fact_id)

      assert Catalog.list_pending_terms(ctx.gall.id) == []

      assert [%{settled_as: "category", settled_categories: ["globular"]}] =
               Catalog.list_pending_terms(ctx.gall.id, include_settled: true)
    end

    test "dropped after the batch is applied, its words stay as text", ctx do
      {:ok, _} = Import.approve_package(test_actor(), ctx.package)
      {:ok, _} = Import.decide_queue_item(test_actor(), ctx.dispute, %{"skip" => true})

      assert Catalog.gall_summary(ctx.gall.id).traits["shape"] in [nil, []]
      assert [%{term: "globular", slot: "shape"}] = Import.list_unmapped(gall_row(ctx.package))

      assert Catalog.list_pending_terms(ctx.gall.id) == []

      assert [%{settled_as: "kept", settled_categories: []}] =
               Catalog.list_pending_terms(ctx.gall.id, include_settled: true)

      assert {:ok, %{text_terms: %{"shape" => ["globular"]}}} = Catalog.gall_page(ctx.gall.id)
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
end
