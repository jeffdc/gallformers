defmodule Gallformers.IngestionPipeline.Stages.LLMClean do
  @moduledoc """
  Uses the LLM client to clean preprocessed text into structured markdown.
  """

  @behaviour Gallformers.IngestionPipeline.StageWorker

  require Logger

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.LLMClient
  alias Gallformers.IngestionPipeline.PipelineConfigReader
  alias Gallformers.IngestionPipeline.Stages.LLMSupport
  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion

  @default_chunk_size 6000
  @default_max_tokens 4096
  @default_max_concurrency 2
  @default_task_timeout 900_000

  @impl true
  def stage_name, do: :llm_clean

  @impl true
  def perform_stage(%SourceIngestion{} = ingestion) do
    Logger.info("Starting llm_clean stage", ingestion_id: ingestion.id, title: ingestion.title)

    with {:ok, preprocessed_text} <-
           Storage.download_artifact(ingestion.id, :preprocess, "text.txt"),
         prompt <- LLMSupport.load_prompt!("llm_clean.txt"),
         chunks <- LLMClient.chunk_text(preprocessed_text, chunk_size(ingestion)),
         _ <-
           Logger.info("llm_clean chunked input",
             ingestion_id: ingestion.id,
             input_chars: String.length(preprocessed_text),
             chunk_count: length(chunks),
             chunk_sizes: Enum.map(chunks, &String.length/1)
           ),
         {:ok, cleaned_text} <- clean_chunks(ingestion, prompt, chunks),
         {:ok, _artifact_path} <-
           Storage.upload_artifact(
             ingestion.id,
             :llm_clean,
             "text.txt",
             cleaned_text,
             "text/plain"
           ),
         {:ok, updated_ingestion} <-
           Ingestions.transition_source_ingestion_workflow(ingestion, :llm_clean_succeeded),
         :ok <- Broadcaster.broadcast_stage_complete(ingestion.id, :llm_clean) do
      Logger.info("Completed llm_clean stage",
        ingestion_id: ingestion.id,
        chunks_processed: length(chunks),
        output_chars: String.length(cleaned_text)
      )

      {:ok, updated_ingestion}
    end
  end

  defp clean_chunks(_ingestion, _prompt, []), do: {:ok, ""}

  defp clean_chunks(ingestion, prompt, chunks) do
    total_chunks = length(chunks)

    Broadcaster.broadcast_chunk_progress(ingestion.id, :llm_clean, %{
      chunk: 0,
      total_chunks: total_chunks,
      tokens: 0,
      tokens_per_sec: nil
    })

    chunks
    |> Enum.with_index(1)
    |> Task.async_stream(
      fn {chunk, index} -> clean_chunk(ingestion, prompt, chunk, index, total_chunks) end,
      max_concurrency: max_concurrency(ingestion),
      ordered: true,
      timeout: task_timeout(ingestion),
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({:ok, []}, &LLMSupport.reduce_async_result/2)
    |> case do
      {:ok, cleaned_chunks} -> {:ok, cleaned_chunks |> Enum.reverse() |> Enum.join("\n\n")}
      error -> error
    end
  end

  defp clean_chunk(ingestion, prompt, chunk, chunk_index, total_chunks) do
    case llm_client().completion(:llm_clean, prompt, chunk, llm_opts(ingestion)) do
      {:ok, cleaned_chunk, usage} ->
        Broadcaster.broadcast_chunk_progress(ingestion.id, :llm_clean, %{
          chunk: chunk_index,
          total_chunks: total_chunks,
          tokens: usage.completion_tokens,
          tokens_per_sec: usage[:tokens_per_sec]
        })

        {:ok, cleaned_chunk}

      {:error, reason} ->
        {:error, reason}

      {:error, reason, status} ->
        {:error, {reason, status}}
    end
  end

  defp llm_opts(ingestion) do
    [max_tokens: max_tokens(ingestion)]
    |> put_pipeline_opt(ingestion, :llm_clean, :model)
    |> put_pipeline_client_opts(ingestion)
  end

  defp llm_client do
    LLMSupport.llm_client(__MODULE__)
  end

  defp chunk_size(i),
    do: PipelineConfigReader.get(i, :llm_clean, :chunk_size, @default_chunk_size)

  defp max_tokens(i),
    do: PipelineConfigReader.get(i, :llm_clean, :max_tokens, @default_max_tokens)

  defp max_concurrency(i),
    do: PipelineConfigReader.get(i, :llm_clean, :max_concurrency, @default_max_concurrency)

  defp task_timeout(i),
    do: PipelineConfigReader.get(i, :llm_clean, :task_timeout, @default_task_timeout)

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
end
