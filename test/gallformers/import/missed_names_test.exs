defmodule Gallformers.Import.MissedNamesTest do
  @moduledoc """
  Names the producer missed (matter `c8c3` item 12): a name the Source
  prints that the tree holds but no batch declares
  (`Gallformers.Import.UnusedNames`) is a question that holds nothing. A
  curator dismisses it, or states what the Source says with it: the name's
  taxon as a Gall's Inducer or Host, attributed to the Source, its passage
  the evidence. No producer run.

  Not async: packages create Sources (unique titles) and the vocabularies
  are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.DoclingFixtures
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.Queue
  alias Gallformers.Import.Replay
  alias Gallformers.Taxa

  setup :audit_test_metadata

  @missed "Galls of Andricus kingi were bred alongside, on Quercus douglasii."

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    plant_fixture(name: "Quercus lobata", parent: quercus)
    douglasii = plant_fixture(name: "Quercus douglasii", parent: quercus)
    andricus = Taxa.get_by_legacy_id(:taxonomy, 33)
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    kingi = taxon_fixture(name: "Andricus kingi", parent: andricus)
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    legacy = source_fixture("Legacy", "1990")
    gall = gall_fixture(name: "Andricus quercuscalifornicus (agamic)", generation: "agamic")
    kingi_gall = gall_fixture(name: "Andricus kingi")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
        confirm(legacy)
      )

    package =
      package(gall: batch() |> unique_batch_id(), doc: doc())
      |> with_review()
      |> deliver!()

    %{
      package: package,
      gall: gall,
      kingi: kingi,
      kingi_gall: kingi_gall,
      douglasii: douglasii
    }
  end

  defp doc do
    missed = %{
      "self_ref" => "#/texts/5",
      "label" => "text",
      "content_layer" => "body",
      "text" => @missed,
      "prov" => [%{"page_no" => 2, "bbox" => %{}, "charspan" => [0, 0]}],
      "children" => []
    }

    DoclingFixtures.document()
    |> Map.update!("texts", &(&1 ++ [missed]))
    |> update_in(["body", "children"], &(&1 ++ [%{"$ref" => "#/texts/5"}]))
  end

  defp missed(package), do: Import.list_queue_items(package, kind: :missed_name, status: :all)

  defp item(package, name), do: Enum.find(missed(package), &(&1.subject["name"] == name))

  defp valid?(item, decision),
    do: Queue.validate_decision(Ecto.Changeset.change(item), item, decision).valid?

  defp host_of(ctx),
    do: %{
      "kind" => "host_of",
      "taxon_id" => ctx.douglasii.id,
      "gall_id" => ctx.gall.id,
      "items" => ["#/texts/5"]
    }

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  defp hosts(gall_id), do: Enum.map(Catalog.gall_summary(gall_id).hosts, & &1.name)

  defp attribution(gall_id, plant, source_id) do
    {:ok, fact_id} =
      Catalog.find_fact(:relationship, %{
        type: "host_of",
        subject_taxon_id: plant.id,
        object_gall_id: gall_id
      })

    Enum.find(Facts.list_attributions(fact_id), &(&1.source_id == source_id))
  end

  describe "questions" do
    test "each name the batches miss is a question holding nothing, with its passages", ctx do
      assert ["Andricus kingi", "Quercus douglasii"] =
               ctx.package |> missed() |> Enum.map(& &1.subject["name"]) |> Enum.sort()

      q = item(ctx.package, "Quercus douglasii")
      assert q.batch_id == gall_row(ctx.package).id
      assert q.subject["taxon_ids"] == [ctx.douglasii.id]
      assert q.subject["items"] == ["#/texts/5"]
      refute Queue.blocking?(q, :gall)
      assert Import.proposed_decision(q) == {:none, :no_proposal}

      # Resolving again keeps the question.
      {:ok, package} = Import.resolve_package(test_actor(), ctx.package)
      assert item(package, "Quercus douglasii").id == q.id
    end

    test "dismiss, or state the name's taxon as a Gall's Inducer or Host", ctx do
      q = item(ctx.package, "Quercus douglasii")
      wasp = item(ctx.package, "Andricus kingi")

      assert valid?(q, %{"dismiss" => true})
      assert valid?(q, %{"dismiss" => true, "note" => "only a comparison"})
      assert valid?(q, %{"state" => host_of(ctx)})

      assert valid?(wasp, %{
               "state" => %{
                 "kind" => "inducer_of",
                 "taxon_id" => ctx.kingi.id,
                 "gall_id" => ctx.kingi_gall.id,
                 "items" => ["#/texts/5"]
               }
             })

      # The name's own taxon, a plant for a Host, a Gall that exists, the name's passages.
      refute valid?(q, %{"state" => %{host_of(ctx) | "taxon_id" => ctx.kingi.id}})
      refute valid?(wasp, %{"state" => %{host_of(ctx) | "taxon_id" => ctx.kingi.id}})
      refute valid?(q, %{"state" => %{host_of(ctx) | "gall_id" => -1}})
      refute valid?(q, %{"state" => %{host_of(ctx) | "items" => []}})
      refute valid?(q, %{"state" => %{host_of(ctx) | "items" => ["#/texts/1"]}})
      refute valid?(q, %{"state" => %{host_of(ctx) | "kind" => "trait"}})
      refute valid?(q, %{"dismiss" => true, "state" => host_of(ctx)})
    end
  end

  describe "stating" do
    test "before the batch is applied: written with it, on the Source's authority", ctx do
      {:ok, _} =
        Import.decide_queue_item(test_actor(), item(ctx.package, "Quercus douglasii"), %{
          "state" => host_of(ctx)
        })

      {:ok, package} = Import.approve_package(test_actor(), ctx.package)

      assert "Quercus douglasii" in hosts(ctx.gall.id)
      attribution = attribution(ctx.gall.id, ctx.douglasii, package.source_id)
      assert [%{whole_item: true} = evidence] = attribution.evidence
      assert evidence.quote == nil or evidence.quote == @missed
    end

    test "after the batch is applied: written at once", ctx do
      {:ok, package} = Import.approve_package(test_actor(), ctx.package)
      refute "Quercus douglasii" in hosts(ctx.gall.id)

      {:ok, _} =
        Import.decide_queue_item(test_actor(), item(package, "Quercus douglasii"), %{
          "state" => host_of(ctx)
        })

      assert "Quercus douglasii" in hosts(ctx.gall.id)
    end

    test "dismissed: nothing is written", ctx do
      {:ok, _} =
        Import.decide_queue_item(test_actor(), item(ctx.package, "Quercus douglasii"), %{
          "dismiss" => true
        })

      {:ok, _} = Import.approve_package(test_actor(), ctx.package)
      refute "Quercus douglasii" in hosts(ctx.gall.id)
    end

    test "a stated name replays, by stable references", ctx do
      q = item(ctx.package, "Quercus douglasii")
      before = MapSet.new(Import.list_replay_entries(), & &1.id)

      {:error, {:undone, entries}} =
        Repo.transaction(fn ->
          {:ok, _} = Import.decide_queue_item(test_actor(), q, %{"state" => host_of(ctx)})
          Repo.rollback({:undone, Enum.reject(Import.list_replay_entries(), &(&1.id in before))})
        end)

      assert [%{kind: :queue_decision, payload: %{"decision" => %{"state" => state}}}] = entries
      assert %{"gall" => _, "taxon" => _} = state

      assert {:ok, _} = Replay.run(entries, actor: test_actor())
      assert Import.get_queue_item!(q.id).decision == %{"state" => host_of(ctx)}
    end
  end
end
