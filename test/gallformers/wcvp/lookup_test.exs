defmodule Gallformers.Wcvp.LookupTest do
  use ExUnit.Case, async: true

  alias Gallformers.Repo
  alias Gallformers.Wcvp.{Lookup, WcvpName}

  setup_all do
    # Create tables and load fixture data into wcvp_test via Repo.WCVP
    Repo.WCVP.query!("DROP TABLE IF EXISTS wcvp_distributions")
    Repo.WCVP.query!("DROP TABLE IF EXISTS wcvp_names")
    Repo.WCVP.query!("DROP TABLE IF EXISTS meta")

    Repo.WCVP.query!("""
    CREATE TABLE wcvp_names (
      plant_name_id TEXT PRIMARY KEY,
      taxon_name TEXT NOT NULL,
      taxon_rank TEXT,
      taxon_status TEXT NOT NULL DEFAULT 'Accepted',
      accepted_plant_name_id TEXT,
      family TEXT NOT NULL,
      genus TEXT NOT NULL,
      species TEXT NOT NULL,
      taxon_authors TEXT,
      powo_id TEXT
    )
    """)

    Repo.WCVP.query!("""
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)
    """)

    Repo.WCVP.query!("INSERT INTO meta (key, value) VALUES ('built_at', '2026-03-01T00:00:00Z')")

    Repo.WCVP.query!("""
    CREATE TABLE wcvp_distributions (
      plant_locality_id TEXT PRIMARY KEY,
      plant_name_id TEXT NOT NULL,
      area_code_l3 TEXT NOT NULL,
      introduced TEXT NOT NULL DEFAULT '0',
      extinct TEXT NOT NULL DEFAULT '0',
      location_doubtful TEXT NOT NULL DEFAULT '0',
      FOREIGN KEY (plant_name_id) REFERENCES wcvp_names(plant_name_id)
    )
    """)

    # Insert test names
    names = [
      {"100", "Quercus alba", "Accepted", "100", "Fagaceae", "Quercus", "alba", "L.",
       "urn:lsid:ipni.org:names:295763-1"},
      {"101", "Quercus rubra", "Accepted", "101", "Fagaceae", "Quercus", "rubra", "L.",
       "urn:lsid:ipni.org:names:295776-1"},
      {"102", "Quercus velutina", "Accepted", "102", "Fagaceae", "Quercus", "velutina", "Lam.",
       nil},
      {"200", "Rosa carolina", "Accepted", "200", "Rosaceae", "Rosa", "carolina", "L.",
       "urn:lsid:ipni.org:names:726498-1"},
      {"300", "Alnus alnobetula subsp. sinuata", "Accepted", "300", "Betulaceae", "Alnus",
       "alnobetula", "(Regel) Raus", nil},
      {"301", "Alnus incana", "Accepted", "301", "Betulaceae", "Alnus", "incana", "(L.) Moench",
       nil},
      {"400", "Quercus borealis", "Synonym", "101", "Fagaceae", "Quercus", "borealis", "F.Michx.",
       nil}
    ]

    for {id, name, status, accepted, family, genus, species, authors, powo} <- names do
      Repo.WCVP.query!(
        """
        INSERT INTO wcvp_names
          (plant_name_id, taxon_name, taxon_status, accepted_plant_name_id,
           family, genus, species, taxon_authors, powo_id)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        """,
        [id, name, status, accepted, family, genus, species, authors, powo]
      )
    end

    Repo.WCVP.query!("""
    UPDATE wcvp_names
    SET taxon_rank = CASE WHEN taxon_name LIKE '% subsp. %' THEN 'Subspecies' ELSE 'Species' END
    """)

    # Insert test distributions
    distributions = [
      {"1", "100", "ALB", "0"},
      {"2", "100", "FLA", "0"},
      {"3", "100", "NCA", "1"},
      {"4", "101", "NCA", "0"},
      {"5", "200", "NCA", "0"}
    ]

    for {loc_id, name_id, area, introduced} <- distributions do
      Repo.WCVP.query!(
        """
        INSERT INTO wcvp_distributions
          (plant_locality_id, plant_name_id, area_code_l3, introduced)
        VALUES ($1, $2, $3, $4)
        """,
        [loc_id, name_id, area, introduced]
      )
    end

    :ok
  end

  describe "available?/0" do
    test "returns true when repo is started" do
      assert Lookup.available?() == true
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
    test "returns WcvpName structs" do
      [result | _] = Lookup.search("Quercus")
      assert %WcvpName{} = result
    end

    test "finds species by genus prefix" do
      results = Lookup.search("Quercus")
      assert length(results) == 3
      assert Enum.all?(results, fn r -> r.genus == "Quercus" end) == true
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
      assert Enum.all?(results, fn r -> r.genus == "Alnus" end) == true
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
    test "returns WcvpName struct with virtual distribution fields populated" do
      result = Lookup.get("100")
      assert %WcvpName{} = result
    end

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

    test "includes taxon_status and accepted_plant_name_id" do
      assert %{taxon_status: "Accepted", accepted_plant_name_id: "100"} = Lookup.get("100")
      assert %{taxon_status: "Synonym", accepted_plant_name_id: "101"} = Lookup.get("400")
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
      assert Enum.any?(results, fn r -> r.taxon_status == "Synonym" end) == true
    end

    test "includes taxon_status and accepted_plant_name_id in results" do
      [result | _] = Lookup.search("Quercus alba")
      assert result.taxon_status == "Accepted"
      assert result.accepted_plant_name_id == "100"
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
      assert Enum.any?(results, fn r -> r.taxon_status == "Synonym" end) == true
    end
  end

  describe "match_by_name/2" do
    test "returns accepted name record for exact match" do
      result = Lookup.match_by_name("Quercus alba")
      assert %WcvpName{} = result
      assert result.plant_name_id == "100"
      assert result.taxon_name == "Quercus alba"
      assert result.taxon_status == "Accepted"
      assert result.family == "Fagaceae"
      assert result.genus == "Quercus"
      assert result.species == "alba"
      assert result.taxon_authors == "L."
      assert result.powo_id == "urn:lsid:ipni.org:names:295763-1"
    end

    test "matches accepted names case-insensitively" do
      result = Lookup.match_by_name("quercus alba")
      assert %WcvpName{} = result
      assert result.plant_name_id == "100"
      assert result.taxon_name == "Quercus alba"
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

    test "resolves synonyms case-insensitively when resolve_synonyms is true" do
      result = Lookup.match_by_name("quercus borealis", resolve_synonyms: true)
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
      assert %WcvpName{} = result
      assert result.plant_name_id == "101"
      assert result.taxon_name == "Quercus rubra"
      assert result.taxon_status == "Accepted"
      assert result.accepted_plant_name_id == "101"
    end

    test "returns nil for an already-accepted name" do
      assert Lookup.get_accepted_name("100") == nil
    end

    test "returns nil for nonexistent plant_name_id" do
      assert Lookup.get_accepted_name("999") == nil
    end
  end

  describe "get_names/1" do
    test "returns the records with those IDs, whatever their status, with rank and authors" do
      results = Lookup.get_names(["400", "100", "999"])

      assert [
               %WcvpName{
                 plant_name_id: "100",
                 taxon_name: "Quercus alba",
                 taxon_rank: "Species",
                 taxon_status: "Accepted",
                 accepted_plant_name_id: "100",
                 taxon_authors: "L."
               },
               %WcvpName{
                 plant_name_id: "400",
                 taxon_status: "Synonym",
                 accepted_plant_name_id: "101",
                 taxon_authors: "F.Michx."
               }
             ] = Enum.sort_by(results, & &1.plant_name_id)
    end

    test "returns nothing for no IDs" do
      assert Lookup.get_names([]) == []
    end
  end

  describe "find_names/1" do
    test "returns every record of those exact names, ignoring case, whatever their status" do
      results =
        Lookup.find_names(["quercus ALBA", "Quercus borealis", "Alnus alnobetula", "Nope"])

      assert ["100", "400"] == results |> Enum.map(& &1.plant_name_id) |> Enum.sort()
      assert Enum.find(results, &(&1.plant_name_id == "400")).taxon_status == "Synonym"
    end

    test "gives an infraspecific record its rank" do
      assert [%WcvpName{taxon_rank: "Subspecies", taxon_authors: "(Regel) Raus"}] =
               Lookup.find_names(["Alnus alnobetula subsp. sinuata"])
    end
  end
end
