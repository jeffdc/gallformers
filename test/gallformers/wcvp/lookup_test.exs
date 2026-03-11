defmodule Gallformers.Wcvp.LookupTest do
  use ExUnit.Case, async: false

  alias Gallformers.Repo
  alias Gallformers.Wcvp.Lookup

  @db_path Application.compile_env(:gallformers, Repo.WCVP)[:database]

  setup_all do
    # Ensure the directory exists
    @db_path |> Path.dirname() |> File.mkdir_p!()

    # Create a minimal WCVP test database (drop first in case a prior run left stale files)
    {:ok, conn} = Exqlite.Sqlite3.open(@db_path)

    :ok = Exqlite.Sqlite3.execute(conn, "DROP TABLE IF EXISTS wcvp_distributions")
    :ok = Exqlite.Sqlite3.execute(conn, "DROP TABLE IF EXISTS wcvp_names")

    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE wcvp_names (
        plant_name_id TEXT PRIMARY KEY,
        taxon_name TEXT NOT NULL,
        taxon_status TEXT NOT NULL DEFAULT 'Accepted',
        accepted_plant_name_id TEXT,
        family TEXT NOT NULL,
        genus TEXT NOT NULL,
        species TEXT NOT NULL,
        taxon_authors TEXT,
        powo_id TEXT
      )
      """)

    :ok = Exqlite.Sqlite3.execute(conn, "DROP TABLE IF EXISTS meta")

    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)
      """)

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "INSERT INTO meta (key, value) VALUES ('built_at', '2026-03-01T00:00:00Z')"
      )

    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE wcvp_distributions (
        plant_name_id TEXT NOT NULL,
        area_code_l3 TEXT NOT NULL,
        introduced TEXT NOT NULL DEFAULT '0',
        extinct TEXT NOT NULL DEFAULT '0',
        location_doubtful TEXT NOT NULL DEFAULT '0',
        PRIMARY KEY (plant_name_id, area_code_l3, introduced),
        FOREIGN KEY (plant_name_id) REFERENCES wcvp_names(plant_name_id)
      )
      """)

    # Insert test names
    {:ok, name_stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "INSERT INTO wcvp_names (plant_name_id, taxon_name, taxon_status, accepted_plant_name_id, family, genus, species, taxon_authors, powo_id) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"
      )

    names = [
      [
        "100",
        "Quercus alba",
        "Accepted",
        "100",
        "Fagaceae",
        "Quercus",
        "alba",
        "L.",
        "urn:lsid:ipni.org:names:295763-1"
      ],
      [
        "101",
        "Quercus rubra",
        "Accepted",
        "101",
        "Fagaceae",
        "Quercus",
        "rubra",
        "L.",
        "urn:lsid:ipni.org:names:295776-1"
      ],
      [
        "102",
        "Quercus velutina",
        "Accepted",
        "102",
        "Fagaceae",
        "Quercus",
        "velutina",
        "Lam.",
        nil
      ],
      [
        "200",
        "Rosa carolina",
        "Accepted",
        "200",
        "Rosaceae",
        "Rosa",
        "carolina",
        "L.",
        "urn:lsid:ipni.org:names:726498-1"
      ],
      [
        "300",
        "Alnus alnobetula subsp. sinuata",
        "Accepted",
        "300",
        "Betulaceae",
        "Alnus",
        "alnobetula",
        "(Regel) Raus",
        nil
      ],
      [
        "301",
        "Alnus incana",
        "Accepted",
        "301",
        "Betulaceae",
        "Alnus",
        "incana",
        "(L.) Moench",
        nil
      ],
      [
        "400",
        "Quercus borealis",
        "Synonym",
        "101",
        "Fagaceae",
        "Quercus",
        "borealis",
        "F.Michx.",
        nil
      ]
    ]

    for params <- names do
      :ok = Exqlite.Sqlite3.bind(name_stmt, params)
      :done = Exqlite.Sqlite3.step(conn, name_stmt)
      :ok = Exqlite.Sqlite3.reset(name_stmt)
    end

    Exqlite.Sqlite3.release(conn, name_stmt)

    # Insert test distributions (plant_name_id, area_code_l3, introduced)
    {:ok, dist_stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "INSERT INTO wcvp_distributions (plant_name_id, area_code_l3, introduced) VALUES (?1, ?2, ?3)"
      )

    distributions = [
      ["100", "ALB", "0"],
      ["100", "FLA", "0"],
      ["100", "NCA", "1"],
      ["101", "NCA", "0"],
      ["200", "NCA", "0"]
    ]

    for params <- distributions do
      :ok = Exqlite.Sqlite3.bind(dist_stmt, params)
      :done = Exqlite.Sqlite3.step(conn, dist_stmt)
      :ok = Exqlite.Sqlite3.reset(dist_stmt)
    end

    Exqlite.Sqlite3.release(conn, dist_stmt)
    Exqlite.Sqlite3.close(conn)

    # Start the WCVP repo (may already be running from another test module)
    case Repo.WCVP.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    on_exit(fn ->
      File.rm(@db_path)
    end)

    :ok
  end

  describe "available?/0" do
    test "returns true when repo is started" do
      assert Lookup.available?()
    end
  end

  describe "built_at/0" do
    test "returns a DateTime from the meta table" do
      result = Lookup.built_at()
      assert %DateTime{} = result
      assert result == ~U[2026-03-01 00:00:00Z]
    end
  end

  describe "search/2" do
    test "finds species by genus prefix" do
      results = Lookup.search("Quercus")
      assert length(results) == 3
      assert Enum.all?(results, fn r -> r.genus == "Quercus" end)
    end

    test "finds exact species by full name" do
      results = Lookup.search("Quercus alba")
      assert length(results) == 1
      assert hd(results).taxon_name == "Quercus alba"
    end

    test "is case insensitive" do
      results = Lookup.search("quercus alba")
      assert length(results) == 1
      assert hd(results).taxon_name == "Quercus alba"
    end

    test "respects limit option" do
      results = Lookup.search("Quercus", limit: 2)
      assert length(results) == 2
    end

    test "returns empty list for nonexistent name" do
      assert Lookup.search("Nonexistent") == []
    end
  end

  describe "search_contains/2" do
    test "matches subspecies by epithet appearing anywhere in name" do
      results = Lookup.search_contains("Alnus sinuata")
      assert length(results) == 1
      assert hd(results).taxon_name == "Alnus alnobetula subsp. sinuata"
    end

    test "splits query into independent terms" do
      results = Lookup.search_contains("Aln sin")
      assert length(results) == 1
      assert hd(results).taxon_name == "Alnus alnobetula subsp. sinuata"
    end

    test "matches genus-only query" do
      results = Lookup.search_contains("Alnus")
      assert length(results) == 2
      assert Enum.all?(results, fn r -> r.genus == "Alnus" end)
    end

    test "is case insensitive" do
      results = Lookup.search_contains("alnus sinuata")
      assert length(results) == 1
      assert hd(results).taxon_name == "Alnus alnobetula subsp. sinuata"
    end

    test "respects limit option" do
      results = Lookup.search_contains("Quercus", limit: 1)
      assert length(results) == 1
    end

    test "returns empty list for no matches" do
      assert Lookup.search_contains("Nonexistent") == []
    end
  end

  describe "get/1" do
    test "returns species with separate native and introduced distributions" do
      result = Lookup.get("100")
      assert result.taxon_name == "Quercus alba"
      assert result.family == "Fagaceae"
      assert result.genus == "Quercus"
      assert result.species == "alba"
      assert result.taxon_authors == "L."
      assert result.powo_id == "urn:lsid:ipni.org:names:295763-1"
      assert result.native_distribution == ["ALB", "FLA"]
      assert result.introduced_distribution == ["NCA"]
    end

    test "returns empty introduced list when all distributions are native" do
      result = Lookup.get("101")
      assert result.native_distribution == ["NCA"]
      assert result.introduced_distribution == []
    end

    test "returns nil for nonexistent plant_name_id" do
      assert Lookup.get("999") == nil
    end
  end

  describe "search/2 with include_synonyms" do
    test "excludes synonyms by default" do
      results = Lookup.search("Quercus")
      assert length(results) == 3
      refute Enum.any?(results, fn r -> r.taxon_status == "Synonym" end)
    end

    test "includes synonyms when option is set" do
      results = Lookup.search("Quercus", include_synonyms: true)
      assert length(results) == 4
      assert Enum.any?(results, fn r -> r.taxon_status == "Synonym" end)
    end

    test "includes taxon_status and accepted_plant_name_id in results" do
      [result | _] = Lookup.search("Quercus alba")
      assert Map.has_key?(result, :taxon_status)
      assert Map.has_key?(result, :accepted_plant_name_id)
      assert result.taxon_status == "Accepted"
    end
  end

  describe "search_contains/2 with include_synonyms" do
    test "excludes synonyms by default" do
      results = Lookup.search_contains("Quercus")
      assert length(results) == 3
      refute Enum.any?(results, fn r -> r.taxon_status == "Synonym" end)
    end

    test "includes synonyms when option is set" do
      results = Lookup.search_contains("Quercus", include_synonyms: true)
      assert length(results) == 4
      assert Enum.any?(results, fn r -> r.taxon_status == "Synonym" end)
    end
  end

  describe "match_by_name/1" do
    test "returns accepted name record for exact match" do
      result = Lookup.match_by_name("Quercus alba")
      assert result.plant_name_id == "100"
      assert result.taxon_name == "Quercus alba"
      assert result.taxon_status == "Accepted"
      assert result.family == "Fagaceae"
      assert result.genus == "Quercus"
      assert result.species == "alba"
      assert result.taxon_authors == "L."
      assert result.powo_id == "urn:lsid:ipni.org:names:295763-1"
    end

    test "returns nil for non-existent name" do
      assert Lookup.match_by_name("Nonexistent species") == nil
    end

    test "returns nil for synonym name (only matches accepted)" do
      assert Lookup.match_by_name("Quercus borealis") == nil
    end

    test "resolves synonym to accepted name when resolve_synonyms is true" do
      result = Lookup.match_by_name("Quercus borealis", resolve_synonyms: true)
      assert result.plant_name_id == "101"
      assert result.taxon_name == "Quercus rubra"
      assert result.taxon_status == "Accepted"
    end

    test "still returns accepted name directly with resolve_synonyms" do
      result = Lookup.match_by_name("Quercus alba", resolve_synonyms: true)
      assert result.plant_name_id == "100"
      assert result.taxon_name == "Quercus alba"
    end

    test "returns nil for non-existent name even with resolve_synonyms" do
      assert Lookup.match_by_name("Nonexistent species", resolve_synonyms: true) == nil
    end
  end

  describe "get_accepted_name/1" do
    test "returns accepted name for a synonym" do
      result = Lookup.get_accepted_name("400")
      assert result.plant_name_id == "101"
      assert result.taxon_name == "Quercus rubra"
      assert result.taxon_status == "Accepted"
    end

    test "returns nil for an already-accepted name" do
      assert Lookup.get_accepted_name("100") == nil
    end

    test "returns nil for nonexistent plant_name_id" do
      assert Lookup.get_accepted_name("999") == nil
    end
  end
end
