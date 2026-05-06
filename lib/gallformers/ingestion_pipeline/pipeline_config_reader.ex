defmodule Gallformers.IngestionPipeline.PipelineConfigReader do
  @moduledoc false

  alias Gallformers.IngestionPipeline.PipelineConfig
  alias Gallformers.Ingestions.SourceIngestion
  alias Gallformers.Repo

  @spec load(SourceIngestion.t()) :: map() | nil
  def load(%SourceIngestion{pipeline_config_id: nil}), do: nil

  def load(%SourceIngestion{pipeline_config_id: id}) when is_integer(id) do
    case Repo.get(PipelineConfig, id) do
      %PipelineConfig{config: config} -> config
      nil -> nil
    end
  end

  @spec get(SourceIngestion.t(), atom(), atom(), term()) :: term()
  def get(%SourceIngestion{pipeline_config_id: nil}, _section, _key, default), do: default

  def get(%SourceIngestion{} = ingestion, section, key, default) do
    case load(ingestion) do
      nil ->
        default

      config when is_map(config) ->
        config
        |> Map.get(to_string(section), %{})
        |> Map.get(to_string(key), default)
    end
  end
end
