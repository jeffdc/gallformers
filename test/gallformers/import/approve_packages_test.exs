defmodule Gallformers.Import.ApprovePackagesTest do
  @moduledoc """
  Approving several packages at once (`6611` Task 7, the Gallformers
  notes' bulk approve): each package nothing holds is approved in turn
  (`Gallformers.Import.approve_package/2`); the others are refused, each
  with its reason.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Import
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem

  setup :audit_test_metadata

  setup do
    load_vocab!()
    plant_fixture(name: "Quercus lobata")
    taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    :ok
  end

  # A package nothing holds: its names resolve and its Gall is new.
  defp ready! do
    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
      |> put_in(["galls", Access.at(0), "new"], true)

    package(gall: gall) |> with_review() |> deliver!()
  end

  # A package held by a Host name ("Q. lobata" names no plant here).
  defp held!, do: package(gall: unique_batch_id(batch())) |> with_review() |> deliver!()

  test "approves each package nothing holds, and refuses the others with why" do
    first = ready!()
    held = held!()
    second = ready!()

    assert %{approved: approved, refused: [{refused, {:open_items, [%QueueItem{} | _]}}]} =
             Import.approve_packages(test_actor(), [first, held, second])

    assert Enum.map(approved, &{&1.id, &1.status}) == [
             {first.id, :approved},
             {second.id, :approved}
           ]

    assert %Package{} = refused
    assert refused.id == held.id

    assert Import.get_package!(first.id).status == :approved
    assert Import.get_package!(second.id).status == :approved
    assert Import.get_package!(held.id).status == :awaiting_review
  end

  test "a package no longer awaiting review is refused" do
    package = ready!()
    {:ok, _} = Import.approve_package(test_actor(), package)

    assert %{approved: [], refused: [{%Package{id: id}, :not_approvable}]} =
             Import.approve_packages(test_actor(), [package])

    assert id == package.id
  end

  test "nothing to approve approves nothing" do
    assert Import.approve_packages(test_actor(), []) == %{approved: [], refused: []}
  end
end
