# WCVP Live Lookup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable admins to look up WCVP data when creating or editing host plants, pre-populating taxonomy and range from a shared SQLite artifact on S3.

**Architecture:** A mix task builds a filtered WCVP SQLite database from the raw CSVs and uploads it to S3. The main app uses a secondary read-only Ecto repo (`Repo.WCVP`) to query it. A refresh module handles stop/download/restart. The host admin form gets a WCVP typeahead for creation and a "Refresh from WCVP" button for updates.

**Tech Stack:** Elixir/Ecto, SQLite3, ExAws/S3, Phoenix LiveView

**Design doc:** `docs/plans/2026-02-20-wcvp-live-lookup-design.md`

---

## Task 1: Create `host_traits` Table and Schema

Create the Class Table Inheritance extension table for host-specific data, mirroring the `gall_traits` pattern exactly.

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_create_host_traits.exs`
- Create: `lib/gallformers/plants/host_traits.ex`
- Modify: `lib/gallformers/species/species.ex` (add `has_one :host_traits`)
- Test: `test/gallformers/plants_test.exs`

**Step 1: Write the failing test**

Add to `test/gallformers/plants_test.exs`:

```elixir
describe "host_traits" do
  setup do
    {:ok, family} = Taxonomy.create_taxonomy(%{name: "Fagaceae", type: "family"})
    {:ok, genus} = Taxonomy.create_taxonomy(%{name: "Quercus", type: "genus", parent_id: family.id})

    {:ok, species} =
      Repo.insert(%Species{name: "Quercus alba", taxoncode: "plant"})

    Taxonomy.link_species_to_taxonomy(species.id, genus.id)

    {:ok, species: species}
  end

  test "creates host_traits with WCVP and POWO IDs", %{species: species} do
    {:ok, traits} =
      Repo.insert(%Gallformers.Plants.HostTraits{
        species_id: species.id,
        wcvp_id: "12345",
        powo_id: "urn:lsid:ipni.org:names:12345-1"
      })

    assert traits.species_id == species.id
    assert traits.wcvp_id == "12345"
    assert traits.powo_id == "urn:lsid:ipni.org:names:12345-1"
  end

  test "species can preload host_traits", %{species: species} do
    {:ok, _} =
      Repo.insert(%Gallformers.Plants.HostTraits{
        species_id: species.id,
        wcvp_id: "99999"
      })

    loaded = Repo.get!(Species, species.id) |> Repo.preload(:host_traits)
    assert loaded.host_traits.wcvp_id == "99999"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/gallformers/plants_test.exs --seed 0`
Expected: Compilation error — `Gallformers.Plants.HostTraits` does not exist.

**Step 3: Generate migration**

Run: `mix ecto.gen.migration create_host_traits`

Write the migration:

```elixir
defmodule Gallformers.Repo.Migrations.CreateHostTraits do
  use Gallformers.Migration

  def change do
    create table(:host_traits, primary_key: false) do
      add :species_id, references(:species, on_delete: :delete_all), primary_key: true
      add :wcvp_id, :string
      add :powo_id, :string
    end

    create index(:host_traits, [:wcvp_id])
    create index(:host_traits, [:powo_id])
  end
