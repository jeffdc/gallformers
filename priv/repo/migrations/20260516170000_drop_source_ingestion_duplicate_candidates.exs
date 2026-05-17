defmodule Gallformers.Repo.Migrations.DropSourceIngestionDuplicateCandidates do
  use Ecto.Migration

  def change do
    drop table(:source_ingestion_duplicate_candidates)
  end
end
