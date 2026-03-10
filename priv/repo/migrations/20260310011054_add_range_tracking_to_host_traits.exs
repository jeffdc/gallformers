defmodule Gallformers.Repo.Migrations.AddRangeTrackingToHostTraits do
  use Gallformers.Migration

  def change do
    alter table(:host_traits) do
      add :range_confirmed, :boolean, default: false, null: false
      add :wcvp_synced_at, :utc_datetime, null: true
    end
  end
end
