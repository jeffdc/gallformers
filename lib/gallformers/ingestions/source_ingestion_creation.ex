defmodule Gallformers.Ingestions.SourceIngestionCreation do
  @moduledoc false

  alias Gallformers.Ingestions.SourceIngestion
  alias Gallformers.Repo
  alias Gallformers.Storage.SourceArtifacts

  @spec create_source_ingestion(map()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t()}
  def create_source_ingestion(attrs \\ %{}) do
    Repo.transaction(fn ->
      attrs = Map.new(attrs)

      source_ingestion =
        %SourceIngestion{}
        |> SourceIngestion.changeset(attrs)
        |> insert_or_rollback()

      maybe_put_canonical_artifacts_path(source_ingestion)
    end)
  end

  defp maybe_put_canonical_artifacts_path(%SourceIngestion{} = source_ingestion) do
    if blank_artifacts_path?(source_ingestion.artifacts_path) do
      source_ingestion
      |> SourceIngestion.changeset(%{
        artifacts_path: SourceArtifacts.private_artifact_prefix(source_ingestion.id)
      })
      |> update_or_rollback()
    else
      source_ingestion
    end
  end

  defp blank_artifacts_path?(artifacts_path), do: artifacts_path in [nil, ""]

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
