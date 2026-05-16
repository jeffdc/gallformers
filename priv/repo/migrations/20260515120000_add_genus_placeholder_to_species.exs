defmodule Gallformers.Repo.Migrations.AddGenusPlaceholderToSpecies do
  use Ecto.Migration

  def change do
    alter table(:species) do
      add :genus_placeholder, :boolean, null: false, default: false
    end
  end
end