end
```

**Step 4: Create the HostTraits schema**

Create `lib/gallformers/plants/host_traits.ex`:

```elixir
defmodule Gallformers.Plants.HostTraits do
  @moduledoc """
  Ecto schema for the host_traits table (1:1 extension of species).

  Stores host-specific attributes for species with taxoncode='plant'.
  Uses Class Table Inheritance pattern: species_id is both PK and FK.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:species_id]
  @optional_fields [:wcvp_id, :powo_id]

  @type t :: %__MODULE__{
          species_id: integer(),
          wcvp_id: String.t() | nil,
          powo_id: String.t() | nil
        }

  @primary_key {:species_id, :integer, autogenerate: false}
  @derive {Phoenix.Param, key: :species_id}

  schema "host_traits" do
    field :wcvp_id, :string
    field :powo_id, :string

    belongs_to :species, Gallformers.Species.Species,
      foreign_key: :species_id,
      references: :id,
      define_field: false
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @impl Gallformers.SchemaFields
  def required_associations, do: []

  @doc """
  Creates a changeset for host traits.
  """
  def changeset(host_traits, attrs) do
    host_traits
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:species_id)
  end
end
```

**Step 5: Add `has_one :host_traits` to Species schema**

In `lib/gallformers/species/species.ex`, add after the existing `has_one :gall_traits` (line 33):

```elixir
has_one :host_traits, Gallformers.Plants.HostTraits, foreign_key: :species_id
```

**Step 6: Run migration and tests**

Run: `mix ecto.migrate && make test`
Expected: All tests pass including the two new ones.

**Step 7: Commit**

```bash
git add lib/gallformers/plants/host_traits.ex lib/gallformers/species/species.ex priv/repo/migrations/*create_host_traits* test/gallformers/plants_test.exs
git commit -m "Add host_traits table with WCVP and POWO IDs"
```

---

## Task 2: WCVP SQLite Build Mix Task

Create a mix task that filters the raw WCVP CSVs and produces a SQLite database.

**Files:**
- Create: `lib/mix/tasks/gallformers/wcvp/build_db.ex`
- Test: `test/mix/tasks/gallformers/wcvp/build_db_test.exs`

**Step 1: Write the failing test**

Create `test/mix/tasks/gallformers/wcvp/build_db_test.exs`:

```elixir
defmodule Mix.Tasks.Gallformers.Wcvp.BuildDbTest do
  use ExUnit.Case, async: false

  @test_dir "test/tmp/wcvp_build"

  setup do
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    # Write minimal test CSV files (pipe-delimited, matching WCVP format)
    names_csv = """
    plant_name_id|ipni_id|taxon_rank|taxon_status|family|genus|species|species_hybrid|infraspecific_rank|infraspecies|parenthetical_author|primary_author|publication_author|place_of_publication|volume_and_page|first_published|nomenclatural_remarks|geographic_area|lifeform_description|climate_description|taxon_name|taxon_authors|accepted_plant_name_id|basionym_plant_name_id|replaced_synonym_author|homotypic_synonym|parent_plant_name_id|powo_id|hybrid_formula|reviewed
    100|ipni-100|Species|Accepted|Fagaceae|Quercus|alba|||||||||||||||Quercus alba|L.|100|||||||urn:lsid:ipni.org:names:100-1|
    200|ipni-200|Species|Accepted|Rosaceae|Rosa|carolina|||||||||||||||Rosa carolina|L.|200|||||||urn:lsid:ipni.org:names:200-1|
    300|ipni-300|Species|Accepted|Poaceae|Zea|mays|||||||||||||||Zea mays|L.|300|||||||urn:lsid:ipni.org:names:300-1|
    400|ipni-400|Species|Synonym|Fagaceae|Quercus|stellata|||||||||||||||Quercus stellata|Wangenh.|100|||||||urn:lsid:ipni.org:names:400-1|
    """

    dist_csv = """
    plant_name_id|continent_code_l1|region_code_l2|area_code_l3|area|introduced|extinct|location_doubtful
    100|7|74|ALB|Alabama|0|0|0
    100|7|74|FLA|Florida|0|0|0
    200|7|74|NCA|North Carolina|0|0|0
    300|3|30|ZAF|South Africa|0|0|0
    """

    File.write!(Path.join(@test_dir, "wcvp_names.csv"), names_csv)
    File.write!(Path.join(@test_dir, "wcvp_distribution.csv"), dist_csv)

    on_exit(fn -> File.rm_rf!(@test_dir) end)

    {:ok, dir: @test_dir}
  end

  test "builds SQLite database with filtered data", %{dir: dir} do
    db_path = Path.join(dir, "wcvp.sqlite")

    Mix.Tasks.Gallformers.Wcvp.BuildDb.run([
      "--names", Path.join(dir, "wcvp_names.csv"),
      "--dist", Path.join(dir, "wcvp_distribution.csv"),
      "--output", db_path
    ])

    assert File.exists?(db_path)

    # Open and verify contents
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    # Quercus alba and Rosa carolina should be present (have Western Hemisphere distribution)
    # Zea mays should NOT be present (only has South Africa distribution)
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM wcvp_names")
    {:row, [count]} = Exqlite.Sqlite3.step(conn, stmt)
    assert count == 2

    # Distribution rows: 2 for Quercus alba + 1 for Rosa carolina = 3
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM wcvp_distributions")
    {:row, [count]} = Exqlite.Sqlite3.step(conn, stmt)
    assert count == 3

    # Verify Quercus alba data
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT taxon_name, family, powo_id FROM wcvp_names WHERE plant_name_id = '100'")
    {:row, [name, family, powo_id]} = Exqlite.Sqlite3.step(conn, stmt)
    assert name == "Quercus alba"
    assert family == "Fagaceae"
    assert powo_id == "urn:lsid:ipni.org:names:100-1"

    Exqlite.Sqlite3.close(conn)
  end

  test "excludes synonyms from names table", %{dir: dir} do
    db_path = Path.join(dir, "wcvp.sqlite")

    Mix.Tasks.Gallformers.Wcvp.BuildDb.run([
      "--names", Path.join(dir, "wcvp_names.csv"),
      "--dist", Path.join(dir, "wcvp_distribution.csv"),
      "--output", db_path
    ])

    {:ok, conn} = Exqlite.Sqlite3.open(db_path)
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM wcvp_names WHERE plant_name_id = '400'")
    {:row, [count]} = Exqlite.Sqlite3.step(conn, stmt)
    assert count == 0

    Exqlite.Sqlite3.close(conn)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/mix/tasks/gallformers/wcvp/build_db_test.exs --seed 0`
Expected: Module `Mix.Tasks.Gallformers.Wcvp.BuildDb` not found.

**Step 3: Implement the mix task**

Create `lib/mix/tasks/gallformers/wcvp/build_db.ex`:

```elixir
defmodule Mix.Tasks.Gallformers.Wcvp.BuildDb do
  @moduledoc """
  Builds a filtered WCVP SQLite database for live lookup.

  Reads raw WCVP CSV files, filters to Western Hemisphere accepted species,
  and produces a SQLite database for use as a secondary read-only data source.

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

  @default_names "priv/repo/data/wcvp/wcvp_names.csv"
  @default_dist "priv/repo/data/wcvp/wcvp_distribution.csv"
  @default_output "priv/data/wcvp.sqlite"

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

    # Step 1: Find species IDs with distribution in our regions
    Logger.info("Scanning distributions for Western Hemisphere species...")

    matching_ids =
      Reader.stream_native_distributions(dist_path)
      |> Stream.filter(fn dist -> MapSet.member?(valid_tdwg_codes, dist.area_code_l3) end)
      |> Enum.reduce(MapSet.new(), fn dist, acc -> MapSet.put(acc, dist.plant_name_id) end)

    Logger.info("  Found #{MapSet.size(matching_ids)} species with Western Hemisphere distribution")

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
      Reader.stream_native_distributions(dist_path)
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

    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE wcvp_distributions (
      plant_name_id TEXT NOT NULL,
      area_code_l3 TEXT NOT NULL,
      PRIMARY KEY (plant_name_id, area_code_l3),
      FOREIGN KEY (plant_name_id) REFERENCES wcvp_names(plant_name_id)
    )
    """)

    # Insert names in a transaction
    Exqlite.Sqlite3.execute(conn, "BEGIN")

    {:ok, name_stmt} =
      Exqlite.Sqlite3.prepare(conn,
        "INSERT INTO wcvp_names (plant_name_id, taxon_name, family, genus, species, taxon_authors, powo_id) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"
      )

    for name <- names do
      Exqlite.Sqlite3.bind(conn, name_stmt, [
        name.plant_name_id,
        name.taxon_name,
        name.family,
        name.genus,
        name.species,
        name.taxon_authors,
        find_powo_id(name)
      ])

      Exqlite.Sqlite3.step(conn, name_stmt)
      Exqlite.Sqlite3.reset(name_stmt)
    end

    # Insert distributions
    {:ok, dist_stmt} =
      Exqlite.Sqlite3.prepare(conn,
        "INSERT OR IGNORE INTO wcvp_distributions (plant_name_id, area_code_l3) VALUES (?1, ?2)"
      )

    for dist <- distributions do
      Exqlite.Sqlite3.bind(conn, dist_stmt, [dist.plant_name_id, dist.area_code_l3])
      Exqlite.Sqlite3.step(conn, dist_stmt)
      Exqlite.Sqlite3.reset(dist_stmt)
    end

    Exqlite.Sqlite3.execute(conn, "COMMIT")

    # Create indexes after bulk insert (faster)
    Exqlite.Sqlite3.execute(conn, "CREATE INDEX idx_wcvp_names_taxon_name ON wcvp_names(taxon_name)")
    Exqlite.Sqlite3.execute(conn, "CREATE INDEX idx_wcvp_names_genus ON wcvp_names(genus)")
    Exqlite.Sqlite3.execute(conn, "CREATE INDEX idx_wcvp_names_family ON wcvp_names(family)")
    Exqlite.Sqlite3.execute(conn, "CREATE INDEX idx_wcvp_dist_id ON wcvp_distributions(plant_name_id)")

    Exqlite.Sqlite3.close(conn)
  end

  # The WCVP Reader.Name struct doesn't include powo_id.
  # We need to extract it from the raw CSV. For now, return nil
  # and we'll add powo_id to the Reader.Name struct.
  defp find_powo_id(%{powo_id: powo_id}) when powo_id not in [nil, ""], do: powo_id
  defp find_powo_id(_), do: nil

  defp upload_to_s3(path) do
    Mix.Task.run("app.start")

    bucket = "gallformers-backups"
    key = "wcvp/wcvp.sqlite"
    data = File.read!(path)

    Logger.info("Uploading to s3://#{bucket}/#{key}...")

    case ExAws.S3.put_object(bucket, key, data) |> Gallformers.S3.request() do
      {:ok, _} ->
        Logger.info("Upload complete")

      {:error, reason} ->
        Logger.error("Upload failed: #{inspect(reason)}")
    end
  end
end
```

**Note:** The `powo_id` field is not currently in the `Reader.Name` struct. Step 4 below adds it.

**Step 4: Add `powo_id` to `Reader.Name` struct**

In `lib/gallformers/wcvp/reader.ex`, add `:powo_id` to the `Name` defstruct (after `:parent_plant_name_id`):

```elixir
defstruct [
  :plant_name_id,
  :taxon_rank,
  :taxon_status,
  :family,
  :genus,
  :species,
  :species_hybrid,
  :infraspecific_rank,
  :infraspecies,
  :taxon_name,
  :taxon_authors,
  :accepted_plant_name_id,
  :parent_plant_name_id,
  :powo_id
]
```

And add to `@name_fields`:

```elixir
"powo_id" => :powo_id
```

**Step 5: Run tests**

Run: `mix test test/mix/tasks/gallformers/wcvp/build_db_test.exs --seed 0`
Expected: All tests pass.

**Step 6: Verify with real data (manual)**

Run: `mix gallformers.wcvp.build_db`
Expected: Produces `priv/data/wcvp.sqlite` with ~156K names.

**Step 7: Commit**

```bash
git add lib/mix/tasks/gallformers/wcvp/build_db.ex lib/gallformers/wcvp/reader.ex test/mix/tasks/gallformers/wcvp/build_db_test.exs
git commit -m "Add mix task to build filtered WCVP SQLite database"
```

---

## Task 3: Secondary Ecto Repo for WCVP

Set up a read-only secondary Ecto repo and refresh module.

**Files:**
- Create: `lib/gallformers/repo/wcvp.ex`
- Create: `lib/gallformers/wcvp/refresh.ex`
- Modify: `lib/gallformers/application.ex` (add to supervision tree)
- Modify: `config/config.exs` (add repo config)
- Modify: `config/dev.exs` (add dev database path)
- Modify: `config/test.exs` (add test database path)
- Modify: `config/prod.exs` (add prod database path)
- Test: `test/gallformers/wcvp/refresh_test.exs`

**Step 1: Create the WCVP repo module**

Create `lib/gallformers/repo/wcvp.ex`:

```elixir
defmodule Gallformers.Repo.WCVP do
  @moduledoc """
  Read-only Ecto repo for querying the WCVP SQLite database.

  This is a secondary database containing filtered WCVP plant data
  (Western Hemisphere accepted species). It is NOT managed by Ecto migrations —
  the database file is built externally and downloaded from S3.
  """
  use Ecto.Repo,
    otp_app: :gallformers,
    adapter: Ecto.Adapters.SQLite3
end
```

**Step 2: Add configuration**

In `config/config.exs`, add before the `import_config` line:

```elixir
# WCVP lookup database (read-only, no migrations)
config :gallformers, Gallformers.Repo.WCVP,
  journal_mode: :wal,
  pool_size: 2
```

In `config/dev.exs`, add:

```elixir
config :gallformers, Gallformers.Repo.WCVP,
  database: Path.expand("../priv/data/wcvp.sqlite", __DIR__)
```

In `config/test.exs`, add:

```elixir
config :gallformers, Gallformers.Repo.WCVP,
  database: Path.expand("../priv/data/wcvp_test.sqlite", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox
```

In `config/prod.exs`, add:

```elixir
config :gallformers, Gallformers.Repo.WCVP,
  database: "/data/wcvp.sqlite"
```

**Important:** Do NOT add `Gallformers.Repo.WCVP` to the `ecto_repos` list in `config.exs` — that list drives migrations and we don't want Ecto trying to migrate the WCVP database.

**Step 3: Add to supervision tree with optional startup**

In `lib/gallformers/application.ex`, add a helper that starts the WCVP repo only if the database file exists. Add the child spec after the main `Gallformers.Repo`:

```elixir
defp wcvp_repo_child_spec do
  db_path = Application.get_env(:gallformers, Gallformers.Repo.WCVP)[:database]

  if db_path && File.exists?(db_path) do
    [Gallformers.Repo.WCVP]
  else
    []
  end
end
```

In the `children` list, splice it in:

```elixir
children =
  [
    GallformersWeb.Telemetry,
    Gallformers.Repo,
    # ... existing children ...
  ] ++ wcvp_repo_child_spec() ++ [
    # ... remaining children ...
  ]
```

**Step 4: Create the refresh module**

Create `lib/gallformers/wcvp/refresh.ex`:

```elixir
defmodule Gallformers.Wcvp.Refresh do
  @moduledoc """
  Handles downloading and hot-swapping the WCVP SQLite database.

  The refresh flow:
  1. Stop the WCVP repo (closes all connections)
  2. Download new database from S3 to a temp file
  3. Move temp file to the database path (atomic on same filesystem)
  4. Restart the WCVP repo
  """

  require Logger

  @s3_bucket "gallformers-backups"
  @s3_key "wcvp/wcvp.sqlite"

  @doc """
  Downloads the latest WCVP database from S3 and restarts the repo.
  Returns `{:ok, :refreshed}` or `{:error, reason}`.
  """
  def refresh do
    db_path = Application.get_env(:gallformers, Gallformers.Repo.WCVP)[:database]
    tmp_path = db_path <> ".tmp"

    with :ok <- stop_repo(),
         :ok <- download(tmp_path),
         :ok <- swap_file(tmp_path, db_path),
         :ok <- start_repo() do
      Logger.info("WCVP database refreshed successfully")
      {:ok, :refreshed}
    else
      {:error, reason} = error ->
        Logger.error("WCVP refresh failed: #{inspect(reason)}")
        # Try to restart repo with old file if it exists
        if File.exists?(db_path), do: start_repo()
        error
    end
  end

  defp stop_repo do
    case Gallformers.Repo.WCVP.stop() do
      :ok -> :ok
      {:error, {:not_found, _}} -> :ok
      error -> error
    end
  end

  defp start_repo do
    case Gallformers.Repo.WCVP.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end

  defp download(dest_path) do
    Logger.info("Downloading WCVP database from S3...")
    File.mkdir_p!(Path.dirname(dest_path))

    case ExAws.S3.get_object(@s3_bucket, @s3_key) |> Gallformers.S3.request() do
      {:ok, %{body: body}} ->
        File.write!(dest_path, body)
        :ok

      {:error, reason} ->
        {:error, {:s3_download_failed, reason}}
    end
  end

  defp swap_file(tmp_path, dest_path) do
    File.rename(tmp_path, dest_path)
  end
end
```

**Step 5: Write test for refresh module**

Create `test/gallformers/wcvp/refresh_test.exs`:

```elixir
defmodule Gallformers.Wcvp.RefreshTest do
  @moduledoc """
  Tests for the WCVP database refresh module.
  Note: S3 is disabled in test environment, so download returns mock data.
  """
  use ExUnit.Case, async: false

  test "refresh returns error when S3 is disabled (test env mock returns non-DB data)" do
    # In test env, S3.request returns {:ok, %{body: %{contents: [], is_truncated: false}}}
    # which is not valid SQLite data, so writing it and opening as a repo would fail.
    # This test verifies the module handles the flow without crashing.
    assert {:error, _} = Gallformers.Wcvp.Refresh.refresh()
  end
end
```

**Step 6: Run tests**

Run: `mix compile --warnings-as-errors && mix test test/gallformers/wcvp/refresh_test.exs --seed 0`
Expected: Tests pass.

**Step 7: Commit**

```bash
git add lib/gallformers/repo/wcvp.ex lib/gallformers/wcvp/refresh.ex lib/gallformers/application.ex config/config.exs config/dev.exs config/test.exs config/prod.exs test/gallformers/wcvp/refresh_test.exs
git commit -m "Add secondary WCVP repo with S3-based refresh"
```

---

## Task 4: WCVP Context Query Functions

Add search and lookup functions that query the WCVP secondary database.

**Files:**
- Create: `lib/gallformers/wcvp/lookup.ex`
- Test: `test/gallformers/wcvp/lookup_test.exs`

**Step 1: Write failing tests**

Create `test/gallformers/wcvp/lookup_test.exs`. These tests need a WCVP test database. The test setup builds one using the build task's internals:

```elixir
defmodule Gallformers.Wcvp.LookupTest do
  use ExUnit.Case, async: false

  alias Gallformers.Wcvp.Lookup

  @test_db "priv/data/wcvp_test.sqlite"

  setup_all do
    # Build a minimal test WCVP database
    File.mkdir_p!("priv/data")
    File.rm(@test_db)

    {:ok, conn} = Exqlite.Sqlite3.open(@test_db)

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

    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE wcvp_distributions (
      plant_name_id TEXT NOT NULL,
      area_code_l3 TEXT NOT NULL,
      PRIMARY KEY (plant_name_id, area_code_l3)
    )
    """)

    Exqlite.Sqlite3.execute(conn, "CREATE INDEX idx_wcvp_names_taxon_name ON wcvp_names(taxon_name)")

    # Insert test data
    Exqlite.Sqlite3.execute(conn, "BEGIN")

    for {id, name, family, genus, species, authors, powo} <- [
          {"100", "Quercus alba", "Fagaceae", "Quercus", "alba", "L.", "powo-100"},
          {"101", "Quercus rubra", "Fagaceae", "Quercus", "rubra", "L.", "powo-101"},
          {"102", "Quercus velutina", "Fagaceae", "Quercus", "velutina", "Lam.", "powo-102"},
          {"200", "Rosa carolina", "Rosaceae", "Rosa", "carolina", "L.", "powo-200"}
        ] do
      {:ok, stmt} =
        Exqlite.Sqlite3.prepare(conn,
          "INSERT INTO wcvp_names VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"
        )

      Exqlite.Sqlite3.bind(conn, stmt, [id, name, family, genus, species, authors, powo])
      Exqlite.Sqlite3.step(conn, stmt)
    end

    for {id, code} <- [{"100", "ALB"}, {"100", "FLA"}, {"101", "NCA"}, {"200", "NCA"}] do
      {:ok, stmt} =
        Exqlite.Sqlite3.prepare(conn, "INSERT INTO wcvp_distributions VALUES (?1, ?2)")

      Exqlite.Sqlite3.bind(conn, stmt, [id, code])
      Exqlite.Sqlite3.step(conn, stmt)
    end

    Exqlite.Sqlite3.execute(conn, "COMMIT")
    Exqlite.Sqlite3.close(conn)

    # Start the WCVP repo for tests
    Gallformers.Repo.WCVP.start_link()

    on_exit(fn ->
      Gallformers.Repo.WCVP.stop()
      File.rm(@test_db)
    end)

    :ok
  end

  describe "available?/0" do
    test "returns true when repo is started" do
      assert Lookup.available?()
    end
  end

  describe "search/2" do
    test "finds species by name prefix" do
      results = Lookup.search("Quercus")
      assert length(results) == 3
      assert Enum.all?(results, fn r -> r.genus == "Quercus" end)
    end

    test "finds species by full binomial" do
      results = Lookup.search("Quercus alba")
      assert length(results) == 1
      assert hd(results).taxon_name == "Quercus alba"
    end

    test "is case-insensitive" do
      results = Lookup.search("quercus alba")
      assert length(results) == 1
    end

    test "respects limit option" do
      results = Lookup.search("Quercus", limit: 2)
      assert length(results) == 2
    end

    test "returns empty list for no match" do
      assert Lookup.search("Nonexistent") == []
    end
  end

  describe "get/1" do
    test "returns species with distributions by plant_name_id" do
      result = Lookup.get("100")
      assert result.taxon_name == "Quercus alba"
      assert result.family == "Fagaceae"
      assert result.powo_id == "powo-100"
      assert Enum.sort(result.distribution) == ["ALB", "FLA"]
    end

    test "returns nil for unknown ID" do
      assert Lookup.get("999") == nil
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/gallformers/wcvp/lookup_test.exs --seed 0`
Expected: `Gallformers.Wcvp.Lookup` not found.

**Step 3: Implement the lookup module**

Create `lib/gallformers/wcvp/lookup.ex`:

```elixir
defmodule Gallformers.Wcvp.Lookup do
  @moduledoc """
  Query functions for the WCVP secondary database.

  All functions return plain maps, not Ecto schemas.
  Returns empty results gracefully when the WCVP repo is not started.
  """

  import Ecto.Query

  alias Gallformers.Repo

  @doc """
  Returns whether the WCVP database is available for queries.
  """
  def available? do
    try do
      Repo.WCVP.query("SELECT 1")
      true
    rescue
      _ -> false
    catch
      :exit, _ -> false
    end
  end

  @doc """
  Searches WCVP names by prefix match on taxon_name.
  Returns a list of maps with name and family/genus info.
  """
  def search(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 20)
    pattern = "#{query}%"

    if available?() do
      from(n in "wcvp_names",
        where: fragment("lower(?) LIKE lower(?)", n.taxon_name, ^pattern),
        order_by: n.taxon_name,
        limit: ^limit,
        select: %{
          plant_name_id: n.plant_name_id,
          taxon_name: n.taxon_name,
          family: n.family,
          genus: n.genus,
          species: n.species,
          taxon_authors: n.taxon_authors,
          powo_id: n.powo_id
        }
      )
      |> Repo.WCVP.all()
    else
      []
    end
  end

  @doc """
  Looks up a WCVP species by plant_name_id.
  Returns a map with name info and distribution codes, or nil.
  """
  def get(plant_name_id) when is_binary(plant_name_id) do
    if available?() do
      case Repo.WCVP.one(
             from(n in "wcvp_names",
               where: n.plant_name_id == ^plant_name_id,
               select: %{
                 plant_name_id: n.plant_name_id,
                 taxon_name: n.taxon_name,
                 family: n.family,
                 genus: n.genus,
                 species: n.species,
                 taxon_authors: n.taxon_authors,
                 powo_id: n.powo_id
               }
             )
           ) do
        nil ->
          nil

        name ->
          distributions =
            from(d in "wcvp_distributions",
              where: d.plant_name_id == ^plant_name_id,
              select: d.area_code_l3
            )
            |> Repo.WCVP.all()

          Map.put(name, :distribution, distributions)
      end
    else
      nil
    end
  end
