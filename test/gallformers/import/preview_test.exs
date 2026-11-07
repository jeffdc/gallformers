defmodule Gallformers.Import.PreviewTest do
  @moduledoc """
  The Facts preview (matter `f14c`, item 4): what approving a package
  would write, given the answers so far, grouped by Gall and category, each
  Fact marked new, held or in conflict, waiting on a question or dropped.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Facts.Fact
  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.QueueItem
  alias Gallformers.Storage.PrivateStub
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobata = plant_fixture(name: "Quercus lobata", parent: quercus)
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

    %{
      quercus: quercus,
      lobata: lobata,
      douglasii: douglasii,
      wasp: wasp,
      torymus: torymus,
      legacy: legacy,
      gall: gall
    }
  end

  # The fixture gall batch, its Host written in full.
  defp gall_batch do
    batch()
    |> unique_batch_id()
    |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
  end

  defp add_facts(batch, facts), do: Map.update!(batch, "facts", &(&1 ++ facts))

  defp host_fact(id, subject, stance) do
    %{
      "id" => id,
      "stance" => stance,
      "kind" => "relationship",
      "type" => "host_of",
      "subject" => subject,
      "object" => "g1",
      "evidence" => [%{"item" => "#/texts/2", "quote" => "Common on Q. lobata"}]
    }
  end

  defp preview!(package) do
    # The test's transaction is audited as the test actor.
    {:ok, preview} = Import.preview_package(package, test_actor())
    preview
  end

  defp approve!(package) do
    {:ok, _} = Import.approve_package(test_actor(), package)
    Import.get_package!(package.id)
  end

  defp entries(preview), do: Enum.flat_map(preview.galls, &all_facts/1)

  defp all_facts(%{facts: facts}) do
    Enum.flat_map(facts, fn
      {:traits, by_trait} -> by_trait |> Map.values() |> List.flatten()
      {_category, list} -> list
    end)
  end

  defp entry(preview, ref), do: Enum.find(entries(preview), &(&1.ref == ref))

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  # What a written Fact is, comparable between the preview and the
  # Source's Facts once applied.
  defp comparable(entry) do
    {entry.ref, entry.kind, entry.category, comparable_value(entry.value), entry.stance,
     entry.words.term, Enum.map(entry.words.evidence, &{&1.quote, &1.item})}
  end

  defp comparable_value(value) do
    Map.new(value, fn
      {key, %{} = v} -> {key, Map.drop(v, [:new])}
      {:of_fact_id, _id} -> {:of_fact_id, nil}
      other -> other
    end)
  end

  describe "a package ready for approval" do
    test "lists the Facts approval writes, grouped by Gall and category", ctx do
      package = package(gall: gall_batch()) |> with_review() |> deliver!()
      preview = preview!(package)

      assert preview.ready? == true
      assert preview.blocking.count == 0

      assert [%{key: gall_id, gall_id: gall_id, name_as_written: "the large stem galls"} = g] =
               preview.galls

      assert gall_id == ctx.gall.id
      assert g.name == "Andricus quercuscalifornicus (agamic)"
      assert [%{ref: "f1", status: :held}] = g.facts.inducer
      assert [%{ref: "f2", status: :new} = host] = g.facts.hosts
      assert host.value.subject.taxon_id == ctx.lobata.id
      assert host.value.subject.name == "Quercus lobata"
      assert host.value.object.gall_id == ctx.gall.id

      assert [%{quote: "Common on Q. lobata throughout the hills", item: "#/texts/2"}] =
               host.words.evidence

      assert Enum.map(g.facts.other, & &1.ref) == ["f3", "f4"]
      assert entry(preview, "f4").value.of_ref == "f3"

      # Nothing is kept.
      assert Import.get_package!(package.id).status == :awaiting_review
      assert Enum.map(Import.list_batches(package), & &1.status) == [:ready]
      assert Import.list_fact_edits(package) == []

      # Approval writes the same Facts: the Source's Facts, as the same view shows them.
      package = approve!(package)
      applied = package.source_id |> Import.facts_for_source() |> Enum.flat_map(&all_facts/1)

      assert Enum.sort(Enum.map(applied, &comparable/1)) ==
               Enum.sort(Enum.map(entries(preview), &comparable/1))
    end

    test "a taxonomy batch's new taxa and acts are their own group", ctx do
      taxonomy =
        taxonomy_batch()
        |> unique_batch_id()
        |> Map.put("taxa", [
          %{
            "ref" => "t1",
            "name_as_written" => "Andricus novus",
            "rank" => "species",
            "new" => %{"status" => "sp. nov."}
          },
          %{"ref" => "t2", "name_as_written" => "Andricus", "rank" => "genus"}
        ])
        |> Map.put("acts", [
          %{
            "id" => "a1",
            "stance" => "confirm",
            "kind" => "name",
            "taxon" => "t1",
            "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
          },
          %{
            "id" => "a2",
            "stance" => "confirm",
            "kind" => "placement",
            "taxon" => "t1",
            "parent" => "t2",
            "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
          }
        ])

      gall =
        gall_batch()
        |> put_in(["taxa", Access.at(0), "name_as_written"], "Andricus novus")
        |> put_in(["galls", Access.at(0), "new"], true)

      package = package(gall: gall, taxonomy: taxonomy) |> with_review() |> deliver!()
      taxa_before = Repo.aggregate(Taxon, :count)
      preview = preview!(package)

      assert [%{name: "Andricus novus", rank: :species, parent: %{name: "Andricus"}}] =
               preview.taxonomy.new_taxa

      assert [%{ref: "a1", kind: :name, status: :new}, %{ref: "a2", kind: :placement} = a2] =
               preview.taxonomy.acts

      assert a2.value.taxon == %{taxon_id: nil, name: "Andricus novus", rank: :species, new: true}

      # The gall batch resolves against the new species: a new Gall, its
      # Inducer the new species.
      assert [%{key: "new:g1", new: true, gall_id: nil, name: name} = g] = preview.galls
      assert name =~ "Andricus novus"

      assert [%{status: :new, value: %{subject: %{name: "Andricus novus", new: true}}}] =
               g.facts.inducer

      assert Repo.aggregate(Taxon, :count) == taxa_before
      _ = ctx
    end

    test "an act that would be a taxonomy question is in conflict with the tree" do
      taxon_fixture(name: "Callirhytis previewa", kingdom: "Animalia")
      taxon_fixture(name: "Andricus previewa", kingdom: "Animalia")

      taxonomy =
        taxonomy_batch()
        |> unique_batch_id()
        |> Map.put("taxa", [
          %{"ref" => "t1", "name_as_written" => "Callirhytis previewa", "rank" => "species"},
          %{"ref" => "t2", "name_as_written" => "Andricus previewa", "rank" => "species"}
        ])
        |> Map.put("acts", [
          %{
            "id" => "a1",
            "stance" => "confirm",
            "kind" => "synonymy",
            "name" => "t1",
            "accepted" => "t2",
            "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
          }
        ])

      package = package(gall: nil, taxonomy: taxonomy) |> with_review() |> deliver!()

      assert [%{ref: "a1", status: :conflict, why: why}] = preview!(package).taxonomy.acts
      assert why =~ "does not hold Callirhytis previewa as a synonym"
    end
  end

  describe "a package held by questions" do
    test "lists the statements waiting, each with its question" do
      # "Q. lobata": the document names no genus to expand it from.
      package = package(gall: unique_batch_id(batch())) |> with_review() |> deliver!()
      [host_item] = Import.list_queue_items(package, kind: :unresolved_host)
      preview = preview!(package)

      refute preview.ready?
      assert preview.blocking.count == 1
      assert preview.blocking.by_kind == %{unresolved_host: 1}
      assert preview.blocking.blocked_batches == ["gall.json"]

      host = entry(preview, "f2")
      assert host.status == :waiting

      assert host.question == %{
               id: host_item.id,
               kind: :unresolved_host,
               statement_ref: "t2",
               batch_id: host_item.batch_id,
               blocking: true
             }

      assert host.value.subject == %{taxon_id: nil, name: nil, rank: nil, new: false}
      assert [%{name_as_written: "Q. lobata", role: "subject"}] = host.words.names

      # What resolves is shown as approval would write it.
      assert %{status: :held} = entry(preview, "f1")
      assert %{status: :new} = entry(preview, "f3")
      assert gall_row(package).status == :blocked
    end

    test "a decided question changes the preview", ctx do
      package = package(gall: unique_batch_id(batch())) |> with_review() |> deliver!()
      [host_item] = Import.list_queue_items(package, kind: :unresolved_host)
      assert entry(preview!(package), "f2").status == :waiting

      {:ok, _} = Import.decide_queue_item(test_actor(), host_item, %{"taxon_id" => ctx.lobata.id})
      preview = preview!(Import.get_package!(package.id))

      assert preview.ready? == true
      assert %{status: :new, question: nil} = host = entry(preview, "f2")
      assert host.value.subject.taxon_id == ctx.lobata.id
    end

    test "a statement whose dispute is open waits on it; dropped by the decision, it says why" do
      gall = gall_batch()
      files = package(gall: gall)

      finding = %{
        "batch" => "gall.json",
        "id" => "f3",
        "problem" => "unsupported",
        "reason" => "Torymus is not reared from this gall",
        "response" => %{"decision" => "disagree", "reason" => "it is"}
      }

      package = files |> with_review([finding], responded: true) |> deliver!()

      case Import.list_queue_items(package, kind: :dispute) do
        [dispute] ->
          assert %{status: :waiting, question: %{id: id, kind: :dispute}} =
                   entry(preview!(package), "f3")

          assert id == dispute.id
          {:ok, _} = Import.decide_queue_item(test_actor(), dispute, %{"skip" => true})

          assert %{status: :dropped, why: why} =
                   entry(preview!(Import.get_package!(package.id)), "f3")

          assert why =~ "disputed finding upheld"

        [] ->
          flunk("the finding was not queued as a dispute")
      end
    end
  end

  describe "new, held or in conflict" do
    test "marks each Fact against what Gallformers holds", ctx do
      # Legacy holds Q. douglasii as a Host; this Source denies it.
      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "host_of", subject_taxon_id: ctx.douglasii.id, object_gall_id: ctx.gall.id},
          confirm(ctx.legacy)
        )

      gall =
        gall_batch()
        |> Map.update!(
          "taxa",
          &(&1 ++
              [%{"ref" => "t4", "name_as_written" => "Quercus douglasii", "rank" => "species"}])
        )
        |> add_facts([host_fact("f5", "t4", "deny")])

      package = package(gall: gall) |> with_review() |> deliver!()
      preview = preview!(package)

      assert %{status: :held} = entry(preview, "f1")
      assert %{status: :new} = entry(preview, "f2")

      assert %{status: :conflict, why: "Gallformers holds it", stance: :deny} =
               entry(preview, "f5")

      assert preview.counts.conflict == 1
    end

    test "another Inducer for a Gall is a conflict", ctx do
      # The Source says Torymus induces the Gall a curator chose for it.
      gall =
        gall_batch()
        |> put_in(["galls", Access.at(0), "identified_by", "inducer"], "t3")
        |> put_in(["facts", Access.at(0), "subject"], "t3")

      package = package(gall: gall) |> with_review() |> deliver!()
      [item] = for %{statement_ref: "g1"} = q <- Import.list_queue_items(package), do: q
      {:ok, _} = Import.decide_queue_item(test_actor(), item, %{"gall_id" => ctx.gall.id})
      preview = preview!(Import.get_package!(package.id))

      assert %{status: :conflict, why: why} = entry(preview, "f1")
      assert why == "Gallformers holds another Inducer: Andricus quercuscalifornicus"
    end
  end

  describe "a package with nothing pending" do
    test "an applied package previews nothing" do
      package = package(gall: gall_batch()) |> with_review() |> deliver!() |> approve!()
      preview = preview!(package)

      assert preview.galls == []
      assert preview.applied == ["gall.json"]
      refute preview.ready?
    end
  end

  test "the preview stores nothing in the private bucket (a new Source's document)" do
    package = package(gall: gall_batch()) |> with_review() |> deliver!()
    keys = PrivateStub.keys()

    preview!(package)
    preview!(package)

    assert PrivateStub.keys() == keys
  end

  test "the preview writes nothing: no audit rows, no replay entries, no Facts" do
    package = package(gall: gall_batch()) |> with_review() |> deliver!()
    facts = Repo.aggregate(Fact, :count)
    entries = length(Import.list_replay_entries())
    items = Repo.aggregate(QueueItem, :count)
    changes = Repo.aggregate(test_audit_changes(), :count)

    preview!(package)

    assert Repo.aggregate(Fact, :count) == facts
    assert length(Import.list_replay_entries()) == entries
    assert Repo.aggregate(QueueItem, :count) == items
    assert Repo.aggregate(test_audit_changes(), :count) == changes
    assert Enum.map(Import.list_batches(package), & &1.status) == [:ready]
    _ = Batch
  end
end
