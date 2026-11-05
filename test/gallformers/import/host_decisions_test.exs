defmodule Gallformers.Import.HostDecisionsTest do
  @moduledoc """
  Host decisions (`6611` Task 3): resolving an unresolved Host to a plant
  while adding the Source's spelling as its synonym, and adding the plant
  from WCVP (its accepted record, the spelling as a synonym when it
  differs). Both go through the Host-name step's recorders, so they replay.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.Queue
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Ranges
  alias Gallformers.Ranges.Wcvp
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobata = plant_fixture(name: "Quercus lobata", parent: quercus)
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

    %{quercus: quercus, lobata: lobata, wasp: wasp, gall: gall}
  end

  defp deliver(host_name) do
    gall =
      batch() |> unique_batch_id() |> put_in(["taxa", Access.at(1), "name_as_written"], host_name)

    package(gall: gall) |> with_review() |> deliver!()
  end

  defp host_item(package),
    do: Enum.find(Import.list_queue_items(package), &(&1.statement_ref == "t2"))

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  defp host_statement(package),
    do:
      package
      |> gall_row()
      |> Import.list_statements()
      |> Enum.find(&(&1.kind == :taxon and &1.ref == "t2"))

  defp synonyms(taxon), do: taxon |> Taxa.list_synonyms() |> Enum.map(& &1.name)

  defp entry_kinds(package_key, since) do
    for e <- Import.list_replay_entries(), e.id > since do
      if e.kind == :queue_decision, do: {e.kind, e.key["package"] == package_key}, else: e.kind
    end
  end

  defp last_entry_id, do: Enum.reduce(Import.list_replay_entries(), 0, &max(&1.id, &2))

  defp valid?(item, decision),
    do: Queue.validate_decision(Ecto.Changeset.change(item), item, decision).valid?

  describe "a plant, with the Source's spelling as its synonym" do
    test "resolves the Host, adds the synonym and frees the gall batch", ctx do
      package = deliver("Quercus lobatus")
      item = host_item(package)
      assert gall_row(package).status == :blocked
      since = last_entry_id()

      decision = %{"taxon_id" => ctx.lobata.id, "add_synonym" => true}

      assert {:ok, %QueueItem{decision: ^decision}} =
               Import.decide_queue_item(test_actor(), item, decision)

      assert "Quercus lobatus" in synonyms(ctx.lobata)
      assert %{resolution: :resolved, taxon_id: id} = host_statement(package)
      assert id == ctx.lobata.id
      assert gall_row(package).status == :ready
      assert entry_kinds(package.key, since) == [:synonym_added, {:queue_decision, true}]
    end

    test "an abbreviated spelling is added in full, under the plant's genus", ctx do
      package = deliver("Q. lobatus")
      item = host_item(package)

      {:ok, _} =
        Import.decide_queue_item(test_actor(), item, %{
          "taxon_id" => ctx.lobata.id,
          "add_synonym" => true
        })

      assert synonyms(ctx.lobata) == ["Quercus lobatus"]
    end

    test "a spelling the plant holds already is not added again", ctx do
      package = deliver("Quercus lobatus")
      {:ok, _} = Import.record_synonym_added(test_actor(), ctx.lobata.id, "Quercus lobatus")

      {:ok, _} =
        Import.decide_queue_item(test_actor(), host_item(package), %{
          "taxon_id" => ctx.lobata.id,
          "add_synonym" => true
        })

      assert synonyms(ctx.lobata) == ["Quercus lobatus"]
    end

    test "must be a plant, with add_synonym true", ctx do
      item = host_item(deliver("Quercus lobatus"))

      assert valid?(item, %{"taxon_id" => ctx.lobata.id, "add_synonym" => true})
      assert valid?(item, %{"taxon_id" => ctx.lobata.id})
      refute valid?(item, %{"taxon_id" => ctx.wasp.id, "add_synonym" => true})
      refute valid?(item, %{"taxon_id" => ctx.lobata.id, "add_synonym" => false})
      refute valid?(item, %{"add_synonym" => true})
      refute valid?(item, %{"skip" => true, "add_synonym" => true})

      name = %{item | kind: :unresolved_name, subject: Map.delete(item.subject, "host")}
      refute valid?(name, %{"taxon_id" => ctx.lobata.id, "add_synonym" => true})
    end
  end

  describe "a plant added from WCVP" do
    test "adds the accepted record under its genus and family, with the spelling as a synonym" do
      package = deliver("Zzyzx wcvponli")
      item = host_item(package)

      assert %{"suggestions" => [%{"wcvp_id" => "500", "action" => "add_from_wcvp"}]} =
               item.proposal

      since = last_entry_id()

      assert {:ok, %QueueItem{decision: decision}} =
               Import.decide_queue_item(test_actor(), item, %{"wcvp_id" => "500"})

      assert [plant_id] = Wcvp.linked_taxon_ids("500")
      assert decision == %{"wcvp_id" => "500", "taxon_id" => plant_id}

      plant = Taxa.get_taxon!(plant_id)
      assert Taxa.accepted_name(plant) == "Zzyzx wcvponly"
      assert plant.kingdom == "Plantae"
      assert synonyms(plant) == ["Zzyzx wcvponli"]

      assert ["Testaceae", "Zzyzx", "Zzyzx wcvponly"] ==
               plant |> Taxa.lineage() |> Enum.map(& &1.name) |> Enum.take(-3)

      assert %{resolution: :resolved, taxon_id: ^plant_id} = host_statement(package)
      assert gall_row(package).status == :ready
      assert List.last(entry_kinds(package.key, since)) == {:queue_decision, true}
      assert :plant_added in entry_kinds(package.key, since)
      assert :synonym_added in entry_kinds(package.key, since)
    end

    test "uses the plant the tree already links to the record" do
      plant = plant_fixture(name: "Zzyzx wcvponly")

      {:ok, _} =
        Import.record_taxonomy_edit(test_actor(), {:set_wcvp, plant.id, %{wcvp_id: "500"}})

      package = deliver("Zzyzx wcvponli")

      {:ok, item} =
        Import.decide_queue_item(test_actor(), host_item(package), %{"wcvp_id" => "500"})

      assert item.decision["taxon_id"] == plant.id
      assert Wcvp.linked_taxon_ids("500") == [plant.id]
      assert synonyms(plant) == ["Zzyzx wcvponli"]
    end

    test "a synonym adds its accepted record, with that record's native range" do
      package = deliver("Wcvphybridus parentus var. crossus")

      {:ok, item} =
        Import.decide_queue_item(test_actor(), host_item(package), %{"wcvp_id" => "901"})

      plant = Taxa.get_taxon!(item.decision["taxon_id"])
      assert Taxa.accepted_name(plant) == "Wcvphybridus × crossus"
      assert Wcvp.linked_taxon_ids("900") == [plant.id]

      assert [%{code: "US-CA", distribution_type: "native"}] =
               Ranges.get_places_for_taxon_with_precision(plant.id)
    end

    test "a record accepted in itself, though not Accepted, can be added" do
      item = host_item(deliver("Wcvphybridus parentus var. crossus"))

      assert valid?(item, %{"wcvp_id" => "900"})
    end

    test "a record with no accepted name, or a synonym of one, cannot be added" do
      item = host_item(deliver("Wcvpunplacedus vagus var. alter"))

      refute valid?(item, %{"wcvp_id" => "902"})
      refute valid?(item, %{"wcvp_id" => "903"})
    end

    test "needs a WCVP record, for a Host" do
      item = host_item(deliver("Zzyzx wcvponli"))

      assert valid?(item, %{"wcvp_id" => "500"})
      refute valid?(item, %{"wcvp_id" => "no such record"})
      refute valid?(item, %{"wcvp_id" => 500})

      name = %{item | kind: :unresolved_name, subject: Map.delete(item.subject, "host")}
      refute valid?(name, %{"wcvp_id" => "500"})
    end
  end

  describe "a Host declared by its common name (d213 Task 6)" do
    defp deliver_common(name) do
      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["taxa", Access.at(1)], %{
          "ref" => "t2",
          "name_as_written" => name,
          "common_name" => true
        })

      package(gall: gall) |> with_review() |> deliver!()
    end

    test "a plant resolves the Host without adding the common name as a synonym", ctx do
      package = deliver_common("the valley oak")
      item = host_item(package)
      assert %QueueItem{kind: :unresolved_host, subject: %{"common_name" => true}} = item
      assert gall_row(package).status == :blocked

      decision = %{"taxon_id" => ctx.lobata.id}

      assert {:ok, %QueueItem{decision: ^decision}} =
               Import.decide_queue_item(test_actor(), item, decision)

      assert synonyms(ctx.lobata) == []
      assert %{resolution: :resolved, taxon_id: id} = host_statement(package)
      assert id == ctx.lobata.id
      assert gall_row(package).status == :ready
    end

    test "only the genus puts the Host statements on the genus", ctx do
      package = deliver_common("the valley oak")
      decision = %{"taxon_id" => ctx.quercus.id}

      assert {:ok, _} = Import.decide_queue_item(test_actor(), host_item(package), decision)
      assert synonyms(ctx.quercus) == []
      assert %{resolution: :resolved, taxon_id: id} = host_statement(package)
      assert id == ctx.quercus.id
      assert gall_row(package).status == :ready
    end

    test "a section of the genus puts the Host statements on the section", ctx do
      {:ok, _} = Taxa.add_common_name(test_actor(), ctx.quercus, "Oaks")
      lobatae = plant_fixture(name: "Lobatae", rank: :section, parent: ctx.quercus)
      white = plant_fixture(name: "Quercus", rank: :section, parent: ctx.quercus)
      package = deliver_common("an unknown oak")
      item = host_item(package)

      assert item.proposal["genus"] == %{"taxon_id" => ctx.quercus.id, "name" => "Quercus"}

      assert Enum.map(item.proposal["sections"], & &1["taxon_id"]) == [lobatae.id, white.id]

      decision = %{"taxon_id" => lobatae.id}

      assert {:ok, %QueueItem{decision: ^decision}} =
               Import.decide_queue_item(test_actor(), item, decision)

      assert synonyms(lobatae) == []
      assert %{resolution: :resolved, taxon_id: id} = host_statement(package)
      assert id == lobatae.id
      assert gall_row(package).status == :ready
    end

    test "a common name is never added as a synonym", ctx do
      item = host_item(deliver_common("the valley oak"))

      assert valid?(item, %{"taxon_id" => ctx.lobata.id})
      refute valid?(item, %{"taxon_id" => ctx.lobata.id, "add_synonym" => true})
    end

    test "a plant added from WCVP takes no synonym either" do
      package = deliver_common("the zzyzx bush")

      {:ok, item} =
        Import.decide_queue_item(test_actor(), host_item(package), %{"wcvp_id" => "500"})

      plant = Taxa.get_taxon!(item.decision["taxon_id"])
      assert Taxa.accepted_name(plant) == "Zzyzx wcvponly"
      assert synonyms(plant) == []
      assert %{resolution: :resolved} = host_statement(package)
    end
  end

  describe "replay" do
    test "both decisions replay to the same plants, synonyms and resolutions", ctx do
      lobatus = deliver("Quercus lobatus")
      wcvp = deliver("Zzyzx wcvponli")

      {entries, after_decisions} =
        logged_and_undone(fn ->
          {:ok, _} =
            Import.decide_queue_item(test_actor(), host_item(lobatus), %{
              "taxon_id" => ctx.lobata.id,
              "add_synonym" => true
            })

          {:ok, _} =
            Import.decide_queue_item(test_actor(), host_item(wcvp), %{"wcvp_id" => "500"})

          snapshot([lobatus, wcvp])
        end)

      assert snapshot([lobatus, wcvp]) != after_decisions
      assert {:ok, _} = Replay.run(entries, actor: test_actor())
      assert snapshot([lobatus, wcvp]) == after_decisions
    end

    test "a decision whose synonym, replayed first, already resolves the Host is done", ctx do
      package = deliver("Quercus lobatus")

      {entries, _} =
        logged_and_undone(fn ->
          Import.decide_queue_item(test_actor(), host_item(package), %{
            "taxon_id" => ctx.lobata.id,
            "add_synonym" => true
          })
        end)

      [synonym, decision] = entries
      assert {:ok, 1} = Replay.run([synonym], actor: test_actor())
      # Resolved again before the decision replays, the Host needs no one.
      {:ok, package} = Import.resolve_package(test_actor(), package)
      assert host_item(package) == nil

      assert {:ok, 1} = Replay.run([decision], actor: test_actor())
      assert %{resolution: :resolved, taxon_id: id} = host_statement(package)
      assert id == ctx.lobata.id
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

  defp snapshot(packages) do
    for package <- packages do
      statement = host_statement(package)
      taxon = statement.taxon_id && Taxa.get_taxon!(statement.taxon_id)

      {statement.resolution, taxon && Taxa.accepted_name(taxon),
       taxon && Enum.sort(synonyms(taxon)),
       Enum.map(Import.list_queue_items(package, status: :all), &{&1.statement_ref, &1.status})}
    end
  end
end
