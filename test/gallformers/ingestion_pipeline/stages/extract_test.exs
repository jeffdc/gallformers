defmodule Gallformers.IngestionPipeline.Stages.ExtractTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.IngestionPipeline.Stages.Extract
  alias Gallformers.Ingestions
  alias Gallformers.Storage.SourceArtifacts

  defmodule StorageBackendStub do
    @behaviour Gallformers.Storage.SourceArtifacts.Backend

    @impl true
    def upload(bucket, path, content, content_type) do
      send(test_pid(), {:upload, bucket, path, content, content_type})
      Process.get(:upload_result, {:ok, %{}})
    end

    @impl true
    def get_object(bucket, path) do
      send(test_pid(), {:get_object, bucket, path})

      case Process.get(:extract_storage_objects, %{}) do
        %{^path => %{body: body}} -> {:ok, %{body: body}}
        _ -> Process.get(:get_object_result, {:ok, %{body: "%PDF-1.4\nfixture\n"}})
      end
    end

    @impl true
    def list_objects(_bucket, _prefix, _continuation_token),
      do: {:ok, %{keys: [], next_continuation_token: nil}}

    @impl true
    def delete_objects(_bucket, _keys), do: {:ok, %{}}

    @impl true
    def copy_object(_dest_bucket, _dest_path, _src_bucket, _src_path), do: {:ok, %{}}

    defp test_pid, do: Process.get(:extract_test_pid, self())
  end

  defmodule ExtractorStub do
    def extract_text(file_path, opts) do
      send(test_pid(), {:extractor_extract, file_path, opts, File.read!(file_path)})

      Process.get(
        :extractor_result,
        {:ok, %{text: "extracted text", page_count: 2, metadata: %{}}}
      )
    end

    defp test_pid, do: Process.get(:extract_test_pid, self())
  end

  defmodule URLExtractorStub do
    def extract_text(url) do
      send(test_pid(), {:url_extractor_extract, url})

      Process.get(
        :url_extractor_result,
        {:ok, %{text: "url extracted text"}}
      )
    end

    defp test_pid, do: Process.get(:extract_test_pid, self())
  end

  setup do
    previous_storage_config = Application.get_env(:gallformers, SourceArtifacts)
    previous_extract_config = Application.get_env(:gallformers, Extract)

    Process.put(:extract_test_pid, self())
    Application.put_env(:gallformers, SourceArtifacts, backend: StorageBackendStub)

    Application.put_env(
      :gallformers,
      Extract,
      extractor: ExtractorStub,
      url_extractor: URLExtractorStub
    )

    on_exit(fn ->
      Process.delete(:extract_test_pid)
      Process.delete(:extract_storage_objects)
      Process.delete(:get_object_result)
      Process.delete(:extractor_result)
      Process.delete(:url_extractor_result)

      if previous_storage_config == nil do
        Application.delete_env(:gallformers, SourceArtifacts)
      else
        Application.put_env(:gallformers, SourceArtifacts, previous_storage_config)
      end

      if previous_extract_config == nil do
        Application.delete_env(:gallformers, Extract)
      else
        Application.put_env(:gallformers, Extract, previous_extract_config)
      end
    end)

    :ok
  end

  describe "perform_stage/1" do
    test "downloads the input pdf, extracts text, uploads the artifact, and updates the stage" do
      ingestion = source_ingestion_fixture()
      input_path = "source-ingestions/#{ingestion.id}/input/source.pdf"
      output_path = "source-ingestions/#{ingestion.id}/extract/text.txt"

      assert {:ok, updated_ingestion} = Extract.perform_stage(ingestion)

      assert_received {:get_object, _, ^input_path}

      assert_received {:extractor_extract, temp_file_path, [ocr_fallback: false],
                       "%PDF-1.4\nfixture\n"}

      refute File.exists?(temp_file_path)

      assert_received {:upload, _, ^output_path, "extracted text", "text/plain"}

      assert updated_ingestion.processing_stage == "extract"
      assert updated_ingestion.status == "processing"
    end

    test "copies text submissions to the extract artifact and updates the stage" do
      text = "Rounded woody gall on oak twigs."
      ingestion = source_ingestion_fixture(%{input_type: "text"})
      input_path = "source-ingestions/#{ingestion.id}/input/source.txt"
      output_path = "source-ingestions/#{ingestion.id}/extract/text.txt"

      put_storage_object(input_path, text)

      assert {:ok, updated_ingestion} = Extract.perform_stage(ingestion)

      assert_received {:get_object, _, ^input_path}
      assert_received {:upload, _, ^output_path, ^text, "text/plain"}
      assert updated_ingestion.processing_stage == "extract"
      assert updated_ingestion.status == "processing"
    end

    test "extracts text from url submissions, uploads the extract artifact, and updates the stage" do
      url = "https://example.com/galls"
      ingestion = source_ingestion_fixture(%{input_type: "url"})
      input_path = "source-ingestions/#{ingestion.id}/input/source.url"
      output_path = "source-ingestions/#{ingestion.id}/extract/text.txt"

      put_storage_object(input_path, url)

      assert {:ok, updated_ingestion} = Extract.perform_stage(ingestion)

      assert_received {:get_object, _, ^input_path}
      assert_received {:url_extractor_extract, ^url}
      assert_received {:upload, _, ^output_path, "url extracted text", "text/plain"}
      assert updated_ingestion.processing_stage == "extract"
      assert updated_ingestion.status == "processing"
    end

    test "returns extractor errors without updating the ingestion" do
      ingestion = source_ingestion_fixture()
      Process.put(:extractor_result, {:error, :extraction_failed, :boom})

      assert {:error, :extraction_failed, :boom} = Extract.perform_stage(ingestion)

      reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
      assert reloaded_ingestion.processing_stage == "submitted"
      assert reloaded_ingestion.status == "processing"
    end

    test "returns url extractor errors without updating the ingestion" do
      url = "not-a-valid-url"
      ingestion = source_ingestion_fixture(%{input_type: "url"})
      input_path = "source-ingestions/#{ingestion.id}/input/source.url"

      put_storage_object(input_path, url)
      Process.put(:url_extractor_result, {:error, :invalid_url})

      assert {:error, :invalid_url} = Extract.perform_stage(ingestion)

      reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
      assert reloaded_ingestion.processing_stage == "submitted"
      assert reloaded_ingestion.status == "processing"
      assert_received {:get_object, _, ^input_path}
      assert_received {:url_extractor_extract, ^url}
      refute_received {:upload, _, _, _, _}
    end

    test "rejects unsupported input types" do
      ingestion = source_ingestion_fixture(%{input_type: "docx"})

      assert {:error, :unsupported_input_type} = Extract.perform_stage(ingestion)
    end
  end

  defp source_ingestion_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          input_type: "pdf",
          status: "processing",
          processing_stage: "submitted"
        },
        attrs
      )

    {:ok, ingestion} = Ingestions.create_source_ingestion(attrs)
    ingestion
  end

  defp put_storage_object(path, body) do
    objects = Process.get(:extract_storage_objects, %{})
    Process.put(:extract_storage_objects, Map.put(objects, path, %{body: body}))
  end
end
