defmodule Gallformers.Import.WorkerTest do
  @moduledoc """
  The import job (`Gallformers.Import.Worker`, inline in tests): a delivered
  package is validated and resolved; Gallformers' own batches need no
  review; an approved package is applied.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Import
  alias Gallformers.Import.Package
  alias Gallformers.Storage.Private

  setup :audit_test_metadata

  defp register(files) do
    key = "pkg-#{System.unique_integer([:positive])}"
    for {name, bytes} <- files, do: :ok = Private.put("import/#{key}/#{name}", bytes)
    {:ok, package} = Import.register_package(test_actor(), key)
    package
  end

  test "a delivered package is validated and resolved, then applied once approved" do
    load_vocab!()
    plant_fixture(name: "Quercus lobata")
    taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
      |> put_in(["galls", Access.at(0), "new"], true)

    package = package(gall: gall) |> with_review() |> register()

    assert {:ok, _job} = Import.enqueue_package(test_actor(), package)
    assert %Package{status: :awaiting_review} = Import.get_package!(package.id)

    assert {:ok, %Package{status: :approved}} = Import.approve_package(test_actor(), package)
    assert [%{status: :applied}] = Import.list_batches(package)
  end

  test "a package of Gallformers' own batches is validated without a review" do
    content = example("gallformers-statement") |> unique_batch_id()
    package = register(batch_files([{"gall.json", content}]))

    assert {:ok, _job} = Import.enqueue_package(test_actor(), package)
    package = Import.get_package!(package.id)

    assert package.status == :awaiting_review
    refute Enum.any?(package.problems, &(&1["level"] == "error"))
  end

  test "with no Oban running (a release task such as the replay), the step is taken at once" do
    content = example("gallformers-statement") |> unique_batch_id()
    package = register(batch_files([{"gall.json", content}]))

    assert {:ok, nil} = Import.enqueue_package(test_actor(), package, :no_such_oban)
    assert Import.get_package!(package.id).status == :awaiting_review
  end

  defmodule Listener do
    @moduledoc false
    @behaviour Gallformers.Import.Events

    @impl true
    def package_advanced(package) do
      send(self(), {:package_advanced, package.id, package.status})
      :ok
    end
  end

  describe "the package events (Gallformers.Import.Events)" do
    setup do
      previous = Application.get_env(:gallformers, Gallformers.Import.Events)
      Application.put_env(:gallformers, Gallformers.Import.Events, listeners: [Listener])

      on_exit(fn ->
        if previous,
          do: Application.put_env(:gallformers, Gallformers.Import.Events, previous),
          else: Application.delete_env(:gallformers, Gallformers.Import.Events)
      end)
    end

    test "each step the job takes a package is told to the listeners" do
      load_vocab!()
      plant_fixture(name: "Quercus lobata")
      taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
      taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")

      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
        |> put_in(["galls", Access.at(0), "new"], true)

      package = package(gall: gall) |> with_review() |> register()
      id = package.id

      {:ok, _job} = Import.enqueue_package(test_actor(), package)
      assert_received {:package_advanced, ^id, :awaiting_review}

      {:ok, _} = Import.approve_package(test_actor(), package)
      assert_received {:package_advanced, ^id, :approved}
    end
  end
end