end
```

**Step 4: Run tests**

Run: `mix test test/gallformers/wcvp/lookup_test.exs --seed 0`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add lib/gallformers/wcvp/lookup.ex test/gallformers/wcvp/lookup_test.exs
git commit -m "Add WCVP lookup context with search and get functions"
```

---

## Task 5: Plants Context Integration

Wire WCVP data into host creation and update flows in the Plants context.

**Files:**
- Modify: `lib/gallformers/plants.ex` (add WCVP-aware creation/update helpers)
- Test: `test/gallformers/plants_test.exs` (add WCVP integration tests)

**Step 1: Write failing tests**

Add to `test/gallformers/plants_test.exs`:

```elixir
describe "host_traits management" do
  setup do
    {:ok, family} = Taxonomy.create_taxonomy(%{name: "Fagaceae", type: "family"})
    {:ok, genus} = Taxonomy.create_taxonomy(%{name: "Quercus", type: "genus", parent_id: family.id})

    {:ok, species} =
      Repo.insert(%Species{name: "Quercus alba", taxoncode: "plant"})

    Taxonomy.link_species_to_taxonomy(species.id, genus.id)

    {:ok, species: species}
  end

  test "upsert_host_traits/2 creates traits for a host", %{species: species} do
    {:ok, traits} =
      Plants.upsert_host_traits(species.id, %{wcvp_id: "12345", powo_id: "powo-12345"})

    assert traits.wcvp_id == "12345"
    assert traits.powo_id == "powo-12345"
  end

  test "upsert_host_traits/2 updates existing traits", %{species: species} do
    {:ok, _} = Plants.upsert_host_traits(species.id, %{wcvp_id: "12345"})
    {:ok, traits} = Plants.upsert_host_traits(species.id, %{wcvp_id: "99999"})

    assert traits.wcvp_id == "99999"
  end

  test "get_host_traits/1 returns traits or nil", %{species: species} do
    assert Plants.get_host_traits(species.id) == nil

    {:ok, _} = Plants.upsert_host_traits(species.id, %{wcvp_id: "12345"})
    traits = Plants.get_host_traits(species.id)

    assert traits.wcvp_id == "12345"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/gallformers/plants_test.exs --seed 0`
