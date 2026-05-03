defmodule Gallformers.IngestionPipeline.Stages.LLMCleanTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.Stages.LLMClean
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
      {:ok, %{body: Process.get(:llm_clean_text_fixture)}}
    end

    @impl true
    def list_objects(_bucket, _prefix, _continuation_token),
      do: {:ok, %{keys: [], next_continuation_token: nil}}

    @impl true
    def delete_objects(_bucket, _keys), do: {:ok, %{}}

    @impl true
    def copy_object(_dest_bucket, _dest_path, _src_bucket, _src_path), do: {:ok, %{}}

    defp test_pid, do: Process.get(:llm_clean_test_pid, self())
  end

  defmodule LLMClientStub do
    def completion(:llm_clean, prompt, chunk, opts) do
      send(test_pid(), {:completion, prompt, chunk, opts})

      case responses()[chunk] do
        nil ->
          {:ok, "cleaned:" <> chunk, %{prompt_tokens: 10, completion_tokens: 20}}

        {:sleep, duration_ms, response} ->
          Process.sleep(duration_ms)
          response

        response ->
          response
      end
    end

    defp test_pid do
      :gallformers
      |> Application.get_env(LLMClean, [])
      |> Keyword.fetch!(:test_pid)
    end

    defp responses do
      :gallformers
      |> Application.get_env(LLMClean, [])
      |> Keyword.get(:responses, %{})
    end
  end

  setup do
    previous_storage_config = Application.get_env(:gallformers, SourceArtifacts)
    previous_llm_clean_config = Application.get_env(:gallformers, LLMClean)

    Process.put(:llm_clean_test_pid, self())
    Application.put_env(:gallformers, SourceArtifacts, backend: StorageBackendStub)
    Application.put_env(:gallformers, LLMClean, llm_client: LLMClientStub, test_pid: self())

    on_exit(fn ->
      Process.delete(:llm_clean_test_pid)
      Process.delete(:llm_clean_text_fixture)

      if previous_storage_config == nil do
        Application.delete_env(:gallformers, SourceArtifacts)
      else
        Application.put_env(:gallformers, SourceArtifacts, previous_storage_config)
      end

      if previous_llm_clean_config == nil do
        Application.delete_env(:gallformers, LLMClean)
      else
        Application.put_env(:gallformers, LLMClean, previous_llm_clean_config)
      end
    end)

    :ok
  end

  test "cleans multiple chunks in order, uploads the artifact, updates the stage, and broadcasts completion" do
    ingestion = source_ingestion_fixture()
    input_path = "source-ingestions/#{ingestion.id}/preprocess/text.txt"
    output_path = "source-ingestions/#{ingestion.id}/llm_clean/text.txt"
    Broadcaster.subscribe(ingestion.id)

    chunk_one = "chunk one " <> String.duplicate("a", 3_500)
    chunk_two = "chunk two " <> String.duplicate("b", 3_500)
    chunk_three = "chunk three " <> String.duplicate("c", 3_500)

    Process.put(:llm_clean_text_fixture, Enum.join([chunk_one, chunk_two, chunk_three], "\n\n"))

    set_llm_responses(%{
      chunk_one => {:ok, "cleaned one", %{prompt_tokens: 1, completion_tokens: 1}},
      chunk_two => {:ok, "cleaned two", %{prompt_tokens: 1, completion_tokens: 1}},
      chunk_three => {:ok, "cleaned three", %{prompt_tokens: 1, completion_tokens: 1}}
    })

    assert {:ok, updated_ingestion} = LLMClean.perform_stage(ingestion)

    assert_received {:get_object, _, ^input_path}
    assert_received {:completion, prompt, ^chunk_one, [max_tokens: 8192]}
    assert_received {:completion, ^prompt, ^chunk_two, [max_tokens: 8192]}
    assert_received {:completion, ^prompt, ^chunk_three, [max_tokens: 8192]}

    assert prompt ==
             File.read!(Path.join([:code.priv_dir(:gallformers), "prompts", "llm_clean.txt"]))

    assert_received {:upload, _, ^output_path, "cleaned one\n\ncleaned two\n\ncleaned three",
                     "text/plain"}

    assert_receive {:stage_complete, :llm_clean}

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)

    assert updated_ingestion.processing_stage == "llm_clean"
    assert reloaded_ingestion.processing_stage == "llm_clean"
    assert reloaded_ingestion.status == "processing"
  end

  test "returns an error without uploading partial output when any chunk fails" do
    ingestion = source_ingestion_fixture()

    chunk_one = "chunk one " <> String.duplicate("a", 3_500)
    chunk_two = "chunk two " <> String.duplicate("b", 3_500)
    chunk_three = "chunk three " <> String.duplicate("c", 3_500)

    Process.put(:llm_clean_text_fixture, Enum.join([chunk_one, chunk_two, chunk_three], "\n\n"))
    set_llm_responses(%{chunk_two => {:error, :rate_limited}})

    assert {:error, :rate_limited} = LLMClean.perform_stage(ingestion)

    refute_received {:upload, _, _, _, _}

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
    assert reloaded_ingestion.processing_stage == "hash_and_dedup"
    assert reloaded_ingestion.status == "processing"
  end

  test "normalizes chunk timeout exits without uploading partial output" do
    ingestion = source_ingestion_fixture()
    chunk = "chunk one " <> String.duplicate("a", 3_500)

    Process.put(:llm_clean_text_fixture, chunk)

    set_llm_config(%{
      task_timeout: 10,
      responses: %{
        chunk => {:sleep, 25, {:ok, "cleaned timeout", %{prompt_tokens: 1, completion_tokens: 1}}}
      }
    })

    assert {:error, :timeout} = LLMClean.perform_stage(ingestion)
    refute_received {:upload, _, _, _, _}

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
    assert reloaded_ingestion.processing_stage == "hash_and_dedup"
    assert reloaded_ingestion.status == "processing"
  end

  defp source_ingestion_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          input_type: "pdf",
          status: "processing",
          processing_stage: "hash_and_dedup"
        },
        attrs
      )

    {:ok, ingestion} = Ingestions.create_source_ingestion(attrs)
    ingestion
  end

  defp set_llm_responses(responses) do
    set_llm_config(%{responses: responses})
  end

  defp set_llm_config(new_values) do
    Application.put_env(
      :gallformers,
      LLMClean,
      Keyword.merge(Application.get_env(:gallformers, LLMClean, []), Map.to_list(new_values))
    )
  end
end
