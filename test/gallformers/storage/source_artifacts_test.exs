defmodule Gallformers.Storage.SourceArtifactsTest do
  use ExUnit.Case, async: false

  alias Gallformers.Sources.Source
  alias Gallformers.Storage.SourceArtifacts

  defmodule BackendStub do
    @behaviour Gallformers.Storage.SourceArtifacts.Backend

    @impl true
    def upload(bucket, path, content, content_type) do
      send(self(), {:upload, bucket, path, content, content_type})
      Process.get(:upload_result, {:ok, %{}})
    end

    @impl true
    def get_object(bucket, path) do
      send(self(), {:get_object, bucket, path})
      Process.get(:get_object_result, {:ok, %{body: ""}})
    end

    @impl true
    def list_objects(bucket, prefix, continuation_token) do
      send(self(), {:list_objects, bucket, prefix, continuation_token})

      case Process.get(:list_objects_results, [
             {:ok, %{keys: [], next_continuation_token: nil, is_truncated: false}}
           ]) do
        [next_result | rest] ->
          Process.put(:list_objects_results, rest)
          next_result

        [] ->
          {:ok, %{keys: [], next_continuation_token: nil, is_truncated: false}}
      end
    end

    @impl true
    def delete_objects(bucket, keys) do
      send(self(), {:delete_objects, bucket, keys})
      Process.get(:delete_objects_result, {:ok, %{}})
    end

    @impl true
    def copy_object(_dest_bucket, _dest_path, _src_bucket, _src_path), do: {:ok, %{}}
  end

  setup do
    previous_config = Application.get_env(:gallformers, SourceArtifacts)
    Application.put_env(:gallformers, SourceArtifacts, backend: BackendStub)

    on_exit(fn ->
      if previous_config == nil do
        Application.delete_env(:gallformers, SourceArtifacts)
      else
        Application.put_env(:gallformers, SourceArtifacts, previous_config)
      end
    end)

    :ok
  end

  describe "private_artifact_prefix/1" do
    test "returns the canonical source-ingestions prefix" do
      assert SourceArtifacts.private_artifact_prefix(42) == "source-ingestions/42"
    end
  end

  describe "private_artifact_path/3" do
    test "builds the canonical stage-aware private artifact path" do
      assert SourceArtifacts.private_artifact_path(42, :extract, "text.txt") ==
               "source-ingestions/42/extract/text.txt"
    end
  end

  describe "private_artifact_path/2" do
    test "returns nil when the persisted artifacts_path is blank" do
      assert SourceArtifacts.private_artifact_path("", "file.txt") == nil
    end

    test "joins a persisted artifacts_path with a string suffix" do
      assert SourceArtifacts.private_artifact_path("source-ingestions/42", "file.txt") ==
               "source-ingestions/42/file.txt"
    end

    test "joins a persisted artifacts_path with a list suffix" do
      assert SourceArtifacts.private_artifact_path("source-ingestions/42", [
               "extract",
               "page1.json"
             ]) ==
               "source-ingestions/42/extract/page1.json"
    end
  end

  describe "public_source_prefix/1" do
    test "returns the canonical published-source prefix" do
      assert SourceArtifacts.public_source_prefix(42) == "sources/42"
    end
  end

  describe "published_markdown_path/1" do
    test "builds a snake_case path under the public sources namespace" do
      source = %Source{id: 42, title: "Oaks & Their Galls"}

      assert SourceArtifacts.published_markdown_path(source) ==
               "sources/42/oaks_their_galls.md"
    end

    test "truncates long filenames deterministically and preserves the markdown suffix" do
      source = %Source{id: 42, title: String.duplicate("A", 200)}
      path = SourceArtifacts.published_markdown_path(source)

      assert path == "sources/42/#{String.duplicate("a", 120)}.md"
    end

    test "falls back to a source-id-based filename when normalization would be blank" do
      source = %Source{id: 55, title: "!!!"}

      assert SourceArtifacts.published_markdown_path(source) == "sources/55/source_55.md"
    end
  end

  describe "published_markdown_url/1" do
    test "builds the public URL from the published markdown path" do
      source = %Source{id: 7, title: "Gall Paper"}

      assert SourceArtifacts.published_markdown_url(source) ==
               "https://gallformers-images-us-east-1.s3.amazonaws.com/sources/7/gall_paper.md"
    end
  end

  describe "upload_private_artifact/5" do
    test "uploads to the private bucket using the canonical path" do
      bucket = SourceArtifacts.private_bucket()

      assert {:ok, path} =
               SourceArtifacts.upload_private_artifact(
                 42,
                 :preprocess,
                 "text.txt",
                 "cleaned text",
                 "text/plain"
               )

      assert path == "source-ingestions/42/preprocess/text.txt"

      assert_received {:upload, ^bucket, "source-ingestions/42/preprocess/text.txt",
                       "cleaned text", "text/plain"}
    end
  end

  describe "download_private_artifact/3" do
    test "returns artifact contents" do
      bucket = SourceArtifacts.private_bucket()
      Process.put(:get_object_result, {:ok, %{body: "artifact contents"}})

      assert {:ok, "artifact contents"} =
               SourceArtifacts.download_private_artifact(42, :metadata, "output.json")

      assert_received {:get_object, ^bucket, "source-ingestions/42/metadata/output.json"}
    end

    test "normalizes missing object errors to not_found" do
      Process.put(:get_object_result, {:error, {:http_error, 404, "missing"}})

      assert {:error, :not_found} =
               SourceArtifacts.download_private_artifact(42, :metadata, "missing.json")
    end
  end

  describe "list_private_artifacts_for_ingestion/1" do
    test "returns all artifact keys across paginated results sorted lexicographically" do
      bucket = SourceArtifacts.private_bucket()

      Process.put(:list_objects_results, [
        {:ok,
         %{
           keys: ["source-ingestions/42/extract/text.txt"],
           next_continuation_token: "page-2",
           is_truncated: true
         }},
        {:ok,
         %{
           keys: [
             "source-ingestions/42/preprocess/text.txt",
             "source-ingestions/42/metadata/output.json"
           ],
           next_continuation_token: nil,
           is_truncated: false
         }}
      ])

      assert {:ok, keys} = SourceArtifacts.list_private_artifacts_for_ingestion(42)

      assert_received {:list_objects, ^bucket, "source-ingestions/42/", nil}
      assert_received {:list_objects, ^bucket, "source-ingestions/42/", "page-2"}

      assert keys == [
               "source-ingestions/42/extract/text.txt",
               "source-ingestions/42/metadata/output.json",
               "source-ingestions/42/preprocess/text.txt"
             ]
    end

    test "does not request another page when the listing is not truncated" do
      bucket = SourceArtifacts.private_bucket()

      Process.put(:list_objects_results, [
        {:ok,
         %{
           keys: ["source-ingestions/42/extract/text.txt"],
           next_continuation_token: "bogus-token",
           is_truncated: false
         }}
      ])

      assert {:ok, keys} = SourceArtifacts.list_private_artifacts_for_ingestion(42)

      assert_received {:list_objects, ^bucket, "source-ingestions/42/", nil}
      refute_received {:list_objects, ^bucket, "source-ingestions/42/", "bogus-token"}
      assert keys == ["source-ingestions/42/extract/text.txt"]
    end
  end

  describe "delete_private_artifacts_for_ingestion/1" do
    test "lists all objects under the ingestion prefix and deletes them in a batch" do
      bucket = SourceArtifacts.private_bucket()

      Process.put(:list_objects_results, [
        {:ok,
         %{
           keys: ["source-ingestions/42/extract/text.txt"],
           next_continuation_token: "page-2",
           is_truncated: true
         }},
        {:ok,
         %{
           keys: [
             "source-ingestions/42/preprocess/text.txt",
             "source-ingestions/42/metadata/output.json"
           ],
           next_continuation_token: nil,
           is_truncated: false
         }}
      ])

      assert :ok = SourceArtifacts.delete_private_artifacts_for_ingestion(42)

      assert_received {:list_objects, ^bucket, "source-ingestions/42/", nil}
      assert_received {:list_objects, ^bucket, "source-ingestions/42/", "page-2"}
      assert_received {:delete_objects, ^bucket, keys}

      assert Enum.sort(keys) == [
               "source-ingestions/42/extract/text.txt",
               "source-ingestions/42/metadata/output.json",
               "source-ingestions/42/preprocess/text.txt"
             ]
    end
  end
end
