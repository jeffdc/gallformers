defmodule Gallformers.Import.QueueTest do
  @moduledoc """
  The admin queue (`9449` §5, Task 13): decisions recorded with who and
  when, decisions honoured when a batch is resolved and applied, the
  approval gate, phase 6 disputes, and generations outside their group.

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
  alias Gallformers.Import.QueueItem

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobata = plant_fixture(name: "Quercus lobata", parent: quercus)
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

    %{lobata: lobata, andricus: andricus, wasp: wasp, galls: galls}
  end

  # The fixture gall batch, its Host in full, its Gall without a generation.
  defp gall_batch do
    batch()
    |> unique_batch_id()
    |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
    |> update_in(["galls", Access.at(0), "identified_by"], &Map.delete(&1, "generation"))
  end

  defp statements(batch),
    do: batch |> Import.list_statements() |> Map.new(&{{&1.kind, &1.ref}, &1})

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  describe "decide_queue_item/3" do
    test "records the decision with who and when, and the statement follows it", ctx do
      package = package(gall: gall_batch()) |> with_review() |> deliver!()

      assert [%QueueItem{kind: :ambiguous_match, statement_ref: "g1"} = item] =
               Import.list_queue_items(package)

      [chosen, _other] = ctx.galls

      assert {:ok, %QueueItem{status: :decided} = decided} =
               Import.decide_queue_item(test_actor(), item, %{"gall_id" => chosen.id})

      assert decided.decision == %{"gall_id" => chosen.id}
      assert decided.decided_by_name == "test"
      assert %DateTime{} = decided.decided_at

      assert %BatchStatement{resolution: :resolved, gall_id: gall_id, method: "decision"} =
               statements(gall_row(package))[{:gall, "g1"}]

      assert gall_id == chosen.id

      # Resolving again keeps the decision.
      {:ok, package} = Import.resolve_package(test_actor(), package)
      assert Import.list_queue_items(package) == []
      assert statements(gall_row(package))[{:gall, "g1"}].gall_id == chosen.id

      {:ok, _} = Import.approve_package(test_actor(), package)
      assert [%{gall_id: ^gall_id}] = [statements(gall_row(package))[{:gall, "g1"}]]
      assert Enum.map(Catalog.gall_summary(chosen.id).hosts, & &1.taxon_id) == [ctx.lobata.id]
    end

    test "a decision must fit its item", ctx do
      package = package(gall: gall_batch()) |> with_review() |> deliver!()
      [item] = Import.list_queue_items(package)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Import.decide_queue_item(test_actor(), item, %{"taxon_id" => ctx.wasp.id})

      assert %{decision: [_]} = errors_on(changeset)

      assert {:error, %Ecto.Changeset{}} =
               Import.decide_queue_item(test_actor(), item, %{"gall_id" => -1})
    end

    test "a decided item cannot be decided again", ctx do
      package = package(gall: gall_batch()) |> with_review() |> deliver!()
      [item] = Import.list_queue_items(package)
      [chosen, _] = ctx.galls
      {:ok, decided} = Import.decide_queue_item(test_actor(), item, %{"gall_id" => chosen.id})

      assert {:error, :already_decided} =
               Import.decide_queue_item(test_actor(), decided, %{"skip" => true})
    end
  end

  describe "approve_package/2" do
    test "waits for open items" do
      package = package(gall: gall_batch()) |> with_review() |> deliver!()

      assert {:error, {:open_items, [%QueueItem{statement_ref: "g1"}]}} =
               Import.approve_package(test_actor(), package)

      assert Import.get_package!(package.id).status == :awaiting_review
    end

    test "skipping a Gall leaves its Facts out", ctx do
      package = package(gall: gall_batch()) |> with_review() |> deliver!()
      [item] = Import.list_queue_items(package)
      {:ok, _} = Import.decide_queue_item(test_actor(), item, %{"skip" => true})

      {:ok, _} = Import.approve_package(test_actor(), package)
      s = statements(gall_row(package))

      assert %BatchStatement{fact_id: nil, delta: nil} = s[{:fact, "f1"}]
      assert s[{:fact, "f1"}].detail["skipped"] =~ "g1"
      for gall <- ctx.galls, do: assert(Catalog.gall_summary(gall.id).hosts == [])
    end
  end

  describe "disputes" do
    test "a phase 6 dispute is queued, and dropping the statement leaves it out", ctx do
      [chosen, _] = ctx.galls

      finding = %{
        "batch" => "gall.json",
        "id" => "f2",
        "problem" => "unsupported",
        "reason" => "the quote does not name the Host",
        "response" => %{"decision" => "disagree", "reason" => "it does"}
      }

      package =
        package(gall: gall_batch())
        |> with_review([finding], responded: true)
        |> deliver!()

      assert [%QueueItem{statement_ref: "f2", subject: subject} = dispute] =
               Import.list_queue_items(package, kind: :dispute)

      assert [%{"reason" => "the quote does not name the Host"}] = subject["findings"]

      [ambiguous] = Import.list_queue_items(package, kind: :ambiguous_match)
      {:ok, _} = Import.decide_queue_item(test_actor(), ambiguous, %{"gall_id" => chosen.id})
      {:ok, _} = Import.decide_queue_item(test_actor(), dispute, %{"skip" => true})

      {:ok, _} = Import.approve_package(test_actor(), package)
      s = statements(gall_row(package))

      assert %BatchStatement{fact_id: nil} = s[{:fact, "f2"}]
      assert is_integer(s[{:fact, "f1"}].fact_id)
      assert Catalog.gall_summary(chosen.id).hosts == []
    end
  end

  describe "generations" do
    test "a generation outside its Inducer's groups is queued", ctx do
      seasonal = Enum.find(Catalog.list_generation_groups(), &(&1.name == "seasonal"))

      Repo.insert_all("generation_group_taxa", [
        %{group_id: seasonal.id, taxon_id: ctx.andricus.id}
      ])

      taxon_fixture(name: "Andricus novus", parent: ctx.andricus)

      gall =
        gall_batch()
        |> put_in(["taxa", Access.at(0), "name_as_written"], "Andricus novus")
        |> put_in(["galls", Access.at(0), "identified_by", "generation"], %{
          "value" => "agamic",
          "as_written" => "agamic"
        })
        |> put_in(["galls", Access.at(0), "new"], true)

      package = package(gall: gall) |> with_review() |> deliver!()
      assert Import.list_queue_items(package) == []
      {:ok, _} = Import.approve_package(test_actor(), package)

      assert [%QueueItem{statement_ref: "g1", subject: %{"generation" => "agamic"}}] =
               Import.list_queue_items(package, kind: :generation_outside_group)

      assert %BatchStatement{gall_id: gall_id} = statements(gall_row(package))[{:gall, "g1"}]
      assert Catalog.get_gall!(gall_id).name == "Andricus novus (agamic)"
    end
  end
end
