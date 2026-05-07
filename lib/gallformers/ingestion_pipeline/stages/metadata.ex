defmodule Gallformers.IngestionPipeline.Stages.Metadata do
  @moduledoc """
  Extracts bibliographic metadata from cleaned markdown via the LLM client.
  """

  @behaviour Gallformers.IngestionPipeline.StageWorker

  require Logger

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.DuplicateSignals
  alias Gallformers.IngestionPipeline.PipelineConfigReader
  alias Gallformers.IngestionPipeline.Stages.LLMSupport
  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion

  @default_max_input_chars 24_000
  @default_max_tokens 1024
  @default_json_attempts 3

  @impl true
  def stage_name, do: :metadata

  @impl true
  def perform_stage(%SourceIngestion{} = ingestion) do
    Logger.info("Starting metadata stage", ingestion_id: ingestion.id)

    with {:ok, cleaned_text} <- Storage.download_artifact(ingestion.id, :llm_clean, "text.txt"),
         prompt <- LLMSupport.load_prompt!("metadata.txt"),
         truncated_text <- String.slice(cleaned_text, 0, max_input_chars(ingestion)),
         _ <-
           Broadcaster.broadcast_chunk_progress(ingestion.id, :metadata, %{
             chunk: 0,
             total_chunks: 1,
             tokens: 0,
             tokens_per_sec: nil
           }),
         {:ok, raw_response, metadata_attrs} <-
           extract_metadata(ingestion, prompt, truncated_text),
         _ <-
           Broadcaster.broadcast_chunk_progress(ingestion.id, :metadata, %{
             chunk: 1,
             total_chunks: 1,
             tokens: 0,
             tokens_per_sec: nil
           }),
         {:ok, parsed_json} <- parse_json_for_upload(raw_response),
         title <- Map.get(metadata_attrs, :title),
         author_count <- length(Map.get(metadata_attrs, :authors, [])),
         {:ok, _updated_signals} <- Ingestions.record_duplicate_signals(ingestion, metadata_attrs),
         {:ok, _artifact_path} <-
           Storage.upload_artifact(
             ingestion.id,
             :metadata,
             "output.json",
             parsed_json,
             "application/json"
           ),
         {:ok, updated_ingestion} <-
           Ingestions.transition_source_ingestion_workflow(ingestion, :metadata_succeeded),
         :ok <- Broadcaster.broadcast_stage_complete(ingestion.id, :metadata) do
      Logger.info("Completed metadata stage",
        ingestion_id: ingestion.id,
        title: title,
        author_count: author_count,
        input_chars: String.length(cleaned_text)
      )

      {:ok, updated_ingestion}
    else
      {:error, reason} ->
        Logger.warning(
          "Metadata stage failed",
          ingestion_id: ingestion.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp extract_metadata(ingestion, prompt, text, attempts_remaining \\ nil)

  defp extract_metadata(ingestion, prompt, text, nil) do
    extract_metadata(ingestion, prompt, text, json_attempts(ingestion))
  end

  defp extract_metadata(ingestion, _prompt, _text, 0) do
    Logger.warning("metadata exhausted all JSON parse attempts",
      ingestion_id: ingestion.id
    )

    {:error, :invalid_json}
  end

  defp extract_metadata(ingestion, prompt, text, attempts_remaining) do
    max_tok = max_tokens(ingestion)

    case llm_client().completion(:metadata, prompt, text, llm_opts(ingestion)) do
      {:ok, _raw_response, usage} when usage.completion_tokens >= max_tok ->
        Logger.warning(
          "metadata JSON truncated at max_tokens limit, not retrying",
          ingestion_id: ingestion.id,
          completion_tokens: usage.completion_tokens,
          max_tokens: max_tok
        )

        {:error, :json_truncated}

      {:ok, raw_response, usage} ->
        case parse_metadata(raw_response) do
          {:ok, metadata} ->
            {:ok, raw_response, DuplicateSignals.signal_attrs(metadata)}

          {:error, :invalid_json} ->
            Logger.info("metadata JSON parse failed, retrying",
              ingestion_id: ingestion.id,
              attempts_remaining: attempts_remaining - 1,
              completion_tokens: usage.completion_tokens
            )

            extract_metadata(ingestion, prompt, text, attempts_remaining - 1)
        end

      {:error, reason} ->
        {:error, reason}

      {:error, reason, status} ->
        {:error, {reason, status}}
    end
  end

  defp parse_metadata(raw_response) do
    case LLMSupport.extract_json_object(raw_response) do
      {:ok, decoded} -> cast_metadata(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  # Strips fences, parses JSON, and re-encodes for clean upload
  defp parse_json_for_upload(raw_response) do
    raw_response
    |> LLMSupport.strip_fenced_json()
    |> Jason.decode()
    |> case do
      {:ok, decoded} -> {:ok, Jason.encode!(decoded, pretty: true)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cast_metadata(%{} = decoded) do
    with {:ok, title} <- cast_optional_string(Map.get(decoded, "title")),
         {:ok, authors} <- cast_authors(Map.get(decoded, "authors", [])),
         {:ok, year} <- cast_optional_integer(Map.get(decoded, "year")),
         {:ok, doi} <- cast_optional_string(Map.get(decoded, "doi")) do
      {:ok, %{title: title, authors: authors, year: year, doi: doi}}
    end
  end

  defp cast_optional_string(nil), do: {:ok, nil}
  defp cast_optional_string(value) when is_binary(value), do: {:ok, value}
  defp cast_optional_string(_value), do: {:error, :invalid_json}

  defp cast_authors(authors) when is_list(authors) do
    if Enum.all?(authors, &is_binary/1) do
      {:ok, Enum.map(authors, &String.trim/1)}
    else
      {:error, :invalid_json}
    end
  end

  defp cast_authors(_authors), do: {:error, :invalid_json}

  defp cast_optional_integer(nil), do: {:ok, nil}
  defp cast_optional_integer(value) when is_integer(value), do: {:ok, value}
  defp cast_optional_integer(_value), do: {:error, :invalid_json}

  defp llm_opts(ingestion) do
    [max_tokens: max_tokens(ingestion)]
    |> put_pipeline_opt(ingestion, :metadata, :model)
    |> put_pipeline_client_opts(ingestion)
  end

  defp llm_client do
    LLMSupport.llm_client(__MODULE__)
  end

  defp max_tokens(i),
    do: PipelineConfigReader.get(i, :metadata, :max_tokens, @default_max_tokens)

  defp max_input_chars(i),
    do: PipelineConfigReader.get(i, :metadata, :max_input_chars, @default_max_input_chars)

  defp json_attempts(i),
    do: PipelineConfigReader.get(i, :metadata, :json_attempts, @default_json_attempts)

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
