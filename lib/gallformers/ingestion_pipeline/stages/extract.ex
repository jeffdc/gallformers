defmodule Gallformers.IngestionPipeline.Stages.Extract do
  @moduledoc """
  Extracts raw text from submitted source-ingestion inputs.
  """

  @behaviour Gallformers.IngestionPipeline.StageWorker

  require Logger

  alias Gallformers.IngestionPipeline.Stages.Extract.PythonExtractor
  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion

  @impl true
  def stage_name, do: :extract

  @impl true
  def perform_stage(%SourceIngestion{input_type: "pdf"} = ingestion) do
    temp_file_path = temp_file_path(ingestion)

    try do
      with {:ok, input_pdf} <- download_input_pdf(ingestion),
           :ok <- File.write(temp_file_path, input_pdf),
           {:ok, result} <- extractor().extract_text(temp_file_path, ocr_fallback: false),
           {:ok, _artifact_path} <-
             Storage.upload_artifact(
               ingestion.id,
               :extract,
               "text.txt",
               result.text,
               "text/plain"
             ),
           {:ok, updated_ingestion} <-
             Ingestions.transition_source_ingestion_workflow(ingestion, :extract_succeeded) do
        Logger.info(
          "Extracted ingestion #{ingestion.id}: #{result.page_count} pages, #{String.length(result.text)} chars"
        )

        {:ok, updated_ingestion}
      end
    after
      cleanup_temp_file(temp_file_path)
    end
  end

  def perform_stage(%SourceIngestion{input_type: "text"} = ingestion) do
    with {:ok, text} <- Storage.download_artifact(ingestion.id, :input, "source.txt"),
         {:ok, _artifact_path} <-
           Storage.upload_artifact(ingestion.id, :extract, "text.txt", text, "text/plain") do
      Ingestions.transition_source_ingestion_workflow(ingestion, :extract_succeeded)
    end
  end

  def perform_stage(%SourceIngestion{input_type: "url"} = ingestion) do
    with {:ok, url} <- Storage.download_artifact(ingestion.id, :input, "source.url"),
         {:ok, %{text: text}} <- url_extractor().extract_text(url),
         {:ok, _artifact_path} <-
           Storage.upload_artifact(ingestion.id, :extract, "text.txt", text, "text/plain") do
      Ingestions.transition_source_ingestion_workflow(ingestion, :extract_succeeded)
    end
  end

  def perform_stage(%SourceIngestion{}), do: {:error, :unsupported_input_type}

  defp download_input_pdf(%SourceIngestion{id: ingestion_id}) do
    Storage.download_artifact(ingestion_id, :input, "source.pdf")
  end

  defp temp_file_path(%SourceIngestion{id: ingestion_id}) do
    Path.join(
      System.tmp_dir!(),
      "source-ingestion-#{ingestion_id}-#{System.unique_integer([:positive])}.pdf"
    )
  end

  defp cleanup_temp_file(temp_file_path) do
    File.rm(temp_file_path)
    :ok
  end

  defp extractor do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:extractor, PythonExtractor)
  end

  defp url_extractor do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(
      :url_extractor,
      Gallformers.IngestionPipeline.Stages.Extract.ReqURLExtractor
    )
  end
end
