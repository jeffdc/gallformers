defmodule Mix.Tasks.Gallformers.Wcvp.BuildDbTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Gallformers.Wcvp.BuildDb

  @test_dir "test/tmp/wcvp_build"

  setup do
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    # Write minimal test CSV files (pipe-delimited, matching real WCVP format)
    # Headers must match the real WCVP file headers exactly
    names_csv =
      """
      plant_name_id|ipni_id|taxon_rank|taxon_status|family|genus_hybrid|genus|species_hybrid|species|infraspecific_rank|infraspecies|parenthetical_author|primary_author|publication_author|place_of_publication|volume_and_page|first_published|nomenclatural_remarks|geographic_area|lifeform_description|climate_description|taxon_name|taxon_authors|accepted_plant_name_id|basionym_plant_name_id|replaced_synonym_author|homotypic_synonym|parent_plant_name_id|powo_id|hybrid_formula|reviewed
      100|ipni-100|Species|Accepted|Fagaceae||Quercus||alba|||||||||||||Quercus alba|L.|100|||||urn:lsid:ipni.org:names:100-1||
      200|ipni-200|Species|Accepted|Rosaceae||Rosa||carolina|||||||||||||Rosa carolina|L.|200|||||urn:lsid:ipni.org:names:200-1||
      300|ipni-300|Species|Accepted|Poaceae||Zea||mays|||||||||||||Zea mays|L.|300|||||urn:lsid:ipni.org:names:300-1||
      400|ipni-400|Species|Synonym|Fagaceae||Quercus||stellata|||||||||||||Quercus stellata|Wangenh.|100|||||urn:lsid:ipni.org:names:400-1||
      """

    dist_csv =
      """
      plant_locality_id|plant_name_id|continent_code_l1|continent|region_code_l2|region|area_code_l3|area|introduced|extinct|location_doubtful
      1|100|7|NORTHERN AMERICA|71|Southeastern U.S.A.|ALA|Alabama|0|0|0
      2|100|7|NORTHERN AMERICA|74|Southeastern U.S.A.|FLA|Florida|0|0|0
      3|200|7|NORTHERN AMERICA|78|Southeastern U.S.A.|NCA|North Carolina|0|0|0
      4|300|3|SOUTHERN AFRICA|30|Southern Africa|ZAF|South Africa|0|0|0
      5|100|7|NORTHERN AMERICA|78|Southeastern U.S.A.|NCA|North Carolina|1|0|0
      """

    File.write!(Path.join(@test_dir, "wcvp_names.csv"), String.trim(names_csv))
    File.write!(Path.join(@test_dir, "wcvp_distribution.csv"), String.trim(dist_csv))

    on_exit(fn -> File.rm_rf!(@test_dir) end)

    {:ok, dir: @test_dir}
  end

  test "builds SQLite database with filtered data", %{dir: dir} do
    db_path = Path.join(dir, "wcvp.sqlite")

    BuildDb.run([
      "--names",
      Path.join(dir, "wcvp_names.csv"),
      "--dist",
      Path.join(dir, "wcvp_distribution.csv"),
      "--output",
      db_path
    ])

    assert File.exists?(db_path)

    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    # Quercus alba and Rosa carolina should be present (have Western Hemisphere distribution)
    # Zea mays should NOT be present (only has South Africa distribution)
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM wcvp_names")
    {:row, [count]} = Exqlite.Sqlite3.step(conn, stmt)
    assert count == 2
    Exqlite.Sqlite3.release(conn, stmt)

    # Distribution rows: 2 native for Quercus alba + 1 introduced + 1 for Rosa carolina = 4
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM wcvp_distributions")
    {:row, [count]} = Exqlite.Sqlite3.step(conn, stmt)
    assert count == 4
    Exqlite.Sqlite3.release(conn, stmt)

    # Verify introduced flag is stored correctly
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT area_code_l3, introduced FROM wcvp_distributions WHERE plant_name_id = '100' ORDER BY area_code_l3, introduced"
      )

    {:row, ["ALA", 0]} = Exqlite.Sqlite3.step(conn, stmt)
    {:row, ["FLA", 0]} = Exqlite.Sqlite3.step(conn, stmt)
    {:row, ["NCA", 1]} = Exqlite.Sqlite3.step(conn, stmt)
    :done = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    # Verify Quercus alba data
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT taxon_name, family, powo_id FROM wcvp_names WHERE plant_name_id = '100'"
      )

    {:row, [name, family, powo_id]} = Exqlite.Sqlite3.step(conn, stmt)
    assert name == "Quercus alba"
    assert family == "Fagaceae"
    assert powo_id == "urn:lsid:ipni.org:names:100-1"
    Exqlite.Sqlite3.release(conn, stmt)

    :ok = Exqlite.Sqlite3.close(conn)
  end

  test "excludes species with only non-Western-Hemisphere distribution", %{dir: dir} do
    db_path = Path.join(dir, "wcvp.sqlite")

    BuildDb.run([
      "--names",
      Path.join(dir, "wcvp_names.csv"),
      "--dist",
      Path.join(dir, "wcvp_distribution.csv"),
      "--output",
      db_path
    ])

    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    # Zea mays (id 300) has only ZAF distribution, should be excluded
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT COUNT(*) FROM wcvp_names WHERE plant_name_id = '300'"
      )

    {:row, [count]} = Exqlite.Sqlite3.step(conn, stmt)
    assert count == 0
    Exqlite.Sqlite3.release(conn, stmt)

    :ok = Exqlite.Sqlite3.close(conn)
  end

  test "excludes synonyms from names table", %{dir: dir} do
    db_path = Path.join(dir, "wcvp.sqlite")

    BuildDb.run([
      "--names",
      Path.join(dir, "wcvp_names.csv"),
      "--dist",
      Path.join(dir, "wcvp_distribution.csv"),
      "--output",
      db_path
    ])

    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    # Quercus stellata (id 400) is a synonym, should be excluded
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT COUNT(*) FROM wcvp_names WHERE plant_name_id = '400'"
      )

    {:row, [count]} = Exqlite.Sqlite3.step(conn, stmt)
    assert count == 0
    Exqlite.Sqlite3.release(conn, stmt)

    :ok = Exqlite.Sqlite3.close(conn)
  end
end
