defmodule Gallformers.Repo.Migrations.AddEvidenceProseToSourceIngestionSpecies do
  use Ecto.Migration

  def change do
    alter table(:source_ingestion_species) do
      add :evidence_prose, :map
    end
  end
end
