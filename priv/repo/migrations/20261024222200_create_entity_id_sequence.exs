defmodule Gallformers.Repo.Migrations.CreateEntityIdSequence do
  @moduledoc """
  Creates `entity_id_seq`, the one ID sequence shared by Galls and taxa
  (`9449` §1, `8567` rule 4). It continues today's species IDs: Galls and
  plant taxa keep their species IDs, so new rows start above the highest one.

  The catalog data migration sets it again after filling the new tables.
  """
  use Ecto.Migration

  def up do
    execute("CREATE SEQUENCE entity_id_seq AS bigint")

    # is_called = false: the next nextval returns exactly this value.
    execute("""
    SELECT setval('entity_id_seq', COALESCE((SELECT MAX(id) FROM species), 0) + 1, false)
    """)
  end

  def down do
    execute("DROP SEQUENCE entity_id_seq")
  end
end
