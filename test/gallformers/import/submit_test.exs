defmodule Gallformers.Import.SubmitTest do
  @moduledoc """
  Delivering a producer's package (`Gallformers.Import.submit_package/3`,
  matter e381 *Delivery*): its files go to the private bucket, then it is
  registered, validated and resolved, ready for review.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures

  alias Gallformers.Import
  alias Gallformers.Storage.Private

  setup :audit_test_metadata

  setup do
    load_vocab!()
    :ok
  end

  defp files, do: package(gall: unique_batch_id(batch())) |> with_review()

  test "stores the files under the key, then registers, validates and resolves" do
    files = files()
    key = "submit-#{System.unique_integer([:positive])}"

    assert {:ok, package} = Import.submit_package(test_actor(), key, files)

    assert package.key == key
    assert package.status == :awaiting_review
    assert package.submitter_name == test_actor().name
    assert Private.get("import/#{key}/gall.json") == {:ok, files["gall.json"]}
    assert [_batch] = Import.list_batches(package)
  end

  test "an invalid package is kept with its problems" do
    files = Map.put(files(), "gall.json", ~s({"format": "nonsense"}))
    key = "submit-#{System.unique_integer([:positive])}"

    assert {:ok, package} = Import.submit_package(test_actor(), key, files)
    assert package.status == :invalid
    assert package.problems != []
  end

  test "only the package's own files are stored" do
    key = "submit-#{System.unique_integer([:positive])}"

    assert Import.submit_package(test_actor(), key, Map.put(files(), "notes.md", "x")) ==
             {:error, {:unknown_files, ["notes.md"]}}

    assert Private.get("import/#{key}/gall.json") == {:error, :not_found}
  end

  test "a key is delivered once" do
    key = "submit-#{System.unique_integer([:positive])}"
    {:ok, _package} = Import.submit_package(test_actor(), key, files())

    assert {:error, :key_taken} = Import.submit_package(test_actor(), key, files())
  end
end
