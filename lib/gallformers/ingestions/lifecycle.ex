defmodule Gallformers.Ingestions.Lifecycle do
  @moduledoc false

  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestion
  alias Gallformers.Repo
  alias Gallformers.Storage.SourceArtifacts

  @spec clear_source_ingestion(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t() | term()}
  def clear_source_ingestion(%SourceIngestion{} = source_ingestion) do
    do_clear_source_ingestion(source_ingestion)
  end

  def clear_source_ingestion(source_ingestion_id) when is_integer(source_ingestion_id) do
    source_ingestion_id
    |> Ingestions.get_source_ingestion!()
    |> do_clear_source_ingestion()
  end

  @spec source_ingestion_clearability(SourceIngestion.t() | integer()) ::
          :failed | :abandoned | nil
  def source_ingestion_clearability(%SourceIngestion{} = source_ingestion) do
    cond do
      source_ingestion.status == "failed" ->
        :failed

      abandoned_source_ingestion?(source_ingestion) ->
        :abandoned

      true ->
        nil
    end
  end

  def source_ingestion_clearability(source_ingestion_id) when is_integer(source_ingestion_id) do
    source_ingestion_id
    |> Ingestions.get_source_ingestion!()
    |> source_ingestion_clearability()
  end

  @spec delete_failed_source_ingestion(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t() | term()}
  def delete_failed_source_ingestion(source_ingestion) do
    case source_ingestion_clearability(source_ingestion) do
      :failed -> clear_source_ingestion(source_ingestion)
      _ -> {:error, clear_source_ingestion_changeset(source_ingestion)}
    end
  end

  @spec delete_source_ingestion(SourceIngestion.t() | integer()) ::
          {:ok, SourceIngestion.t()} | {:error, Ecto.Changeset.t() | term()}
  def delete_source_ingestion(%SourceIngestion{} = source_ingestion) do
    do_delete_source_ingestion(source_ingestion)
  end

  def delete_source_ingestion(source_ingestion_id) when is_integer(source_ingestion_id) do
    source_ingestion_id
    |> Ingestions.get_source_ingestion!()
    |> do_delete_source_ingestion()
  end

  defp do_clear_source_ingestion(%SourceIngestion{} = source_ingestion) do
    case source_ingestion_clearability(source_ingestion) do
      clearability when clearability in [:failed, :abandoned] ->
        do_delete_source_ingestion(source_ingestion)

      nil ->
        {:error, clear_source_ingestion_changeset(source_ingestion)}
    end
  end

  defp do_delete_source_ingestion(%SourceIngestion{} = source_ingestion) do
    with :ok <- SourceArtifacts.delete_private_artifacts_for_ingestion(source_ingestion.id) do
      Repo.delete(source_ingestion)
    end
  end

  defp clear_source_ingestion_changeset(%SourceIngestion{} = source_ingestion) do
    source_ingestion
    |> SourceIngestion.changeset(%{})
    |> Ecto.Changeset.add_error(:status, "only failed or abandoned ingestions can be cleared")
  end

  defp clear_source_ingestion_changeset(source_ingestion_id)
       when is_integer(source_ingestion_id) do
    source_ingestion_id
    |> Ingestions.get_source_ingestion!()
    |> clear_source_ingestion_changeset()
  end

  # With the Elixir pipeline removed, any ingestion still in "processing" is
  # by definition abandoned — nothing will advance it.
  defp abandoned_source_ingestion?(%SourceIngestion{status: "processing"}), do: true
  defp abandoned_source_ingestion?(%SourceIngestion{}), do: false
end
