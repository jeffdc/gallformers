defmodule Gallformers.Import.IntakeTest do
  @moduledoc """
  Registering and validating a package delivered to the private bucket
  (`import/<key>/`): the package row, its batches (producer `batch_id`
  unique), its unmapped entries, and the validation problems.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.ImportFixtures

  alias Gallformers.CatalogFixtures
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Storage.Private

  setup :audit_test_metadata

  defp deliver(files) do
    key = "pkg-#{System.unique_integer([:positive])}"
    for {name, bytes} <- files, do: :ok = Private.put("import/#{key}/#{name}", bytes)
    {:ok, package} = Import.register_package(test_actor(), key)
    package
  end

  defp with_batch_ids(pkg, gall_id, taxonomy_id \\ nil) do
    pkg
    |> Map.update!("gall.json", &set_batch_id(&1, gall_id))
    |> then(fn p ->
      if taxonomy_id, do: Map.update!(p, "taxonomy.json", &set_batch_id(&1, taxonomy_id)), else: p
    end)
  end

  defp set_batch_id(bytes, id),
    do: bytes |> Jason.decode!() |> Map.put("batch_id", id) |> Jason.encode!()

  defp unique_id, do: "batch-#{System.unique_integer([:positive])}-0000"

  defp changes_for(table, id) do
    Repo.all(
      from c in Carbonite.Change, where: c.table_name == ^table and c.table_pk == ^["#{id}"]
    )
  end

  describe "register_package/3" do
    test "records a received package under import/<key>/" do
      assert {:ok, %Package{} = package} = Import.register_package(test_actor(), "abc-123")
      assert package.key == "abc-123"
      assert package.s3_prefix == "import/abc-123/"
      assert package.status == :received
      assert package.submitter_name == "test"
      assert package.problems == []
    end

    test "a key is registered once" do
      assert {:ok, _} = Import.register_package(test_actor(), "twice")
      assert {:error, changeset} = Import.register_package(test_actor(), "twice")
      assert %{key: [_]} = errors_on(changeset)
    end

    test "a key must be a plain folder name" do
      assert {:error, changeset} = Import.register_package(test_actor(), "../escape")
      assert %{key: [_]} = errors_on(changeset)
    end

    test "is audited" do
      {:ok, package} = Import.register_package(test_actor(), "audited")
      assert [%Carbonite.Change{op: :insert}] = changes_for("import_packages", package.id)
    end
  end

  describe "validate_package/3" do
    test "a valid package is validated and its batches recorded" do
      files =
        package(taxonomy: taxonomy_batch())
        |> with_batch_ids(unique_id(), unique_id())
        |> with_review()

      package = deliver(files)

      assert {:ok, %Package{status: :validated, problems: []} = package} =
               Import.validate_package(test_actor(), package)

      assert package.format_version == 3
      assert package.vocabulary_version == "2026-10-07"
      assert %DateTime{} = package.validated_at

      [taxonomy, gall] = Import.list_batches(package)
      assert %Batch{file: "taxonomy.json", batch_type: :taxonomy, mode: :replace} = taxonomy
      assert %Batch{file: "gall.json", batch_type: :gall, status: :pending} = gall
      assert gall.producer_batch_id == Jason.decode!(files["gall.json"])["batch_id"]
      assert gall.sha256 == sha256(files["gall.json"])
      assert gall.content["facts"] |> length() == 4
    end

    test "the batches' unmapped entries are kept" do
      unmapped = %{
        "term" => "lignified",
        "slot" => "texture",
        "gall" => "g1",
        "note" => "no value fits",
        "evidence" => [%{"item" => "#/texts/1", "quote" => "pale tan"}]
      }

      gall = Map.put(batch(), "unmapped", [unmapped])
      package = deliver(package(gall: gall) |> with_batch_ids(unique_id()) |> with_review())

      {:ok, package} = Import.validate_package(test_actor(), package)
      [gall_batch] = Import.list_batches(package)

      assert [entry] = Import.list_unmapped(gall_batch)
      assert entry.term == "lignified"
      assert entry.slot == "texture"
      assert entry.gall_ref == "g1"
      assert entry.note == "no value fits"
      assert [%{"item" => "#/texts/1"}] = entry.evidence
    end

    test "an invalid package keeps its problems and records no batches" do
      bad = put_in(batch(), ["facts", Access.at(1), "evidence", Access.at(0), "quote"], "Rare")
      package = deliver(package(gall: bad) |> with_batch_ids(unique_id()) |> with_review())

      assert {:ok, %Package{status: :invalid} = package} =
               Import.validate_package(test_actor(), package)

      assert [%{"level" => "error", "file" => "gall.json", "message" => message}] =
               package.problems

      assert message =~ "quote not found"
      assert Import.list_batches(package) == []
    end

    test "warnings do not make a package invalid" do
      gall =
        Map.update!(
          batch(),
          "taxa",
          &(&1 ++ [%{"ref" => "t9", "name_as_written" => "X", "rank" => "genus"}])
        )

      package = deliver(package(gall: gall) |> with_batch_ids(unique_id()) |> with_review())

      assert {:ok, %Package{status: :validated, problems: [%{"level" => "warning"}]}} =
               Import.validate_package(test_actor(), package)
    end

    test "the readiness gate applies unless review: false" do
      files = package() |> with_batch_ids(unique_id())
      package = deliver(files)

      assert {:ok, %Package{status: :invalid, problems: [problem]}} =
               Import.validate_package(test_actor(), package)

      assert problem["file"] == "review.json"
      assert problem["message"] =~ "no review.json"

      assert {:ok, %Package{status: :validated}} =
               Import.validate_package(test_actor(), package, review: false)
    end

    test "a batch_id delivered before is a problem (each batch is imported once)" do
      id = unique_id()
      first = deliver(package() |> with_batch_ids(id) |> with_review())
      {:ok, %Package{status: :validated}} = Import.validate_package(test_actor(), first)

      second = deliver(package() |> with_batch_ids(id) |> with_review())

      assert {:ok, %Package{status: :invalid, problems: [problem]}} =
               Import.validate_package(test_actor(), second)

      assert problem["file"] == "gall.json"
      assert problem["message"] =~ id
      assert problem["message"] =~ first.key
    end

    test "validating again replaces the package's batches" do
      package = deliver(package() |> with_batch_ids(unique_id()) |> with_review())
      {:ok, package} = Import.validate_package(test_actor(), package)
      [before] = Import.list_batches(package)

      {:ok, package} = Import.validate_package(test_actor(), package)
      assert [again] = Import.list_batches(package)
      assert again.producer_batch_id == before.producer_batch_id
    end

    test "a package with no files in the bucket" do
      {:ok, package} =
        Import.register_package(test_actor(), "empty-#{System.unique_integer([:positive])}")

      assert {:ok, %Package{status: :invalid, problems: problems}} =
               Import.validate_package(test_actor(), package, review: false)

      assert [%{"file" => "package", "message" => "no taxonomy.json or gall.json"}] = problems
    end

    test "an applied package cannot be validated again" do
      package = deliver(package() |> with_batch_ids(unique_id()) |> with_review())
      {:ok, package} = Import.validate_package(test_actor(), package)

      Repo.update_all(from(p in Package, where: p.id == ^package.id), set: [status: "approved"])
      package = Import.get_package!(package.id)

      assert {:error, :not_validatable} = Import.validate_package(test_actor(), package)
    end
  end

  describe "attributions.batch_id" do
    test "points at an import batch" do
      source = CatalogFixtures.source_fixture("Batch FK", "2024")
      {:ok, fact} = Facts.create_fact(test_actor(), %{kind: "test"})

      attrs = %{fact_id: fact.id, source_id: source.id, stance: :confirm, batch_id: -1}
      assert {:error, changeset} = Facts.attribute(test_actor(), attrs)
      assert %{batch_id: ["does not exist"]} = errors_on(changeset)

      package = deliver(package() |> with_batch_ids(unique_id()) |> with_review())
      {:ok, package} = Import.validate_package(test_actor(), package)
      [batch] = Import.list_batches(package)

      assert {:ok, %{attribution: attribution}} =
               Facts.attribute(test_actor(), %{attrs | batch_id: batch.id})

      assert attribution.batch_id == batch.id
    end
  end
end