Expected: `Plants.upsert_host_traits/2` undefined.

**Step 3: Implement context functions**

Add to `lib/gallformers/plants.ex`:

```elixir
alias Gallformers.Plants.HostTraits

@doc """
Gets host traits for a species, or nil if none exist.
"""
@spec get_host_traits(integer()) :: HostTraits.t() | nil
def get_host_traits(species_id) do
  Repo.get(HostTraits, species_id)
end

@doc """
Creates or updates host traits for a species.
"""
@spec upsert_host_traits(integer(), map()) :: {:ok, HostTraits.t()} | {:error, Ecto.Changeset.t()}
def upsert_host_traits(species_id, attrs) do
  case Repo.get(HostTraits, species_id) do
    nil ->
      %HostTraits{species_id: species_id}
      |> HostTraits.changeset(attrs)
      |> Repo.insert()

    existing ->
      existing
      |> HostTraits.changeset(attrs)
      |> Repo.update()
  end
end
```

**Step 4: Run tests**

Run: `mix test test/gallformers/plants_test.exs --seed 0`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add lib/gallformers/plants.ex test/gallformers/plants_test.exs
git commit -m "Add host_traits context functions for WCVP ID management"
```

---

## Task 6: Admin UX — WCVP Typeahead on Host Creation

Add WCVP search to the host creation flow.

**Files:**
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex` (add WCVP search events and assigns)
- Modify: `lib/gallformers_web/live/admin/host_live/form.html.heex` (add WCVP typeahead UI)
- Test: `test/gallformers_web/live/admin/host_live/form_test.exs`

