defmodule Gallformers.Repo.Migrations.AllowImageWithoutSpecies do
  @moduledoc """
  New images belong to a Gall or a taxon by their typed reference
  (`image.gall_id` / `image.taxon_id`, `20261025000600_add_typed_image_refs`)
  and carry no `species_id` (matter a856, Task 5), so the column becomes
  nullable. `Images` requires exactly one typed reference on every write;
  the database keeps only `image_one_typed_ref` (at most one) until the
  rows left on excluded non-galls are gone and `species_id` is dropped.
  """
  use Ecto.Migration

  def up do
    execute "ALTER TABLE image ALTER COLUMN species_id DROP NOT NULL"
  end

  def down do
    execute "ALTER TABLE image ALTER COLUMN species_id SET NOT NULL"
  end
end
