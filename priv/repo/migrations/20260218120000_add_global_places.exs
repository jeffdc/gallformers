defmodule Gallformers.Repo.Migrations.AddGlobalPlaces do
  use Gallformers.Migration

  # -- Continent definitions (8 geographic continents) --
  # All continent codes use X prefix to avoid collisions with ISO country codes.
  # North America was originally "NA" in the DB but is renamed to "XN" here
  # because "NA" is Namibia's ISO 3166-1 alpha-2 code.

  @north_america_countries ~w(US CA MX GL PM)
  @central_america_countries ~w(BZ CR SV GT HN NI PA)
  @caribbean_countries ~w(AG BS BB CU DM DO GD HT JM KN LC VC TT AW BQ CW GP MQ BL MF SX AI BM VG KY MS PR TC VI)
  @south_america_countries ~w(AR BO BR CL CO EC GY PY PE SR UY VE GF FK GS)
  @europe_countries ~w(AL AD AT BY BE BA BG HR CZ DK EE FI FR DE GR HU IS IE IT LV LI LT LU MT MD MC ME NL MK NO PL PT RO RU SM RS SK SI ES SE CH UA GB VA FO GI GG IM JE SJ AX XK)
  @africa_countries ~w(DZ AO BJ BW BF BI CV CM CF TD KM CG CI CD DJ EG GQ ER SZ ET GA GM GH GN GW KE LS LR LY MG MW ML MR MU MA MZ NA NE NG RW ST SN SC SL SO ZA SS SD TZ TG TN UG ZM ZW EH RE YT SH TF BV)
  @asia_countries ~w(AF AM AZ BH BD BT BN KH CN CY GE IN ID IR IQ IL JP JO KZ KW KG LA LB MY MV MN MM NP KP KR OM PK PS PH QA SA SG LK SY TJ TH TL TR TM AE UZ VN YE TW HK MO IO)
  @oceania_countries ~w(AU FJ FM KI MH NR NZ PW PG SB TO TV VU WS AS CK GU MP NC NF NU PF PN WF TK CX CC HM UM)

  # -- Country name lookup --
  # Full English names for all countries. Existing DB countries (US, CA) and
  # Saint Pierre and Miquelon (reclassified from province to country) are
  # handled separately and not in this map.

  @country_names %{
    "MX" => "Mexico",
    "GL" => "Greenland",
    "BZ" => "Belize",
    "CR" => "Costa Rica",
    "SV" => "El Salvador",
    "GT" => "Guatemala",
    "HN" => "Honduras",
    "NI" => "Nicaragua",
    "PA" => "Panama",
    "AG" => "Antigua and Barbuda",
    "BS" => "Bahamas",
    "BB" => "Barbados",
    "CU" => "Cuba",
    "DM" => "Dominica",
    "DO" => "Dominican Republic",
    "GD" => "Grenada",
    "HT" => "Haiti",
    "JM" => "Jamaica",
    "KN" => "Saint Kitts and Nevis",
    "LC" => "Saint Lucia",
    "VC" => "Saint Vincent and the Grenadines",
    "TT" => "Trinidad and Tobago",
    "AW" => "Aruba",
    "BQ" => "Bonaire, Sint Eustatius and Saba",
    "CW" => "Curaçao",
    "GP" => "Guadeloupe",
    "MQ" => "Martinique",
    "BL" => "Saint Barthélemy",
    "MF" => "Saint Martin",
    "SX" => "Sint Maarten",
    "AI" => "Anguilla",
    "BM" => "Bermuda",
    "VG" => "British Virgin Islands",
    "KY" => "Cayman Islands",
    "MS" => "Montserrat",
    "PR" => "Puerto Rico",
    "TC" => "Turks and Caicos Islands",
    "VI" => "United States Virgin Islands",
    "AR" => "Argentina",
    "BO" => "Bolivia",
    "BR" => "Brazil",
    "CL" => "Chile",
    "CO" => "Colombia",
    "EC" => "Ecuador",
    "GY" => "Guyana",
    "PY" => "Paraguay",
    "PE" => "Peru",
    "SR" => "Suriname",
    "UY" => "Uruguay",
    "VE" => "Venezuela",
    "GF" => "French Guiana",
    "FK" => "Falkland Islands",
    "GS" => "South Georgia and the South Sandwich Islands",
    "AL" => "Albania",
    "AD" => "Andorra",
    "AT" => "Austria",
    "BY" => "Belarus",
    "BE" => "Belgium",
    "BA" => "Bosnia and Herzegovina",
    "BG" => "Bulgaria",
    "HR" => "Croatia",
    "CZ" => "Czechia",
    "DK" => "Denmark",
    "EE" => "Estonia",
    "FI" => "Finland",
    "FR" => "France",
    "DE" => "Germany",
    "GR" => "Greece",
    "HU" => "Hungary",
    "IS" => "Iceland",
    "IE" => "Ireland",
    "IT" => "Italy",
    "LV" => "Latvia",
    "LI" => "Liechtenstein",
    "LT" => "Lithuania",
    "LU" => "Luxembourg",
    "MT" => "Malta",
    "MD" => "Moldova",
    "MC" => "Monaco",
    "ME" => "Montenegro",
    "NL" => "Netherlands",
    "MK" => "North Macedonia",
    "NO" => "Norway",
    "PL" => "Poland",
    "PT" => "Portugal",
    "RO" => "Romania",
    "RU" => "Russia",
    "SM" => "San Marino",
    "RS" => "Serbia",
    "SK" => "Slovakia",
    "SI" => "Slovenia",
    "ES" => "Spain",
    "SE" => "Sweden",
    "CH" => "Switzerland",
    "UA" => "Ukraine",
    "GB" => "United Kingdom",
    "VA" => "Vatican City",
    "FO" => "Faroe Islands",
    "GI" => "Gibraltar",
    "GG" => "Guernsey",
    "IM" => "Isle of Man",
    "JE" => "Jersey",
    "SJ" => "Svalbard and Jan Mayen",
    "AX" => "Åland Islands",
    "XK" => "Kosovo",
    "DZ" => "Algeria",
    "AO" => "Angola",
    "BJ" => "Benin",
    "BW" => "Botswana",
    "BF" => "Burkina Faso",
    "BI" => "Burundi",
    "CV" => "Cabo Verde",
    "CM" => "Cameroon",
    "CF" => "Central African Republic",
    "TD" => "Chad",
    "KM" => "Comoros",
    "CG" => "Republic of the Congo",
    "CI" => "Côte d'Ivoire",
    "CD" => "Democratic Republic of the Congo",
    "DJ" => "Djibouti",
    "EG" => "Egypt",
    "GQ" => "Equatorial Guinea",
    "ER" => "Eritrea",
    "SZ" => "Eswatini",
    "ET" => "Ethiopia",
    "GA" => "Gabon",
    "GM" => "Gambia",
    "GH" => "Ghana",
    "GN" => "Guinea",
    "GW" => "Guinea-Bissau",
    "KE" => "Kenya",
    "LS" => "Lesotho",
    "LR" => "Liberia",
    "LY" => "Libya",
    "MG" => "Madagascar",
    "MW" => "Malawi",
    "ML" => "Mali",
    "MR" => "Mauritania",
    "MU" => "Mauritius",
    "MA" => "Morocco",
    "MZ" => "Mozambique",
    "NA" => "Namibia",
    "NE" => "Niger",
    "NG" => "Nigeria",
    "RW" => "Rwanda",
    "ST" => "São Tomé and Príncipe",
    "SN" => "Senegal",
    "SC" => "Seychelles",
    "SL" => "Sierra Leone",
    "SO" => "Somalia",
    "ZA" => "South Africa",
    "SS" => "South Sudan",
    "SD" => "Sudan",
    "TZ" => "Tanzania",
    "TG" => "Togo",
    "TN" => "Tunisia",
    "UG" => "Uganda",
    "ZM" => "Zambia",
    "ZW" => "Zimbabwe",
    "EH" => "Western Sahara",
    "RE" => "Réunion",
    "YT" => "Mayotte",
    "SH" => "Saint Helena, Ascension and Tristan da Cunha",
    "TF" => "French Southern Territories",
    "BV" => "Bouvet Island",
    "AF" => "Afghanistan",
    "AM" => "Armenia",
    "AZ" => "Azerbaijan",
    "BH" => "Bahrain",
    "BD" => "Bangladesh",
    "BT" => "Bhutan",
    "BN" => "Brunei",
    "KH" => "Cambodia",
    "CN" => "China",
    "CY" => "Cyprus",
    "GE" => "Georgia",
    "IN" => "India",
    "ID" => "Indonesia",
    "IR" => "Iran",
    "IQ" => "Iraq",
    "IL" => "Israel",
    "JP" => "Japan",
    "JO" => "Jordan",
    "KZ" => "Kazakhstan",
    "KW" => "Kuwait",
    "KG" => "Kyrgyzstan",
    "LA" => "Laos",
    "LB" => "Lebanon",
    "MY" => "Malaysia",
    "MV" => "Maldives",
    "MN" => "Mongolia",
    "MM" => "Myanmar",
    "NP" => "Nepal",
    "KP" => "North Korea",
    "KR" => "South Korea",
    "OM" => "Oman",
    "PK" => "Pakistan",
    "PS" => "Palestine",
    "PH" => "Philippines",
    "QA" => "Qatar",
    "SA" => "Saudi Arabia",
    "SG" => "Singapore",
    "LK" => "Sri Lanka",
    "SY" => "Syria",
    "TJ" => "Tajikistan",
    "TH" => "Thailand",
    "TL" => "Timor-Leste",
    "TR" => "Turkey",
    "TM" => "Turkmenistan",
    "AE" => "United Arab Emirates",
    "UZ" => "Uzbekistan",
    "VN" => "Vietnam",
    "YE" => "Yemen",
    "TW" => "Taiwan",
    "HK" => "Hong Kong",
    "MO" => "Macau",
    "IO" => "British Indian Ocean Territory",
    "AU" => "Australia",
    "FJ" => "Fiji",
    "FM" => "Micronesia",
    "KI" => "Kiribati",
    "MH" => "Marshall Islands",
    "NR" => "Nauru",
    "NZ" => "New Zealand",
    "PW" => "Palau",
    "PG" => "Papua New Guinea",
    "SB" => "Solomon Islands",
    "TO" => "Tonga",
    "TV" => "Tuvalu",
    "VU" => "Vanuatu",
    "WS" => "Samoa",
    "AS" => "American Samoa",
    "CK" => "Cook Islands",
    "GU" => "Guam",
    "MP" => "Northern Mariana Islands",
    "NC" => "New Caledonia",
    "NF" => "Norfolk Island",
    "NU" => "Niue",
    "PF" => "French Polynesia",
    "PN" => "Pitcairn Islands",
    "WF" => "Wallis and Futuna",
    "TK" => "Tokelau",
    "CX" => "Christmas Island",
    "CC" => "Cocos (Keeling) Islands",
    "HM" => "Heard Island and McDonald Islands",
    "UM" => "United States Minor Outlying Islands"
  }

  def up do
    # 1. Recreate place table: change UNIQUE constraint from name to code
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

    # 2. Rename North America continent code from NA to XN.
    # NA is Namibia's ISO alpha-2 code, so we use the X prefix convention
    # consistent with all other custom continent codes (XC, XB, XS, etc.).
    execute "UPDATE place SET code = 'XN' WHERE code = 'NA' AND type = 'continent'"

    # 3. Reclassify Saint Pierre and Miquelon from province to country
    execute "UPDATE place SET type = 'country' WHERE code = 'PM' AND name = 'Saint Pierre and Miquelon'"

    # 4. Migrate US/CA codes to ISO 3166-2 format (CC-XX)
    execute "UPDATE place SET code = 'US-' || code WHERE type = 'state'"
    execute "UPDATE place SET code = 'CA-' || code WHERE type = 'province'"

    # 5. Fix Canada country code from CAN to CA
    execute "UPDATE place SET code = 'CA' WHERE name = 'Canada' AND code = 'CAN'"

    # 6. Fix name casing
    execute "UPDATE place SET name = 'District of Columbia' WHERE name = 'District Of Columbia'"

    # 7. Insert 7 new continents (XN already exists, renamed from NA above)
    for {name, code} <- continents() do
      execute "INSERT OR IGNORE INTO place (name, code, type) VALUES ('#{esc(name)}', '#{code}', 'continent')"
    end

    # 8. Insert all new countries
    for {code, name} <- all_new_countries() do
      execute "INSERT OR IGNORE INTO place (name, code, type) VALUES ('#{name}', '#{code}', 'country')"
    end

    # 9. Insert subdivisions from data file (skip US and CA — already in DB)
    subdivisions = load_subdivisions()
    new_subdivisions = Enum.reject(subdivisions, fn s -> s["country"] in ["US", "CA"] end)

    for sub <- new_subdivisions do
      execute "INSERT OR IGNORE INTO place (name, code, type) VALUES ('#{esc(sub["name"])}', '#{sub["code"]}', '#{sub["type"]}')"
    end

    # 10. Flush so all inserted records have IDs before wiring hierarchy
    flush()

    # 11. Wire countries to continents
    wire_countries_to_continent("XN", @north_america_countries)
    wire_countries_to_continent("XC", @central_america_countries)
    wire_countries_to_continent("XB", @caribbean_countries)
    wire_countries_to_continent("XS", @south_america_countries)
    wire_countries_to_continent("XE", @europe_countries)
    wire_countries_to_continent("XF", @africa_countries)
    wire_countries_to_continent("XA", @asia_countries)
    wire_countries_to_continent("XO", @oceania_countries)

    # 12. Wire subdivisions to countries (by ISO 3166-2 code prefix)
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
    # 1. Remove hierarchy links for all new continents
    for code <- ~w(XC XB XS XE XF XA XO) do
      execute """
      DELETE FROM place_hierarchy WHERE parent_id = (
        SELECT id FROM place WHERE code = '#{code}' AND type = 'continent'
      )
      """
    end

    # 2. Remove hierarchy links for new countries under XN (keep US, CA which were original)
    execute """
    DELETE FROM place_hierarchy
    WHERE parent_id = (SELECT id FROM place WHERE code = 'XN' AND type = 'continent')
    AND place_id NOT IN (
      SELECT id FROM place WHERE code IN ('US', 'CA')
    )
    """

    # 3. Remove hierarchy links for subdivisions of non-US/CA countries
    execute """
    DELETE FROM place_hierarchy
    WHERE place_id IN (
      SELECT sub.id FROM place sub
      WHERE sub.type IN ('state', 'province')
      AND sub.code LIKE '__-%'
      AND SUBSTR(sub.code, 1, 2) NOT IN ('US', 'CA')
    )
    """

    # 4. Remove all new subdivisions (non-US/CA)
    execute """
    DELETE FROM place
    WHERE type IN ('state', 'province')
    AND code LIKE '__-%'
    AND SUBSTR(code, 1, 2) NOT IN ('US', 'CA')
    """

    # 5. Remove all new countries (keep US, CA, PM which will be restored)
    for {code, _name} <- all_new_countries() do
      if code != "PM" do
        execute "DELETE FROM place WHERE code = '#{code}' AND type = 'country'"
      end
    end

    # 6. Remove new continents (keep XN which will be renamed back to NA)
    for code <- ~w(XC XB XS XE XF XA XO) do
      execute "DELETE FROM place WHERE code = '#{code}' AND type = 'continent'"
    end

    # 7. Restore Saint Pierre and Miquelon as province
    execute "UPDATE place SET type = 'province' WHERE code = 'PM' AND name = 'Saint Pierre and Miquelon'"

    # 8. Restore original US/CA codes (strip prefix)
    execute "UPDATE place SET code = SUBSTR(code, 4) WHERE type = 'state' AND code LIKE 'US-%'"
    execute "UPDATE place SET code = SUBSTR(code, 4) WHERE type = 'province' AND code LIKE 'CA-%'"

    # 9. Restore Canada code to CAN
    execute "UPDATE place SET code = 'CAN' WHERE name = 'Canada' AND code = 'CA'"

    # 10. Restore original name casing
    execute "UPDATE place SET name = 'District Of Columbia' WHERE name = 'District of Columbia'"

    # 11. Rename North America back to NA
    execute "UPDATE place SET code = 'NA' WHERE code = 'XN' AND type = 'continent'"

    # 12. Recreate original table with UNIQUE on name instead of code
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

  # -- Helpers --

  defp continents do
    [
      {"North America", "XN"},
      {"Central America", "XC"},
      {"Caribbean", "XB"},
      {"South America", "XS"},
      {"Europe", "XE"},
      {"Africa", "XF"},
      {"Asia", "XA"},
      {"Oceania", "XO"}
    ]
  end

  defp all_new_countries do
    # All countries from all continents, excluding US and CA (already in DB).
    # PM (Saint Pierre and Miquelon) is already in DB as a province and gets
    # reclassified to country, so it's also excluded from inserts.
    existing = MapSet.new(~w(US CA PM))

    all_continent_countries()
    |> Enum.reject(fn code -> MapSet.member?(existing, code) end)
    |> Enum.uniq()
    |> Enum.map(fn code -> {code, esc(Map.fetch!(@country_names, code))} end)
  end

  defp all_continent_countries do
    @north_america_countries ++
      @central_america_countries ++
      @caribbean_countries ++
      @south_america_countries ++
      @europe_countries ++
      @africa_countries ++
      @asia_countries ++
      @oceania_countries
  end

  defp wire_countries_to_continent(continent_code, country_codes) do
    for code <- country_codes do
      execute """
      INSERT OR IGNORE INTO place_hierarchy (place_id, parent_id)
      SELECT country.id, continent.id
      FROM place country, place continent
      WHERE country.code = '#{code}' AND country.type = 'country'
      AND continent.code = '#{continent_code}' AND continent.type = 'continent'
      """
    end
  end

  defp load_subdivisions do
    path = Path.join(:code.priv_dir(:gallformers), "repo/data/global_places.json")
    path |> File.read!() |> Jason.decode!()
  end

  defp esc(str), do: String.replace(str, "'", "''")
end
