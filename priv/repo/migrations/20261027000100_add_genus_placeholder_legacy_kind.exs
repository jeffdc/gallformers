defmodule Gallformers.Repo.Migrations.AddGenusPlaceholderLegacyKind do
  @moduledoc """
  Adds the `genus_placeholder` kind to `legacy_taxon_ids` (`803b` Task 12):
  `legacy_id` is an old genus placeholder plant's `species.id` ("Quercus
  spp"), mapped to its genus taxon. Placeholders become no taxon, so their
  old `/host/:id` URLs redirect (301) to the genus page through it. Written
  by the catalog data migration, which rebuilds the table on every run.
  """
  use Ecto.Migration

  def up do
    drop constraint(:legacy_taxon_ids, :legacy_taxon_ids_kind_check)

    create constraint(:legacy_taxon_ids, :legacy_taxon_ids_kind_check,
             check: "kind IN ('taxonomy', 'gall_inducer', 'genus_placeholder')"
           )
  end

  def down do
    # `legacy_taxon_ids` is audited: the delete needs a recorded transaction.
    Carbonite.Migrations.insert_migration_transaction("drop_genus_placeholder_legacy_kind")
    execute("DELETE FROM legacy_taxon_ids WHERE kind = 'genus_placeholder'")

    drop constraint(:legacy_taxon_ids, :legacy_taxon_ids_kind_check)

    create constraint(:legacy_taxon_ids, :legacy_taxon_ids_kind_check,
             check: "kind IN ('taxonomy', 'gall_inducer')"
           )
  end
end
