defmodule Gallformers.IngestionPipeline.FullPipelineTest do
  use Gallformers.DataCase, async: false
  use Oban.Testing, repo: Gallformers.Repo

  import Gallformers.IngestionPipelineFixtures

  alias Gallformers.Accounts
  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.DuplicateResolution
  alias Gallformers.IngestionPipeline.FullPipelineTest, as: TestSupport
  alias Gallformers.IngestionPipeline.Stages.{DataExtract, Extract, LLMClean, Metadata}
  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.IngestionPipeline.Worker
  alias Gallformers.IngestionPipeline.Workflow
  alias Gallformers.Ingestions
  alias Gallformers.Repo
  alias Gallformers.Storage.SourceArtifacts

  defmodule StorageBackendStub do
    @behaviour Gallformers.Storage.SourceArtifacts.Backend

    @impl true
    def upload(_bucket, path, content, content_type) do
      update_state(fn state ->
        objects = Map.put(state.objects, path, %{body: content, content_type: content_type})
        {{:ok, %{}}, %{state | objects: objects}}
      end)
    end

    @impl true
    def get_object(_bucket, path) do
      get_state(fn state ->
        case Map.fetch(state.objects, path) do
          {:ok, %{body: body}} -> {:ok, %{body: body}}
          :error -> {:error, :not_found}
        end
      end)
    end

    @impl true
    def list_objects(_bucket, prefix, _continuation_token) do
      get_state(fn state ->
        keys =
          state.objects
          |> Map.keys()
          |> Enum.filter(&String.starts_with?(&1, prefix))
          |> Enum.sort()

        {:ok, %{keys: keys, next_continuation_token: nil}}
      end)
    end

    @impl true
    def delete_objects(_bucket, keys) do
      update_state(fn state ->
        objects = Map.drop(state.objects, keys)
        {{:ok, %{}}, %{state | objects: objects}}
      end)
    end

    @impl true
    def copy_object(_dest_bucket, dest_path, _src_bucket, src_path) do
      update_state(fn state ->
        case Map.fetch(state.objects, src_path) do
          {:ok, object} ->
            objects = Map.put(state.objects, dest_path, object)
            {{:ok, %{}}, %{state | objects: objects}}

          :error ->
            {{:error, :not_found}, state}
        end
      end)
    end

    defp get_state(fun) do
      Agent.get(state_pid(), fun)
    end

    defp update_state(fun) do
      Agent.get_and_update(state_pid(), fun)
    end

    defp state_pid do
      TestSupport.config(:state_pid)
    end
  end

  defmodule ExtractorStub do
    def extract_text(file_path, _opts) do
      pdf_body = File.read!(file_path)

      TestSupport.agent_get(fn state ->
        Map.fetch!(state.python_results, pdf_body)
      end)
    end
  end

  defmodule LLMClientStub do
    def completion(stage, _prompt, text, _opts) do
      TestSupport.agent_get_and_update(&pop_response(&1, {stage, text}))
    end

    defp pop_response(state, key) do
      configured = Map.fetch!(state.llm_responses, key)

      case configured do
        [response | rest] ->
          next_responses =
            if rest == [] do
              Map.delete(state.llm_responses, key)
            else
              Map.put(state.llm_responses, key, rest)
            end

          {response, %{state | llm_responses: next_responses}}

        response ->
          {response, state}
      end
    end
  end

  setup do
    previous_storage_config = Application.get_env(:gallformers, SourceArtifacts)
    previous_extract_config = Application.get_env(:gallformers, Extract)
    previous_llm_clean_config = Application.get_env(:gallformers, LLMClean)
    previous_metadata_config = Application.get_env(:gallformers, Metadata)
    previous_data_extract_config = Application.get_env(:gallformers, DataExtract)
    previous_test_config = Application.get_env(:gallformers, __MODULE__)

    {:ok, state_pid} =
      Agent.start_link(fn ->
        %{
          objects: %{},
          python_results: %{},
          llm_responses: %{}
        }
      end)

    Application.put_env(:gallformers, __MODULE__, state_pid: state_pid)
    Application.put_env(:gallformers, SourceArtifacts, backend: StorageBackendStub)
    Application.put_env(:gallformers, Extract, extractor: ExtractorStub)
    Application.put_env(:gallformers, LLMClean, llm_client: LLMClientStub)
    Application.put_env(:gallformers, Metadata, llm_client: LLMClientStub)
    Application.put_env(:gallformers, DataExtract, llm_client: LLMClientStub)

    on_exit(fn ->
      if Process.alive?(state_pid) do
        Agent.stop(state_pid)
      end

      restore_env(SourceArtifacts, previous_storage_config)
      restore_env(Extract, previous_extract_config)
      restore_env(LLMClean, previous_llm_clean_config)
      restore_env(Metadata, previous_metadata_config)
      restore_env(DataExtract, previous_data_extract_config)
      restore_env(__MODULE__, previous_test_config)
    end)

    :ok
  end

  test "normal path reaches review-ready with the expected checkpoints, artifacts, and broadcasts" do
    ingestion = source_ingestion_fixture()
    ingestion_id = ingestion.id
    assert :ok = Broadcaster.subscribe(ingestion_id)

    extracted_text =
      """
      A biological and systematic study of Philippine galls

      Smith, J.A.

      Published 1919.

      DOI 10.1234/Normal.

      Rounded woody gall on oak twigs.
      """

    preprocessed_text = String.trim(extracted_text)
    cleaned_text = "# Cleaned gall paper\n\nRounded woody gall on oak twigs."

    metadata_json =
      Jason.encode!(%{
        title: "A biological and systematic study of Philippine galls",
        authors: ["Smith, J.A."],
        year: 1919,
        doi: "10.1234/normal"
      })

    records_json = Jason.encode!([valid_record("Andricus normalis", "Quercus alba", 0.91)])

    seed_pipeline_input(ingestion, "pdf:normal", extracted_text)

    configure_llm_responses(%{
      {:llm_clean, preprocessed_text} => {:ok, cleaned_text, usage()},
      {:metadata, cleaned_text} => {:ok, metadata_json, usage()},
      {:data_extract, cleaned_text} => {:ok, records_json, usage()}
    })

    states =
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = Worker.enqueue(ingestion_id)
        drain_worker_jobs(ingestion_id)
      end)

    assert states == [
             {"processing", "extract"},
             {"processing", "preprocess"},
             {"processing", "hash_and_dedup"},
             {"processing", "llm_clean"},
             {"processing", "metadata"},
             {"processing", "data_extract"},
             {"processing", "assemble"},
             {"needs_review", "review"}
           ]

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion_id)
    assert Workflow.state(reloaded_ingestion) == {"needs_review", "review"}

    assert Enum.map(Ingestions.list_source_ingestion_species(ingestion_id), fn species_entry ->
             {species_entry.position, species_entry.extracted_name, species_entry.status}
           end) == [{0, "Andricus normalis", "pending"}]

    assert_artifact_keys_include(ingestion_id, [
      "source-ingestions/#{ingestion_id}/extract/text.txt",
      "source-ingestions/#{ingestion_id}/preprocess/text.txt",
      "source-ingestions/#{ingestion_id}/llm_clean/text.txt",
      "source-ingestions/#{ingestion_id}/metadata/output.json",
      "source-ingestions/#{ingestion_id}/data_extract/output.json",
      "source-ingestions/#{ingestion_id}/assemble/output.md"
    ])

    assert_receive {:stage_complete, :hash_and_dedup}
    assert_receive {:stage_complete, :llm_clean}
    assert_receive {:stage_complete, :metadata}
    assert_receive {:stage_complete, :data_extract}
    assert_receive {:stage_complete, :assemble}
    assert_receive {:review_ready, ^ingestion_id}
  end

  test "exact hash duplicate path auto-confirms and skips LLM stages" do
    extracted_text =
      """
      Hash duplicate study

      Smith, J.A.

      Rounded woody gall on oak twigs.
      """

    preprocessed_text = String.trim(extracted_text)
    preprocessed_hash = compute_sha256(preprocessed_text)

    canonical =
      source_ingestion_fixture(%{
        input_type: "pdf",
        preprocessed_text_sha256: preprocessed_hash
      })

    ingestion = source_ingestion_fixture()
    ingestion_id = ingestion.id
    assert :ok = Broadcaster.subscribe(ingestion_id)

    seed_pipeline_input(ingestion, "pdf:hash-duplicate", extracted_text)

    states =
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = Worker.enqueue(ingestion_id)
        drain_worker_jobs(ingestion_id)
      end)

    assert states == [
             {"processing", "extract"},
             {"processing", "preprocess"},
             {"duplicate_confirmed", "duplicate_review"}
           ]

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion_id)
    assert Workflow.state(reloaded_ingestion) == {"duplicate_confirmed", "duplicate_review"}
    assert reloaded_ingestion.duplicate_of_source_ingestion_id == canonical.id

    [candidate] = Ingestions.list_duplicate_candidates(ingestion)
    assert candidate.status == "auto_confirmed"

    artifact_keys = artifact_keys_for(ingestion_id)
    assert "source-ingestions/#{ingestion_id}/llm_clean/text.txt" not in artifact_keys
    assert "source-ingestions/#{ingestion_id}/metadata/output.json" not in artifact_keys
    assert "source-ingestions/#{ingestion_id}/data_extract/output.json" not in artifact_keys
    assert "source-ingestions/#{ingestion_id}/assemble/output.md" not in artifact_keys

    assert_receive {:stage_complete, :hash_and_dedup}
    assert_receive {:review_ready, ^ingestion_id}
  end

  test "exact DOI duplicate path auto-confirms and skips LLM stages" do
    canonical =
      source_ingestion_fixture(%{
        input_type: "pdf",
        normalized_doi: "10.1234/doi-duplicate"
      })

    ingestion = source_ingestion_fixture()
    ingestion_id = ingestion.id
    assert :ok = Broadcaster.subscribe(ingestion_id)

    extracted_text =
      """
      DOI duplicate study

      Smith, J.A.

      Published 1919.

      DOI 10.1234/doi-duplicate.

      Rounded woody gall on oak twigs.
      """

    seed_pipeline_input(ingestion, "pdf:doi-duplicate", extracted_text)

    states =
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = Worker.enqueue(ingestion_id)
        drain_worker_jobs(ingestion_id)
      end)

    assert states == [
             {"processing", "extract"},
             {"processing", "preprocess"},
             {"duplicate_confirmed", "duplicate_review"}
           ]

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion_id)
    assert Workflow.state(reloaded_ingestion) == {"duplicate_confirmed", "duplicate_review"}
    assert reloaded_ingestion.duplicate_of_source_ingestion_id == canonical.id

    assert_receive {:stage_complete, :hash_and_dedup}
    assert_receive {:review_ready, ^ingestion_id}
  end

  test "probable duplicate path pauses for review and confirm_duplicate ends at duplicate_confirmed" do
    reviewer = user_fixture()

    canonical =
      source_ingestion_fixture(%{
        title_fingerprint: "probable_duplicate_study",
        author_fingerprint: "smith",
        publication_year: 1919
      })

    ingestion = source_ingestion_fixture()
    ingestion_id = ingestion.id
    assert :ok = Broadcaster.subscribe(ingestion_id)

    extracted_text =
      """
      Probable duplicate study

      Smith, J.A.

      Published 1919.

      Rounded woody gall on oak twigs.
      """

    seed_pipeline_input(ingestion, "pdf:probable-confirm", extracted_text)

    states =
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = Worker.enqueue(ingestion_id)
        drain_worker_jobs(ingestion_id)
      end)

    assert states == [
             {"processing", "extract"},
             {"processing", "preprocess"},
             {"needs_duplicate_review", "duplicate_review"}
           ]

    [candidate] = Ingestions.list_duplicate_candidates(ingestion)
    assert candidate.status == "pending"
    assert candidate.candidate_source_ingestion_id == canonical.id

    assert_receive {:needs_duplicate_review, [broadcast_candidate]}
    assert broadcast_candidate.id == candidate.id

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, confirmed_ingestion} =
               DuplicateResolution.confirm_duplicate(candidate.id, reviewer.id)

      assert Workflow.state(confirmed_ingestion) == {"duplicate_confirmed", "duplicate_review"}

      assert drain_worker_jobs(ingestion_id) == [{"duplicate_confirmed", "duplicate_review"}]
    end)

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion_id)
    assert Workflow.state(reloaded_ingestion) == {"duplicate_confirmed", "duplicate_review"}
    assert reloaded_ingestion.duplicate_of_source_ingestion_id == canonical.id
  end

  test "duplicate rejection resumes through the centralized workflow and reaches review-ready" do
    reviewer = user_fixture()
    ingestion = source_ingestion_fixture()
    ingestion_id = ingestion.id
    assert :ok = Broadcaster.subscribe(ingestion_id)

    canonical =
      source_ingestion_fixture(%{
        title_fingerprint: "probable_duplicate_reject",
        author_fingerprint: "smith",
        publication_year: 1919
      })

    extracted_text =
      """
      Probable duplicate reject

      Smith, J.A.

      Published 1919.

      Rounded woody gall on oak twigs.
      """

    preprocessed_text = String.trim(extracted_text)
    cleaned_text = "# Resume after duplicate review\n\nRounded woody gall on oak twigs."

    metadata_json =
      Jason.encode!(%{
        title: "Probable duplicate reject",
        authors: ["Smith, J.A."],
        year: 1919,
        doi: nil
      })

    records_json = Jason.encode!([valid_record("Andricus rejectus", "Quercus alba", 0.87)])

    seed_pipeline_input(ingestion, "pdf:probable-reject", extracted_text)

    configure_llm_responses(%{
      {:llm_clean, preprocessed_text} => {:ok, cleaned_text, usage()},
      {:metadata, cleaned_text} => {:ok, metadata_json, usage()},
      {:data_extract, cleaned_text} => {:ok, records_json, usage()}
    })

    pause_states =
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = Worker.enqueue(ingestion_id)
        drain_worker_jobs(ingestion_id)
      end)

    assert pause_states == [
             {"processing", "extract"},
             {"processing", "preprocess"},
             {"needs_duplicate_review", "duplicate_review"}
           ]

    [candidate] = Ingestions.list_duplicate_candidates(ingestion)
    assert candidate.candidate_source_ingestion_id == canonical.id
    assert_receive {:needs_duplicate_review, [_candidate]}

    resumed_states =
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, resumed_ingestion} =
                 DuplicateResolution.reject_duplicate(candidate.id, reviewer.id)

        assert Workflow.state(resumed_ingestion) == {"processing", "duplicate_review"}
        drain_worker_jobs(ingestion_id)
      end)

    assert resumed_states == [
             {"processing", "llm_clean"},
             {"processing", "metadata"},
             {"processing", "data_extract"},
             {"processing", "assemble"},
             {"needs_review", "review"}
           ]

    reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion_id)
    assert Workflow.state(reloaded_ingestion) == {"needs_review", "review"}

    [rejected_candidate] = Ingestions.list_duplicate_candidates(ingestion)
    assert rejected_candidate.status == "rejected"

    assert_artifact_keys_include(ingestion_id, [
      "source-ingestions/#{ingestion_id}/llm_clean/text.txt",
      "source-ingestions/#{ingestion_id}/metadata/output.json",
      "source-ingestions/#{ingestion_id}/data_extract/output.json",
      "source-ingestions/#{ingestion_id}/assemble/output.md"
    ])

    assert_receive {:stage_complete, :llm_clean}
    assert_receive {:stage_complete, :metadata}
    assert_receive {:stage_complete, :data_extract}
    assert_receive {:stage_complete, :assemble}
    assert_receive {:review_ready, ^ingestion_id}
  end

  test "llm_clean only marks the ingestion failed after the final Oban attempt" do
    ingestion = source_ingestion_fixture()
    ingestion_id = ingestion.id
    assert :ok = Broadcaster.subscribe(ingestion_id)

    extracted_text =
      """
      LLM error path study

      Smith, J.A.

      Published 1919.

      Rounded woody gall on oak twigs.
      """

    preprocessed_text = String.trim(extracted_text)

    seed_pipeline_input(ingestion, "pdf:llm-error", extracted_text)

    configure_llm_responses(%{
      {:llm_clean, preprocessed_text} => {:error, :server_error, 500}
    })

    states_before_failure =
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = Worker.enqueue(ingestion_id)
        drain_worker_jobs_until(ingestion_id, {"processing", "hash_and_dedup"})
      end)

    assert states_before_failure == [
             {"processing", "extract"},
             {"processing", "preprocess"},
             {"processing", "hash_and_dedup"}
           ]

    clear_worker_jobs(ingestion_id)

    assert {:error, {:server_error, 500}} =
             Worker.perform(worker_job(ingestion_id, attempt: 1, max_attempts: 3))

    reloaded_after_first_attempt = Ingestions.get_source_ingestion!(ingestion_id)
    assert Workflow.state(reloaded_after_first_attempt) == {"processing", "hash_and_dedup"}
    assert is_nil(reloaded_after_first_attempt.error_stage)
    assert is_nil(reloaded_after_first_attempt.error_message)
    assert is_nil(reloaded_after_first_attempt.failed_at)
    refute_receive {:error, :llm_clean, {:server_error, 500}}

    assert {:error, {:server_error, 500}} =
             Worker.perform(worker_job(ingestion_id, attempt: 2, max_attempts: 3))

    reloaded_after_second_attempt = Ingestions.get_source_ingestion!(ingestion_id)
    assert Workflow.state(reloaded_after_second_attempt) == {"processing", "hash_and_dedup"}
    refute_receive {:error, :llm_clean, {:server_error, 500}}

    assert {:error, {:server_error, 500}} =
             Worker.perform(worker_job(ingestion_id, attempt: 3, max_attempts: 3))

    failed_ingestion = Ingestions.get_source_ingestion!(ingestion_id)
    assert Workflow.state(failed_ingestion) == {"failed", "failed"}
    assert failed_ingestion.error_stage == "llm_clean"
    assert failed_ingestion.error_message == "{:server_error, 500}"
    refute is_nil(failed_ingestion.failed_at)

    assert_receive {:error, :llm_clean, {:server_error, 500}}
  end

  def config(key) do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.fetch!(key)
  end

  def agent_get(fun) do
    Agent.get(config(:state_pid), fun)
  end

  def agent_get_and_update(fun) do
    Agent.get_and_update(config(:state_pid), fun)
  end

  defp restore_env(module, nil), do: Application.delete_env(:gallformers, module)
  defp restore_env(module, value), do: Application.put_env(:gallformers, module, value)

  defp seed_pipeline_input(ingestion, pdf_body, extracted_text) do
    agent_get_and_update(fn state ->
      objects =
        Map.put(
          state.objects,
          Storage.artifact_path(ingestion.id, :input, "source.pdf"),
          %{body: pdf_body, content_type: "application/pdf"}
        )

      python_results =
        Map.put(state.python_results, pdf_body, {:ok, %{text: extracted_text, page_count: 1}})

      {:ok, %{state | objects: objects, python_results: python_results}}
    end)
  end

  defp configure_llm_responses(responses) do
    agent_get_and_update(fn state ->
      {:ok, %{state | llm_responses: Map.merge(state.llm_responses, Map.new(responses))}}
    end)
  end

  defp artifact_keys_for(ingestion_id) do
    agent_get(fn state ->
      state.objects
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "source-ingestions/#{ingestion_id}/"))
      |> Enum.sort()
    end)
  end

  defp assert_artifact_keys_include(ingestion_id, expected_keys) do
    artifact_keys = artifact_keys_for(ingestion_id)

    assert Enum.all?(expected_keys, &(&1 in artifact_keys)) == true
  end

  defp drain_worker_jobs(ingestion_id) do
    do_drain_worker_jobs(ingestion_id, nil, [])
  end

  defp drain_worker_jobs_until(ingestion_id, target_state) do
    do_drain_worker_jobs(ingestion_id, target_state, [])
  end

  defp do_drain_worker_jobs(ingestion_id, target_state, acc) do
    case pop_next_worker_job(ingestion_id) do
      nil ->
        acc |> Enum.reverse() |> collapse_duplicate_states()

      job ->
        assert :ok = Worker.perform(job)
        state = ingestion_id |> Ingestions.get_source_ingestion!() |> Workflow.state()

        if target_state == state do
          [state | acc] |> Enum.reverse() |> collapse_duplicate_states()
        else
          do_drain_worker_jobs(ingestion_id, target_state, [state | acc])
        end
    end
  end

  defp pop_next_worker_job(ingestion_id) do
    all_enqueued(worker: Worker, args: %{ingestion_id: ingestion_id})
    |> Enum.sort_by(& &1.id)
    |> List.first()
    |> case do
      nil ->
        nil

      job ->
        Repo.delete!(job)
        job
    end
  end

  defp clear_worker_jobs(ingestion_id) do
    all_enqueued(worker: Worker, args: %{ingestion_id: ingestion_id})
    |> Enum.each(&Repo.delete!/1)
  end

  defp collapse_duplicate_states(states) do
    Enum.reduce(states, [], fn state, acc ->
      case acc do
        [^state | _rest] -> acc
        _ -> [state | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp worker_job(ingestion_id, opts) do
    %Oban.Job{
      args: %{"ingestion_id" => ingestion_id},
      attempt: Keyword.get(opts, :attempt, 1),
      max_attempts: Keyword.get(opts, :max_attempts, 3)
    }
  end

  defp usage do
    %{prompt_tokens: 1, completion_tokens: 1}
  end

  defp compute_sha256(text) do
    :sha256
    |> :crypto.hash(text)
    |> Base.encode16(case: :lower)
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

  defp user_fixture do
    {:ok, user} =
      Accounts.create_user(%{
        auth0_id: "auth0|full-pipeline-#{System.unique_integer([:positive])}",
        display_name: "Full Pipeline Reviewer"
      })

    user
  end
end
