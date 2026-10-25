defmodule Gallformers.Audit.Migration do
  @moduledoc """
  Migration helpers for audited tables.

  Call `track_table/2` in the migration that creates a table, after creating
  it, and `untrack_table/2` in that migration's `down/0` before dropping it.
  The helpers issue migration commands, so they only work inside an
  `Ecto.Migration`.

      def up do
        create table(:taxa) do
          ...
        end

        Gallformers.Audit.Migration.track_table("taxa")
      end

      def down do
        Gallformers.Audit.Migration.untrack_table("taxa")
        drop table(:taxa)
      end
  """

  @type option :: {:primary_key_columns, [String.t()]} | {:table_prefix, String.t()}

  @doc """
  Installs the audit trigger on `table`.

  Updates keep the values they replaced (`store_changed_from`), and each
  change records the row's primary key.

  ## Options

    * `:primary_key_columns` - the columns identifying a row (default
      `["id"]`); Carbonite stores them, and each change's key values, in
      alphabetical order of column name
    * `:table_prefix` - the table's schema (default `"public"`)
  """
  @spec track_table(String.t(), [option()]) :: :ok
  def track_table(table, opts \\ []) when is_binary(table) do
    prefix_opts = Keyword.take(opts, [:table_prefix])
    primary_key_columns = Keyword.get(opts, :primary_key_columns, ["id"])

    :ok = Carbonite.Migrations.create_trigger(table, prefix_opts)

    :ok =
      Carbonite.Migrations.put_trigger_config(
        table,
        :primary_key_columns,
        primary_key_columns,
        prefix_opts
      )

    :ok = Carbonite.Migrations.put_trigger_config(table, :store_changed_from, true, prefix_opts)
  end

  @doc "Removes the audit trigger from `table`. Recorded history is kept."
  @spec untrack_table(String.t(), [option()]) :: :ok
  def untrack_table(table, opts \\ []) when is_binary(table) do
    Carbonite.Migrations.drop_trigger(table, Keyword.take(opts, [:table_prefix]))
  end
end
