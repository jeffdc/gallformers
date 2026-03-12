defmodule Mix.Tasks.ConvertSqlite do
  @moduledoc """
  Convert data from the SQLite production copy to the Postgres dev database.

  Reads from `priv/gallformers.sqlite` (or a custom path) and writes to the
  configured Postgres repo. Schema must already exist — run `mix ecto.migrate`
  first. All Postgres tables are truncated before loading.

  ## Usage

      mix convert_sqlite
      mix convert_sqlite --sqlite-path path/to/gallformers.sqlite
  """

  use Mix.Task

  alias Ecto.Adapters.SQL
  alias Gallformers.Repo, as: PgRepo
  alias Mix.Tasks.ConvertSqlite.SQLiteRepo

  @shortdoc "Convert data from SQLite prod copy to Postgres"

  @requirements ["app.config"]

  @default_sqlite_path "priv/gallformers.sqlite"
  @batch_size 1000

  # Dialyzer has trouble tracing Mix task invocations
  @dialyzer [:no_unused, :no_return, :no_match]

  # Tables to skip (SQLite-only, internal, or virtual)
  @skip_tables ~w(
    migration schema_migrations versions
    species_fts species_fts_config species_fts_content species_fts_data
    species_fts_docsize species_fts_idx
    _litestream_seq _litestream_lock sqlite_sequence
  )

  # Tables in FK dependency order for insertion.
  # Truncation happens in reverse order with CASCADE.
  @table_order [
    # 1. Filter field tables (no FKs)
    "alignment",
    "cells",
    "color",
    "form",
    "plant_part",
    "season",
    "shape",
    "texture",
    "walls",
    # 2. Standalone reference tables
    "abundance",
    "glossary",
    "place",
    # 3. Self-referencing
    "taxonomy",
    # 4. No FK deps on above
    "source",
    "users",
    "articles",
    "keys",
    # 5. FK to abundance
    "species",
    # 6. FK to species (through junctions)
    "alias",
    # 7. 1:1 extensions of species
    "gall_traits",
    "host_traits",
    # 8. FK to species + source
    "image",
    "content_images",
    # 9. FK to species x2
    "gallhost",
    "species_source",
    # 10. Junction tables
    "alias_species",
    "taxonomy_alias",
    "species_taxonomy",
    "place_hierarchy",
    "host_range",
    "gall_range",
    # 11. Gall trait junctions
    "gall_color",
    "gall_walls",
    "gall_cells",
    "gall_shape",
    "gall_texture",
    "gall_alignment",
    "gall_plant_part",
    "gall_form",
    "gall_season",
    # 12. Analytics
    "daily_stats",
    "daily_page_stats",
    "daily_referrer_stats",
    "daily_device_stats",
    "daily_browser_stats",
    # 13. Settings (Postgres-only, will be empty in SQLite)
    "site_settings",
    # 14. Large table last
    "page_views"
  ]

  # Columns to skip per table (exist in SQLite but not in Postgres)
  @skip_columns %{
    "species" => MapSet.new(["taxonomy_id"])
  }

  # Tables with unique constraints in Postgres that don't exist in SQLite.
  # Map of table => list of column names forming the unique key.
  # Rows will be deduplicated on these columns (first occurrence wins).
  @dedup_keys %{
    "gallhost" => ["host_species_id", "gall_species_id"],
    "species_source" => ["species_id", "source_id"]
  }

  # Boolean columns that need 0/1 -> true/false conversion.
  # Map of table_name => MapSet of column names.
  @boolean_columns %{
    "species" => MapSet.new(["datacomplete"]),
    "source" => MapSet.new(["datacomplete"]),
    "taxonomy" => MapSet.new(["is_placeholder"]),
    "gall_traits" => MapSet.new(["undescribed", "range_confirmed"]),
    "host_traits" => MapSet.new(["range_confirmed"]),
    "articles" => MapSet.new(["is_published"]),
    "users" => MapSet.new(["show_on_about"]),
    "species_source" => MapSet.new(["useasdefault"]),
    "site_settings" => MapSet.new([])
  }

  # Empty string -> NULL conversion is driven by the Postgres schema:
  # only nullable columns get the conversion. NOT NULL columns keep their
  # empty strings. This is queried at runtime via get_pg_nullable_columns/1.

  # Timestamp columns that need string -> DateTime conversion.
  # SQLite stores these as TEXT; Postgrex needs %DateTime{} or %NaiveDateTime{}.
  @timestamp_columns %{
    "taxonomy" => MapSet.new(["inserted_at", "updated_at"]),
    "source" => MapSet.new(["inserted_at", "updated_at"]),
    "users" => MapSet.new(["inserted_at", "updated_at"]),
    "articles" => MapSet.new(["inserted_at", "updated_at", "published_at"]),
    "keys" => MapSet.new(["inserted_at", "updated_at"]),
    "species" => MapSet.new(["inserted_at", "updated_at"]),
    "alias" => MapSet.new(["inserted_at", "updated_at"]),
    "gall_traits" => MapSet.new(["range_computed_at"]),
    "host_traits" => MapSet.new(["wcvp_synced_at"]),
    "content_images" => MapSet.new(["inserted_at", "updated_at"]),
    "gallhost" => MapSet.new(["inserted_at", "updated_at"]),
    "page_views" => MapSet.new(["inserted_at"]),
    "site_settings" => MapSet.new(["inserted_at", "updated_at"])
  }

  # Date columns (analytics tables store dates as TEXT in SQLite).
  @date_columns %{
    "daily_stats" => MapSet.new(["date"]),
    "daily_page_stats" => MapSet.new(["date"]),
    "daily_referrer_stats" => MapSet.new(["date"]),
    "daily_device_stats" => MapSet.new(["date"]),
    "daily_browser_stats" => MapSet.new(["date"])
  }

  # Tables that have an auto-increment `id` column whose sequence needs resetting.
  # Junction tables and tables with composite PKs are excluded.
  @tables_with_id_sequence ~w(
    alignment cells color form plant_part season shape texture walls
    abundance glossary place taxonomy source users articles keys
    species alias image content_images gallhost species_source
    daily_stats daily_page_stats daily_referrer_stats daily_device_stats
    daily_browser_stats site_settings page_views
  )

  # ──────────────────────────────────────────────────────────────────────────
  # Entry point
  # ──────────────────────────────────────────────────────────────────────────

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [sqlite_path: :string])
    sqlite_path = Keyword.get(opts, :sqlite_path, @default_sqlite_path)

    unless File.exists?(sqlite_path) do
      Mix.Shell.IO.error("SQLite file not found: #{sqlite_path}")
      Mix.Shell.IO.error("Run `make download-db` to get the production copy.")
      exit({:shutdown, 1})
    end

    Mix.Task.run("app.start")

    start_time = System.monotonic_time(:millisecond)

    sqlite_repo = start_sqlite_repo!(sqlite_path)

    try do
      info("Truncating Postgres tables...")
      truncate_all_tables!()

      # Pin a single Postgres connection so SET applies to all queries.
      # 10 minute timeout for the full conversion (page_views is large).
      PgRepo.checkout(
        fn ->
          # Disable FK triggers during bulk load
          info("Disabling FK constraints...")
          SQL.query!(PgRepo, "SET session_replication_role = 'replica'")

          info("Converting #{length(convertible_tables())} tables...\n")

          results =
            Enum.map(convertible_tables(), fn table ->
              convert_table(sqlite_repo, table)
            end)

          # Re-enable FK triggers
          info("\nRe-enabling FK constraints...")
          SQL.query!(PgRepo, "SET session_replication_role = 'origin'")

          info("Resetting Postgres sequences...")
          reset_sequences!()

          elapsed = System.monotonic_time(:millisecond) - start_time

          print_summary(results, elapsed)
          verify_counts(sqlite_repo, results)
        end,
        timeout: :timer.minutes(10)
      )
    after
      # Stop the temporary SQLite repo
      Supervisor.stop(sqlite_repo)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # SQLite repo setup
  # ──────────────────────────────────────────────────────────────────────────

  defp start_sqlite_repo!(sqlite_path) do
    abs_path = Path.expand(sqlite_path)
    info("Opening SQLite: #{abs_path}")

    # Start a temporary Ecto repo backed by SQLite
    {:ok, _pid} =
      SQLiteRepo.start_link(
        database: abs_path,
        pool_size: 1,
        journal_mode: :wal
      )

    SQLiteRepo
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Truncation
  # ──────────────────────────────────────────────────────────────────────────

  defp truncate_all_tables! do
    # Truncate all tables at once with CASCADE to handle FK dependencies
    tables = @table_order |> Enum.reverse() |> Enum.join(", ")

    SQL.query!(
      PgRepo,
      "TRUNCATE #{tables} CASCADE"
    )

    info("Truncated #{length(@table_order)} tables.")
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Table conversion
  # ──────────────────────────────────────────────────────────────────────────

  defp convert_table(sqlite_repo, table) do
    # Check if table exists in SQLite
    case sqlite_table_exists?(sqlite_repo, table) do
      false ->
        IO.write("  #{pad_table(table)} skipped (not in SQLite)\n")
        {table, 0, :skipped}

      true ->
        # Get column info from both sides
        sqlite_cols = get_sqlite_columns(sqlite_repo, table)
        pg_cols = get_pg_columns(table)

        # Determine columns to transfer: intersection of both schemas,
        # minus any explicitly skipped columns
        skip = Map.get(@skip_columns, table, MapSet.new())

        transfer_cols =
          sqlite_cols
          |> Enum.filter(&MapSet.member?(pg_cols, &1))
          |> Enum.reject(&MapSet.member?(skip, &1))

        count = convert_table_data(sqlite_repo, table, transfer_cols)
        IO.write("  #{pad_table(table)} #{count} rows\n")
        {table, count, :ok}
    end
  end

  defp convert_table_data(sqlite_repo, table, columns) do
    col_list = Enum.join(columns, ", ")

    # Read all rows from SQLite
    %{rows: rows} =
      SQL.query!(sqlite_repo, "SELECT #{col_list} FROM \"#{table}\"")

    if rows == [] or rows == nil do
      0
    else
      # Deduplicate if needed (Postgres has unique constraints SQLite lacks)
      rows = maybe_dedup_rows(rows, table, columns)
      booleans = Map.get(@boolean_columns, table, MapSet.new())
      nullable = get_pg_nullable_columns(table)
      timestamps = Map.get(@timestamp_columns, table, MapSet.new())
      dates = Map.get(@date_columns, table, MapSet.new())
      varchar_limits = get_pg_varchar_limits(table)

      # Build column index for transformations
      col_indices =
        columns
        |> Enum.with_index()
        |> Map.new()

      # Transform rows
      transformed_rows =
        Enum.map(rows, fn row ->
          transform_row(
            row,
            columns,
            col_indices,
            booleans,
            nullable,
            timestamps,
            dates,
            varchar_limits
          )
        end)

      # Insert in batches
      insert_batches!(table, columns, transformed_rows)
    end
  end

  defp transform_row(
         row,
         columns,
         col_indices,
         booleans,
         nullable,
         timestamps,
         dates,
         varchar_limits
       ) do
    Enum.map(columns, fn col ->
      idx = Map.fetch!(col_indices, col)
      value = Enum.at(row, idx)

      value
      |> maybe_convert_boolean(col, booleans)
      |> maybe_convert_timestamp(col, timestamps)
      |> maybe_convert_date(col, dates)
      |> maybe_truncate_varchar(col, varchar_limits)
      |> maybe_nullify_empty_string(col, nullable)
    end)
  end

  defp maybe_convert_boolean(value, col, booleans) do
    if MapSet.member?(booleans, col) do
      value in [1, true, "true"]
    else
      value
    end
  end

  defp maybe_convert_timestamp(nil, _col, _timestamps), do: nil

  defp maybe_convert_timestamp(value, col, timestamps) when is_binary(value) do
    if MapSet.member?(timestamps, col) do
      parse_timestamp!(value)
    else
      value
    end
  end

  defp maybe_convert_timestamp(value, _col, _timestamps), do: value

  # Parse SQLite timestamp strings into NaiveDateTime.
  # Handles both "2026-02-04 13:47:58" and "2026-02-04T13:47:58Z" formats.
  defp parse_timestamp!(str) do
    str
    |> String.replace("T", " ")
    |> String.replace("Z", "")
    |> String.replace(~r/\.\d+$/, "")
    |> NaiveDateTime.from_iso8601!()
  end

  defp maybe_convert_date(nil, _col, _dates), do: nil

  defp maybe_convert_date(value, col, dates) when is_binary(value) do
    if MapSet.member?(dates, col) do
      Date.from_iso8601!(value)
    else
      value
    end
  end

  defp maybe_convert_date(value, _col, _dates), do: value

  defp maybe_truncate_varchar(value, col, varchar_limits) when is_binary(value) do
    case Map.get(varchar_limits, col) do
      nil ->
        value

      limit when byte_size(value) > limit ->
        truncated = String.slice(value, 0, limit)
        IO.puts("    WARNING: truncated #{col} from #{String.length(value)} to #{limit} chars")
        truncated

      _limit ->
        value
    end
  end

  defp maybe_truncate_varchar(value, _col, _varchar_limits), do: value

  # Convert empty strings to NULL, but only for columns that are nullable in Postgres.
  # NOT NULL columns keep their empty strings as-is.
  defp maybe_nullify_empty_string(value, col, nullable) do
    if value == "" and MapSet.member?(nullable, col) do
      nil
    else
      value
    end
  end

  defp maybe_dedup_rows(rows, table, columns) do
    case Map.get(@dedup_keys, table) do
      nil ->
        rows

      key_cols ->
        col_indices = columns |> Enum.with_index() |> Map.new()
        key_indices = Enum.map(key_cols, &Map.fetch!(col_indices, &1))

        original_count = length(rows)

        deduped =
          rows
          |> Enum.uniq_by(fn row ->
            Enum.map(key_indices, &Enum.at(row, &1))
          end)

        deduped_count = length(deduped)

        if deduped_count < original_count do
          IO.puts("    (deduplicated: #{original_count} -> #{deduped_count} rows)")
        end

        deduped
    end
  end

  defp insert_batches!(table, columns, rows) do
    total =
      rows
      |> Enum.chunk_every(@batch_size)
      |> Enum.reduce(0, fn batch, acc ->
        insert_batch!(table, columns, batch)
        acc + length(batch)
      end)

    total
  end

  defp insert_batch!(table, columns, rows) do
    num_cols = length(columns)
    num_rows = length(rows)

    # Build parameterized placeholders: ($1, $2, $3), ($4, $5, $6), ...
    {placeholders, _} =
      Enum.map_reduce(1..num_rows, 1, fn _row_idx, param_start ->
        params =
          Enum.map_join(param_start..(param_start + num_cols - 1), ", ", &"$#{&1}")

        {"(#{params})", param_start + num_cols}
      end)

    col_list = Enum.map_join(columns, ", ", fn c -> "\"#{c}\"" end)
    values_list = Enum.join(placeholders, ", ")

    sql = "INSERT INTO \"#{table}\" (#{col_list}) VALUES #{values_list}"

    # Flatten all row values into a single params list
    params = List.flatten(rows)

    SQL.query!(PgRepo, sql, params, timeout: :timer.minutes(5))
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Sequence reset
  # ──────────────────────────────────────────────────────────────────────────

  defp reset_sequences! do
    Enum.each(@tables_with_id_sequence, fn table ->
      # Only reset if the table has an id column with a sequence
      sql = """
      SELECT setval(
        pg_get_serial_sequence('#{table}', 'id'),
        COALESCE((SELECT MAX(id) FROM "#{table}"), 0) + 1,
        false
      )
      """

      try do
        SQL.query!(PgRepo, sql)
      rescue
        # Table might not have a sequence (e.g., if empty or no id column)
        Postgrex.Error -> :ok
      end
    end)

    info("Sequences reset.")
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Verification
  # ──────────────────────────────────────────────────────────────────────────

  defp verify_counts(sqlite_repo, results) do
    dedup_tables = Map.keys(@dedup_keys) |> MapSet.new()

    info("\n#{"=" |> String.duplicate(68)}")
    info("Verification: SQLite vs Postgres row counts")
    info("#{"=" |> String.duplicate(68)}")
    info("")

    header =
      String.pad_trailing("Table", 28) <>
        String.pad_leading("SQLite", 10) <>
        String.pad_leading("Postgres", 10) <>
        "  Status"

    info(header)
    info(String.duplicate("-", 68))

    mismatches =
      results
      |> Enum.filter(fn {_, _, status} -> status == :ok end)
      |> Enum.reduce(0, fn {table, converted_count, _}, acc ->
        mismatch? = verify_table_count(sqlite_repo, table, converted_count, dedup_tables)
        if mismatch?, do: acc + 1, else: acc
      end)

    info("")

    if mismatches > 0 do
      Mix.Shell.IO.error("#{mismatches} table(s) have mismatched counts!")
    else
      info("#{IO.ANSI.green()}All table counts match.#{IO.ANSI.reset()}")
    end
  end

  # Returns true if there's a mismatch, false if counts are OK.
  defp verify_table_count(sqlite_repo, table, converted_count, dedup_tables) do
    sqlite_count = get_count(sqlite_repo, table)
    pg_count = get_count(PgRepo, table)

    {sqlite_label, expected, status_label} =
      if MapSet.member?(dedup_tables, table) do
        {"#{sqlite_count}->#{converted_count}", converted_count, "OK (deduped)"}
      else
        {Integer.to_string(sqlite_count), sqlite_count, "OK"}
      end

    ok? = pg_count == expected
    status = if ok?, do: status_label, else: "MISMATCH"
    color = if ok?, do: IO.ANSI.green(), else: IO.ANSI.red()

    line =
      String.pad_trailing(table, 28) <>
        String.pad_leading(sqlite_label, 10) <>
        String.pad_leading(Integer.to_string(pg_count), 10) <>
        "  #{color}#{status}#{IO.ANSI.reset()}"

    info(line)
    not ok?
  end

  defp get_count(repo, table) do
    %{rows: [[count]]} =
      SQL.query!(repo, "SELECT COUNT(*) FROM \"#{table}\"")

    count
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Summary
  # ──────────────────────────────────────────────────────────────────────────

  defp print_summary(results, elapsed_ms) do
    converted = Enum.filter(results, fn {_, _, s} -> s == :ok end)
    skipped = Enum.filter(results, fn {_, _, s} -> s == :skipped end)
    total_rows = Enum.reduce(converted, 0, fn {_, count, _}, acc -> acc + count end)

    seconds = elapsed_ms / 1000

    info(
      "\nDone! Converted #{length(converted)} tables (#{total_rows} total rows) in #{Float.round(seconds, 1)}s"
    )

    if skipped != [] do
      names = Enum.map_join(skipped, ", ", fn {name, _, _} -> name end)
      info("Skipped #{length(skipped)} tables: #{names}")
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────────────────

  defp convertible_tables do
    Enum.filter(@table_order, fn table ->
      table not in @skip_tables
    end)
  end

  defp sqlite_table_exists?(sqlite_repo, table) do
    %{rows: rows} =
      SQL.query!(
        sqlite_repo,
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
        [table]
      )

    rows != []
  end

  defp get_sqlite_columns(sqlite_repo, table) do
    %{rows: rows} =
      SQL.query!(sqlite_repo, "PRAGMA table_info(\"#{table}\")")

    Enum.map(rows, fn [_cid, name | _rest] -> name end)
  end

  defp get_pg_columns(table) do
    %{rows: rows} =
      SQL.query!(
        PgRepo,
        "SELECT column_name FROM information_schema.columns WHERE table_name = $1",
        [table]
      )

    rows |> Enum.map(fn [col] -> col end) |> MapSet.new()
  end

  # Returns a MapSet of column names that are nullable in Postgres.
  defp get_pg_nullable_columns(table) do
    %{rows: rows} =
      SQL.query!(
        PgRepo,
        """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_name = $1
          AND is_nullable = 'YES'
        """,
        [table]
      )

    rows |> Enum.map(fn [col] -> col end) |> MapSet.new()
  end

  # Returns a map of column_name => max_length for varchar columns with limits.
  defp get_pg_varchar_limits(table) do
    %{rows: rows} =
      SQL.query!(
        PgRepo,
        """
        SELECT column_name, character_maximum_length
        FROM information_schema.columns
        WHERE table_name = $1
          AND data_type = 'character varying'
          AND character_maximum_length IS NOT NULL
        """,
        [table]
      )

    Map.new(rows, fn [col, limit] -> {col, limit} end)
  end

  defp pad_table(name), do: String.pad_trailing(name, 26)

  defp info(msg), do: Mix.Shell.IO.info(msg)
end

# Temporary Ecto repo for reading the SQLite file.
# Defined outside the task module so Ecto can manage it properly.
defmodule Mix.Tasks.ConvertSqlite.SQLiteRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :gallformers,
    adapter: Ecto.Adapters.SQLite3
end
