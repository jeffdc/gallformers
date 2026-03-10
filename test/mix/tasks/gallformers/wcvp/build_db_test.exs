defmodule Mix.Tasks.Gallformers.Wcvp.BuildDbTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Gallformers.Wcvp.BuildDb

  @names_path "test/support/fixtures/wcvp_names_sample.csv"
  @dist_path "test/support/fixtures/wcvp_distributions_sample.csv"

  setup do
    output =
      Path.join(System.tmp_dir!(), "test_wcvp_#{System.unique_integer([:positive])}.sqlite")

    on_exit(fn -> File.rm(output) end)
    {:ok, output: output}
  end

  describe "build_db" do
    test "creates all three tables", %{output: output} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path, "--output", output])

      {:ok, conn} = Exqlite.Sqlite3.open(output)

      tables = query_all(conn, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
      assert tables == [["meta"], ["wcvp_distributions"], ["wcvp_names"]]

      :ok = Exqlite.Sqlite3.close(conn)
    end

    test "wcvp_names has ALL rows from sample (including synonyms, unplaced, varieties)", %{
      output: output
    } do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path, "--output", output])

      {:ok, conn} = Exqlite.Sqlite3.open(output)

      [[count]] = query_all(conn, "SELECT COUNT(*) FROM wcvp_names")
      assert count == 9

      # Verify synonym is present
      [[status]] =
        query_all(conn, "SELECT taxon_status FROM wcvp_names WHERE plant_name_id = '102'")

      assert status == "Synonym"

      # Verify unplaced is present
      [[status]] =
        query_all(conn, "SELECT taxon_status FROM wcvp_names WHERE plant_name_id = '107'")

      assert status == "Unplaced"

      # Verify variety is present
      [[rank]] =
        query_all(conn, "SELECT taxon_rank FROM wcvp_names WHERE plant_name_id = '108'")

      assert rank == "Variety"

      :ok = Exqlite.Sqlite3.close(conn)
    end

    test "wcvp_distributions has ALL rows (including introduced and extinct)", %{output: output} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path, "--output", output])

      {:ok, conn} = Exqlite.Sqlite3.open(output)

      [[count]] = query_all(conn, "SELECT COUNT(*) FROM wcvp_distributions")
      assert count == 13

      # Verify introduced row is present
      [[introduced]] =
        query_all(
          conn,
          "SELECT introduced FROM wcvp_distributions WHERE plant_locality_id = '12'"
        )

      assert introduced == "1"

      # Verify extinct row is present
      [[extinct]] =
        query_all(
          conn,
          "SELECT extinct FROM wcvp_distributions WHERE plant_locality_id = '13'"
        )

      assert extinct == "1"

      :ok = Exqlite.Sqlite3.close(conn)
    end

    test "meta table has built_at with ISO 8601 timestamp", %{output: output} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path, "--output", output])

      {:ok, conn} = Exqlite.Sqlite3.open(output)

      [[value]] = query_all(conn, "SELECT value FROM meta WHERE key = 'built_at'")
      # ISO 8601 format: 2026-03-09T...
      assert value =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

      :ok = Exqlite.Sqlite3.close(conn)
    end

    test "all 31 name columns are present", %{output: output} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path, "--output", output])

      {:ok, conn} = Exqlite.Sqlite3.open(output)

      columns =
        query_all(conn, "PRAGMA table_info(wcvp_names)")
        |> Enum.map(fn row -> Enum.at(row, 1) end)

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

    test "all 11 distribution columns are present", %{output: output} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path, "--output", output])

      {:ok, conn} = Exqlite.Sqlite3.open(output)

      columns =
        query_all(conn, "PRAGMA table_info(wcvp_distributions)")
        |> Enum.map(fn row -> Enum.at(row, 1) end)

      assert length(columns) == 11

      expected = ~w[
        plant_locality_id plant_name_id continent_code_l1 continent region_code_l2
        region area_code_l3 area introduced extinct location_doubtful
      ]

      assert columns == expected
    end

    test "synonym record has correct accepted_plant_name_id", %{output: output} do
      BuildDb.run(["--names", @names_path, "--dist", @dist_path, "--output", output])

      {:ok, conn} = Exqlite.Sqlite3.open(output)

      [[accepted_id]] =
        query_all(
          conn,
          "SELECT accepted_plant_name_id FROM wcvp_names WHERE plant_name_id = '102'"
        )

      assert accepted_id == "101"

      :ok = Exqlite.Sqlite3.close(conn)
    end
  end

  # Helper to run a query and collect all rows
  defp query_all(conn, sql) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
    rows = collect_rows(conn, stmt, [])
    Exqlite.Sqlite3.release(conn, stmt)
    rows
  end

  defp collect_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> collect_rows(conn, stmt, acc ++ [row])
      :done -> acc
    end
  end
end
