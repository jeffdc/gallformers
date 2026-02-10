defmodule Gallformers.Repo.Migrations.AddFormerUndescribedAliasType do
  use Gallformers.Migration

  def up do
    safe_recreate_table :alias do
      execute("""
      CREATE TABLE alias_new (
        id INTEGER PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type = 'common' OR type = 'scientific' OR type = 'former_undescribed'),
        description TEXT NOT NULL DEFAULT '',
        inserted_at TEXT,
        updated_at TEXT
      )
      """)

      execute("INSERT INTO alias_new SELECT * FROM alias")
      execute("DROP TABLE alias")
      execute("ALTER TABLE alias_new RENAME TO alias")
    end
  end

  def down do
    safe_recreate_table :alias do
      execute("""
      CREATE TABLE alias_new (
        id INTEGER PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type = 'common' OR type = 'scientific'),
        description TEXT NOT NULL DEFAULT '',
        inserted_at TEXT,
        updated_at TEXT
      )
      """)

      execute("INSERT INTO alias_new SELECT * FROM alias WHERE type != 'former_undescribed'")
      execute("DROP TABLE alias")
      execute("ALTER TABLE alias_new RENAME TO alias")
    end
  end
end
