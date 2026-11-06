defmodule Mix.Tasks.Gallformers.Wcvp.BuildDbTest do
  use ExUnit.Case, async: false

  alias Gallformers.Repo
  alias Mix.Tasks.Gallformers.Wcvp.BuildDb

  @names_path "test/support/fixtures/wcvp_names_sample.csv"
  @dist_path "test/support/fixtures/wcvp_distributions_sample.csv"

  setup do
    # This checkout's WCVP test database (config/test_db_names.exs), for
    # verification queries
    database = Repo.WCVP.config()[:database]

    conn_opts = [
      database: database,
      username: System.get_env("PGUSER") || System.get_env("USER"),
      password: System.get_env("PGPASSWORD"),
      hostname: System.get_env("PGHOST") || "localhost"
    ]

    on_exit(fn ->
      # Restore fixture state for other tests that query the WCVP test database directly
      # (e.g., host_range_live_test calls Wcvp.Lookup.built_at() which hits the real DB)
      System.cmd("psql", ["-d", database, "-f", "priv/repo/wcvp_test_setup.sql", "--quiet"],
        stderr_to_stdout: true
      )
    end)

    {:ok, conn_opts: conn_opts}
  end

  describe "build_db" do
    test "creates all three tables", %{conn_opts: conn_opts} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path])

      {:ok, conn} = Postgrex.start_link(conn_opts)

      %{rows: rows} =
        Postgrex.query!(
          conn,
          """
          SELECT table_name FROM information_schema.tables
          WHERE table_schema = 'public'
          ORDER BY table_name
          """,
          []
        )

      tables = Enum.map(rows, fn [name] -> name end)
      assert tables == ["meta", "wcvp_distributions", "wcvp_names"]

      GenServer.stop(conn)
    end

    test "wcvp_names has ALL rows from sample (including synonyms, unplaced, varieties)",
         %{conn_opts: conn_opts} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path])

      {:ok, conn} = Postgrex.start_link(conn_opts)

      %{rows: [[count]]} = Postgrex.query!(conn, "SELECT COUNT(*) FROM wcvp_names", [])
      assert count == 9

      # Verify synonym is present
      %{rows: [[status]]} =
        Postgrex.query!(
          conn,
          "SELECT taxon_status FROM wcvp_names WHERE plant_name_id = $1",
          ["102"]
        )

      assert status == "Synonym"

      # Verify unplaced is present
      %{rows: [[status]]} =
        Postgrex.query!(
          conn,
          "SELECT taxon_status FROM wcvp_names WHERE plant_name_id = $1",
          ["107"]
        )

      assert status == "Unplaced"

      # Verify variety is present
      %{rows: [[rank]]} =
        Postgrex.query!(
          conn,
          "SELECT taxon_rank FROM wcvp_names WHERE plant_name_id = $1",
          ["108"]
        )

      assert rank == "Variety"

      GenServer.stop(conn)
    end

    test "wcvp_distributions has ALL rows (including introduced and extinct)",
         %{conn_opts: conn_opts} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path])

      {:ok, conn} = Postgrex.start_link(conn_opts)

      %{rows: [[count]]} =
        Postgrex.query!(conn, "SELECT COUNT(*) FROM wcvp_distributions", [])

      assert count == 13

      # Verify introduced row is present
      %{rows: [[introduced]]} =
        Postgrex.query!(
          conn,
          "SELECT introduced FROM wcvp_distributions WHERE plant_locality_id = $1",
          ["12"]
        )

      assert introduced == "1"

      # Verify extinct row is present
      %{rows: [[extinct]]} =
        Postgrex.query!(
          conn,
          "SELECT extinct FROM wcvp_distributions WHERE plant_locality_id = $1",
          ["13"]
        )

      assert extinct == "1"

      GenServer.stop(conn)
    end

    test "meta table has built_at with ISO 8601 timestamp", %{conn_opts: conn_opts} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path])

      {:ok, conn} = Postgrex.start_link(conn_opts)

      %{rows: [[value]]} =
        Postgrex.query!(conn, "SELECT value FROM meta WHERE key = $1", ["built_at"])

      # ISO 8601 format: 2026-03-09T...
      assert value =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

      GenServer.stop(conn)
    end

    test "all 31 name columns are present", %{conn_opts: conn_opts} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path])

      {:ok, conn} = Postgrex.start_link(conn_opts)

      %{rows: rows} =
        Postgrex.query!(
          conn,
          """
          SELECT column_name FROM information_schema.columns
          WHERE table_name = 'wcvp_names' AND table_schema = 'public'
          ORDER BY ordinal_position
          """,
          []
        )

      columns = Enum.map(rows, fn [name] -> name end)
      assert length(columns) == 31

      expected = ~w[
        plant_name_id ipni_id taxon_rank taxon_status family genus_hybrid genus
        species_hybrid species infraspecific_rank infraspecies parenthetical_author
        primary_author publication_author place_of_publication volume_and_page
        first_published nomenclatural_remarks geographic_area lifeform_description
        climate_description taxon_name taxon_authors accepted_plant_name_id
        basionym_plant_name_id replaced_synonym_author homotypic_synonym
        parent_plant_name_id powo_id hybrid_formula reviewed
      ]

      assert columns == expected
    end

    test "all 11 distribution columns are present", %{conn_opts: conn_opts} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path])

      {:ok, conn} = Postgrex.start_link(conn_opts)

      %{rows: rows} =
        Postgrex.query!(
          conn,
          """
          SELECT column_name FROM information_schema.columns
          WHERE table_name = 'wcvp_distributions' AND table_schema = 'public'
          ORDER BY ordinal_position
          """,
          []
        )

      columns = Enum.map(rows, fn [name] -> name end)
      assert length(columns) == 11

      expected = ~w[
        plant_locality_id plant_name_id continent_code_l1 continent region_code_l2
        region area_code_l3 area introduced extinct location_doubtful
      ]

      assert columns == expected
    end

    test "synonym record has correct accepted_plant_name_id", %{conn_opts: conn_opts} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path])

      {:ok, conn} = Postgrex.start_link(conn_opts)

      %{rows: [[accepted_id]]} =
        Postgrex.query!(
          conn,
          "SELECT accepted_plant_name_id FROM wcvp_names WHERE plant_name_id = $1",
          ["102"]
        )

      assert accepted_id == "101"

      GenServer.stop(conn)
    end
  end
end
