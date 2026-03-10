defmodule Mix.Tasks.Gallformers.Wcvp.BuildDb do
  @moduledoc """
  Reads raw WCVP CSV files and produces a SQLite database containing ALL data
  from both files — no filtering by taxon_status, taxon_rank, or TDWG region.

  ## Usage

      mix gallformers.wcvp.build_db [options]

  ## Options

      --names   Path to wcvp_names.csv (default: priv/repo/data/wcvp/wcvp_names.csv)
      --dist    Path to wcvp_distribution.csv (default: priv/repo/data/wcvp/wcvp_distribution.csv)
      --output  Output SQLite path (default: priv/data/wcvp.sqlite)
      --upload  Upload to S3 after building
  """

  use Mix.Task
  require Logger

  @shortdoc "Build WCVP SQLite database from CSV files"

  @default_names "priv/repo/data/wcvp/wcvp_names.csv"
  @default_dist "priv/repo/data/wcvp/wcvp_distribution.csv"
  @default_output "priv/data/wcvp.sqlite"

  @s3_bucket "gallformers-backups"
  @s3_key "public/wcvp.sqlite"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [names: :string, dist: :string, output: :string, upload: :boolean]
      )

    names_path = opts[:names] || @default_names
    dist_path = opts[:dist] || @default_dist
    output_path = opts[:output] || @default_output

    Logger.info("Building WCVP SQLite database...")
    Logger.info("  Names: #{names_path}")
    Logger.info("  Distributions: #{dist_path}")
    Logger.info("  Output: #{output_path}")

    File.mkdir_p!(Path.dirname(output_path))
    File.rm(output_path)

    {:ok, conn} = Exqlite.Sqlite3.open(output_path)

    # Read headers from CSVs
    names_header = read_header(names_path)
    dist_header = read_header(dist_path)

    # Create tables
    create_names_table(conn, names_header)
    create_distributions_table(conn, dist_header)
    create_meta_table(conn)

    # Insert all data in a single transaction
    :ok = Exqlite.Sqlite3.execute(conn, "BEGIN")

    names_count = insert_rows(conn, "wcvp_names", names_header, names_path)
    Logger.info("  Inserted #{names_count} name records")

    dist_count = insert_rows(conn, "wcvp_distributions", dist_header, dist_path)
    Logger.info("  Inserted #{dist_count} distribution records")

    # Insert meta
    insert_meta(conn)

    :ok = Exqlite.Sqlite3.execute(conn, "COMMIT")

    # Create indexes after bulk insert for performance
    create_indexes(conn)

    :ok = Exqlite.Sqlite3.close(conn)

    Logger.info("WCVP database built: #{output_path}")

    if opts[:upload] do
      upload_to_s3(output_path)
    end
  end

  defp read_header(path) do
    [header_line | _] = File.stream!(path) |> Enum.take(1)
    header_line |> String.trim() |> String.split("|")
  end

  defp create_names_table(conn, columns) do
    col_defs =
      Enum.map_join(columns, ", ", fn col ->
        if col == "plant_name_id", do: "plant_name_id TEXT PRIMARY KEY", else: "#{col} TEXT"
      end)

    :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE wcvp_names (#{col_defs})")
  end

  defp create_distributions_table(conn, columns) do
    col_defs =
      Enum.map_join(columns, ", ", fn col ->
        if col == "plant_locality_id",
          do: "plant_locality_id TEXT PRIMARY KEY",
          else: "#{col} TEXT"
      end)

    :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE wcvp_distributions (#{col_defs})")
  end

  defp create_meta_table(conn) do
    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)"
      )
  end

  defp insert_rows(conn, table, columns, csv_path) do
    col_count = length(columns)
    placeholders = Enum.map_join(1..col_count, ", ", fn i -> "?#{i}" end)
    col_names = Enum.join(columns, ", ")

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "INSERT INTO #{table} (#{col_names}) VALUES (#{placeholders})"
      )

    count =
      csv_path
      |> File.stream!()
      |> Stream.drop(1)
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.reduce(0, fn line, count ->
        values = String.split(line, "|")
        # Pad or trim to match column count
        values = pad_values(values, col_count)
        :ok = Exqlite.Sqlite3.bind(stmt, values)
        :done = Exqlite.Sqlite3.step(conn, stmt)
        :ok = Exqlite.Sqlite3.reset(stmt)
        count + 1
      end)

    Exqlite.Sqlite3.release(conn, stmt)
    count
  end

  defp pad_values(values, expected) do
    actual = length(values)

    cond do
      actual == expected -> values
      actual < expected -> values ++ List.duplicate("", expected - actual)
      true -> Enum.take(values, expected)
    end
  end

  defp insert_meta(conn) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "INSERT INTO meta (key, value) VALUES (?1, ?2)")

    :ok = Exqlite.Sqlite3.bind(stmt, ["built_at", timestamp])
    :done = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
  end

  defp create_indexes(conn) do
    indexes = [
      "CREATE INDEX idx_wcvp_names_taxon_name ON wcvp_names(taxon_name COLLATE NOCASE)",
      "CREATE INDEX idx_wcvp_names_genus ON wcvp_names(genus)",
      "CREATE INDEX idx_wcvp_names_family ON wcvp_names(family)",
      "CREATE INDEX idx_wcvp_names_accepted ON wcvp_names(accepted_plant_name_id)",
      "CREATE INDEX idx_wcvp_names_status ON wcvp_names(taxon_status)",
      "CREATE INDEX idx_wcvp_dist_name_id ON wcvp_distributions(plant_name_id)",
      "CREATE INDEX idx_wcvp_dist_area ON wcvp_distributions(area_code_l3)"
    ]

    Enum.each(indexes, fn sql -> :ok = Exqlite.Sqlite3.execute(conn, sql) end)
  end

  defp upload_to_s3(path) do
    Mix.Task.run("app.start")

    data = File.read!(path)

    Logger.info("Uploading to s3://#{@s3_bucket}/#{@s3_key}...")

    case ExAws.S3.put_object(@s3_bucket, @s3_key, data) |> Gallformers.S3.request() do
      {:ok, _} ->
        Logger.info("Upload complete")

      {:error, reason} ->
        Logger.error("Upload failed: #{inspect(reason)}")
    end
  end
end
