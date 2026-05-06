defmodule Gallformers.Repo.Migrations.AddPipelineConfigs do
  use Ecto.Migration

  def change do
    create table(:pipeline_configs) do
      add :name, :string, null: false
      add :config, :jsonb, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pipeline_configs, [:name])

    alter table(:source_ingestions) do
      add :pipeline_config_id, references(:pipeline_configs, on_delete: :nilify_all)
    end
  end
end
