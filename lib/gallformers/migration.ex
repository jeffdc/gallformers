defmodule Gallformers.Migration do
  @moduledoc """
  Safe migration module for SQLite.

  Use this instead of `Ecto.Migration` to ensure foreign key constraints
  don't cause silent data loss during table recreation.

  ## The Problem (three interacting constraints)

  Modifying constraints, foreign keys, or NOT NULL columns in SQLite requires
  recreating the table entirely (CREATE new → INSERT INTO new → DROP old →
  RENAME new). This interacts badly with Ecto + exqlite in three ways:

  ### 1. CASCADE foreign keys cause data loss on DROP TABLE

  If the table being dropped is referenced by other tables with
  `ON DELETE CASCADE`, SQLite performs an implicit `DELETE FROM` before
  dropping. This silently destroys all referencing rows. The fix is
  `PRAGMA foreign_keys = OFF`, but this pragma is **ignored inside
  transactions** — and Ecto wraps migrations in transactions by default.

  Setting `@disable_ddl_transaction true` fixes this, but introduces
  problem #2.

  ### 2. Connection pool dispatches statements to different connections

  With `@disable_ddl_transaction true`, the migration runner does NOT
  hold a single database connection. Each `execute/1` call goes through
  `Ecto.Adapters.SQL.sql_call/5`, which calls `get_conn_or_pool/2`. Without
  a checked-out connection in the process dictionary, this returns the pool,
  and DBConnection checks out a fresh connection for each statement.

  With pool_size > 1, this means:
  - `execute("DROP TABLE alias")` runs on connection A
  - `execute("ALTER TABLE alias_new RENAME TO alias")` runs on connection B
  - Connection B doesn't see the DROP, fails with "already exists"

  ### 3. Multi-statement strings are silently truncated

  You might think `execute("DROP TABLE x; ALTER TABLE y RENAME TO x")` would
  work. It doesn't. exqlite wraps SQLite's C API `sqlite3_prepare_v2()`, which
  **only parses and prepares the first statement** in a multi-statement string.
  Everything after the first semicolon is silently discarded. No error is raised.
  The migration appears to succeed but only the first statement executed.

  ## The Solution

  This module addresses all three constraints:

  1. Sets `@disable_ddl_transaction true` so PRAGMAs take effect.
  2. Provides `safe_recreate_table/2` which uses `Repo.checkout/1` to pin
     all statements to a single pooled connection for the duration.
  3. Calls `Ecto.Migration.Runner.flush/0` inside the checkout block to
     force immediate execution of all queued statements while the connection
     is still pinned.

  The `Runner.flush/0` call is critical and non-obvious. Ecto's migration
  runner **queues** `execute/1` calls during `up/0` and only flushes them
  **after** `up/0` returns (see `Runner.perform_operation/3`). Without the
  explicit flush, all statements would execute after the `Repo.checkout`
  block has released the connection — defeating the purpose entirely.

  **This is the only combination that works.** We investigated and ruled out:
  - Multi-statement `execute` strings (silently truncated by sqlite3_prepare_v2)
  - Separate `execute` calls without checkout (connection pool dispatching)
  - `Repo.checkout` without `Runner.flush()` (statements execute after release)
  - `Repo.transaction` (PRAGMAs ignored inside transactions)

  ## Usage

      defmodule Gallformers.Repo.Migrations.MyMigration do
        use Gallformers.Migration  # NOT Ecto.Migration

        def up do
          # Your migration code
        end
      end

  ## Table Recreation

  When changing constraints in SQLite, you must recreate the table using
  `safe_recreate_table/2`. This pins all statements to a single connection,
  disables foreign keys for the duration, and verifies FK integrity afterward.

      def up do
        safe_recreate_table :users do
          execute "CREATE TABLE users_new (...)"
          execute "INSERT INTO users_new SELECT * FROM users"
          execute "DROP TABLE users"
          execute "ALTER TABLE users_new RENAME TO users"
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Migration

      # Disabling DDL transactions is required so that PRAGMA foreign_keys = OFF
      # takes effect (PRAGMAs are no-ops inside transactions). The migration lock
      # is also disabled since it requires a transaction.
      @disable_ddl_transaction true
      @disable_migration_lock true

      import Gallformers.Migration, only: [safe_recreate_table: 2]
    end
  end

  @doc """
  Safely recreates a table, handling foreign key constraints and connection
  pinning correctly.

  Uses `Repo.checkout/1` to pin all statements to a single pooled connection,
  disables foreign keys, executes the block, re-enables foreign keys, runs
  a FK integrity check, and flushes all queued statements before the checkout
  is released.

  The explicit `Runner.flush()` at the end is essential — without it, the
  queued `execute` calls would not run until after `up/0` returns, by which
  point the checkout has been released and statements scatter across the pool.

  ## Example

      safe_recreate_table :users do
        execute "CREATE TABLE users_new (...)"
        execute "INSERT INTO users_new SELECT * FROM users"
        execute "DROP TABLE users"
        execute "ALTER TABLE users_new RENAME TO users"
      end
  """
  defmacro safe_recreate_table(_table_name, do: block) do
    # Bind outside quote to avoid leaking an alias into the caller's scope
    runner = Ecto.Migration.Runner

    quote do
      Gallformers.Repo.checkout(fn ->
        Ecto.Migration.execute("PRAGMA foreign_keys = OFF")

        unquote(block)

        Ecto.Migration.execute("PRAGMA foreign_keys = ON")
        Ecto.Migration.execute("PRAGMA foreign_key_check")
        unquote(runner).flush()
      end)
    end
  end
end
