defmodule Gallformers.Repo.Migrations.CreateNonGallRedirects do
  @moduledoc """
  Creates `non_gall_redirects` (`803b` Task 12), owned by
  `Gallformers.Catalog`: the old gall `species` IDs excluded as non-galls
  (`priv/catalog_migration/non_galls.csv`) with their old names. Their old
  `/gall/:id` URLs redirect (301) to the gall-lookalikes Article. Filled
  only by the data migration; audited, as every new table is.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  def up do
    create table(:non_gall_redirects, primary_key: false) do
      add :species_id, :bigint, primary_key: true
      add :name, :text, null: false
    end

    Audit.track_table("non_gall_redirects", primary_key_columns: ["species_id"])
  end

  def down do
    Audit.untrack_table("non_gall_redirects")
    drop table(:non_gall_redirects)
  end
end
