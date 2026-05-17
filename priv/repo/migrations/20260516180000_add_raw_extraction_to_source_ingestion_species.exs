defmodule Gallformers.Repo.Migrations.AddRawExtractionToSourceIngestionSpecies do
  use Ecto.Migration

  def change do
    alter table(:source_ingestion_species) do
      add :raw_extraction, :map
    end
  end
end
