defmodule Gallformers.Repo.Migrations.AddGallformersCodeToGallTraits do
  use Gallformers.Migration

  def change do
    alter table(:gall_traits) do
      add :gallformers_code, :string
    end

    create unique_index(:gall_traits, [:gallformers_code],
      where: "gallformers_code IS NOT NULL",
      name: :gall_traits_gallformers_code_unique
    )
  end
end
