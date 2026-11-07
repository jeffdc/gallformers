defmodule Gallformers.Import.GallDecisionsTest do
  @moduledoc """
  Gall decisions that drop statements or re-read a Host (matter `d213`,
  Task 8): choosing a Gall can leave out statements of the Source that
  disagree with it (they never become Facts), and can say the Source means
  another plant by a Host name, which re-resolves every use of that name
  in the package. Both replay.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.Queue
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobata = plant_fixture(name: "Quercus lobata", parent: quercus)
    nigra = plant_fixture(name: "Quercus nigra", parent: quercus)
    marilandica = plant_fixture(name: "Quercus marilandica", parent: quercus)
    andricus = taxon_fixture(name: "Andricus", rank: :genus, kingdom: "Animalia")
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    legacy = source_fixture("Legacy", "1990")

    # Two Galls of the wasp that no generation tells apart.
    galls =
      for name <- [
            "Andricus quercuscalifornicus stem gall",
            "Andricus quercuscalifornicus bud gall"
          ] do
        gall = gall_fixture(name: name)

        {:ok, _} =
          Catalog.assert_relationship(
            test_actor(),
            %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
            confirm(legacy)
          )

        gall
      end

    %{
      quercus: quercus,
      lobata: lobata,
      nigra: nigra,
      marilandica: marilandica,
      andricus: andricus,
      wasp: wasp,
      legacy: legacy,
      galls: galls
    }
  end

  # The fixture gall batch, its Gall without a generation (two candidates),
  # its Host `host`, and a second Host Fact naming "Quercus nigra" in full.
  defp gall_batch(host) do
    batch()
    |> unique_batch_id()
    |> put_in(["taxa", Access.at(1), "name_as_written"], host)
    |> update_in(
      ["taxa"],
      &(&1 ++ [%{"ref" => "t4", "name_as_written" => "Quercus nigra", "rank" => "species"}])
    )
    |> update_in(["galls", Access.at(0), "identified_by"], &Map.delete(&1, "generation"))
    |> update_in(["facts"], fn facts ->
      facts ++
        [
          %{
            "id" => "f5",
            "stance" => "confirm",
            "kind" => "relationship",
            "type" => "host_of",
            "subject" => "t4",
            "object" => "g1",
            "evidence" => [%{"item" => "#/texts/2", "quote" => "Common on Q. lobata"}]
          }
        ]
    end)
  end

  defp deliver(host \\ "Quercus lobata"),
    do: package(gall: gall_batch(host)) |> with_review() |> deliver!()

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  defp statements(package),
    do: package |> gall_row() |> Import.list_statements() |> Map.new(&{{&1.kind, &1.ref}, &1})

  defp gall_item(package),
    do: Enum.find(Import.list_queue_items(package), &(&1.statement_ref == "g1"))

  defp valid?(item, decision),
    do: Queue.validate_decision(Ecto.Changeset.change(item), item, decision).valid?

  describe "dropping statements" do
    test "a dropped statement writes no Fact; the others are written", ctx do
      package = deliver()
      [chosen, _other] = ctx.galls
      decision = %{"gall_id" => chosen.id, "drop" => ["f2"]}

      assert {:ok, %QueueItem{decision: ^decision}} =
               Import.decide_queue_item(test_actor(), gall_item(package), decision)

      {:ok, _} = Import.approve_package(test_actor(), package)
      s = statements(package)

      assert %BatchStatement{fact_id: nil} = s[{:fact, "f2"}]
      assert s[{:fact, "f2"}].detail["skipped"] =~ "left out"
      assert is_integer(s[{:fact, "f1"}].fact_id)
      assert is_integer(s[{:fact, "f5"}].fact_id)
    end

    test "only this batch's statements about this Gall can be dropped", ctx do
      item = gall_item(deliver())
      [chosen, _other] = ctx.galls

      assert valid?(item, %{"gall_id" => chosen.id, "drop" => ["f2", "f5"]})
      assert valid?(item, %{"new" => true, "drop" => ["f2"]})
      refute valid?(item, %{"gall_id" => chosen.id, "drop" => ["f99"]})
      refute valid?(item, %{"gall_id" => chosen.id, "drop" => "f2"})
      refute valid?(item, %{"gall_id" => chosen.id, "drop" => ["t2"]})
      refute valid?(item, %{"drop" => ["f2"]})
    end
  end

  describe "a Host read in the Source's sense" do
    test "every use of the name in the package resolves to the plant meant", ctx do
      package = deliver("Q. nigra")
      s = statements(package)
      assert s[{:taxon, "t2"}].taxon_id == ctx.nigra.id
      assert s[{:taxon, "t4"}].taxon_id == ctx.nigra.id

      [chosen, _other] = ctx.galls

      decision = %{
        "gall_id" => chosen.id,
        "host_reading" => %{"name" => "Q. nigra", "taxon_id" => ctx.marilandica.id}
      }

      assert {:ok, %QueueItem{decision: stored}} =
               Import.decide_queue_item(test_actor(), gall_item(package), decision)

      assert stored["host_reading"]["sensu"] == "A 2024"

      s = statements(package)
      assert %{resolution: :resolved, taxon_id: t2} = s[{:taxon, "t2"}]
      assert %{resolution: :resolved, taxon_id: t4} = s[{:taxon, "t4"}]
      assert t2 == ctx.marilandica.id
      assert t4 == ctx.marilandica.id

      # The tree records the misapplied name, in the Source's sense.
      assert [%{name: "Quercus nigra", sensu: "A 2024"}] =
               Taxa.list_synonyms(ctx.marilandica.id)

      # The Source's name keeps its usual sense elsewhere.
      assert {:ok, %{id: id}} = Taxa.resolve_name("Quercus nigra", rank: :species)
      assert id == ctx.nigra.id
    end

    test "the plant must be a plant and the name one the batch uses", ctx do
      item = gall_item(deliver("Q. nigra"))
      [chosen, _other] = ctx.galls
      reading = &%{"gall_id" => chosen.id, "host_reading" => &1}

      assert valid?(item, reading.(%{"name" => "Q. nigra", "taxon_id" => ctx.marilandica.id}))
      refute valid?(item, reading.(%{"name" => "Q. alba", "taxon_id" => ctx.marilandica.id}))
      refute valid?(item, reading.(%{"name" => "Q. nigra", "taxon_id" => -1}))
      refute valid?(item, reading.(%{"name" => "Q. nigra"}))
    end
  end

  describe "a genus Host: the plant chosen for this Gall" do
    # Ashmead's "an unknown oak" Galls, each stated on Quercus: g1 and g2
    # both on the genus, g1 also identified by it. Choosing a plant for g1
    # leaves g2's Quercus as it is.
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
        |> update_in(["galls", Access.at(0), "identified_by"], fn ident ->
          ident |> Map.delete("generation") |> Map.put("host", "t2")
        end)
        |> update_in(["galls"], fn galls ->
          galls ++
            [
              %{
                "ref" => "g2",
                "name_as_written" => "the small bud galls",
                "identified_by" => %{"inducer" => "t1"}
              }
            ]
        end)
        |> update_in(["facts"], fn facts ->
          facts ++
            [
              %{
                "id" => "f20",
                "stance" => "confirm",
                "kind" => "relationship",
                "type" => "host_of",
                "subject" => "t2",
                "object" => "g2",
                "evidence" => [%{"item" => "#/texts/2", "quote" => "Common on Q. lobata"}]
              }
            ]
        end)

      package = package(gall: gall) |> with_review() |> deliver!()
      items = Map.new(Import.list_queue_items(package), &{&1.statement_ref, &1})
      %{package: package, lobatae: lobatae, g1: items["g1"], g2: items["g2"]}
    end

    test "a reading of the genus is refused: it would move every Gall's Host", ctx do
      [chosen, _other] = ctx.galls

      decision = %{
        "gall_id" => chosen.id,
        "host_reading" => %{"name" => "Quercus", "taxon_id" => ctx.lobatae.id}
      }

      refute valid?(ctx.g1, decision)
      assert {:error, changeset} = Import.decide_queue_item(test_actor(), ctx.g1, decision)

      assert {"this Host is a genus: choose a plant for this Gall instead", _} =
               changeset.errors[:decision]
    end

    test "this Gall's Host statements go in on the plant chosen; other Galls' Quercus stay",
         ctx do
      [chosen, other] = ctx.galls
      decision = %{"gall_id" => chosen.id, "host_taxon_id" => ctx.lobatae.id}

      assert {:ok, %QueueItem{decision: ^decision}} =
               Import.decide_queue_item(test_actor(), ctx.g1, decision)

      {:ok, _} = Import.decide_queue_item(test_actor(), ctx.g2, %{"gall_id" => other.id})

      # No reading: "Quercus" still means the genus, and the tree records no synonym.
      assert statements(ctx.package)[{:taxon, "t2"}].taxon_id == ctx.quercus.id
      assert Taxa.list_synonyms(ctx.lobatae.id) == []

      {:ok, _} = Import.approve_package(test_actor(), ctx.package)
      s = statements(ctx.package)

      assert s[{:fact, "f2"}].detail["chosen_host_taxon_id"] == ctx.lobatae.id
      refute Map.has_key?(s[{:fact, "f20"}].detail || %{}, "chosen_host_taxon_id")
      assert host_ids(chosen.id) == [ctx.lobatae.id]
      assert host_ids(other.id) == [ctx.quercus.id]
    end

    test "a new Gall is created on the plant chosen", ctx do
      decision = %{"new" => true, "host_taxon_id" => ctx.lobatae.id}
      {:ok, _} = Import.decide_queue_item(test_actor(), ctx.g1, decision)
      {:ok, _} = Import.decide_queue_item(test_actor(), ctx.g2, %{"skip" => true})
      {:ok, _} = Import.approve_package(test_actor(), ctx.package)

      assert %BatchStatement{method: "created", gall_id: id} =
               statements(ctx.package)[{:gall, "g1"}]

      assert Catalog.get_gall!(id).host_qualifier_taxon_id == ctx.lobatae.id
      assert host_ids(id) == [ctx.lobatae.id]
    end

    test "only with a Gall chosen or new, on a plant, never with a reading", ctx do
      [chosen, _other] = ctx.galls
      on = &Map.put(&1, "host_taxon_id", ctx.lobatae.id)

      assert valid?(ctx.g1, on.(%{"gall_id" => chosen.id}))
      assert valid?(ctx.g1, on.(%{"new" => true, "drop" => ["f3"]}))
      refute valid?(ctx.g1, on.(%{"skip" => true}))
      refute valid?(ctx.g1, %{"gall_id" => chosen.id, "host_taxon_id" => -1})
      refute valid?(ctx.g1, %{"gall_id" => chosen.id, "host_taxon_id" => ctx.wasp.id})

      refute valid?(
               ctx.g1,
               on.(%{
                 "gall_id" => chosen.id,
                 "host_reading" => %{"name" => "Q. nigra", "taxon_id" => ctx.marilandica.id}
               })
             )
    end

    test "the plant chosen replays, by a stable reference", ctx do
      [chosen, other] = ctx.galls

      {entries, after_decision} =
        logged_and_undone(fn ->
          {:ok, _} =
            Import.decide_queue_item(test_actor(), ctx.g1, %{
              "gall_id" => chosen.id,
              "host_taxon_id" => ctx.lobatae.id
            })

          {:ok, _} = Import.decide_queue_item(test_actor(), ctx.g2, %{"gall_id" => other.id})
          {:ok, _} = Import.approve_package(test_actor(), ctx.package)
          {host_ids(chosen.id), host_ids(other.id)}
        end)

      assert [%{"host_taxon" => %{"name" => "Lobatae", "rank" => "section"}} | _] =
               for(
                 %{kind: :queue_decision} = e <- entries,
                 e.payload["decision"]["host_taxon"],
                 do: e.payload["decision"]
               )

      assert after_decision == {[ctx.lobatae.id], [ctx.quercus.id]}
      assert {:ok, _} = Replay.run(entries, actor: test_actor())
      assert_replays_again(entries, test_actor())
      assert {host_ids(chosen.id), host_ids(other.id)} == after_decision
    end
  end

  defp host_ids(gall_id),
    do: gall_id |> Catalog.gall_summary() |> Map.fetch!(:hosts) |> Enum.map(& &1.taxon_id)

  describe "a new Gall's generation" do
    defp created_gall(package) do
      case statements(package)[{:gall, "g1"}] do
        %BatchStatement{method: "created", gall_id: id} -> Catalog.get_gall!(id)
        _ -> nil
      end
    end

    test "the new Gall is created with the generation chosen", _ctx do
      package = deliver()
      decision = %{"new" => true, "generation" => "sexual", "drop" => ["f3"]}

      assert {:ok, %QueueItem{decision: ^decision}} =
               Import.decide_queue_item(test_actor(), gall_item(package), decision)

      {:ok, _} = Import.approve_package(test_actor(), package)

      gall = created_gall(package)
      assert gall.generation_value_id == Catalog.get_generation_value("sexual").id
      assert gall.name == "Andricus quercuscalifornicus (sexgen)"
      assert %BatchStatement{fact_id: nil} = statements(package)[{:fact, "f3"}]
    end

    test "the generation must be one, go with new, and not be one the Inducer's Galls hold",
         ctx do
      agamic =
        gall_fixture(name: "Andricus quercuscalifornicus agamic gall", generation: "agamic")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: ctx.wasp.id, object_gall_id: agamic.id},
          confirm(ctx.legacy)
        )

      item = gall_item(deliver())
      [chosen, _other] = ctx.galls

      assert valid?(item, %{"new" => true, "generation" => "sexual"})
      refute valid?(item, %{"new" => true, "generation" => "agamic"})
      refute valid?(item, %{"new" => true, "generation" => "biannual"})
      refute valid?(item, %{"new" => true, "generation" => 1})
      refute valid?(item, %{"gall_id" => chosen.id, "generation" => "sexual"})
      refute valid?(item, %{"skip" => true, "generation" => "sexual"})
      refute valid?(item, %{"generation" => "sexual"})
    end

    test "the generation replays", _ctx do
      package = deliver()

      {entries, generation} =
        logged_and_undone(fn ->
          {:ok, _} =
            Import.decide_queue_item(test_actor(), gall_item(package), %{
              "new" => true,
              "generation" => "sexual"
            })

          {:ok, _} = Import.approve_package(test_actor(), package)
          created_gall(package).generation_value_id
        end)

      assert generation == Catalog.get_generation_value("sexual").id
      assert created_gall(package) == nil
      assert {:ok, _} = Replay.run(entries, actor: test_actor())
      assert_replays_again(entries, test_actor())
      assert created_gall(package).generation_value_id == generation
    end
  end

  describe "a new Inducer under a chosen genus, for a gall batch" do
    test "the taxon is created under the genus", ctx do
      gall =
        put_in(
          gall_batch("Quercus lobata"),
          ["taxa", Access.at(0), "name_as_written"],
          "Andricus ignotus"
        )

      package = package(gall: gall) |> with_review() |> deliver!()
      name = Enum.find(Import.list_queue_items(package), &(&1.statement_ref == "t1"))

      {:ok, _} =
        Import.decide_queue_item(test_actor(), name, %{
          "new" => true,
          "parent_id" => ctx.andricus.id
        })

      for item <- Import.list_queue_items(package),
          do: {:ok, _} = Import.decide_queue_item(test_actor(), item, %{"new" => true})

      {:ok, _} = Import.approve_package(test_actor(), package)

      assert %BatchStatement{method: "created", taxon_id: id} =
               statements(package)[{:taxon, "t1"}]

      assert Taxa.get_taxon!(id).parent_id == ctx.andricus.id
    end
  end

  describe "replay" do
    test "the drop and the reading replay to the same statements and tree", ctx do
      package = deliver("Q. nigra")
      [chosen, _other] = ctx.galls

      {entries, after_decision} =
        logged_and_undone(fn ->
          {:ok, _} =
            Import.decide_queue_item(test_actor(), gall_item(package), %{
              "gall_id" => chosen.id,
              "drop" => ["f3"],
              "host_reading" => %{"name" => "Q. nigra", "taxon_id" => ctx.marilandica.id}
            })

          {:ok, _} = Import.approve_package(test_actor(), package)
          snapshot(package, ctx)
        end)

      assert snapshot(package, ctx) != after_decision
      assert {:ok, _} = Replay.run(entries, actor: test_actor())
      assert_replays_again(entries, test_actor())
      assert snapshot(package, ctx) == after_decision
    end
  end

  defp snapshot(package, ctx) do
    s = statements(package)

    %{
      hosts: for(ref <- ["t2", "t4"], do: s[{:taxon, ref}] && s[{:taxon, ref}].taxon_id),
      facts:
        for(
          ref <- ["f1", "f2", "f3", "f5"],
          do: s[{:fact, ref}] && s[{:fact, ref}].fact_id != nil
        ),
      synonyms: for(n <- Taxa.list_synonyms(ctx.marilandica.id), do: {n.name, n.sensu})
    }
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