**This task requires the WCVP test database to be available.** The test setup from Task 4 creates the necessary test fixtures.

**Step 1: Add WCVP assigns and event handlers**

In `lib/gallformers_web/live/admin/host_live/form.ex`:

Add to `build_default_assigns/1` (the function that initializes all assigns):

```elixir
|> assign(:wcvp_search_query, "")
|> assign(:wcvp_search_results, [])
|> assign(:wcvp_selected, nil)
|> assign(:wcvp_available, Gallformers.Wcvp.Lookup.available?())
```

Add event handlers:

```elixir
@impl true
def handle_event("search_wcvp", %{"value" => query}, socket) do
  results =
    if String.length(query) >= 3 do
      Gallformers.Wcvp.Lookup.search(query, limit: 10)
    else
      []
    end

  {:noreply,
   socket
   |> assign(:wcvp_search_query, query)
   |> assign(:wcvp_search_results, results)}
end

@impl true
def handle_event("select_wcvp", %{"id" => plant_name_id}, socket) do
  case Gallformers.Wcvp.Lookup.get(plant_name_id) do
    nil ->
      {:noreply, put_flash(socket, :error, "WCVP species not found")}

    wcvp_data ->
      {:noreply,
       socket
       |> assign(:wcvp_selected, wcvp_data)
       |> assign(:wcvp_search_results, [])
       |> init_new_host_from_wcvp(wcvp_data)}
  end
end

@impl true
def handle_event("clear_wcvp", _params, socket) do
  {:noreply,
   socket
   |> assign(:wcvp_selected, nil)
   |> assign(:wcvp_search_query, "")
   |> assign(:wcvp_search_results, [])}
end
```

