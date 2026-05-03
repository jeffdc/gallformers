defmodule Gallformers.IngestionPipeline.Stages.LLMClean do
  @moduledoc """
  Uses the LLM client to clean preprocessed text into structured markdown.
  """

  @behaviour Gallformers.IngestionPipeline.StageWorker

  require Logger

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.LLMClient
  alias Gallformers.IngestionPipeline.Stages.LLMSupport
  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion

  @default_chunk_size 6000
  @default_max_tokens 8192
  @default_max_concurrency 2
  @default_task_timeout :timer.minutes(5)

  @impl true
  def stage_name, do: :llm_clean

  @impl true
  def perform_stage(%SourceIngestion{} = ingestion) do
    Logger.info("Starting llm_clean stage", ingestion_id: ingestion.id, title: ingestion.title)

    with {:ok, preprocessed_text} <-
           Storage.download_artifact(ingestion.id, :preprocess, "text.txt"),
         prompt <- LLMSupport.load_prompt!("llm_clean.txt"),
         chunks <- LLMClient.chunk_text(preprocessed_text, chunk_size()),
         {:ok, cleaned_text} <- clean_chunks(prompt, chunks),
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

  defp clean_chunks(_prompt, []), do: {:ok, ""}

  defp clean_chunks(prompt, chunks) do
    chunks
    |> Task.async_stream(
      &clean_chunk(prompt, &1),
      max_concurrency: max_concurrency(),
      ordered: true,
      timeout: task_timeout(),
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({:ok, []}, &LLMSupport.reduce_async_result/2)
    |> case do
      {:ok, cleaned_chunks} -> {:ok, cleaned_chunks |> Enum.reverse() |> Enum.join("\n\n")}
      error -> error
    end
  end

  defp clean_chunk(prompt, chunk) do
    case llm_client().completion(:llm_clean, prompt, chunk, max_tokens: max_tokens()) do
      {:ok, cleaned_chunk, _usage} -> {:ok, cleaned_chunk}
      {:error, reason} -> {:error, reason}
      {:error, reason, status} -> {:error, {reason, status}}
    end
  end

  defp llm_client do
    LLMSupport.llm_client(__MODULE__)
  end

  defp chunk_size, do: config()[:chunk_size] || @default_chunk_size
  defp max_tokens, do: config()[:max_tokens] || @default_max_tokens
  defp max_concurrency, do: config()[:max_concurrency] || @default_max_concurrency
  defp task_timeout, do: config()[:task_timeout] || @default_task_timeout

  defp config do
    Application.get_env(:gallformers, __MODULE__, [])
  end
end
