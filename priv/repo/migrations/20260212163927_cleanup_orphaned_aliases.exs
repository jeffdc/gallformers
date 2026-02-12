defmodule Gallformers.Repo.Migrations.CleanupOrphanedAliases do
  use Gallformers.Migration

  def up do
    # Delete alias records that have no alias_species link.
    # Currently 2 orphans: "Bud Gall Wasp (unisexual generation)" and "Fake plastic tree".
    # Root cause: species deletion CASCADEs alias_species rows but leaves alias records.
    # The application code is being fixed to prevent future orphans.
    execute("""
    DELETE FROM alias
    WHERE id NOT IN (SELECT alias_id FROM alias_species)
    """)
  end

  def down do
    # Orphaned aliases cannot be restored — they had no species links.
    :ok
  end
end
