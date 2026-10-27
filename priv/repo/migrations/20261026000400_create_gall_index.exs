defmodule Gallformers.Repo.Migrations.CreateGallIndex do
  @moduledoc """
  Creates `gall_index`, the ID tool's stored per-Gall lookup table (`803b`
  §3, Task 8), owned by `Gallformers.Catalog.ReadModels.GallIndex`: one row
  per Gall with what the ID tool filters on, computed from current Facts
  and `Gallformers.Taxa`. A read model, refreshed by an Oban job when a
  Gall's Facts or its taxa change and rebuilt by the catalog data
  migration, so it is not audited.

    * `inducer_taxon_id` — the current Inducer; `inducer_ancestor_ids` the
      Inducers and every taxon above them (the Inducer family filter).
    * `host_taxon_ids` — the current Hosts; `host_ancestor_ids` the Hosts
      and every taxon above them (the Host genus / section filter).
    * `trait_value_ids` — the current Trait values; `detachable` the
      current detachable value.
    * `undescribed` — no current Inducer at species rank or below.
    * `image_id` — the default image.
    * `place_ids` — the leaf places of the potential range; empty with
      `everywhere` when the range is every region.
  """
  use Ecto.Migration

  def change do
    create table(:gall_index, primary_key: false) do
      add :gall_id, references(:galls, type: :bigint, on_delete: :delete_all), primary_key: true
      add :name, :text, null: false
      add :inducer_taxon_id, :bigint
      add :inducer_ancestor_ids, {:array, :bigint}, null: false, default: []
      add :host_taxon_ids, {:array, :bigint}, null: false, default: []
      add :host_ancestor_ids, {:array, :bigint}, null: false, default: []
      add :trait_value_ids, {:array, :bigint}, null: false, default: []
      add :detachable, :text
      add :undescribed, :boolean, null: false
      add :image_id, references(:image, type: :bigint, on_delete: :nilify_all)
      add :place_ids, {:array, :bigint}, null: false, default: []
      add :everywhere, :boolean, null: false
      add :refreshed_at, :utc_datetime, null: false
    end

    for column <- ~w(inducer_ancestor_ids host_taxon_ids host_ancestor_ids trait_value_ids place_ids)a do
      create index(:gall_index, [column], using: :gin)
    end

    create index(:gall_index, [:image_id])
  end
end
