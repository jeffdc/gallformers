defmodule Gallformers.Repo.Migrations.ExtendTaxonActFacts do
  @moduledoc """
  The taxonomic-act Facts' gaps before they drive the tree (matter `f923`
  Task 2):

    * `placement_facts.parent_id` may be null: a taxon placed at the root
      of the tree (today's tree has roots at kingdom and family rank). The
      natural key stays taxon + parent, with "at the root" one value
      (`COALESCE(parent_id, 0)`; IDs start at 1).
    * `name_facts` gain `sensu` (a name in a Source's sense, as written)
      and `authorship` (the form first recorded), with
      `normalized_authorship` (`Gallformers.Taxa.NameNormalizer.normalize_authorship/1`;
      `''` when there is none). Both join the natural key: taxon +
      normalized name + rank + sensu (ignoring case) + normalized
      authorship.
  """
  use Ecto.Migration

  def up do
    execute "ALTER TABLE placement_facts ALTER COLUMN parent_id DROP NOT NULL"

    drop index(:placement_facts, [:taxon_id, :parent_id])

    execute """
    CREATE UNIQUE INDEX placement_facts_natural_key_index
    ON placement_facts (taxon_id, COALESCE(parent_id, 0))
    """

    alter table(:name_facts) do
      add :sensu, :text
      add :authorship, :text
      add :normalized_authorship, :text, null: false, default: ""
    end

    drop index(:name_facts, [:taxon_id, :normalized_name, :rank])

    execute """
    CREATE UNIQUE INDEX name_facts_natural_key_index
    ON name_facts (taxon_id, normalized_name, rank, lower(COALESCE(sensu, '')), normalized_authorship)
    """
  end

  def down do
    Carbonite.Migrations.insert_migration_transaction("narrow_taxon_act_facts")

    execute "DROP INDEX name_facts_natural_key_index"

    alter table(:name_facts) do
      remove :normalized_authorship
      remove :authorship
      remove :sensu
    end

    create unique_index(:name_facts, [:taxon_id, :normalized_name, :rank])

    execute "DROP INDEX placement_facts_natural_key_index"
    create unique_index(:placement_facts, [:taxon_id, :parent_id])

    execute "DELETE FROM placement_facts WHERE parent_id IS NULL"
    execute "ALTER TABLE placement_facts ALTER COLUMN parent_id SET NOT NULL"
  end
end
