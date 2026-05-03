defmodule Gallformers.IngestionPipeline.DuplicateResolution do
  @moduledoc """
  Pipeline-facing adapter for human duplicate-review decisions.
  """

  use Boundary,
    deps: [
      Gallformers.Ingestions,
      Gallformers.IngestionPipeline.Worker,
      Gallformers.IngestionPipeline.Workflow
    ],
    exports: :all

  alias Gallformers.IngestionPipeline.Worker
  alias Gallformers.IngestionPipeline.Workflow
  alias Gallformers.Ingestions

  @doc """
  Confirms that a duplicate candidate is a true duplicate and re-enqueues the
  orchestrator so it can observe the terminal duplicate-confirmed state.
  """
  @spec confirm_duplicate(integer(), integer()) ::
          {:ok, Ingestions.SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def confirm_duplicate(candidate_id, reviewed_by_id)
      when is_integer(candidate_id) and is_integer(reviewed_by_id) do
    candidate = Ingestions.get_duplicate_candidate!(candidate_id)

    with {:ok, %{source_ingestion: source_ingestion}} <-
           Ingestions.confirm_duplicate_candidate(candidate, %{reviewed_by_id: reviewed_by_id}),
         {:ok, _job} <- worker_module().enqueue(source_ingestion.id) do
      {:ok, source_ingestion}
    end
  end

  @doc """
  Rejects a duplicate candidate. If the last pending candidate is rejected, the
  ingestion resumes processing and the orchestrator is re-enqueued.
  """
  @spec reject_duplicate(integer(), integer()) ::
          {:ok, Ingestions.SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def reject_duplicate(candidate_id, reviewed_by_id)
      when is_integer(candidate_id) and is_integer(reviewed_by_id) do
    candidate = Ingestions.get_duplicate_candidate!(candidate_id)

    with {:ok, %{source_ingestion: source_ingestion}} <-
           Ingestions.reject_duplicate_candidate(candidate, %{reviewed_by_id: reviewed_by_id}),
         :ok <- maybe_reenqueue(source_ingestion) do
      {:ok, source_ingestion}
    end
  end

  @doc """
  Rejects every pending duplicate candidate for an ingestion and re-enqueues the
  orchestrator so the pipeline can continue.
  """
  @spec promote_to_unique(integer(), integer()) ::
          {:ok, Ingestions.SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def promote_to_unique(ingestion_id, reviewed_by_id)
      when is_integer(ingestion_id) and is_integer(reviewed_by_id) do
    ingestion = Ingestions.get_source_ingestion!(ingestion_id)

    ingestion
    |> Ingestions.list_duplicate_candidates()
    |> Enum.filter(&(&1.status == "pending"))
    |> Enum.reduce_while({:ok, ingestion}, fn candidate, {:ok, _current_ingestion} ->
      case Ingestions.reject_duplicate_candidate(candidate, %{reviewed_by_id: reviewed_by_id}) do
        {:ok, %{source_ingestion: updated_ingestion}} -> {:cont, {:ok, updated_ingestion}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, updated_ingestion} ->
        with :ok <- maybe_reenqueue(updated_ingestion) do
          {:ok, updated_ingestion}
        end

      error ->
        error
    end
  end

  defp maybe_reenqueue(source_ingestion) do
    if Workflow.resumable?(source_ingestion) do
      case worker_module().enqueue(source_ingestion.id) do
        {:ok, _job} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    else
      :ok
    end
  end

  defp worker_module do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:worker_module, Worker)
  end
end
