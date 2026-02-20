defmodule Gallformers.Repo.Migrations.AddWesternHemispherePlaces do
  use Gallformers.Migration

  @moduledoc """
  Expands the place table from ~69 US/CA entries to the full Western Hemisphere.

  Changes:
  1. Recreates `place` table: move UNIQUE from `name` to `code`
     (names like "Amazonas" appear in multiple countries)
  2. Migrates existing US/CA codes to ISO 3166-2 format (CA → US-CA, AB → CA-AB)
  3. Fixes Saint Pierre & Miquelon: type province → country
  4. Inserts hierarchy structure: region → continents → countries
  5. Inserts ~440 new subdivisions from Natural Earth data
  6. Wires all place_hierarchy links
  """

  # Countries by continent for hierarchy wiring
  @north_america_countries ["US", "CA", "MX", "GL", "PM"]
  @central_america_countries ["BZ", "CR", "SV", "GT", "HN", "NI", "PA"]
  @caribbean_countries [
    "AG", "BS", "BB", "CU", "DM", "DO", "GD", "HT", "JM",
    "KN", "LC", "VC", "TT",
    # Territories
    "AW", "BQ", "CW", "GP", "MQ", "BL", "MF", "SX",
    "AI", "BM", "VG", "KY", "MS", "PR", "TC", "VI"
  ]
  @south_america_countries [
    "AR", "BO", "BR", "CL", "CO", "EC", "GY", "PY", "PE", "SR", "UY", "VE",
    # Territories
    "GF", "FK", "GS"
  ]

  def up do
    # -- Step 1: Recreate place table to move UNIQUE from name to code ----------
    safe_recreate_table :place do
      execute """
      CREATE TABLE "place_new" (
        id INTEGER PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        code TEXT UNIQUE NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('continent', 'country', 'region', 'state', 'province', 'county', 'city'))
      )
      """

      execute "INSERT INTO place_new SELECT * FROM place"
      execute "DROP TABLE place"
      execute "ALTER TABLE place_new RENAME TO place"
    end

    # -- Step 2: Migrate existing codes to ISO 3166-2 ---------------------------
    # Fix SPM type BEFORE bulk province update so it's excluded
    execute "UPDATE place SET type = 'country' WHERE code = 'PM' AND name = 'Saint Pierre and Miquelon'"

    # US states: AL → US-AL, CA → US-CA, etc.
    execute "UPDATE place SET code = 'US-' || code WHERE type = 'state'"

    # CA provinces: AB → CA-AB, BC → CA-BC, etc.
    execute "UPDATE place SET code = 'CA-' || code WHERE type = 'province'"

    # Canada country code: CAN → CA (match ISO alpha-2 like US)
    execute "UPDATE place SET code = 'CA' WHERE name = 'Canada' AND code = 'CAN'"

    # Fix DC name capitalization
    execute "UPDATE place SET name = 'District of Columbia' WHERE name = 'District Of Columbia'"

    # -- Step 3: Insert hierarchy structure --------------------------------------
    # Region
    execute "INSERT OR IGNORE INTO place (name, code, type) VALUES ('Western Hemisphere', 'WH', 'region')"

    # Continents (North America already exists as id=1)
    execute "INSERT OR IGNORE INTO place (name, code, type) VALUES ('Central America', 'XC', 'continent')"
    execute "INSERT OR IGNORE INTO place (name, code, type) VALUES ('Caribbean', 'XB', 'continent')"
    execute "INSERT OR IGNORE INTO place (name, code, type) VALUES ('South America', 'XS', 'continent')"

    # -- Step 4: Insert new countries -------------------------------------------
    for {name, code} <- new_countries() do
      execute "INSERT OR IGNORE INTO place (name, code, type) VALUES ('#{esc(name)}', '#{code}', 'country')"
    end

    # -- Step 5: Insert subdivisions from data file -----------------------------
    subdivisions = load_subdivisions()

    # Skip US and CA entries (already exist with updated codes)
    new_subdivisions = Enum.reject(subdivisions, fn s -> s["country"] in ["US", "CA"] end)

    for sub <- new_subdivisions do
      execute "INSERT OR IGNORE INTO place (name, code, type) VALUES ('#{esc(sub["name"])}', '#{sub["code"]}', '#{sub["type"]}')"
    end

    # -- Step 6: Wire hierarchy links -------------------------------------------
    flush()

    # Wire continents → region
    execute """
    INSERT OR IGNORE INTO place_hierarchy (place_id, parent_id)
    SELECT p.id, r.id FROM place p, place r
    WHERE r.code = 'WH'
    AND p.code IN ('NA', 'XC', 'XB', 'XS')
    """

    # Wire countries → continents
    wire_countries_to_continent("NA", @north_america_countries)
    wire_countries_to_continent("XC", @central_america_countries)
    wire_countries_to_continent("XB", @caribbean_countries)
    wire_countries_to_continent("XS", @south_america_countries)

    # Wire subdivisions → countries
    # For existing US/CA subdivisions, hierarchy links already exist (state→US, province→CA)
    # For new subdivisions, wire by country code prefix (MX-AGU → MX, BR-AC → BR, etc.)
    execute """
    INSERT OR IGNORE INTO place_hierarchy (place_id, parent_id)
    SELECT sub.id, country.id
    FROM place sub
    JOIN place country ON country.code = SUBSTR(sub.code, 1, 2) AND country.type = 'country'
    WHERE sub.type IN ('state', 'province')
    AND sub.code LIKE '__-%'
    AND NOT EXISTS (
      SELECT 1 FROM place_hierarchy ph WHERE ph.place_id = sub.id
    )
    """
  end

  def down do
    # Remove all hierarchy links
    execute "DELETE FROM place_hierarchy WHERE parent_id IN (SELECT id FROM place WHERE code IN ('WH', 'XC', 'XB', 'XS'))"

    # Remove new subdivisions (keep US/CA)
    execute """
    DELETE FROM place
    WHERE type IN ('state', 'province')
    AND code LIKE '__-%'
    AND SUBSTR(code, 1, 2) NOT IN ('US', 'CA')
    """

    # Remove new countries
    codes = new_countries() |> Enum.map(fn {_, code} -> "'#{code}'" end) |> Enum.join(",")
    execute "DELETE FROM place WHERE code IN (#{codes})"

    # Remove new continents and region
    execute "DELETE FROM place WHERE code IN ('WH', 'XC', 'XB', 'XS')"

    # Restore SPM as province
    execute "UPDATE place SET type = 'province' WHERE code = 'PM' AND name = 'Saint Pierre and Miquelon'"

    # Restore original codes
    execute "UPDATE place SET code = SUBSTR(code, 4) WHERE type = 'state' AND code LIKE 'US-%'"
    execute "UPDATE place SET code = SUBSTR(code, 4) WHERE type = 'province' AND code LIKE 'CA-%'"
    execute "UPDATE place SET code = 'CAN' WHERE name = 'Canada' AND code = 'CA'"
    execute "UPDATE place SET name = 'District Of Columbia' WHERE name = 'District of Columbia'"

    # Recreate original table with UNIQUE on name
    safe_recreate_table :place do
      execute """
      CREATE TABLE "place_new" (
        id INTEGER PRIMARY KEY NOT NULL,
        name TEXT UNIQUE NOT NULL,
        code TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('continent', 'country', 'region', 'state', 'province', 'county', 'city'))
      )
      """

      execute "INSERT INTO place_new SELECT * FROM place"
      execute "DROP TABLE place"
      execute "ALTER TABLE place_new RENAME TO place"
    end
  end

  # -- Helpers ------------------------------------------------------------------

  defp wire_countries_to_continent(continent_code, country_codes) do
    codes = Enum.map(country_codes, &"'#{&1}'") |> Enum.join(",")

    execute """
    INSERT OR IGNORE INTO place_hierarchy (place_id, parent_id)
    SELECT c.id, cont.id FROM place c, place cont
    WHERE cont.code = '#{continent_code}'
    AND c.code IN (#{codes})
    """
  end

  defp load_subdivisions do
    path = Path.join(:code.priv_dir(:gallformers), "repo/data/western_hemisphere_places.json")
    path |> File.read!() |> Jason.decode!()
  end

  defp new_countries do
    [
      # North America (US and CA already exist)
      {"Mexico", "MX"},
      {"Greenland", "GL"},
      # Central America
      {"Belize", "BZ"},
      {"Costa Rica", "CR"},
      {"El Salvador", "SV"},
      {"Guatemala", "GT"},
      {"Honduras", "HN"},
      {"Nicaragua", "NI"},
      {"Panama", "PA"},
      # Caribbean - sovereign nations
      {"Antigua and Barbuda", "AG"},
      {"Bahamas", "BS"},
      {"Barbados", "BB"},
      {"Cuba", "CU"},
      {"Dominica", "DM"},
      {"Dominican Republic", "DO"},
      {"Grenada", "GD"},
      {"Haiti", "HT"},
      {"Jamaica", "JM"},
      {"Saint Kitts and Nevis", "KN"},
      {"Saint Lucia", "LC"},
      {"Saint Vincent and the Grenadines", "VC"},
      {"Trinidad and Tobago", "TT"},
      # Caribbean - territories
      {"Aruba", "AW"},
      {"Bonaire, Sint Eustatius and Saba", "BQ"},
      {"Curaçao", "CW"},
      {"Guadeloupe", "GP"},
      {"Martinique", "MQ"},
      {"Saint Barthélemy", "BL"},
      {"Saint Martin", "MF"},
      {"Sint Maarten", "SX"},
      {"Anguilla", "AI"},
      {"Bermuda", "BM"},
      {"British Virgin Islands", "VG"},
      {"Cayman Islands", "KY"},
      {"Montserrat", "MS"},
      {"Puerto Rico", "PR"},
      {"Turks and Caicos Islands", "TC"},
      {"United States Virgin Islands", "VI"},
      # South America - sovereign nations
      {"Argentina", "AR"},
      {"Bolivia", "BO"},
      {"Brazil", "BR"},
      {"Chile", "CL"},
      {"Colombia", "CO"},
      {"Ecuador", "EC"},
      {"Guyana", "GY"},
      {"Paraguay", "PY"},
      {"Peru", "PE"},
      {"Suriname", "SR"},
      {"Uruguay", "UY"},
      {"Venezuela", "VE"},
      # South America - territories
      {"French Guiana", "GF"},
      {"Falkland Islands", "FK"},
      {"South Georgia and the South Sandwich Islands", "GS"}
    ]
  end

  defp esc(str), do: String.replace(str, "'", "''")
end