Add the WCVP-to-host initialization helper:

```elixir
defp init_new_host_from_wcvp(socket, wcvp_data) do
  # Use the existing init_new_host_state flow but with WCVP name
  socket = init_new_host_state(socket, wcvp_data.taxon_name)

  # Resolve WCVP distribution to gallformers places
  tdwg_lookup = Gallformers.Wcvp.Tdwg.load()
  places = Gallformers.Wcvp.Tdwg.convert_tdwg_codes(wcvp_data.distribution, tdwg_lookup)
  place_codes = Enum.map(places, & &1.code)

  matching_places =
    socket.assigns.all_places
    |> Enum.filter(fn p -> p.code in place_codes end)
    |> Enum.map(& &1.id)

  socket
  |> assign(:places, matching_places)
  |> assign(:wcvp_prefilled, %{
    wcvp_id: wcvp_data.plant_name_id,
    powo_id: wcvp_data.powo_id
  })
end
```

Modify `save_host/3` for `:new` mode to include host_traits when WCVP data was used:

After the successful `Plants.create_host_with_associations/1` call, add:

```elixir
{:ok, host} ->
  # Save WCVP IDs if this host was pre-filled from WCVP
  if wcvp = socket.assigns[:wcvp_prefilled] do
    Plants.upsert_host_traits(host.id, wcvp)
  end

  {:noreply,
   socket
   |> put_flash(:info, "Host created successfully")
   |> push_navigate(to: ~p"/admin/hosts/#{host.id}")}
```

