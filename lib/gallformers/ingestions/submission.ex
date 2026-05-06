defmodule Gallformers.Ingestions.Submission do
  @moduledoc false

  require Logger

  alias Gallformers.IngestionPipeline.Storage
  alias Gallformers.Ingestions.{SourceIngestion, SourceIngestionCreation}
  alias Gallformers.Utils

  @doc """
  Creates a persisted ingestion, uploads its initial input artifact, and
  enqueues the pipeline worker.
  """
  @spec submit_source_ingestion(map()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t() | term()}
  def submit_source_ingestion(attrs) do
    attrs = Map.new(attrs)

    with :ok <- validate_submission_attrs(attrs),
         {:ok, source_ingestion} <- create_submission_record(attrs),
         {:ok, _artifact_path} <- upload_submission_artifact(source_ingestion, attrs),
         {:ok, _job} <- enqueue_submission_worker(source_ingestion) do
      {:ok, source_ingestion}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:submission_error, source_ingestion, reason} ->
        cleanup_submission_artifacts(source_ingestion.id)
        {:error, reason}
    end
  end

  defp validate_submission_attrs(attrs) do
    changeset =
      {%{}, submission_types()}
      |> Ecto.Changeset.cast(attrs, Map.keys(submission_types()))
      |> Ecto.Changeset.validate_required([:input_type, :uploaded_by_id])
      |> Ecto.Changeset.validate_inclusion(:input_type, ~w(pdf url text))
      |> validate_submission_fields()

    if changeset.valid? do
      :ok
    else
      {:error, changeset}
    end
  end

  defp validate_submission_fields(changeset) do
    case Ecto.Changeset.get_field(changeset, :input_type) do
      "pdf" ->
        changeset
        |> Ecto.Changeset.validate_required([:filename, :content])
        |> validate_non_blank(:filename)

      "url" ->
        changeset
        |> Ecto.Changeset.validate_required([:url])
        |> validate_non_blank(:url)

      "text" ->
        changeset
        |> Ecto.Changeset.validate_required([:text])
        |> validate_non_blank(:text)

      _ ->
        changeset
    end
  end

  defp validate_non_blank(changeset, field) do
    Ecto.Changeset.validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and String.trim(value) == "" do
        [{field, "can't be blank"}]
      else
        []
      end
    end)
  end

  defp create_submission_record(attrs) do
    creation_attrs = %{
      input_type: Utils.attr_value(attrs, :input_type),
      uploaded_by_id: Utils.attr_value(attrs, :uploaded_by_id)
    }

    creation_attrs =
      case Utils.attr_value(attrs, :pipeline_config_id) do
        nil -> creation_attrs
        "" -> creation_attrs
        id -> Map.put(creation_attrs, :pipeline_config_id, id)
      end

    SourceIngestionCreation.create_source_ingestion(creation_attrs)
  end

  defp upload_submission_artifact(source_ingestion, attrs) do
    {filename, content, content_type} = submission_artifact_spec(attrs)

    case Storage.upload_artifact(source_ingestion.id, :input, filename, content, content_type) do
      {:ok, artifact_path} -> {:ok, artifact_path}
      {:error, reason} -> {:submission_error, source_ingestion, reason}
    end
  end

  defp enqueue_submission_worker(source_ingestion) do
    case worker_module().enqueue(source_ingestion.id) do
      {:ok, job} -> {:ok, job}
      {:error, reason} -> {:submission_error, source_ingestion, reason}
    end
  end

  defp worker_module do
    :gallformers
    |> Application.get_env(Gallformers.Ingestions, [])
    |> Keyword.get(:worker_module, default_worker_module())
  end

  defp default_worker_module do
    Module.concat([Gallformers.IngestionPipeline, Worker])
  end

  defp submission_types do
    %{
      input_type: :string,
      uploaded_by_id: :integer,
      pipeline_config_id: :integer,
      filename: :string,
      content: :binary,
      url: :string,
      text: :string
    }
  end

  defp submission_artifact_spec(attrs) do
    case Utils.attr_value(attrs, :input_type) do
      "pdf" -> {"source.pdf", Utils.attr_value(attrs, :content), "application/pdf"}
      "url" -> {"source.url", Utils.attr_value(attrs, :url), "text/plain"}
      "text" -> {"source.txt", Utils.attr_value(attrs, :text), "text/plain"}
    end
  end

  defp cleanup_submission_artifacts(ingestion_id) do
    case Storage.delete_artifacts_for_ingestion(ingestion_id) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to clean up source ingestion artifacts after submission error",
          ingestion_id: ingestion_id,
          reason: inspect(reason)
        )

        :ok
    end
  end
end
