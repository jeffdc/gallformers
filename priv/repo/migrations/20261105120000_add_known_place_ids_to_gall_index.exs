defmodule Gallformers.Repo.Migrations.AddKnownPlaceIdsToGallIndex do
  @moduledoc """
  Adds `known_place_ids` to `gall_index`: the leaf places where a Gall is
  known to occur (`Gallformers.Catalog.ReadModels.PotentialRange.known_for_galls/1`):
  its potential range's places that a Host gives natively, plus introduced
  ones in a country where the Gall is recorded. Empty for a Gall with no
  range data. Browse by place and the place page count it (matter bc0d).
  Filled by the next rebuild (`GallIndex.rebuild_all/0`).
  """
  use Ecto.Migration

  def change do
    alter table(:gall_index) do
      add :known_place_ids, {:array, :bigint}, null: false, default: []
    end

    create index(:gall_index, [:known_place_ids], using: :gin)
  end
end
