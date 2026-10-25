defmodule Gallformers.Repo.Migrations.AddTypedImageRefs do
  @moduledoc """
  Gives `image` its typed reference (`9449` §1 "Kept, re-keyed"; Task 16):
  a Gall (`gall_id`) or a taxon (`taxon_id`), at most one, beside
  `species_id`, which today's code still reads and writes. Paths are
  unchanged.

  The catalog data migration fills them: an image of a gall row gets its
  Gall (same ID), an image of a plant its taxon (same ID), an image of a
  genus placeholder plant its genus taxon. Images added by today's code
  after the migration have no typed reference until it runs again (it
  always runs from a fresh production copy at cutover). When today's code
  goes, `species_id` is dropped and exactly one typed reference required.

  `image` is not audited: it is kept as it is, re-keyed.
  """
  use Ecto.Migration

  def change do
    alter table(:image) do
      add :gall_id, references(:galls, type: :bigint, on_delete: :nilify_all)
      add :taxon_id, references(:taxa, type: :bigint, on_delete: :nilify_all)
    end

    create constraint(:image, :image_one_typed_ref, check: "gall_id IS NULL OR taxon_id IS NULL")
    create index(:image, [:gall_id], where: "gall_id IS NOT NULL")
    create index(:image, [:taxon_id], where: "taxon_id IS NOT NULL")
  end
end
