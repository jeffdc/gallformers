defmodule Gallformers.IngestionPipeline.Stages.DataExtract do
  @moduledoc """
  Extracts structured gall records from cleaned markdown via the LLM client.
  """

  @behaviour Gallformers.IngestionPipeline.StageWorker

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.LLMClient
  alias Gallformers.IngestionPipeline.Schema
  alias Gallformers.IngestionPipeline.Stages.LLMSupport
  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion

  require Logger

  @default_chunk_size 3000
  @default_max_tokens 6000
  @default_max_concurrency 2
  @default_task_timeout :timer.minutes(10)
  @default_json_attempts 3

  @impl true
  def stage_name, do: :data_extract

  @impl true
  def perform_stage(%SourceIngestion{} = ingestion) do
    Logger.info("Starting data_extract stage", ingestion_id: ingestion.id)

    with {:ok, cleaned_text} <- Storage.download_artifact(ingestion.id, :llm_clean, "text.txt"),
         prompt <- load_prompt(schema_module()),
         chunks <- LLMClient.chunk_text(cleaned_text, chunk_size()),
         chunk_count = length(chunks),
         {:ok, records} <- extract_chunks(prompt, chunks),
         record_count = length(records),
         {:ok, validated_records} <- normalize_validate(schema_module().validate(records)),
         {:ok, _artifact_path} <-
           Storage.upload_artifact(
             ingestion.id,
             :data_extract,
             "output.json",
             Jason.encode!(validated_records, pretty: true),
             "application/json"
           ),
         {:ok, updated_ingestion} <-
           Ingestions.transition_source_ingestion_workflow(ingestion, :data_extract_succeeded),
         :ok <- Broadcaster.broadcast_stage_complete(ingestion.id, :data_extract) do
      Logger.info("Completed data_extract stage",
        ingestion_id: ingestion.id,
        chunks: chunk_count,
        records_extracted: record_count,
        records_validated: length(validated_records)
      )

      {:ok, updated_ingestion}
    else
      {:error, :invalid_contract, _} = error ->
        error

      {:error, reason} ->
        Logger.warning("data_extract stage failed",
          ingestion_id: ingestion.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp extract_chunks(_prompt, []), do: {:ok, []}

  defp extract_chunks(prompt, chunks) do
    chunks
    |> Task.async_stream(
      &extract_chunk(prompt, &1),
      max_concurrency: max_concurrency(),
      ordered: true,
      timeout: task_timeout(),
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({:ok, []}, &LLMSupport.reduce_async_result/2)
    |> case do
      {:ok, chunk_records} ->
        {:ok, chunk_records |> Enum.reverse() |> List.flatten()}

      error ->
        error
    end
  end

  defp extract_chunk(prompt, chunk, attempts_remaining \\ json_attempts())

  defp extract_chunk(_prompt, _chunk, 0), do: {:error, :invalid_json}

  defp extract_chunk(prompt, chunk, attempts_remaining) do
    case llm_client().completion(:data_extract, prompt, chunk,
           max_tokens: max_tokens(),
           merge_prompt: true
         ) do
      {:ok, response, _usage} ->
        case parse_json_response(response) do
          {:ok, records} ->
            {:ok, records}

          {:error, :invalid_json} ->
            extract_chunk(prompt, chunk, attempts_remaining - 1)
        end

      {:error, reason} ->
        {:error, reason}

      {:error, reason, status} ->
        {:error, {reason, status}}
    end
  end

  defp parse_json_response(response) do
    LLMSupport.extract_json_array(response)
  end

  defp load_prompt(schema_module) do
    LLMSupport.load_prompt!("data_extract.txt", %{"SCHEMA" => schema_module.prompt_text()})
  end

  defp llm_client do
    LLMSupport.llm_client(__MODULE__)
  end

  defp normalize_validate({:ok, data}), do: {:ok, data}
  defp normalize_validate(error), do: error

  defp schema_module do
    config()[:schema_module] || Schema
  end

  defp chunk_size, do: config()[:chunk_size] || @default_chunk_size
  defp max_tokens, do: config()[:max_tokens] || @default_max_tokens
  defp max_concurrency, do: config()[:max_concurrency] || @default_max_concurrency
  defp task_timeout, do: config()[:task_timeout] || @default_task_timeout
  defp json_attempts, do: config()[:json_attempts] || @default_json_attempts

  defp config do
    Application.get_env(:gallformers, __MODULE__, [])
  end
end
