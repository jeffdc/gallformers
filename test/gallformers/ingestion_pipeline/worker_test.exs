defmodule Gallformers.IngestionPipeline.WorkerTest do
  use Gallformers.DataCase, async: false
  use Oban.Testing, repo: Gallformers.Repo

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.Worker
  alias Gallformers.Ingestions

  defmodule ExtractStageStub do
    @behaviour Gallformers.IngestionPipeline.StageWorker

    @impl true
    def stage_name, do: :extract

    @impl true
    def perform_stage(ingestion) do
      send(test_pid(), {:performed_stage, :extract, ingestion.id, ingestion.processing_stage})
      {:ok, %{ingestion | processing_stage: "extract"}}
    end

    defp test_pid, do: Process.get(:worker_test_pid, self())
  end

  defmodule DuplicateReviewStageStub do
    @behaviour Gallformers.IngestionPipeline.StageWorker

    @impl true
    def stage_name, do: :llm_clean

    @impl true
    def perform_stage(ingestion) do
      send(test_pid(), {:performed_stage, :llm_clean, ingestion.id, ingestion.processing_stage})
      {:ok, %{ingestion | processing_stage: "llm_clean"}}
    end

    defp test_pid, do: Process.get(:worker_test_pid, self())
  end

  defmodule NeedsDuplicateReviewStageStub do
    @behaviour Gallformers.IngestionPipeline.StageWorker

    @impl true
    def stage_name, do: :extract

    @impl true
    def perform_stage(ingestion) do
      {:ok, %{ingestion | status: "needs_duplicate_review", processing_stage: "duplicate_review"}}
    end
  end

  defmodule FailingStageStub do
    @behaviour Gallformers.IngestionPipeline.StageWorker

    @impl true
    def stage_name, do: :extract

    @impl true
    def perform_stage(_ingestion), do: {:error, :extract_failed}
  end

  setup do
    previous_config = Application.get_env(:gallformers, Worker)
    Process.put(:worker_test_pid, self())

    on_exit(fn ->
      Process.delete(:worker_test_pid)

      if previous_config == nil do
        Application.delete_env(:gallformers, Worker)
      else
        Application.put_env(:gallformers, Worker, previous_config)
      end
    end)

    :ok
  end

  describe "enqueue/1" do
    test "inserts an Oban job with the ingestion id" do
      ingestion = source_ingestion_fixture()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, job} = Worker.enqueue(ingestion.id)
        assert job.queue == "extraction"
        assert job.worker == "Gallformers.IngestionPipeline.Worker"
        assert job.args == %{ingestion_id: ingestion.id}

        assert_enqueued(worker: Worker, queue: "extraction", args: %{ingestion_id: ingestion.id})
      end)
    end

    test "deduplicates queued jobs for the same ingestion id" do
      ingestion = source_ingestion_fixture()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, first_job} = Worker.enqueue(ingestion.id)
        assert {:ok, duplicate_job} = Worker.enqueue(ingestion.id)

        assert first_job.args == %{ingestion_id: ingestion.id}
        assert duplicate_job.conflict? == true

        assert length(
                 all_enqueued(
                   worker: Worker,
                   queue: "extraction",
                   args: %{ingestion_id: ingestion.id}
                 )
               ) == 1
      end)
    end
  end

  describe "perform/1" do
    test "dispatches submitted ingestions to the extract stage and re-enqueues itself" do
      ingestion = source_ingestion_fixture()
      ingestion_id = ingestion.id

      put_stage_modules(%{extract: ExtractStageStub})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(Worker, %{ingestion_id: ingestion.id})

        assert_received {:performed_stage, :extract, ^ingestion_id, "submitted"}

        assert_enqueued(worker: Worker, queue: "extraction", args: %{ingestion_id: ingestion.id})
      end)
    end

    test "does not re-enqueue when a stage pauses for duplicate review" do
      ingestion = source_ingestion_fixture()

      put_stage_modules(%{extract: NeedsDuplicateReviewStageStub})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(Worker, %{ingestion_id: ingestion.id})

        refute_enqueued(worker: Worker, queue: "extraction", args: %{ingestion_id: ingestion.id})
      end)
    end

    test "treats duplicate_review as paused when review is still pending" do
      ingestion =
        source_ingestion_fixture(%{
          status: "needs_duplicate_review",
          processing_stage: "duplicate_review"
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(Worker, %{ingestion_id: ingestion.id})

        refute_receive {:performed_stage, _, _, _}
        refute_enqueued(worker: Worker, queue: "extraction", args: %{ingestion_id: ingestion.id})
      end)
    end

    test "resumes duplicate_review through llm_clean once review state returns to processing" do
      ingestion =
        source_ingestion_fixture(%{
          status: "processing",
          processing_stage: "duplicate_review"
        })

      ingestion_id = ingestion.id
      put_stage_modules(%{llm_clean: DuplicateReviewStageStub})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(Worker, %{ingestion_id: ingestion.id})

        assert_received {:performed_stage, :llm_clean, ^ingestion_id, "duplicate_review"}

        assert_enqueued(worker: Worker, queue: "extraction", args: %{ingestion_id: ingestion.id})
      end)
    end

    test "keeps the ingestion resumable on non-final attempts when a stage fails" do
      ingestion = source_ingestion_fixture()

      put_stage_modules(%{extract: FailingStageStub})
      assert :ok = Broadcaster.subscribe(ingestion.id)

      assert {:error, :extract_failed} =
               Worker.perform(worker_job(ingestion.id, attempt: 1, max_attempts: 3))

      reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion.id)

      assert reloaded_ingestion.status == "processing"
      assert reloaded_ingestion.processing_stage == "submitted"
      assert is_nil(reloaded_ingestion.error_stage)
      assert is_nil(reloaded_ingestion.error_message)
      assert is_nil(reloaded_ingestion.failed_at)

      refute_receive {:error, :extract, :extract_failed}
    end

    test "marks the ingestion failed and broadcasts the stage error on the final attempt" do
      ingestion = source_ingestion_fixture()

      put_stage_modules(%{extract: FailingStageStub})
      assert :ok = Broadcaster.subscribe(ingestion.id)

      assert {:error, :extract_failed} =
               Worker.perform(worker_job(ingestion.id, attempt: 3, max_attempts: 3))

      failed_ingestion = Ingestions.get_source_ingestion!(ingestion.id)

      assert failed_ingestion.status == "failed"
      assert failed_ingestion.processing_stage == "failed"
      assert failed_ingestion.error_stage == "extract"
      assert failed_ingestion.error_message == "extract_failed"
      refute is_nil(failed_ingestion.failed_at)

      assert_receive {:error, :extract, :extract_failed}
    end

    test "retries failed ingestions from their stored failed stage" do
      ingestion =
        source_ingestion_fixture(%{
          status: "failed",
          processing_stage: "failed",
          error_stage: "extract",
          error_message: "boom"
        })

      ingestion_id = ingestion.id
      put_stage_modules(%{extract: ExtractStageStub})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(Worker, %{ingestion_id: ingestion.id})

        assert_received {:performed_stage, :extract, ^ingestion_id, "submitted"}

        reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion_id)
        assert reloaded_ingestion.status == "processing"
        assert reloaded_ingestion.processing_stage == "submitted"
        assert is_nil(reloaded_ingestion.error_stage)
        assert is_nil(reloaded_ingestion.error_message)
        assert is_nil(reloaded_ingestion.failed_at)

        assert_enqueued(worker: Worker, queue: "extraction", args: %{ingestion_id: ingestion.id})
      end)
    end

    test "retries llm_clean failures from duplicate_review when duplicate candidates exist" do
      ingestion =
        source_ingestion_fixture(%{
          status: "failed",
          processing_stage: "failed",
          error_stage: "llm_clean",
          error_message: "boom"
        })

      candidate_source = source_ingestion_fixture(%{input_type: "url"})
      {:ok, _candidate} = Ingestions.create_duplicate_candidate(ingestion, candidate_source)

      ingestion_id = ingestion.id
      put_stage_modules(%{llm_clean: DuplicateReviewStageStub})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(Worker, %{ingestion_id: ingestion.id})

        assert_received {:performed_stage, :llm_clean, ^ingestion_id, "duplicate_review"}

        reloaded_ingestion = Ingestions.get_source_ingestion!(ingestion_id)
        assert reloaded_ingestion.status == "processing"
        assert reloaded_ingestion.processing_stage == "duplicate_review"
      end)
    end

    test "no-ops for terminal stages" do
      for {status, attrs} <- [
            {"needs_review", %{processing_stage: "review"}},
            {"complete", %{}}
          ] do
        ingestion =
          source_ingestion_fixture()
          |> transition_to!(status, attrs)

        Oban.Testing.with_testing_mode(:manual, fn ->
          assert :ok = perform_job(Worker, %{ingestion_id: ingestion.id})
          refute_receive {:performed_stage, _, _, _}

          refute_enqueued(
            worker: Worker,
            queue: "extraction",
            args: %{ingestion_id: ingestion.id}
          )
        end)
      end
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

  defp transition_to!(ingestion, status, attrs) do
    {:ok, updated_ingestion} =
      Ingestions.transition_source_ingestion_status(ingestion, status, attrs)

    updated_ingestion
  end

  defp put_stage_modules(stage_modules) do
    put_worker_config(stage_modules: stage_modules)
  end

  defp put_worker_config(overrides) do
    config =
      :gallformers
      |> Application.get_env(Worker, [])
      |> Keyword.merge(overrides)

    Application.put_env(:gallformers, Worker, config)
  end

  defp worker_job(ingestion_id, opts) do
    %Oban.Job{
      args: %{"ingestion_id" => ingestion_id},
      attempt: Keyword.get(opts, :attempt, 1),
      max_attempts: Keyword.get(opts, :max_attempts, 3)
    }
  end
end
