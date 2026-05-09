defmodule Gallformers.IngestionPipeline.Broadcaster do
  @moduledoc """
  PubSub helpers for ingestion pipeline progress updates.
  """

  use Boundary, deps: [], exports: :all

  require Logger

  @topic_prefix "ingestion:"

  @type stage :: atom() | String.t()

  @doc """
  Subscribes the current process to an ingestion-specific PubSub topic.
  """
  @spec subscribe(integer()) :: :ok | {:error, term()}
  def subscribe(ingestion_id) when is_integer(ingestion_id) do
    result = Phoenix.PubSub.subscribe(Gallformers.PubSub, topic(ingestion_id))

    Logger.debug(
      "Broadcaster.subscribe topic=#{topic(ingestion_id)} pid=#{inspect(self())} result=#{inspect(result)}"
    )

    result
  end

  @doc """
  Broadcasts that a stage completed for an ingestion.
  """
  @spec broadcast_stage_complete(integer(), stage()) :: :ok
  def broadcast_stage_complete(ingestion_id, stage) do
    broadcast(ingestion_id, {:stage_complete, stage})
  end

  @doc """
  Broadcasts percent progress for a stage.
  """
  @spec broadcast_progress(integer(), stage(), integer()) :: :ok
  def broadcast_progress(ingestion_id, stage, percent) when is_integer(percent) do
    broadcast(ingestion_id, {:progress, stage, percent})
  end

  @doc """
  Broadcasts a stage error.
  """
  @spec broadcast_error(integer(), stage(), term()) :: :ok
  def broadcast_error(ingestion_id, stage, reason) do
    broadcast(ingestion_id, {:error, stage, reason})
  end

  @doc """
  Broadcasts that duplicate review is required.
  """
  @spec broadcast_duplicate_review(integer(), list()) :: :ok
  def broadcast_duplicate_review(ingestion_id, candidates) when is_list(candidates) do
    broadcast(ingestion_id, {:needs_duplicate_review, candidates})
  end

  @doc """
  Broadcasts chunk-level progress for a stage (e.g., LLM streaming).
  """
  @spec broadcast_chunk_progress(integer(), stage(), map()) :: :ok
  def broadcast_chunk_progress(ingestion_id, stage, progress) when is_map(progress) do
    broadcast(ingestion_id, {:chunk_progress, stage, progress})
  end

  @doc """
  Broadcasts a warning for a specific chunk within a stage.
  """
  @spec broadcast_chunk_warning(integer(), stage(), map()) :: :ok
  def broadcast_chunk_warning(ingestion_id, stage, warning) when is_map(warning) do
    broadcast(ingestion_id, {:chunk_warning, stage, warning})
  end

  @doc """
  Broadcasts that an ingestion is ready for review.
  """
  @spec broadcast_review_ready(integer()) :: :ok
  def broadcast_review_ready(ingestion_id) do
    broadcast(ingestion_id, {:review_ready, ingestion_id})
  end

  defp broadcast(ingestion_id, message) do
    tag =
      case message do
        {atom, _stage, %{chunk: chunk}} -> "#{atom}/chunk=#{chunk}"
        {atom, stage} when is_atom(stage) -> "#{atom}/#{stage}"
        {atom, stage, _} -> "#{atom}/#{inspect(stage)}"
        other -> inspect(other)
      end

    Logger.debug(
      "Broadcaster.broadcast topic=#{topic(ingestion_id)} tag=#{tag} from_pid=#{inspect(self())}"
    )

    Phoenix.PubSub.broadcast(Gallformers.PubSub, topic(ingestion_id), message)
  end

  defp topic(ingestion_id), do: @topic_prefix <> Integer.to_string(ingestion_id)
end
