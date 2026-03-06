defmodule Gallformers.Repo.Migrations.AddDistributionTypeToHostRange do
  use Gallformers.Migration

  def change do
    alter table(:host_range) do
      add :distribution_type, :string, null: false, default: "native"
    end

    # SQLite doesn't support ALTER TABLE ADD CHECK, but the Ecto schema
    # validates at the application level via validate_inclusion
  end
end
