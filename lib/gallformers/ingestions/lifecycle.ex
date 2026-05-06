defmodule Gallformers.Ingestions.Lifecycle do
  @moduledoc false

  import Ecto.Query

  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.{DuplicateCandidate, SourceIngestion}
  alias Gallformers.Repo
  alias Gallformers.Utils

  @spec clear_source_ingestion(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t() | term()}
  def clear_source_ingestion(%SourceIngestion{} = source_ingestion) do
    do_clear_source_ingestion(source_ingestion)
  end

  def clear_source_ingestion(source_ingestion_id) when is_integer(source_ingestion_id) do
    source_ingestion_id
    |> Ingestions.get_source_ingestion!()
    |> do_clear_source_ingestion()
  end

  @spec source_ingestion_clearability(SourceIngestion.t() | integer()) ::
          :failed | :abandoned | nil
  def source_ingestion_clearability(%SourceIngestion{} = source_ingestion) do
    cond do
      source_ingestion.status == "failed" ->
        :failed

      abandoned_source_ingestion?(source_ingestion) ->
        :abandoned

      true ->
        nil
    end
  end

  def source_ingestion_clearability(source_ingestion_id) when is_integer(source_ingestion_id) do
    source_ingestion_id
    |> Ingestions.get_source_ingestion!()
    |> source_ingestion_clearability()
  end

  @spec delete_failed_source_ingestion(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t() | term()}
  def delete_failed_source_ingestion(source_ingestion) do
    case source_ingestion_clearability(source_ingestion) do
      :failed -> clear_source_ingestion(source_ingestion)
      _ -> {:error, clear_source_ingestion_changeset(source_ingestion)}
    end
  end

  @spec retry_failed_source_ingestion(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def retry_failed_source_ingestion(%SourceIngestion{} = source_ingestion) do
    case retry_stage_for_failed_ingestion(source_ingestion) do
      {:ok, retry_stage} ->
        Ingestions.transition_source_ingestion_status(source_ingestion, :processing, %{
          processing_stage: retry_stage,
          error_stage: nil,
          error_message: nil,
          failed_at: nil
        })

      {:error, :not_failed} ->
        {:error, retry_failed_source_ingestion_changeset(source_ingestion, "must be failed")}

      {:error, :missing_error_stage} ->
        {:error,
         retry_failed_source_ingestion_changeset(
           source_ingestion,
           "must record the failed stage before retrying"
         )}

      {:error, :unknown_error_stage} ->
        {:error,
         retry_failed_source_ingestion_changeset(
           source_ingestion,
           "has an unknown failed stage and cannot be retried"
         )}
    end
  end

  def retry_failed_source_ingestion(source_ingestion_id) when is_integer(source_ingestion_id) do
    source_ingestion_id
    |> Ingestions.get_source_ingestion!()
    |> retry_failed_source_ingestion()
  end

  defp do_clear_source_ingestion(%SourceIngestion{} = source_ingestion) do
    case source_ingestion_clearability(source_ingestion) do
      clearability when clearability in [:failed, :abandoned] ->
        do_delete_source_ingestion(source_ingestion)

      nil ->
        {:error, clear_source_ingestion_changeset(source_ingestion)}
    end
  end

  defp do_delete_source_ingestion(%SourceIngestion{} = source_ingestion) do
    with :ok <- Storage.delete_artifacts_for_ingestion(source_ingestion.id) do
      Repo.delete(source_ingestion)
    end
  end

  defp clear_source_ingestion_changeset(%SourceIngestion{} = source_ingestion) do
    source_ingestion
    |> SourceIngestion.changeset(%{})
    |> Ecto.Changeset.add_error(:status, "only failed or abandoned ingestions can be cleared")
  end

  defp retry_failed_source_ingestion_changeset(
         %SourceIngestion{} = source_ingestion,
         message
       ) do
    source_ingestion
    |> SourceIngestion.changeset(%{})
    |> Ecto.Changeset.add_error(:status, message)
  end

  defp abandoned_source_ingestion?(%SourceIngestion{
         id: source_ingestion_id,
         status: "processing"
       }) do
    not active_worker_job_exists?(source_ingestion_id)
  end

  defp abandoned_source_ingestion?(%SourceIngestion{}), do: false

  defp retry_stage_for_failed_ingestion(%SourceIngestion{status: "failed"} = source_ingestion) do
    source_ingestion
    |> Utils.attr_value(:error_stage)
    |> retry_stage_for_error_stage(source_ingestion)
  end

  defp retry_stage_for_failed_ingestion(%SourceIngestion{}), do: {:error, :not_failed}

  defp retry_stage_for_error_stage(nil, _source_ingestion), do: {:error, :missing_error_stage}
  defp retry_stage_for_error_stage("extract", _source_ingestion), do: {:ok, "submitted"}
  defp retry_stage_for_error_stage("preprocess", _source_ingestion), do: {:ok, "extract"}
  defp retry_stage_for_error_stage("hash_and_dedup", _source_ingestion), do: {:ok, "preprocess"}

  defp retry_stage_for_error_stage("llm_clean", source_ingestion),
    do: {:ok, llm_clean_retry_stage(source_ingestion)}

  defp retry_stage_for_error_stage("metadata", _source_ingestion), do: {:ok, "llm_clean"}
  defp retry_stage_for_error_stage("data_extract", _source_ingestion), do: {:ok, "metadata"}
  defp retry_stage_for_error_stage("assemble", _source_ingestion), do: {:ok, "data_extract"}
  defp retry_stage_for_error_stage("upload", _source_ingestion), do: {:ok, "assemble"}

  defp retry_stage_for_error_stage(_error_stage, _source_ingestion),
    do: {:error, :unknown_error_stage}

  defp llm_clean_retry_stage(%SourceIngestion{id: source_ingestion_id}) do
    if duplicate_candidates_exist?(source_ingestion_id) do
      "duplicate_review"
    else
      "hash_and_dedup"
    end
  end

  defp duplicate_candidates_exist?(source_ingestion_id) when is_integer(source_ingestion_id) do
    from(duplicate_candidate in DuplicateCandidate,
      where: duplicate_candidate.source_ingestion_id == ^source_ingestion_id
    )
    |> Repo.exists?()
  end

  defp active_worker_job_exists?(source_ingestion_id) do
    from(job in "oban_jobs",
      where:
        field(job, :worker) == ^"Gallformers.IngestionPipeline.Worker" and
          field(job, :state) in ^["available", "scheduled", "executing", "retryable"] and
          fragment(
            "?->>'ingestion_id' = ?",
            field(job, :args),
            ^Integer.to_string(source_ingestion_id)
          )
    )
    |> Repo.exists?()
  end
end
