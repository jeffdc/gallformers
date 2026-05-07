defmodule Gallformers.IngestionPipeline.Stages.DataExtract do
  @moduledoc """
  Extracts structured gall records from cleaned markdown via the LLM client.
  """

  @behaviour Gallformers.IngestionPipeline.StageWorker

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.LLMClient
  alias Gallformers.IngestionPipeline.PipelineConfigReader
  alias Gallformers.IngestionPipeline.Schema
  alias Gallformers.IngestionPipeline.Stages.LLMSupport
  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion

  require Logger

  @default_chunk_size 3000
  @default_max_tokens 8192
  @default_max_concurrency 2
  @default_json_attempts 3
  @default_task_timeout 900_000
  @max_split_depth 2

  @impl true
  def stage_name, do: :data_extract

  @impl true
  def perform_stage(%SourceIngestion{} = ingestion) do
    Logger.info("Starting data_extract stage", ingestion_id: ingestion.id)

    with {:ok, cleaned_text} <- Storage.download_artifact(ingestion.id, :llm_clean, "text.txt"),
         prompt <- load_prompt(schema_module()),
         chunks <- LLMClient.chunk_text(cleaned_text, chunk_size(ingestion)),
         chunk_count = length(chunks),
         {:ok, records} <- extract_chunks(ingestion, prompt, chunks),
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

  defp extract_chunks(_ingestion, _prompt, []), do: {:ok, []}

  defp extract_chunks(ingestion, prompt, chunks) do
    total_chunks = length(chunks)

    Broadcaster.broadcast_chunk_progress(ingestion.id, :data_extract, %{
      chunk: 0,
      total_chunks: total_chunks,
      tokens: 0,
      tokens_per_sec: nil
    })

    chunks
    |> Enum.with_index(1)
    |> Task.async_stream(
      fn {chunk, index} ->
        extract_chunk_with_progress(ingestion, prompt, chunk, index, total_chunks)
      end,
      max_concurrency: max_concurrency(ingestion),
      ordered: true,
      timeout: task_timeout(ingestion),
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

  defp extract_chunk_with_progress(ingestion, prompt, chunk, chunk_index, total_chunks) do
    case extract_chunk(ingestion, prompt, chunk) do
      {:ok, records, usage} ->
        Broadcaster.broadcast_chunk_progress(ingestion.id, :data_extract, %{
          chunk: chunk_index,
          total_chunks: total_chunks,
          tokens: usage.completion_tokens,
          tokens_per_sec: usage[:tokens_per_sec]
        })

        {:ok, records}

      error ->
        error
    end
  end

  defp extract_chunk(ingestion, prompt, chunk, attempts_remaining \\ nil, split_depth \\ 0)

  defp extract_chunk(ingestion, prompt, chunk, nil, split_depth) do
    extract_chunk(ingestion, prompt, chunk, json_attempts(ingestion), split_depth)
  end

  defp extract_chunk(ingestion, _prompt, _chunk, 0, _split_depth) do
    Logger.warning("data_extract chunk exhausted all JSON parse attempts",
      ingestion_id: ingestion.id
    )

    {:error, :invalid_json}
  end

  defp extract_chunk(ingestion, prompt, chunk, attempts_remaining, split_depth) do
    max_tok = max_tokens(ingestion)

    case llm_client().completion(
           :data_extract,
           prompt,
           chunk,
           llm_opts(ingestion) ++ [merge_prompt: true]
         ) do
      {:ok, _response, usage} when usage.completion_tokens >= max_tok ->
        handle_truncated_chunk(ingestion, prompt, chunk, usage, max_tok, split_depth)

      {:ok, response, usage} ->
        case parse_json_response(response) do
          {:ok, records} ->
            {:ok, records, usage}

          {:error, :invalid_json} ->
            Logger.info("data_extract JSON parse failed, retrying",
              ingestion_id: ingestion.id,
              attempts_remaining: attempts_remaining - 1,
              completion_tokens: usage.completion_tokens
            )

            extract_chunk(ingestion, prompt, chunk, attempts_remaining - 1, split_depth)
        end

      {:error, reason} ->
        {:error, reason}

      {:error, reason, status} ->
        {:error, {reason, status}}
    end
  end

  defp handle_truncated_chunk(ingestion, prompt, chunk, usage, max_tok, split_depth)
       when split_depth < @max_split_depth do
    sub_chunks = LLMClient.chunk_text(chunk, div(String.length(chunk), 2))

    if length(sub_chunks) > 1 do
      Logger.info(
        "data_extract output truncated, splitting chunk and retrying",
        ingestion_id: ingestion.id,
        completion_tokens: usage.completion_tokens,
        max_tokens: max_tok,
        input_chars: String.length(chunk),
        sub_chunks: length(sub_chunks),
        split_depth: split_depth + 1
      )

      extract_sub_chunks(ingestion, prompt, sub_chunks, split_depth + 1)
    else
      Logger.warning(
        "data_extract output truncated but chunk cannot be split further",
        ingestion_id: ingestion.id,
        completion_tokens: usage.completion_tokens,
        max_tokens: max_tok,
        input_chars: String.length(chunk)
      )

      {:error, :json_truncated}
    end
  end

  defp handle_truncated_chunk(ingestion, _prompt, chunk, usage, max_tok, split_depth) do
    Logger.warning(
      "data_extract output truncated at max split depth, giving up",
      ingestion_id: ingestion.id,
      completion_tokens: usage.completion_tokens,
      max_tokens: max_tok,
      input_chars: String.length(chunk),
      split_depth: split_depth
    )

    {:error, :json_truncated}
  end

  defp extract_sub_chunks(ingestion, prompt, sub_chunks, split_depth) do
    init = {:ok, [], %{completion_tokens: 0, tokens_per_sec: nil}}

    Enum.reduce_while(sub_chunks, init, fn sub_chunk, {:ok, acc, acc_usage} ->
      case extract_chunk(ingestion, prompt, sub_chunk, nil, split_depth) do
        {:ok, records, usage} ->
          merged = %{
            completion_tokens: acc_usage.completion_tokens + usage.completion_tokens,
            tokens_per_sec: usage[:tokens_per_sec]
          }

          {:cont, {:ok, acc ++ records, merged}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp parse_json_response(response) do
    LLMSupport.extract_json_array(response)
  end

  defp load_prompt(schema_module) do
    LLMSupport.load_prompt!("data_extract.txt", %{"SCHEMA" => schema_module.prompt_text()})
  end

  defp llm_opts(ingestion) do
    [max_tokens: max_tokens(ingestion)]
    |> put_pipeline_opt(ingestion, :data_extract, :model)
    |> put_pipeline_client_opts(ingestion)
  end

  defp llm_client do
    LLMSupport.llm_client(__MODULE__)
  end

  defp normalize_validate({:ok, data}), do: {:ok, data}
  defp normalize_validate(error), do: error

  defp schema_module do
    app_config()[:schema_module] || Schema
  end

  defp chunk_size(i),
    do: PipelineConfigReader.get(i, :data_extract, :chunk_size, @default_chunk_size)

  defp max_tokens(i),
    do: PipelineConfigReader.get(i, :data_extract, :max_tokens, @default_max_tokens)

  defp max_concurrency(i),
    do: PipelineConfigReader.get(i, :data_extract, :max_concurrency, @default_max_concurrency)

  defp json_attempts(i),
    do: PipelineConfigReader.get(i, :data_extract, :json_attempts, @default_json_attempts)

  defp task_timeout(i),
    do: PipelineConfigReader.get(i, :data_extract, :task_timeout, @default_task_timeout)

  defp put_pipeline_opt(opts, ingestion, section, key) do
    case PipelineConfigReader.get(ingestion, section, key, nil) do
      nil -> opts
      value -> Keyword.put(opts, key, value)
    end
  end

  defp put_pipeline_client_opts(opts, ingestion) do
    opts
    |> put_pipeline_opt(ingestion, :client, :api_url)
    |> put_pipeline_opt(ingestion, :client, :stall_timeout)
    |> put_pipeline_opt(ingestion, :client, :retry_backoffs)
  end

  defp app_config do
    Application.get_env(:gallformers, __MODULE__, [])
  end
end
