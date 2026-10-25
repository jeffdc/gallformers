defmodule Gallformers.Repo.Migrations.InstallCarbonite do
  @moduledoc """
  Installs Carbonite's audit trail in its own schema, `carbonite_default`
  (matter `ede2`). No table is tracked here: each new table declares its
  tracking with `Gallformers.Audit.Migration.track_table/2` in the migration
  that creates it.

  Carbonite already rejects a write to a tracked table when its database
  transaction has no audit record. The check constraint added here also
  rejects an audit record that does not name an actor and an operation, so an
  empty record cannot stand in for attribution.
  """
  use Ecto.Migration

  def up do
    Carbonite.Migrations.up(1..12)

    # A CHECK whose expression is NULL passes, and a missing key makes these
    # comparisons NULL, hence the COALESCE.
    execute("""
    ALTER TABLE carbonite_default.transactions
      ADD CONSTRAINT transactions_meta_attribution CHECK (
        COALESCE(
          jsonb_typeof(meta -> 'actor') = 'object'
          AND jsonb_typeof(meta -> 'actor' -> 'type') = 'string'
          AND jsonb_typeof(meta -> 'actor' -> 'name') = 'string'
          AND jsonb_typeof(meta -> 'operation') = 'string'
          AND meta ->> 'operation' <> '',
          false
        )
      )
    """)
  end

  def down do
    execute(
      "ALTER TABLE carbonite_default.transactions DROP CONSTRAINT transactions_meta_attribution"
    )

    Carbonite.Migrations.down(12..1//-1)
  end
end
