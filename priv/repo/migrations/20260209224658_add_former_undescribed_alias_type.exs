defmodule Gallformers.Repo.Migrations.AddFormerUndescribedAliasType do
  use Gallformers.Migration

  def up do
    execute("PRAGMA writable_schema = ON")

    execute("""
    UPDATE sqlite_master
    SET sql = REPLACE(
      sql,
      'CHECK (type = ''common'' OR type = ''scientific'')',
      'CHECK (type = ''common'' OR type = ''scientific'' OR type = ''former_undescribed'')'
    )
    WHERE type = 'table' AND name = 'alias'
    """)

    execute("PRAGMA writable_schema = OFF")
    execute("PRAGMA integrity_check")
  end

  def down do
    execute("PRAGMA writable_schema = ON")

    execute("""
    UPDATE sqlite_master
    SET sql = REPLACE(
      sql,
      'CHECK (type = ''common'' OR type = ''scientific'' OR type = ''former_undescribed'')',
      'CHECK (type = ''common'' OR type = ''scientific'')'
    )
    WHERE type = 'table' AND name = 'alias'
    """)

    execute("PRAGMA writable_schema = OFF")
    execute("PRAGMA integrity_check")
  end
end
