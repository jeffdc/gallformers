defmodule Gallformers.IngestionPipeline.PipelineConfigs do
  @moduledoc false

  import Ecto.Query

  alias Gallformers.IngestionPipeline.PipelineConfig
  alias Gallformers.Repo

  @spec list_pipeline_configs() :: [PipelineConfig.t()]
  def list_pipeline_configs do
    PipelineConfig
    |> order_by(:name)
    |> Repo.all()
  end

  @spec get_pipeline_config!(integer()) :: PipelineConfig.t()
  def get_pipeline_config!(id), do: Repo.get!(PipelineConfig, id)

  @spec create_pipeline_config(map()) :: {:ok, PipelineConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_pipeline_config(attrs) do
    %PipelineConfig{}
    |> PipelineConfig.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_pipeline_config(PipelineConfig.t(), map()) ::
          {:ok, PipelineConfig.t()} | {:error, Ecto.Changeset.t()}
  def update_pipeline_config(%PipelineConfig{} = pipeline_config, attrs) do
    pipeline_config
    |> PipelineConfig.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_pipeline_config(PipelineConfig.t()) ::
          {:ok, PipelineConfig.t()} | {:error, Ecto.Changeset.t()}
  def delete_pipeline_config(%PipelineConfig{} = pipeline_config) do
    Repo.delete(pipeline_config)
  end

  @spec change_pipeline_config(PipelineConfig.t(), map()) :: Ecto.Changeset.t()
  def change_pipeline_config(%PipelineConfig{} = pipeline_config, attrs \\ %{}) do
    PipelineConfig.changeset(pipeline_config, attrs)
  end

  @spec config_options() :: [{integer(), String.t()}]
  def config_options do
    PipelineConfig
    |> order_by(:name)
    |> select([c], {c.id, c.name})
    |> Repo.all()
  end
end
