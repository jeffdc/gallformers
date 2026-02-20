defmodule Gallformers.Repo.Migrations.CreateHostTraits do
  use Gallformers.Migration

  def change do
    create table(:host_traits, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), primary_key: true
      add :wcvp_id, :string
      add :powo_id, :string
    end

    create index(:host_traits, [:wcvp_id])
    create index(:host_traits, [:powo_id])
  end
end