**Step 2: Add WCVP typeahead to the template**

In the host form template (`form.html.heex`), add a WCVP search section that appears in `:new` mode, before the main form. This uses the existing `.typeahead` component:

```heex
<div :if={@live_action == :new && @wcvp_available} class="mb-6">
  <.card title="Pre-fill from WCVP" icon="globe">
    <.typeahead
      id="wcvp-search"
      query={@wcvp_search_query}
      results={@wcvp_search_results}
      selected={@wcvp_selected && @wcvp_selected.taxon_name}
      search_event="search_wcvp"
      select_event="select_wcvp"
      clear_event="clear_wcvp"
      placeholder="Search WCVP by species name..."
      label="WCVP Lookup"
      result_label_fn={fn r -> "#{r.taxon_name} #{r.taxon_authors} (#{r.family})" end}
      result_id_fn={fn r -> r.plant_name_id end}
    />
    <p class="text-xs text-gray-500 mt-1">
      Optional. Search the World Checklist of Vascular Plants to pre-fill taxonomy and range.
    </p>
  </.card>
</div>
```

**Step 3: Write LiveView test**

Add to `test/gallformers_web/live/admin/host_live/form_test.exs` (or create if needed):

```elixir
describe "WCVP integration" do
  test "shows WCVP search on new host form when available", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

    if Gallformers.Wcvp.Lookup.available?() do
      assert has_element?(view, "#wcvp-search")
    end
  end
end
```

**Step 4: Run tests**

Run: `mix test test/gallformers_web/live/admin/host_live/ --seed 0`
Expected: Tests pass.

**Step 5: Commit**

```bash
git add lib/gallformers_web/live/admin/host_live/form.ex lib/gallformers_web/live/admin/host_live/form.html.heex test/gallformers_web/live/admin/host_live/
git commit -m "Add WCVP typeahead to host creation form"
```

---

## Task 7: Admin UX — Refresh from WCVP on Host Edit

Add a "Refresh from WCVP" button to the host edit form.

**Files:**
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex` (add refresh event handler)
- Modify: `lib/gallformers_web/live/admin/host_live/form.html.heex` (add refresh button and diff display)

**Step 1: Add assigns and event handler**

Add to `build_default_assigns/1`:

```elixir
|> assign(:wcvp_diff, nil)
|> assign(:wcvp_refreshing, false)
```

Add to `load_host_for_edit/2`, load existing host_traits:

```elixir
|> assign(:host_traits, Plants.get_host_traits(host_id))
```

Add event handlers:

```elixir
@impl true
def handle_event("refresh_from_wcvp", _params, socket) do
  host_traits = socket.assigns.host_traits
  host = socket.assigns.host

  # Look up by wcvp_id if available, otherwise by name
  wcvp_data =
    cond do
      host_traits && host_traits.wcvp_id not in [nil, ""] ->
        Gallformers.Wcvp.Lookup.get(host_traits.wcvp_id)

      true ->
        case Gallformers.Wcvp.Lookup.search(host.name, limit: 1) do
          [match] -> Gallformers.Wcvp.Lookup.get(match.plant_name_id)
          [] -> nil
        end
    end

  case wcvp_data do
    nil ->
      {:noreply, put_flash(socket, :error, "No matching species found in WCVP")}

    data ->
      diff = build_wcvp_diff(socket, data)
      {:noreply, assign(socket, :wcvp_diff, diff)}
  end
end

@impl true
def handle_event("apply_wcvp_updates", _params, socket) do
  diff = socket.assigns.wcvp_diff

  with {:ok, _} <- apply_wcvp_range_updates(socket, diff),
       {:ok, _} <- Plants.upsert_host_traits(socket.assigns.host.id, %{
         wcvp_id: diff.wcvp_data.plant_name_id,
         powo_id: diff.wcvp_data.powo_id
       }) do
    {:noreply,
     socket
     |> assign(:wcvp_diff, nil)
     |> put_flash(:info, "Host updated from WCVP")
     |> push_navigate(to: ~p"/admin/hosts/#{socket.assigns.host.id}")}
  else
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Failed to apply WCVP updates: #{inspect(reason)}")}
  end
end

@impl true
def handle_event("cancel_wcvp_refresh", _params, socket) do
  {:noreply, assign(socket, :wcvp_diff, nil)}
end
```

Add helpers:

```elixir
defp build_wcvp_diff(socket, wcvp_data) do
  tdwg_lookup = Gallformers.Wcvp.Tdwg.load()
  wcvp_places = Gallformers.Wcvp.Tdwg.convert_tdwg_codes(wcvp_data.distribution, tdwg_lookup)
  wcvp_place_codes = MapSet.new(Enum.map(wcvp_places, & &1.code))

  current_places = socket.assigns.places
  current_place_codes =
    socket.assigns.all_places
    |> Enum.filter(fn p -> p.id in current_places end)
    |> Enum.map(& &1.code)
    |> MapSet.new()

  added = MapSet.difference(wcvp_place_codes, current_place_codes)
  removed = MapSet.difference(current_place_codes, wcvp_place_codes)

  %{
    wcvp_data: wcvp_data,
    places_added: MapSet.to_list(added),
    places_removed: MapSet.to_list(removed),
    has_changes: MapSet.size(added) > 0 or MapSet.size(removed) > 0
  }
end

defp apply_wcvp_range_updates(socket, diff) do
  host_id = socket.assigns.host.id
  tdwg_lookup = Gallformers.Wcvp.Tdwg.load()
  wcvp_places = Gallformers.Wcvp.Tdwg.convert_tdwg_codes(diff.wcvp_data.distribution, tdwg_lookup)
  wcvp_place_codes = Enum.map(wcvp_places, & &1.code)

  new_place_ids =
    socket.assigns.all_places
    |> Enum.filter(fn p -> p.code in wcvp_place_codes end)
    |> Enum.map(& &1.id)

  Ranges.update_host_places(host_id, new_place_ids)
