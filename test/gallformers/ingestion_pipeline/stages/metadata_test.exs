defmodule Gallformers.IngestionPipeline.Stages.MetadataTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.Stages.Metadata
  alias Gallformers.Ingestions
  alias Gallformers.Storage.SourceArtifacts

  defmodule StorageBackendStub do
    @behaviour Gallformers.Storage.SourceArtifacts.Backend

    @impl true
    def upload(bucket, path, content, content_type) do
      send(test_pid(), {:upload, bucket, path, content, content_type})
      {:ok, %{}}
    end

    @impl true
    def get_object(bucket, path) do
      send(test_pid(), {:get_object, bucket, path})
      {:ok, %{body: Process.get(:metadata_text_fixture)}}
    end

    @impl true
    def list_objects(_bucket, _prefix, _continuation_token),
      do: {:ok, %{keys: [], next_continuation_token: nil}}

    @impl true
    def delete_objects(_bucket, _keys), do: {:ok, %{}}

    @impl true
    def copy_object(_dest_bucket, _dest_path, _src_bucket, _src_path), do: {:ok, %{}}

    defp test_pid, do: Process.get(:metadata_test_pid, self())
  end

  defmodule LLMClientStub do
    def completion(:metadata, prompt, text, opts) do
      send(test_pid(), {:completion, prompt, text, opts})

      responses = responses()
      attempt = Process.get(:metadata_attempt, 0)
      response = Enum.at(responses, attempt, List.last(responses))
      Process.put(:metadata_attempt, attempt + 1)
      response
    end

    defp test_pid do
      :gallformers
      |> Application.get_env(Metadata, [])
      |> Keyword.fetch!(:test_pid)
    end

    defp responses do
      :gallformers
      |> Application.get_env(Metadata, [])
      |> Keyword.get(:responses, [])
    end
  end

  setup do
    previous_storage_config = Application.get_env(:gallformers, SourceArtifacts)
    previous_metadata_config = Application.get_env(:gallformers, Metadata)

    Process.put(:metadata_test_pid, self())
    Application.put_env(:gallformers, SourceArtifacts, backend: StorageBackendStub)
    Application.put_env(:gallformers, Metadata, llm_client: LLMClientStub, test_pid: self())

    on_exit(fn ->
      Process.delete(:metadata_test_pid)
      Process.delete(:metadata_text_fixture)
      Process.delete(:metadata_attempt)

      if previous_storage_config == nil do
        Application.delete_env(:gallformers, SourceArtifacts)
      else
        Application.put_env(:gallformers, SourceArtifacts, previous_storage_config)
      end

      if previous_metadata_config == nil do
        Application.delete_env(:gallformers, Metadata)
      else
        Application.put_env(:gallformers, Metadata, previous_metadata_config)
      end
    end)

    :ok
  end

  test "parses valid JSON, persists normalized signals, uploads the artifact, and updates the stage" do
    ingestion = source_ingestion_fixture()
    input_path = "source-ingestions/#{ingestion.id}/llm_clean/text.txt"
    output_path = "source-ingestions/#{ingestion.id}/metadata/output.json"
    Broadcaster.subscribe(ingestion.id)

    cleaned_text = "Intro" <> String.duplicate("x", 25_000)

    raw_response =
      ~s({"title":"A Study of Gall Insects.","authors":["Smith, J.A."," Jones "],"year":1919,"doi":"DOI:10.1234/Example."})

    # Expected parsed JSON (upload is always pretty-printed)
    {:ok, expected_data} =
      Jason.decode(
        ~S({"title":"A Study of Gall Insects.","authors":["Smith, J.A."," Jones "],"year":1919,"doi":"DOI:10.1234/Example."})
      )

    Process.put(:metadata_text_fixture, cleaned_text)
    set_responses([{:ok, raw_response, %{prompt_tokens: 10, completion_tokens: 5}}])

    assert {:ok, updated_ingestion} = Metadata.perform_stage(ingestion)

    assert_received {:get_object, _, ^input_path}
    assert_received {:completion, prompt, truncated_text, [max_tokens: 1024]}
    assert String.length(truncated_text) == 24_000
    assert String.starts_with?(truncated_text, "Intro") == true

    assert prompt ==
             File.read!(Path.join([:code.priv_dir(:gallformers), "prompts", "metadata.txt"]))

    # Compare decoded content (upload is pretty-printed)
    assert_received {:upload, _, ^output_path, actual_upload, "application/json"}
    assert {:ok, actual_data} = Jason.decode(actual_upload)
    assert actual_data == expected_data
    assert_receive {:stage_complete, :metadata}

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)

    assert updated_ingestion.processing_stage == "metadata"
    assert reloaded_ingestion.processing_stage == "metadata"
    assert reloaded_ingestion.status == "processing"
    assert reloaded_ingestion.title == "A Study of Gall Insects."
    assert reloaded_ingestion.normalized_title == "a study of gall insects"
    assert reloaded_ingestion.title_fingerprint == "study_gall_insects"
    assert reloaded_ingestion.authors == ["Smith, J.A.", "Jones"]
    assert reloaded_ingestion.author_fingerprint == "smith_jones"
    assert reloaded_ingestion.publication_year == 1919
    assert reloaded_ingestion.doi == "DOI:10.1234/Example."
    assert reloaded_ingestion.normalized_doi == "10.1234/example"
  end

  test "unwraps fenced JSON before parsing" do
    ingestion = source_ingestion_fixture()

    Process.put(:metadata_text_fixture, "cleaned text")

    set_responses([
      {:ok, "```json\n{\"title\":\"Fenced\",\"authors\":[\"A\"],\"year\":2020,\"doi\":null}\n```",
       %{prompt_tokens: 1, completion_tokens: 1}}
    ])

    assert {:ok, _updated_ingestion} = Metadata.perform_stage(ingestion)

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
    assert reloaded_ingestion.title == "Fenced"
    assert reloaded_ingestion.authors == ["A"]
    assert reloaded_ingestion.publication_year == 2020
  end

  test "retries malformed JSON three times and returns invalid_json" do
    ingestion = source_ingestion_fixture()
    Process.put(:metadata_text_fixture, "cleaned text")

    set_responses([
      {:ok, "{invalid", %{prompt_tokens: 1, completion_tokens: 1}},
      {:ok, "{still invalid", %{prompt_tokens: 1, completion_tokens: 1}},
      {:ok, "```json\nnot json\n```", %{prompt_tokens: 1, completion_tokens: 1}}
    ])

    assert {:error, :invalid_json} = Metadata.perform_stage(ingestion)

    assert Process.get(:metadata_attempt) == 3
    refute_received {:upload, _, _, _, _}

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
    assert reloaded_ingestion.processing_stage == "llm_clean"
    assert reloaded_ingestion.status == "processing"
  end

  test "skips retry when response hits max_tokens (truncated JSON)" do
    ingestion = source_ingestion_fixture()
    Process.put(:metadata_text_fixture, "cleaned text")

    set_responses([
      {:ok, "{\"title\": \"Truncated", %{prompt_tokens: 100, completion_tokens: 1024}}
    ])

    assert {:error, :json_truncated} = Metadata.perform_stage(ingestion)

    assert Process.get(:metadata_attempt) == 1
    refute_received {:upload, _, _, _, _}
  end

  test "broadcasts chunk_progress after metadata extraction succeeds" do
    ingestion = source_ingestion_fixture()
    Broadcaster.subscribe(ingestion.id)

    Process.put(:metadata_text_fixture, "cleaned text")

    set_responses([
      {:ok, ~s({"title":"Progress Test","authors":["A"],"year":2020,"doi":null}),
       %{prompt_tokens: 10, completion_tokens: 5}}
    ])

    assert {:ok, _updated} = Metadata.perform_stage(ingestion)

    assert_receive {:chunk_progress, :metadata,
                    %{chunk: 0, total_chunks: 1, tokens: 0, tokens_per_sec: nil}}

    assert_receive {:chunk_progress, :metadata,
                    %{chunk: 1, total_chunks: 1, tokens: 0, tokens_per_sec: nil}}
  end

  test "passes stall_timeout instead of receive_timeout from pipeline config" do
    ingestion = source_ingestion_fixture()
    Process.put(:metadata_text_fixture, "cleaned text")

    set_responses([
      {:ok, ~s({"title":"Timeout Test","authors":["A"],"year":2020,"doi":null}),
       %{prompt_tokens: 10, completion_tokens: 5}}
    ])

    assert {:ok, _updated} = Metadata.perform_stage(ingestion)

    assert_received {:completion, _prompt, _text, opts}
    refute Keyword.has_key?(opts, :receive_timeout)
  end

  test "surfaces llm client errors without uploading or advancing the stage" do
    ingestion = source_ingestion_fixture()
    Process.put(:metadata_text_fixture, "cleaned text")

    set_responses([{:error, :http_error, 401}])

    assert {:error, {:http_error, 401}} = Metadata.perform_stage(ingestion)

    refute_received {:upload, _, _, _, _}

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
    assert reloaded_ingestion.processing_stage == "llm_clean"
    assert reloaded_ingestion.status == "processing"
  end

  defp source_ingestion_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          input_type: "pdf",
          status: "processing",
          processing_stage: "llm_clean"
        },
        attrs
      )

    {:ok, ingestion} = Ingestions.create_source_ingestion(attrs)
    ingestion
  end

  defp set_responses(responses) do
    Process.delete(:metadata_attempt)

    Application.put_env(
      :gallformers,
      Metadata,
      Keyword.merge(Application.get_env(:gallformers, Metadata, []), responses: responses)
    )
  end
end
