defmodule Gallformers.Import.ResolveTest do
  @moduledoc """
  Resolving a validated package (`Gallformers.Import.resolve_package/2`):
  each batch's statements stored with their resolutions, the admin queue
  filled, and the Host-name step (`d585`): an unresolved Host name holds the
  gall batch until an admin resolves it.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures, only: [plant_fixture: 1]
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Import
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem
  alias Gallformers.Storage.Private
  alias Gallformers.Taxa

  setup :audit_test_metadata

  defp deliver(files) do
    key = "pkg-#{System.unique_integer([:positive])}"
    for {name, bytes} <- files, do: :ok = Private.put("import/#{key}/#{name}", bytes)
    {:ok, package} = Import.register_package(test_actor(), key)
    {:ok, %Package{status: :validated} = package} = Import.validate_package(test_actor(), package)
    package
  end

  defp unique(batch),
    do: Map.put(batch, "batch_id", "batch-#{System.unique_integer([:positive])}-0000")

  # The fixture gall batch with its Host written the way an old Source does.
  defp gall_batch(host_name) do
    batch()
    |> unique()
    |> put_in(["taxa", Access.at(1), "name_as_written"], host_name)
  end

  defp statements(batch),
    do: batch |> Import.list_statements() |> Map.new(&{{&1.kind, &1.ref}, &1})

  setup do
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
    torymus = taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    velutina = plant_fixture(name: "Quercus velutina")
    %{wasp: wasp, torymus: torymus, velutina: velutina}
  end

  test "stores each batch's statements and queues what needs an admin", ctx do
    package = deliver(package(gall: gall_batch("Quercus velutina")) |> with_review())

    assert {:ok, %Package{status: :awaiting_review} = package} =
             Import.resolve_package(test_actor(), package)

    [batch] = Import.list_batches(package)
    assert batch.status == :ready

    s = statements(batch)
    assert %BatchStatement{resolution: :resolved, taxon_id: wasp_id} = s[{:taxon, "t1"}]
    assert wasp_id == ctx.wasp.id
    assert %BatchStatement{resolution: :resolved, taxon_id: host_id} = s[{:taxon, "t2"}]
    assert host_id == ctx.velutina.id
    assert %BatchStatement{resolution: :resolved} = s[{:taxon, "t3"}]

    # No Gall of this Inducer yet, and the Source does not say it is new.
    assert %BatchStatement{resolution: :unresolved} = s[{:gall, "g1"}]

    assert [%QueueItem{kind: :unresolved_name, statement_ref: "g1", status: :open}] =
             Import.list_queue_items(package)
  end

  test "an unresolved Host name holds the gall batch until an admin resolves it", ctx do
    package = deliver(package(gall: gall_batch("Quercus tinctoria")) |> with_review())

    {:ok, package} = Import.resolve_package(test_actor(), package)
    [batch] = Import.list_batches(package)

    assert batch.status == :blocked
    refute Import.applicable?(batch)
    assert %BatchStatement{resolution: :unresolved} = statements(batch)[{:taxon, "t2"}]

    assert [%QueueItem{statement_ref: "t2", subject: subject}] =
             Import.list_queue_items(package, kind: :unresolved_host)

    assert subject["name_as_written"] == "Quercus tinctoria"

    # The admin adds the historical name as a synonym; resolving again frees the batch.
    {:ok, _} = Taxa.add_synonym(test_actor(), ctx.velutina, "Quercus tinctoria")
    {:ok, package} = Import.resolve_package(test_actor(), package)
    [batch] = Import.list_batches(package)

    assert batch.status == :ready
    assert Import.applicable?(batch) == true

    assert %BatchStatement{resolution: :resolved, method: "synonym"} =
             statements(batch)[{:taxon, "t2"}]

    assert Import.list_queue_items(package, kind: :unresolved_host) == []
  end

  test "resolving again replaces the statements", _ctx do
    package = deliver(package(gall: gall_batch("Quercus velutina")) |> with_review())
    {:ok, package} = Import.resolve_package(test_actor(), package)
    {:ok, package} = Import.resolve_package(test_actor(), package)

    [batch] = Import.list_batches(package)
    assert length(Import.list_statements(batch)) == 4
    assert length(Import.list_queue_items(package)) == 1
  end

  test "a taxonomy batch's new taxon is new in the gall batch too", _ctx do
    taxonomy =
      taxonomy_batch()
      |> unique()
      |> put_in(["taxa", Access.at(0)], %{
        "ref" => "t1",
        "name_as_written" => "Andricus novus",
        "rank" => "species",
        "new" => %{"status" => "sp. nov."}
      })

    gall =
      gall_batch("Quercus velutina")
      |> put_in(["taxa", Access.at(0), "name_as_written"], "Andricus novus")
      |> put_in(["galls", Access.at(0), "new"], true)

    package = deliver(package(gall: gall, taxonomy: taxonomy) |> with_review())
    {:ok, package} = Import.resolve_package(test_actor(), package)
    [taxonomy_batch, gall_batch] = Import.list_batches(package)

    assert %BatchStatement{resolution: :new} = statements(taxonomy_batch)[{:taxon, "t1"}]
    assert %BatchStatement{resolution: :new} = statements(gall_batch)[{:taxon, "t1"}]
    assert %BatchStatement{resolution: :new} = statements(gall_batch)[{:gall, "g1"}]
  end

  test "only a validated package can be resolved" do
    {:ok, package} =
      Import.register_package(test_actor(), "unvalidated-#{System.unique_integer([:positive])}")

    assert {:error, :not_resolvable} = Import.resolve_package(test_actor(), package)
  end
end