end
```

**Step 2: Add refresh button and diff display to template**

In the edit form section of `form.html.heex`:

```heex
<div :if={@mode == :edit && @wcvp_available} class="mb-4">
  <.button
    :if={is_nil(@wcvp_diff)}
    phx-click="refresh_from_wcvp"
    type="button"
    kind="secondary"
    size="sm"
  >
    <.icon name="arrow-clockwise" class="w-4 h-4 mr-1" /> Refresh from WCVP
  </.button>

  <div :if={@wcvp_diff} class="border rounded-lg p-4 bg-amber-50 dark:bg-amber-950">
    <h4 class="font-medium mb-2">WCVP Data Comparison</h4>

    <div :if={!@wcvp_diff.has_changes} class="text-sm text-gray-600">
      No differences found. Host data matches WCVP.
    </div>

    <div :if={@wcvp_diff.has_changes} class="text-sm space-y-2">
      <div :if={@wcvp_diff.places_added != []}>
        <span class="font-medium text-green-700">+ Places to add:</span>
        <%= Enum.join(@wcvp_diff.places_added, ", ") %>
      </div>
      <div :if={@wcvp_diff.places_removed != []}>
        <span class="font-medium text-red-700">- Places to remove:</span>
        <%= Enum.join(@wcvp_diff.places_removed, ", ") %>
      </div>
    </div>

    <div class="mt-3 flex gap-2">
      <.button :if={@wcvp_diff.has_changes} phx-click="apply_wcvp_updates" type="button" size="sm">
        Apply Updates
      </.button>
      <.button phx-click="cancel_wcvp_refresh" type="button" kind="secondary" size="sm">
        Cancel
      </.button>
    </div>
  </div>
</div>
```

**Step 3: Run tests and manual verification**

Run: `mix compile --warnings-as-errors && mix test test/gallformers_web/live/admin/host_live/ --seed 0`
Expected: Tests pass, no compilation warnings.

**Step 4: Commit**

```bash
git add lib/gallformers_web/live/admin/host_live/form.ex lib/gallformers_web/live/admin/host_live/form.html.heex
git commit -m "Add Refresh from WCVP button to host edit form"
```

---

## Task 8: Backfill WCVP IDs for Existing Hosts

Create a one-time mix task to backfill `wcvp_id` and `powo_id` for hosts already matched through the reconciliation pipeline.

**Files:**
- Create: `lib/mix/tasks/gallformers/wcvp/backfill_ids.ex`
- Test: manual verification (depends on real WCVP data)

**Step 1: Implement the backfill task**

Create `lib/mix/tasks/gallformers/wcvp/backfill_ids.ex`:

```elixir
defmodule Mix.Tasks.Gallformers.Wcvp.BackfillIds do
  @moduledoc """
  Backfills wcvp_id and powo_id into host_traits for existing host species
  by matching against the WCVP names database.

  ## Usage

      mix gallformers.wcvp.backfill_ids           # dry run
      mix gallformers.wcvp.backfill_ids --commit   # write to database
  """

  use Mix.Task
  require Logger

  alias Gallformers.Plants
  alias Gallformers.Plants.HostTraits
  alias Gallformers.Repo
  alias Gallformers.Wcvp.Lookup

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [commit: :boolean])
    commit? = opts[:commit] || false

    unless Lookup.available?() do
      Logger.error("WCVP database not available. Run mix gallformers.wcvp.build_db first.")
      exit(:shutdown)
    end

    # Get all host species without host_traits (or with nil wcvp_id)
    hosts =
      from(s in "species",
        left_join: ht in "host_traits",
        on: s.id == ht.species_id,
        where: s.taxoncode == "plant" and is_nil(ht.wcvp_id),
        select: %{id: s.id, name: s.name}
      )
      |> Repo.all()

    Logger.info("Found #{length(hosts)} hosts without WCVP IDs")

    matched =
      Enum.reduce(hosts, 0, fn host, count ->
        case Lookup.search(host.name, limit: 1) do
          [match] when match.taxon_name == host.name ->
            if commit? do
              wcvp_data = Lookup.get(match.plant_name_id)

              Plants.upsert_host_traits(host.id, %{
                wcvp_id: match.plant_name_id,
                powo_id: wcvp_data && wcvp_data.powo_id
              })
            end

            Logger.info("  Matched: #{host.name} -> WCVP #{match.plant_name_id}")
            count + 1

          _ ->
            count
        end
      end)

    Logger.info("Matched #{matched}/#{length(hosts)} hosts")

    unless commit? do
      Logger.info("Dry run complete. Use --commit to write changes.")
    end
  end
end
```

**Step 2: Add import for Ecto.Query**

Add `import Ecto.Query` at the top of the module.

**Step 3: Run dry run**

Run: `mix gallformers.wcvp.backfill_ids`
Expected: Shows matched hosts without writing.

**Step 4: Commit**

```bash
git add lib/mix/tasks/gallformers/wcvp/backfill_ids.ex
git commit -m "Add mix task to backfill WCVP IDs for existing hosts"
```

---

## Task 9: Final Verification and Precommit

**Step 1: Run full precommit**

Run: `mix precommit`
Expected: Format, credo, compile (with --warnings-as-errors), and all tests pass.

**Step 2: Manual smoke test**

1. Build the WCVP database: `mix gallformers.wcvp.build_db`
2. Start the dev server: `mix phx.server`
3. Navigate to `/admin/hosts/new`
4. Verify the WCVP search field appears
5. Search for "Quercus alba" — should show results from WCVP
6. Select a result — form should pre-fill with name, taxonomy, and range
7. Navigate to an existing host's edit page
8. Click "Refresh from WCVP" — should show diff or "no differences"

**Step 3: Final commit if any fixups needed**

```bash
git add -A
git commit -m "Fix issues found during smoke testing"
```

---

Plan complete and saved to `docs/plans/2026-02-20-wcvp-live-lookup-implementation.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?