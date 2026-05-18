defmodule Gallformers.Repo.Migrations.AddNormalizedTextToSourceIngestions do
  use Ecto.Migration

  def change do
    alter table(:source_ingestions) do
      add :normalized_text, :text
    end
  end
end
