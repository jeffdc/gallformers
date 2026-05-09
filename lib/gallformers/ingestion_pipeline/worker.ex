defmodule Gallformers.IngestionPipeline.Worker do
  @moduledoc """
  Oban orchestrator for the source ingestion pipeline.
  """

  require Logger

  use Boundary,
    deps: [
      Gallformers.Ingestions,
      Gallformers.IngestionPipeline.Broadcaster,
      Gallformers.IngestionPipeline.Workflow
    ],
    exports: :all

  use Oban.Worker,
    queue: :extraction,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:ingestion_id],
      states: [:available, :scheduled, :retryable]
    ]

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.Workflow
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion

  @type stage_result :: {:ok, SourceIngestion.t()} | {:error, term()}

  @doc """
  Enqueues the orchestrator for an ingestion.
  """
  @spec enqueue(integer()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(ingestion_id) when is_integer(ingestion_id) do
    %{ingestion_id: ingestion_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ingestion_id" => ingestion_id}} = job) do
    ingestion_id
    |> ingestions_module().get_source_ingestion!()
    |> resume_failed_ingestion()
    |> dispatch_stage(job)
  end

  defp resume_failed_ingestion(%SourceIngestion{status: "failed"} = ingestion) do
    case ingestions_module().retry_failed_source_ingestion(ingestion) do
      {:ok, resumed_ingestion} -> resumed_ingestion
      {:error, changeset} -> raise_retry_reset_error(ingestion, changeset)
    end
  end

  defp resume_failed_ingestion(%SourceIngestion{} = ingestion), do: ingestion

  defp dispatch_stage(%SourceIngestion{} = ingestion, %Oban.Job{} = job) do
    case Workflow.next_stage(ingestion) do
      :paused ->
        :ok

      :terminal ->
        :ok

      {:run, stage} ->
        run_stage(stage_module(stage), ingestion, job)

      {:error, :invalid_state} ->
        {:error, :invalid_state}
    end
  end

  defp run_stage(module, %SourceIngestion{} = ingestion, %Oban.Job{} = job) do
    case module.perform_stage(ingestion) do
      {:ok, %SourceIngestion{status: "needs_duplicate_review"}} ->
        :ok

      {:ok, %SourceIngestion{id: ingestion_id}} ->
        case enqueue(ingestion_id) do
          {:ok, %Oban.Job{conflict?: true} = job} ->
            Logger.warning(
              "Worker.enqueue conflict — next stage NOT scheduled. ingestion=#{ingestion_id} stage_module=#{inspect(module)} existing_job_id=#{job.id} state=#{job.state}"
            )

            :ok

          {:ok, %Oban.Job{} = job} ->
            Logger.debug(
              "Worker.enqueue ingestion=#{ingestion_id} stage_module=#{inspect(module)} job_id=#{job.id} state=#{job.state}"
            )

            :ok

          {:error, changeset} ->
            {:error, changeset}
        end

      {:error, :invalid_contract, messages} ->
        handle_stage_error(ingestion, module, {:invalid_contract, messages}, job)

      {:error, reason} ->
        handle_stage_error(ingestion, module, reason, job)
    end
  end

  defp handle_stage_error(%SourceIngestion{} = ingestion, module, reason, %Oban.Job{} = job) do
    stage = module.stage_name()

    if final_attempt?(job) do
      Logger.error(
        "Source ingestion stage failed permanently",
        ingestion_id: ingestion.id,
        stage: stage,
        attempt: job.attempt,
        max_attempts: job.max_attempts,
        reason: inspect(reason)
      )

      case ingestions_module().transition_source_ingestion_workflow(
             ingestion,
             {:stage_failed, stage, reason}
           ) do
        {:ok, _failed_ingestion} ->
          Broadcaster.broadcast_error(ingestion.id, stage, reason)
          {:error, reason}

        {:error, :invalid_transition} ->
          Logger.error(
            "Source ingestion failure transition was invalid",
            ingestion_id: ingestion.id,
            stage: stage,
            attempt: job.attempt,
            max_attempts: job.max_attempts,
            reason: inspect(reason)
          )

          {:error, :invalid_transition}

        {:error, :invalid_state} ->
          Logger.error(
            "Source ingestion failure transition saw invalid state",
            ingestion_id: ingestion.id,
            stage: stage,
            attempt: job.attempt,
            max_attempts: job.max_attempts,
            reason: inspect(reason)
          )

          {:error, :invalid_state}

        {:error, changeset} ->
          Logger.error(
            "Source ingestion failure transition changeset error",
            ingestion_id: ingestion.id,
            stage: stage,
            attempt: job.attempt,
            max_attempts: job.max_attempts,
            reason: inspect(reason),
            changeset_errors: inspect(changeset.errors)
          )

          {:error, changeset}
      end
    else
      Logger.warning(
        "Source ingestion stage failed and will retry",
        ingestion_id: ingestion.id,
        stage: stage,
        attempt: job.attempt,
        max_attempts: job.max_attempts,
        reason: inspect(reason)
      )

      {:error, reason}
    end
  end

  defp final_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts})
       when is_integer(attempt) and is_integer(max_attempts) do
    attempt >= max_attempts
  end

  defp final_attempt?(%Oban.Job{}), do: false

  @spec raise_retry_reset_error(SourceIngestion.t(), Ecto.Changeset.t()) :: no_return()
  defp raise_retry_reset_error(%SourceIngestion{} = ingestion, changeset) do
    Logger.error(
      "Source ingestion retry reset failed",
      ingestion_id: ingestion.id,
      changeset_errors: inspect(changeset.errors)
    )

    raise ArgumentError,
          "failed ingestion #{ingestion.id} could not be reset for retry: #{inspect(changeset.errors)}"
  end

  defp stage_module(stage) do
    case Map.fetch(stage_modules(), stage) do
      {:ok, module} ->
        module

      :error ->
        raise ArgumentError, "no stage module configured for #{inspect(stage)}"
    end
  end

  defp stage_modules do
    default_stage_modules()
    |> Map.merge(config_stage_modules())
  end

  defp default_stage_modules do
    %{
      extract: Module.concat([Gallformers.IngestionPipeline.Stages, Extract]),
      preprocess: Module.concat([Gallformers.IngestionPipeline.Stages, Preprocess]),
      hash_and_dedup: Module.concat([Gallformers.IngestionPipeline.Stages, HashAndDedup]),
      llm_clean: Module.concat([Gallformers.IngestionPipeline.Stages, LLMClean]),
      metadata: Module.concat([Gallformers.IngestionPipeline.Stages, Metadata]),
      data_extract: Module.concat([Gallformers.IngestionPipeline.Stages, DataExtract]),
      assemble: Module.concat([Gallformers.IngestionPipeline.Stages, Assemble]),
      upload: Module.concat([Gallformers.IngestionPipeline.Stages, Upload])
    }
  end

  defp config_stage_modules do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:stage_modules, %{})
  end

  defp ingestions_module do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:ingestions_module, Ingestions)
  end
end
