defmodule Mix.Tasks.Gallformers.Wcvp.BuildDb do
  @moduledoc """
  Reads raw WCVP CSV files, filters to accepted species with distribution in
  mapped TDWG regions, and produces a SQLite database for use as a secondary
  read-only data source.

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

  alias Gallformers.Wcvp.Reader
  alias Gallformers.Wcvp.Tdwg

  @shortdoc "Build filtered WCVP SQLite database from CSV files"

  @default_names "priv/repo/data/wcvp/wcvp_names.csv"
  @default_dist "priv/repo/data/wcvp/wcvp_distribution.csv"
  @default_output "priv/data/wcvp.sqlite"

  @s3_bucket "gallformers-backups"
  @s3_key "wcvp/wcvp.sqlite"

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

    # Load TDWG region filter
    tdwg_lookup = Tdwg.load()
    valid_tdwg_codes = MapSet.new(Map.keys(tdwg_lookup))

    # Step 1: Find species IDs with any established distribution in our regions
    Logger.info("Scanning distributions for mapped region species...")

    matching_ids =
      Reader.stream_established_distributions(dist_path)
      |> Stream.filter(fn dist -> MapSet.member?(valid_tdwg_codes, dist.area_code_l3) end)
      |> Enum.reduce(MapSet.new(), fn dist, acc -> MapSet.put(acc, dist.plant_name_id) end)

    Logger.info("  Found #{MapSet.size(matching_ids)} species with mapped region distribution")

    # Step 2: Filter accepted names to those with matching distributions
    Logger.info("Filtering accepted names...")

    accepted_names =
      Reader.stream_accepted_names(names_path)
      |> Stream.filter(fn name -> MapSet.member?(matching_ids, name.plant_name_id) end)
      |> Enum.to_list()

    Logger.info("  Kept #{length(accepted_names)} accepted names")

    # Step 3: Collect distributions for matching species (only our regions)
    Logger.info("Collecting distributions...")

    distributions =
      Reader.stream_established_distributions(dist_path)
      |> Stream.filter(fn dist ->
        MapSet.member?(matching_ids, dist.plant_name_id) and
          MapSet.member?(valid_tdwg_codes, dist.area_code_l3)
      end)
      |> Enum.to_list()

    Logger.info("  Collected #{length(distributions)} distribution records")

    # Step 4: Write SQLite database
    File.mkdir_p!(Path.dirname(output_path))
    File.rm(output_path)

    Logger.info("Writing SQLite database...")
    write_database(output_path, accepted_names, distributions)

    Logger.info("WCVP database built: #{output_path}")

    # Step 5: Optional S3 upload
    if opts[:upload] do
      upload_to_s3(output_path)
    end
  end

  defp write_database(path, names, distributions) do
    {:ok, conn} = Exqlite.Sqlite3.open(path)

    # Create tables
    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE wcvp_names (
        plant_name_id TEXT PRIMARY KEY,
        taxon_name TEXT NOT NULL,
        family TEXT NOT NULL,
        genus TEXT NOT NULL,
        species TEXT NOT NULL,
        taxon_authors TEXT,
        powo_id TEXT
      )
      """)

    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE wcvp_distributions (
        plant_name_id TEXT NOT NULL,
        area_code_l3 TEXT NOT NULL,
        introduced INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (plant_name_id, area_code_l3, introduced),
        FOREIGN KEY (plant_name_id) REFERENCES wcvp_names(plant_name_id)
      )
      """)

    # Insert names in a transaction
    :ok = Exqlite.Sqlite3.execute(conn, "BEGIN")

    {:ok, name_stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "INSERT INTO wcvp_names (plant_name_id, taxon_name, family, genus, species, taxon_authors, powo_id) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"
      )

    for name <- names do
      :ok =
        Exqlite.Sqlite3.bind(name_stmt, [
          name.plant_name_id,
          name.taxon_name,
          name.family,
          name.genus,
          name.species,
          name.taxon_authors,
          powo_id_or_nil(name)
        ])

      :done = Exqlite.Sqlite3.step(conn, name_stmt)
      :ok = Exqlite.Sqlite3.reset(name_stmt)
    end

    Exqlite.Sqlite3.release(conn, name_stmt)

    # Insert distributions
    {:ok, dist_stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "INSERT OR IGNORE INTO wcvp_distributions (plant_name_id, area_code_l3, introduced) VALUES (?1, ?2, ?3)"
      )

    for dist <- distributions do
      introduced = if dist.introduced == "1", do: 1, else: 0

      :ok =
        Exqlite.Sqlite3.bind(dist_stmt, [dist.plant_name_id, dist.area_code_l3, introduced])

      :done = Exqlite.Sqlite3.step(conn, dist_stmt)
      :ok = Exqlite.Sqlite3.reset(dist_stmt)
    end

    Exqlite.Sqlite3.release(conn, dist_stmt)

    :ok = Exqlite.Sqlite3.execute(conn, "COMMIT")

    # Create indexes after bulk insert (faster)
    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "CREATE INDEX idx_wcvp_names_taxon_name ON wcvp_names(taxon_name COLLATE NOCASE)"
      )

    :ok =
      Exqlite.Sqlite3.execute(conn, "CREATE INDEX idx_wcvp_names_genus ON wcvp_names(genus)")

    :ok =
      Exqlite.Sqlite3.execute(conn, "CREATE INDEX idx_wcvp_names_family ON wcvp_names(family)")

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "CREATE INDEX idx_wcvp_dist_id ON wcvp_distributions(plant_name_id)"
      )

    :ok = Exqlite.Sqlite3.close(conn)
  end

  defp powo_id_or_nil(%{powo_id: powo_id}) when powo_id not in [nil, ""], do: powo_id
  defp powo_id_or_nil(_), do: nil

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
