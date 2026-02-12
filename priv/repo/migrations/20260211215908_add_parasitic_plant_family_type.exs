defmodule Gallformers.Repo.Migrations.AddParasiticPlantFamilyType do
  use Gallformers.Migration

  def up do
    execute("""
    UPDATE taxonomy
    SET description = 'Plant (gall forming)'
    WHERE type = 'family' AND description = 'Plant'
      AND name LIKE '%(gall)%'
    """)
  end

  def down do
    execute("""
    UPDATE taxonomy
    SET description = 'Plant'
    WHERE type = 'family' AND description = 'Plant (gall forming)'
    """)
  end
end
