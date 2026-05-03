defmodule Gallformers.IngestionPipeline.Stages.HashAndDedup do
  @moduledoc """
  Computes MinHash signals and executes the duplicate-detection ladder.
  """

  @behaviour Gallformers.IngestionPipeline.StageWorker

  require Logger

  alias Gallformers.IngestionPipeline.Broadcaster
  alias Gallformers.IngestionPipeline.DuplicateDetection
  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion
  alias Gallformers.MinHash

  @impl true
  def stage_name, do: :hash_and_dedup

  @impl true
  def perform_stage(%SourceIngestion{} = ingestion) do
    Logger.info("Starting hash_and_dedup stage", ingestion_id: ingestion.id)

    with {:ok, preprocessed_text} <-
           Storage.download_artifact(ingestion.id, :preprocess, "text.txt"),
         signature <- MinHash.compute_signature(preprocessed_text),
         {:ok, ingestion_with_signature} <-
           Ingestions.record_duplicate_signals(ingestion, %{minhash_signature: signature}),
         candidates <- DuplicateDetection.fetch_candidates(ingestion_with_signature) do
      Logger.debug("Fetched duplicate candidates",
        ingestion_id: ingestion.id,
        candidate_count: length(candidates)
      )

      case DuplicateDetection.run_ladder(ingestion_with_signature, candidates) do
        {:exact_duplicate, candidate} ->
          Logger.info("Exact duplicate detected",
            ingestion_id: ingestion.id,
            candidate_id: candidate.id
          )

          confirm_exact_duplicate(ingestion_with_signature, candidate)

        {:probable_duplicate, _candidate, _evidence} ->
          Logger.info("Probable duplicate detected, pausing for review",
            ingestion_id: ingestion.id
          )

          create_probable_duplicate_candidates(ingestion_with_signature, candidates)

        :no_match ->
          Logger.info("No duplicate matches found", ingestion_id: ingestion.id)
          complete_without_match(ingestion_with_signature)
      end
    end
  end

  defp confirm_exact_duplicate(ingestion, candidate) do
    exact_evidence = %{match_type: "exact_duplicate"}

    with {:ok, ingestion_in_review} <-
           Ingestions.transition_source_ingestion_workflow(
             ingestion,
             :duplicate_review_requested
           ),
         {:ok, duplicate_candidate} <-
           create_or_reuse_candidate(ingestion_in_review, candidate, %{
             evidence: exact_evidence
           }),
         {:ok, %{source_ingestion: confirmed_ingestion}} <-
           Ingestions.confirm_duplicate_candidate(duplicate_candidate, %{
             status: "auto_confirmed"
           }),
         :ok <- Broadcaster.broadcast_stage_complete(ingestion_in_review.id, :hash_and_dedup),
         :ok <- Broadcaster.broadcast_review_ready(ingestion_in_review.id) do
      {:ok, confirmed_ingestion}
    end
  end

  defp create_probable_duplicate_candidates(ingestion, candidates) do
    probable_matches = DuplicateDetection.probable_matches(ingestion, candidates)

    with {:ok, created_candidates} <- persist_probable_candidates(ingestion, probable_matches),
         {:ok, updated_ingestion} <-
           Ingestions.transition_source_ingestion_workflow(
             ingestion,
             :duplicate_review_requested
           ),
         :ok <- Broadcaster.broadcast_duplicate_review(ingestion.id, created_candidates) do
      {:ok, updated_ingestion}
    end
  end

  defp complete_without_match(ingestion) do
    with {:ok, updated_ingestion} <-
           Ingestions.transition_source_ingestion_workflow(
             ingestion,
             :hash_and_dedup_succeeded
           ),
         :ok <- Broadcaster.broadcast_stage_complete(ingestion.id, :hash_and_dedup) do
      {:ok, updated_ingestion}
    end
  end

  defp persist_probable_candidates(ingestion, matches) do
    Enum.reduce_while(matches, {:ok, []}, fn %{candidate: candidate, evidence: evidence},
                                             {:ok, acc} ->
      case create_or_reuse_candidate(ingestion, candidate, %{evidence: evidence}) do
        {:ok, duplicate_candidate} -> {:cont, {:ok, [duplicate_candidate | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, created_candidates} -> {:ok, Enum.reverse(created_candidates)}
      error -> error
    end
  end

  defp create_or_reuse_candidate(ingestion, candidate, attrs) do
    case Enum.find(
           Ingestions.list_duplicate_candidates(ingestion),
           &(&1.candidate_source_ingestion_id == candidate.id)
         ) do
      nil ->
        Ingestions.create_duplicate_candidate(ingestion, candidate, attrs)

      existing_candidate ->
        {:ok, existing_candidate}
    end
  end
end
