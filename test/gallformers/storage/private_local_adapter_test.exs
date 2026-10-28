defmodule Gallformers.Storage.Private.LocalAdapterTest do
  @moduledoc """
  The private bucket on the local disk, for development: nothing reaches S3.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Storage.Private.LocalAdapter

  setup do
    bucket = "test-bucket-#{System.unique_integer([:positive])}"
    on_exit(fn -> File.rm_rf!(Path.join(LocalAdapter.root(), bucket)) end)
    %{bucket: bucket}
  end

  test "an object put can be got back", %{bucket: bucket} do
    assert :ok = LocalAdapter.put_object(bucket, "import/k1/gall.json", ~s({"a": 1}), [])
    assert LocalAdapter.get_object(bucket, "import/k1/gall.json") == {:ok, ~s({"a": 1})}
  end

  test "it is a file under the root, by bucket and key", %{bucket: bucket} do
    :ok = LocalAdapter.put_object(bucket, "sources/1/doc.txt", "text", content_type: "text/plain")
    assert File.read!(Path.join([LocalAdapter.root(), bucket, "sources/1/doc.txt"])) == "text"
  end

  test "a missing object is not found", %{bucket: bucket} do
    assert LocalAdapter.get_object(bucket, "import/none/gall.json") == {:error, :not_found}
  end

  test "a key may not climb out of its bucket", %{bucket: bucket} do
    assert LocalAdapter.put_object(bucket, "../escape.txt", "x", []) == {:error, :invalid_key}
    assert LocalAdapter.get_object(bucket, "a/../../escape.txt") == {:error, :invalid_key}
  end
end
