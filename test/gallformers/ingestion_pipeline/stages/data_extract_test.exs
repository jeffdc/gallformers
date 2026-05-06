defmodule Gallformers.IngestionPipeline.Stages.DataExtractTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.Stages.DataExtract
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
      {:ok, %{body: Process.get(:data_extract_text_fixture)}}
    end

    @impl true
    def list_objects(_bucket, _prefix, _continuation_token),
      do: {:ok, %{keys: [], next_continuation_token: nil}}

    @impl true
    def delete_objects(_bucket, _keys), do: {:ok, %{}}

    @impl true
    def copy_object(_dest_bucket, _dest_path, _src_bucket, _src_path), do: {:ok, %{}}

    defp test_pid, do: Process.get(:data_extract_test_pid, self())
  end

  defmodule LLMClientStub do
    def completion(:data_extract, prompt, chunk, opts) do
      send(test_pid(), {:completion, prompt, chunk, opts})
      response_for(chunk)
    end

    defp response_for(chunk) do
      responses = responses()
      configured = Map.fetch!(responses, chunk)

      case configured do
        {:sleep, duration_ms, response} ->
          Process.sleep(duration_ms)
          response

        response when is_tuple(response) ->
          response

        response_list when is_list(response_list) ->
          attempt = Process.get({:data_extract_attempt, chunk}, 0)
          Process.put({:data_extract_attempt, chunk}, attempt + 1)
          Enum.at(response_list, attempt, List.last(response_list))
      end
    end

    defp test_pid do
      :gallformers
      |> Application.get_env(DataExtract, [])
      |> Keyword.fetch!(:test_pid)
    end

    defp responses do
      :gallformers
      |> Application.get_env(DataExtract, [])
      |> Keyword.fetch!(:responses)
    end
  end

  defmodule SchemaStub do
    def prompt_text do
      send(test_pid(), :prompt_text)
      "SCHEMA TEXT"
    end

    def validate(records) do
      send(test_pid(), {:validate, records})

      case validate_response() do
        nil -> {:ok, records}
        response -> response
      end
    end

    defp validate_response do
      :gallformers
      |> Application.get_env(DataExtract, [])
      |> Keyword.get(:validate_response)
    end

    defp test_pid do
      :gallformers
      |> Application.get_env(DataExtract, [])
      |> Keyword.fetch!(:test_pid)
    end
  end

  setup do
    previous_storage_config = Application.get_env(:gallformers, SourceArtifacts)
    previous_data_extract_config = Application.get_env(:gallformers, DataExtract)

    Process.put(:data_extract_test_pid, self())
    Application.put_env(:gallformers, SourceArtifacts, backend: StorageBackendStub)

    Application.put_env(
      :gallformers,
      DataExtract,
      llm_client: LLMClientStub,
      schema_module: SchemaStub,
      test_pid: self()
    )

    on_exit(fn ->
      Process.delete(:data_extract_test_pid)
      Process.delete(:data_extract_text_fixture)

      if previous_storage_config == nil do
        Application.delete_env(:gallformers, SourceArtifacts)
      else
        Application.put_env(:gallformers, SourceArtifacts, previous_storage_config)
      end

      if previous_data_extract_config == nil do
        Application.delete_env(:gallformers, DataExtract)
      else
        Application.put_env(:gallformers, DataExtract, previous_data_extract_config)
      end
    end)

    :ok
  end

  test "injects schema into the prompt, validates merged records, uploads output, and updates the stage" do
    ingestion = source_ingestion_fixture()
    input_path = "source-ingestions/#{ingestion.id}/llm_clean/text.txt"
    output_path = "source-ingestions/#{ingestion.id}/data_extract/output.json"
    Broadcaster.subscribe(ingestion.id)

    chunk_one = "chunk one " <> String.duplicate("a", 1_800)
    chunk_two = "chunk two " <> String.duplicate("b", 1_800)
    chunk_three = "chunk three " <> String.duplicate("c", 1_800)

    record_one = valid_record("Gall One", "Host One", 0.8)
    record_two = valid_record("Gall Two", "Host Two", 0.81)
    record_three = valid_record("Gall Three", "Host Three", 0.82)

    Process.put(
      :data_extract_text_fixture,
      Enum.join([chunk_one, chunk_two, chunk_three], "\n\n")
    )

    set_data_extract_config(%{
      responses: %{
        chunk_one =>
          {:ok, Jason.encode!([record_one]), %{prompt_tokens: 1, completion_tokens: 1}},
        chunk_two =>
          {:ok, "```json\n#{Jason.encode!([record_two])}\n```",
           %{prompt_tokens: 1, completion_tokens: 1}},
        chunk_three =>
          {:ok, "Here is the JSON array:\n#{Jason.encode!([record_three])}",
           %{prompt_tokens: 1, completion_tokens: 1}}
      }
    })

    assert {:ok, updated_ingestion} = DataExtract.perform_stage(ingestion)

    assert_received {:get_object, _, ^input_path}
    assert_received :prompt_text
    assert_received {:completion, prompt, ^chunk_one, [max_tokens: 8192, merge_prompt: true]}
    assert_received {:completion, ^prompt, ^chunk_two, [max_tokens: 8192, merge_prompt: true]}
    assert_received {:completion, ^prompt, ^chunk_three, [max_tokens: 8192, merge_prompt: true]}
    assert String.contains?(prompt, "SCHEMA TEXT") == true
    assert String.contains?(prompt, "{{SCHEMA}}") == false

    expected_records = [record_one, record_two, record_three]
    assert_received {:validate, ^expected_records}

    assert_received {:upload, _, ^output_path, json_content, "application/json"}
    assert Jason.decode!(json_content) == expected_records
    assert_receive {:stage_complete, :data_extract}

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
    assert updated_ingestion.processing_stage == "data_extract"
    assert reloaded_ingestion.processing_stage == "data_extract"
    assert reloaded_ingestion.status == "processing"
  end

  test "returns schema validation errors without uploading partial output" do
    ingestion = source_ingestion_fixture()
    chunk = "chunk one " <> String.duplicate("a", 3_500)
    record = valid_record("Gall One", "Host One", 0.8)

    Process.put(:data_extract_text_fixture, chunk)

    set_data_extract_config(%{
      responses: %{
        chunk => {:ok, Jason.encode!([record]), %{prompt_tokens: 1, completion_tokens: 1}}
      },
      validate_response:
        {:error, :invalid_contract,
         ["Record 0: traits.shape.suggested contains invalid value \"bad\""]}
    })

    assert {:error, :invalid_contract,
            ["Record 0: traits.shape.suggested contains invalid value \"bad\""]} =
             DataExtract.perform_stage(ingestion)

    assert_received {:validate, [^record]}
    refute_received {:upload, _, _, _, _}

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
    assert reloaded_ingestion.processing_stage == "metadata"
    assert reloaded_ingestion.status == "processing"
  end

  test "retries malformed chunk JSON before succeeding" do
    ingestion = source_ingestion_fixture()
    chunk = "chunk one " <> String.duplicate("a", 3_500)
    record = valid_record("Gall Retry", "Host Retry", 0.83)

    Process.put(:data_extract_text_fixture, chunk)

    set_data_extract_config(%{
      responses: %{
        chunk => [
          {:ok, "not json", %{prompt_tokens: 1, completion_tokens: 1}},
          {:ok, Jason.encode!([record]), %{prompt_tokens: 1, completion_tokens: 1}}
        ]
      }
    })

    assert {:ok, _updated_ingestion} = DataExtract.perform_stage(ingestion)

    assert_received {:completion, _prompt, ^chunk, [max_tokens: 8192, merge_prompt: true]}
    assert_received {:completion, _prompt, ^chunk, [max_tokens: 8192, merge_prompt: true]}
    assert_received {:validate, [^record]}
  end

  test "skips retry when response hits max_tokens (truncated JSON)" do
    ingestion = source_ingestion_fixture()
    chunk = "chunk one " <> String.duplicate("a", 3_500)

    Process.put(:data_extract_text_fixture, chunk)

    set_data_extract_config(%{
      responses: %{
        chunk => {:ok, "[{\"incomplete\": true", %{prompt_tokens: 100, completion_tokens: 8192}}
      }
    })

    assert {:error, :json_truncated} = DataExtract.perform_stage(ingestion)

    assert_received {:completion, _prompt, ^chunk, _opts}
    refute_received {:completion, _, ^chunk, _}
    refute_received {:upload, _, _, _, _}
  end

  test "splits chunk and retries when output is truncated and chunk has paragraph boundaries" do
    ingestion = source_ingestion_fixture()
    Broadcaster.subscribe(ingestion.id)

    para_one = "paragraph one " <> String.duplicate("x", 1_400)
    para_two = "paragraph two " <> String.duplicate("y", 1_400)
    full_chunk = para_one <> "\n\n" <> para_two

    record_one = valid_record("Gall Split A", "Host Split A", 0.9)
    record_two = valid_record("Gall Split B", "Host Split B", 0.91)

    Process.put(:data_extract_text_fixture, full_chunk)

    set_data_extract_config(%{
      responses: %{
        full_chunk =>
          {:ok, "[{\"incomplete\": true", %{prompt_tokens: 100, completion_tokens: 8192}},
        para_one =>
          {:ok, Jason.encode!([record_one]), %{prompt_tokens: 1, completion_tokens: 100}},
        para_two =>
          {:ok, Jason.encode!([record_two]), %{prompt_tokens: 1, completion_tokens: 100}}
      }
    })

    assert {:ok, _updated_ingestion} = DataExtract.perform_stage(ingestion)

    assert_received {:completion, _prompt, ^full_chunk, _opts}
    assert_received {:completion, _prompt, ^para_one, _opts}
    assert_received {:completion, _prompt, ^para_two, _opts}

    expected_records = [record_one, record_two]
    assert_received {:validate, ^expected_records}
    assert_received {:upload, _, _, json_content, "application/json"}
    assert Jason.decode!(json_content) == expected_records
  end

  test "surfaces llm client errors without uploading partial output" do
    ingestion = source_ingestion_fixture()
    chunk = "chunk one " <> String.duplicate("a", 3_500)

    Process.put(:data_extract_text_fixture, chunk)

    set_data_extract_config(%{
      responses: %{
        chunk => {:error, :transport_error, :econnrefused}
      }
    })

    assert {:error, {:transport_error, :econnrefused}} = DataExtract.perform_stage(ingestion)

    refute_received {:upload, _, _, _, _}

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
    assert reloaded_ingestion.processing_stage == "metadata"
    assert reloaded_ingestion.status == "processing"
  end

  test "normalizes chunk timeout exits without uploading partial output" do
    ingestion = source_ingestion_fixture()
    chunk = "chunk one " <> String.duplicate("a", 3_500)

    Process.put(:data_extract_text_fixture, chunk)

    set_data_extract_config(%{
      task_timeout: 10,
      responses: %{
        chunk =>
          {:sleep, 25,
           {:ok, Jason.encode!([valid_record("Gall Timeout", "Host Timeout", 0.8)]),
            %{
              prompt_tokens: 1,
              completion_tokens: 1
            }}}
      }
    })

    assert {:error, :timeout} = DataExtract.perform_stage(ingestion)
    refute_received {:upload, _, _, _, _}

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)
    assert reloaded_ingestion.processing_stage == "metadata"
    assert reloaded_ingestion.status == "processing"
  end

  defp source_ingestion_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          input_type: "pdf",
          status: "processing",
          processing_stage: "metadata"
        },
        attrs
      )

    {:ok, ingestion} = Ingestions.create_source_ingestion(attrs)
    ingestion
  end

  defp set_data_extract_config(new_values) do
    Application.put_env(
      :gallformers,
      DataExtract,
      Keyword.merge(Application.get_env(:gallformers, DataExtract, []), Map.to_list(new_values))
    )
  end

  defp valid_record(gall_name, host_name, confidence) do
    %{
      "gall_species" => %{
        "name" => gall_name,
        "authority" => nil,
        "family" => "Cynipidae",
        "order" => "Hymenoptera"
      },
      "host_species" => %{
        "name" => host_name,
        "authority" => nil,
        "family" => "Fagaceae"
      },
      "traits" => %{},
      "description" => "Gall description",
      "location" => nil,
      "confidence" => confidence
    }
  end
end
