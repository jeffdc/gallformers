defmodule Gallformers.Storage.LocalBackendTest do
  use ExUnit.Case, async: true

  alias Gallformers.Storage.LocalBackend

  setup do
    root =
      Path.join(System.tmp_dir!(), "local_backend_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  describe "upload/4 and get_object/2" do
    test "round-trips content through the filesystem", %{root: root} do
      bucket = root
      path = "source-ingestions/1/extract/text.txt"

      assert {:ok, _} = LocalBackend.upload(bucket, path, "hello world", "text/plain")
      assert {:ok, %{body: "hello world"}} = LocalBackend.get_object(bucket, path)
    end

    test "overwrites existing file on re-upload", %{root: root} do
      bucket = root
      path = "source-ingestions/1/extract/text.txt"

      LocalBackend.upload(bucket, path, "first", "text/plain")
      LocalBackend.upload(bucket, path, "second", "text/plain")

      assert {:ok, %{body: "second"}} = LocalBackend.get_object(bucket, path)
    end
  end

  describe "get_object/2 errors" do
    test "returns not_found for missing file", %{root: root} do
      assert {:error, :not_found} = LocalBackend.get_object(root, "no/such/file.txt")
    end
  end

  describe "list_objects/3" do
    test "lists files under a prefix", %{root: root} do
      LocalBackend.upload(root, "ingestions/1/a.txt", "a", "text/plain")
      LocalBackend.upload(root, "ingestions/1/b.txt", "b", "text/plain")
      LocalBackend.upload(root, "ingestions/2/c.txt", "c", "text/plain")

      assert {:ok, %{keys: keys, is_truncated: false, next_continuation_token: nil}} =
               LocalBackend.list_objects(root, "ingestions/1/", nil)

      assert Enum.sort(keys) == ["ingestions/1/a.txt", "ingestions/1/b.txt"]
    end

    test "returns empty list for missing prefix", %{root: root} do
      assert {:ok, %{keys: [], is_truncated: false, next_continuation_token: nil}} =
               LocalBackend.list_objects(root, "nonexistent/", nil)
    end
  end

  describe "delete_objects/2" do
    test "deletes listed files", %{root: root} do
      LocalBackend.upload(root, "del/a.txt", "a", "text/plain")
      LocalBackend.upload(root, "del/b.txt", "b", "text/plain")

      assert {:ok, _} = LocalBackend.delete_objects(root, ["del/a.txt", "del/b.txt"])

      assert {:error, :not_found} = LocalBackend.get_object(root, "del/a.txt")
      assert {:error, :not_found} = LocalBackend.get_object(root, "del/b.txt")
    end

    test "succeeds even if files don't exist", %{root: root} do
      assert {:ok, _} = LocalBackend.delete_objects(root, ["ghost.txt"])
    end
  end

  describe "copy_object/4" do
    test "copies from source bucket/path to destination bucket/path", %{root: root} do
      src_bucket = Path.join(root, "src")
      dest_bucket = Path.join(root, "dest")

      LocalBackend.upload(src_bucket, "original.txt", "copied content", "text/plain")

      assert {:ok, _} =
               LocalBackend.copy_object(dest_bucket, "copy.txt", src_bucket, "original.txt")

      assert {:ok, %{body: "copied content"}} = LocalBackend.get_object(dest_bucket, "copy.txt")
    end
  end
end
