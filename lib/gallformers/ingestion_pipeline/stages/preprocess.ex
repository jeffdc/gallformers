defmodule Gallformers.IngestionPipeline.Stages.Preprocess do
  @moduledoc """
  Deterministically preprocesses extracted text and persists duplicate signals.
  """

  @behaviour Gallformers.IngestionPipeline.StageWorker

  require Logger

  alias Gallformers.IngestionPipeline.DuplicateSignals
  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion

  # The heuristics are applied in the order they are listed here.
  @heuristics [
    Gallformers.IngestionPipeline.Heuristics.StripBHLBoilerplate,
    Gallformers.IngestionPipeline.Heuristics.StripPlatePages,
    Gallformers.IngestionPipeline.Heuristics.StripPageHeaders,
    Gallformers.IngestionPipeline.Heuristics.RejoinHyphenated,
    Gallformers.IngestionPipeline.Heuristics.RejoinLines
  ]

  @impl true
  def stage_name, do: :preprocess

  @impl true
  def perform_stage(%SourceIngestion{} = ingestion) do
    Logger.info("Starting preprocess stage", ingestion_id: ingestion.id)

    with {:ok, extracted_text} <- Storage.download_artifact(ingestion.id, :extract, "text.txt"),
         cleaned_text <- run_heuristics(extracted_text),
         sniffed <- cheap_sniff(cleaned_text),
         sha256 <- compute_sha256(cleaned_text),
         {:ok, _updated_signals} <-
           Ingestions.record_duplicate_signals(ingestion, signal_attrs(sniffed, sha256)),
         {:ok, _artifact_path} <-
           Storage.upload_artifact(
             ingestion.id,
             :preprocess,
             "text.txt",
             cleaned_text,
             "text/plain"
           ),
         {:ok, updated_ingestion} <-
           Ingestions.transition_source_ingestion_workflow(ingestion, :preprocess_succeeded) do
      Logger.info(
        "Preprocess stage completed",
        ingestion_id: ingestion.id,
        text_length: String.length(extracted_text)
      )

      {:ok, updated_ingestion}
    else
      {:error, reason} ->
        Logger.warning(
          "Preprocess stage failed",
          ingestion_id: ingestion.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  rescue
    exception ->
      Logger.error(
        "Preprocess stage failed",
        ingestion_id: ingestion.id,
        error: Exception.message(exception),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      reraise exception, __STACKTRACE__
  end

  defp run_heuristics(text) do
    @heuristics
    |> Enum.reduce(text, fn heuristic, text ->
      heuristic.apply(text)
    end)
    |> String.trim()
  end

  defp cheap_sniff(text) when is_binary(text) do
    doi_regex = ~r/10\.\d{4,}\/[^\s]+/i

    doi =
      text
      |> String.slice(0, 2000)
      |> then(&Regex.run(doi_regex, &1))
      |> case do
        [match | _] -> normalize_sniffed_doi(match)
        _ -> nil
      end

    start_text = String.slice(text, 0, 1000)

    year =
      case Regex.run(~r/\b(18|19|20)\d{2}\b/, start_text) do
        [match | _] -> String.to_integer(match)
        _ -> nil
      end

    title =
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.find(fn line ->
        String.length(line) >= 20 and
          not Gallformers.Utilities.all_caps?(line) and
          not Regex.match?(~r/^\d+$/, line) and
          not Regex.match?(doi_regex, line)
      end)

    authors =
      (Regex.scan(~r/\b[A-Z][a-z]+,[ ]+(?:[A-Z]\.[ ]*){1,3}/, start_text) ++
         Regex.scan(~r/\b(?:[A-Z]\.[ ]*){1,3}[ ]+[A-Z][a-z]+\b/, start_text))
      |> List.flatten()
      |> Enum.map(&String.trim/1)
      |> Enum.uniq()

    %{doi: doi, title: title, authors: authors, year: year}
  end

  defp normalize_sniffed_doi(doi) do
    doi
    |> String.downcase()
    |> String.trim()
    |> String.trim_trailing(".")
    |> String.trim_trailing(",")
    |> String.trim_trailing(";")
    |> String.trim_trailing(":")
    |> String.trim_trailing(")")
  end

  defp compute_sha256(text) when is_binary(text) do
    :sha256
    |> :crypto.hash(text)
    |> Base.encode16(case: :lower)
  end

  defp signal_attrs(sniffed, sha256) do
    DuplicateSignals.signal_attrs(
      %{
        doi: sniffed.doi,
        title: sniffed.title,
        authors: sniffed.authors,
        year: sniffed.year
      },
      %{preprocessed_text_sha256: sha256}
    )
  end
end
