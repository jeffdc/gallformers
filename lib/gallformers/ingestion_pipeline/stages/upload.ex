defmodule Gallformers.IngestionPipeline.Stages.Upload do
  @moduledoc """
  Finalizes a successful ingestion by compiling the artifact manifest and
  marking the ingestion ready for human review.
  """

  @behaviour Gallformers.IngestionPipeline.StageWorker

  require Logger

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.Stages.LLMSupport
  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion

  @impl true
  def stage_name, do: :upload

  @spec artifact_manifest(integer()) :: {:ok, [String.t()]} | {:error, term()}
  def artifact_manifest(ingestion_id) when is_integer(ingestion_id) do
    Storage.list_artifacts_for_ingestion(ingestion_id)
  end

  @impl true
  def perform_stage(%SourceIngestion{} = ingestion) do
    Logger.info("Starting upload stage", ingestion_id: ingestion.id)

    with {:ok, records_json} <- Storage.download_artifact(ingestion.id, :data_extract, "output.json"),
         {:ok, records} <- decode_records(records_json),
         {:ok, _species_entries} <-
           Ingestions.ensure_source_ingestion_species_entries(ingestion, records),
         {:ok, manifest} <- artifact_manifest(ingestion.id),
         {:ok, updated_ingestion} <-
           Ingestions.transition_source_ingestion_workflow(ingestion, :upload_succeeded),
         :ok <- Broadcaster.broadcast_review_ready(ingestion.id) do
      Logger.info(
        "Upload stage completed",
        ingestion_id: ingestion.id,
        artifact_count: length(manifest)
      )

      {:ok, updated_ingestion}
    else
      {:error, reason} ->
        Logger.warning(
          "Upload stage failed",
          ingestion_id: ingestion.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp decode_records(json) when is_binary(json) do
    case json |> LLMSupport.strip_fenced_json() |> Jason.decode() do
      {:ok, records} when is_list(records) -> {:ok, records}
      {:ok, _other} -> {:error, :invalid_data_extract_payload}
      {:error, reason} -> {:error, reason}
    end
  end
end
