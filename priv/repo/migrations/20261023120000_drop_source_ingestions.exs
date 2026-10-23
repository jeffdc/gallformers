defmodule Gallformers.Repo.Migrations.DropSourceIngestions do
  @moduledoc """
  Drops the tables of the retired source-ingestion system (matter 47ae).

  All three tables were empty in production when this was written, and the
  daily full backups hold them up to this point.

  `down/0` is a no-op: the code that used these tables is gone, so recreating
  them would serve no purpose. The original definitions are in
  `20260421123000_add_source_ingestions.exs`.
  """
  use Ecto.Migration

  def up do
    drop table(:source_ingestion_species)
    drop table(:source_ingestion_duplicate_candidates)
    drop table(:source_ingestions)
  end

  def down, do: :ok
end
