#!/usr/bin/env python3
"""
Generate a draft TDWG L3 → gallformers places mapping for the entire globe.

Reads:
  - priv/repo/data/wcvp/wcvp_distribution.csv  (all TDWG L3 codes + names)
  - priv/repo/data/tdwg_to_places.json          (existing 103 Western Hemisphere entries)
  - priv/gallformers.sqlite                      (place + place_hierarchy tables)

Outputs:
  - Updated tdwg_to_places.json with all TDWG codes mapped
  - Report on stdout: matched, unmatched, preserved existing

Usage:
    python3 services/boundaries/generate_tdwg_mapping.py
"""

import csv
import json
import sqlite3
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent

DIST_CSV = PROJECT_ROOT / "priv/repo/data/wcvp/wcvp_distribution.csv"
EXISTING_JSON = PROJECT_ROOT / "priv/repo/data/tdwg_to_places.json"
PLACES_DB = PROJECT_ROOT / "priv/gallformers.sqlite"
OUTPUT_JSON = PROJECT_ROOT / "priv/repo/data/tdwg_to_places.json"


# ── Hardcoded mappings for complex cases ─────────────────────────────────────

# TDWG code → list of ISO country codes (for multi-country regions)
MULTI_COUNTRY = {
    "BLT": ["EE", "LV", "LT"],  # Baltic States
    "YUG": ["RS", "ME", "BA", "HR", "SI", "MK", "XK"],  # NW Balkans
    "CZE": ["CZ", "SK"],  # Czechia-Slovakia
    "KOR": ["KR", "KP"],  # Korea
    "LBS": ["LB", "SY"],  # Lebanon-Syria
    "SUD": ["SD", "SS"],  # Sudan-South Sudan
    "GST": ["AE", "BH", "QA"],  # Gulf States
    "TCS": ["GE", "AM", "AZ"],  # Transcaucasus
    "NCS": ["RU"],  # North Caucasus → Russia (country-level, too complex for subdivisions)
}

# TDWG code → list of ISO subdivision codes (sub-country regions)
# These map a TDWG region to specific subdivisions within a country.
SUB_COUNTRY = {
    # Australia
    "NSW": ["AU-NSW"],  # New South Wales (includes Lord Howe in DB)
    "NTA": ["AU-NT"],
    "QLD": ["AU-QLD"],
    "SOA": ["AU-SA"],
    "TAS": ["AU-TAS"],
    "VIC": ["AU-VIC"],
    "WAU": ["AU-WA"],

    # China
    "CHC": ["CN-SC", "CN-CQ", "CN-GZ", "CN-YN", "CN-HB"],  # South-Central
    "CHH": ["CN-HI"],  # Hainan
    "CHI": ["CN-NM"],  # Inner Mongolia
    "CHM": ["CN-HL", "CN-JL", "CN-LN"],  # Manchuria
    "CHN": ["CN-HE", "CN-SX", "CN-SD", "CN-BJ", "CN-TJ"],  # North-Central
    "CHQ": ["CN-QH"],  # Qinghai
    "CHS": ["CN-ZJ", "CN-FJ", "CN-AH", "CN-JX", "CN-JS", "CN-SH", "CN-GD", "CN-GX", "CN-HN", "CN-HA"],  # Southeast
    "CHT": ["CN-XZ"],  # Tibet
    "CHX": ["CN-XJ"],  # Xinjiang

    # Russia (sub-regions mapped to country-level since subdivision mapping is very complex)
    # Each gets all Russian subdivisions with precision "country"
    "RUC": ["RU"],  # Central European Russia
    "RUE": ["RU"],  # East European Russia
    "RUN": ["RU"],  # North European Russia
    "RUS": ["RU"],  # South European Russia
    "RUW": ["RU"],  # Northwest European Russia
    "WSB": ["RU"],  # West Siberia
    "KRA": ["RU"],  # Krasnoyarsk
    "IRK": ["RU"],  # Irkutsk
    "YAK": ["RU"],  # Yakutiya
    "BRY": ["RU"],  # Buryatiya
    "CTA": ["RU"],  # Chita
    "AMU": ["RU"],  # Amur
    "KHA": ["RU"],  # Khabarovsk
    "MAG": ["RU"],  # Magadan
    "SAK": ["RU"],  # Sakhalin
    "KAM": ["RU"],  # Kamchatka
    "TVA": ["RU"],  # Tuva
    "PRM": ["RU"],  # Primorye
    "KUR": ["RU"],  # Kuril Is.
    "ALT": ["RU"],  # Altay

    # South Africa
    "CPP": ["ZA-EC", "ZA-WC", "ZA-NC"],  # Cape Provinces
    "NAT": ["ZA-NL"],  # KwaZulu-Natal
    "OFS": ["ZA-FS"],  # Free State
    "TVL": ["ZA-LP", "ZA-MP", "ZA-NW", "ZA-GT"],  # Northern Provinces (Transvaal)

    # New Zealand
    "NZN": ["NZ-AUK", "NZ-BOP", "NZ-GIS", "NZ-HKB", "NZ-MWT", "NZ-NTL", "NZ-TKI", "NZ-WKO", "NZ-WGN"],  # North Island
    "NZS": ["NZ-CAN", "NZ-MBH", "NZ-NSN", "NZ-OTA", "NZ-STL", "NZ-TAS", "NZ-WTC"],  # South Island

    # Japan
    "JAP": ["JP-01", "JP-02", "JP-03", "JP-04", "JP-05", "JP-06", "JP-07",
            "JP-08", "JP-09", "JP-10", "JP-11", "JP-12", "JP-13", "JP-14",
            "JP-15", "JP-16", "JP-17", "JP-18", "JP-19", "JP-20", "JP-21",
            "JP-22", "JP-23", "JP-24", "JP-25", "JP-26", "JP-27", "JP-28",
            "JP-29", "JP-30", "JP-31", "JP-32", "JP-33", "JP-34", "JP-35",
            "JP-36", "JP-37", "JP-38", "JP-39", "JP-40", "JP-41", "JP-42",
            "JP-43", "JP-44", "JP-45", "JP-46"],  # Main islands (Hokkaido through Kyushu)
    "NNS": ["JP-47"],  # Nansei-shoto (Okinawa etc.)
    "OGA": [],  # Ogasawara-shoto (Bonin Islands) — no DB entry, use JP country
    "KZN": [],  # Kazan-retto — no DB entry, use JP country

    # Italian islands
    "SAR": ["IT-CA", "IT-CI", "IT-NU", "IT-OG", "IT-OR", "IT-OT", "IT-SS", "IT-VS"],  # Sardegna provinces
    "SIC": ["IT-AG", "IT-CL", "IT-CT", "IT-EN", "IT-ME", "IT-PA", "IT-RG", "IT-SR", "IT-TP"],  # Sicilia provinces

    # Spanish islands
    "BAL": ["ES-PM"],  # Baleares
    "CNY": ["ES-GC", "ES-TF"],  # Canary Islands (Las Palmas + Santa Cruz de Tenerife)

    # Greek islands
    "KRI": ["GR-M"],  # Kriti (Crete)
    "EAI": ["GR-K"],  # East Aegean Islands (North Aegean)

    # India
    "IND": ["IN"],  # India proper → country-level
    "AND": [],  # Andaman Is. — no specific subdivision in DB, use IN country
    "NCB": [],  # Nicobar Is. — same
    "LDV": [],  # Laccadive Is. — same
    "ASS": ["IN-AS", "IN-ML", "IN-MN", "IN-MZ", "IN-NL", "IN-TR", "IN-AR"],  # Assam + NE India
    "EHM": ["IN-SK", "IN-WB"],  # East Himalaya (Sikkim + parts of WB)
    "WHM": ["IN-HP", "IN-UT", "IN-JK"],  # West Himalaya (Himachal Pradesh, Uttarakhand, J&K)

    # Indonesia
    "JAW": ["ID-JB", "ID-JK", "ID-JI", "ID-JT", "ID-BT", "ID-YO"],  # Java + Banten + Yogyakarta
    "LSI": ["ID-NB", "ID-NT"],  # Lesser Sunda Islands (NTB, NTT)
    "MOL": ["ID-MA", "ID-MU"],  # Maluku
    "SUL": ["ID-SN", "ID-ST", "ID-SG", "ID-SA", "ID-SR", "ID-GO"],  # Sulawesi
    "SUM": ["ID-AC", "ID-SU", "ID-SB", "ID-SS", "ID-JA", "ID-BE", "ID-LA", "ID-BB", "ID-RI", "ID-KR"],  # Sumatra + islands

    # Borneo (split between Malaysia, Indonesia, Brunei)
    "BOR": ["MY-12", "MY-13", "MY-15",  # Sabah, Sarawak, Labuan
            "BN",  # Brunei
            "ID-KB", "ID-KT", "ID-KI", "ID-KS"],  # Kalimantan provinces (Barat, Tengah, Timur, Selatan)

    # Corse (France)
    "COR": ["FR-2A", "FR-2B"],  # Corse (Corse-du-Sud + Haute-Corse)

    # Krym (Crimea) - map to Ukraine
    "KRY": ["UA"],

    # Malaysia peninsula
    "MLY": ["MY-01", "MY-02", "MY-03", "MY-04", "MY-05", "MY-06", "MY-07",
            "MY-08", "MY-09", "MY-10", "MY-11", "MY-14"],  # Peninsular Malaysia states

    # Philippines
    "PHI": ["PH"],  # Country-level

    # Caprivi Strip (Namibia)
    "CPV": ["NA"],  # Part of Namibia, map to country

    # Cabinda (Angola exclave)
    "CAB": ["AO"],  # Part of Angola
}

# TDWG code → simple ISO country code (1:1 mapping where name doesn't match well)
DIRECT_COUNTRY = {
    "AFG": "AF",
    "ALB": "AL",
    "ALG": "DZ",
    "ANG": "AO",
    "ARU": "AW",
    "AUT": "AT",
    "BAN": "BD",
    "BEN": "BJ",
    "BER": "BM",
    "BGM": "BE",
    "BKN": "BF",
    "BLR": "BY",
    "BOT": "BW",
    "BUL": "BG",
    "BUR": "BI",
    "CAF": "CF",
    "CBD": "KH",
    "CHA": "TD",
    "CMN": "CM",
    "CON": "CG",
    "CVI": "CV",
    "CYP": "CY",
    "DEN": "DK",
    "DJI": "DJ",
    "EGY": "EG",
    "EQG": "GQ",
    "ERI": "ER",
    "ETH": "ET",
    "FIN": "FI",
    "FRA": "FR",
    "GAB": "GA",
    "GAM": "GM",
    "GER": "DE",
    "GHA": "GH",
    "GNB": "GW",
    "GRB": "GB",
    "GRC": "GR",
    "GUI": "GN",
    "HUN": "HU",
    "ICE": "IS",
    "IRE": "IE",
    "IRN": "IR",
    "IRQ": "IQ",
    "ITA": "IT",
    "IVO": "CI",
    "KAZ": "KZ",
    "KEN": "KE",
    "KGZ": "KG",
    "KUW": "KW",
    "LAO": "LA",
    "LBR": "LR",
    "LBY": "LY",
    "LES": "LS",
    "MAU": "MU",
    "MDG": "MG",
    "MDV": "MV",
    "MLI": "ML",
    "MLW": "MW",
    "MON": "MN",
    "MOR": "MA",
    "MOZ": "MZ",
    "MTN": "MR",
    "MYA": "MM",
    "NAM": "NA",
    "NEP": "NP",
    "NET": "NL",
    "NGA": "NG",
    "NGR": "NE",
    "NOR": "NO",
    "OMA": "OM",
    "PAK": "PK",
    "POL": "PL",
    "POR": "PT",
    "ROM": "RO",
    "RWA": "RW",
    "SAU": "SA",
    "SEN": "SN",
    "SIE": "SL",
    "SOM": "SO",
    "SPA": "ES",
    "SRL": "LK",
    "SVA": "SJ",
    "SWE": "SE",
    "SWI": "CH",
    "SWZ": "SZ",
    "TAI": "TW",
    "TAN": "TZ",
    "THA": "TH",
    "TKM": "TM",
    "TOG": "TG",
    "TUN": "TN",
    "TUR": "TR",
    "TZK": "TJ",
    "UGA": "UG",
    "UKR": "UA",
    "UZB": "UZ",
    "VIE": "VN",
    "ZAI": "CD",
    "ZAM": "ZM",
    "ZIM": "ZW",
    "BAH": "BS",
    "FIJ": "FJ",
    "NRU": "NR",
    "PAL": "PS",
    "SIN": "EG",  # Sinai → Egypt
    "YEM": "YE",
    "COM": "KM",
    "SEY": "SC",
    "SOC": "YE",  # Socotra → Yemen
    "REU": "RE",  # Réunion → not an ISO country, handled separately
    "FRG": "GF",  # French Guiana
    "TRT": "TT",  # Trinidad-Tobago
    "PUE": "PR",  # Puerto Rico
    "NLA": "CW",  # Netherlands Antilles → Curaçao as closest
    "VNA": "VE",  # Venezuelan Antilles → Venezuela
}

# TDWG codes for island territories and remote places with specific ISO mappings
ISLAND_TERRITORIES = {
    "ALD": "SC",  # Aldabra → Seychelles
    "ASC": "SH",  # Ascension → Saint Helena territory
    "AZO": "PT",  # Azores → Portugal
    "CAY": "KY",  # Cayman Islands
    "CGS": "IO",  # Chagos Archipelago → BIOT
    "CKI": "CC",  # Cocos (Keeling) Islands
    "CTM": "NZ",  # Chatham Islands → New Zealand
    "FAL": "FK",  # Falkland Islands
    "FOR": "FO",  # Føroyar (Faroe Islands)
    "GAL": "EC",  # Galápagos → Ecuador
    "GNL": "GL",  # Greenland
    "MDR": "PT",  # Madeira → Portugal
    "MCI": "KM",  # Mozambique Channel Is. → Comoros
    "NFK": "NF",  # Norfolk Island
    "NUE": "NU",  # Niue
    "NWC": "NC",  # New Caledonia
    "ROD": "MU",  # Rodrigues → Mauritius
    "SAM": "WS",  # Samoa (Western)
    "STH": "SH",  # St. Helena
    "TCI": "TC",  # Turks & Caicos
    "TON": "TO",  # Tonga
    "TUV": "TV",  # Tuvalu
    "VAN": "VU",  # Vanuatu
    "WAL": "WF",  # Wallis-Futuna
    "XMS": "CX",  # Christmas Island
    "COO": "CK",  # Cook Islands
    "FIJ": "FJ",  # Fiji
    "GIL": "KI",  # Gilbert Is. → Kiribati
    "TOK": "TK",  # Tokelau
    "MXI": "MX",  # Mexican Pacific Islands → Mexico
    "CPI": "CR",  # Central American Pacific Is. → Costa Rica (Cocos Island)
    "DSV": "CL",  # Desventurados → Chile
    "JNF": "CL",  # Juan Fernández → Chile
    "EAS": "CL",  # Easter Island → Chile
    "PIT": "PN",  # Pitcairn Islands

    # Caribbean islands
    "LEE": None,  # Leeward Islands — multi-country, handled specially
    "WIN": None,  # Windward Islands — multi-country, handled specially
    "SWC": None,  # Southwest Caribbean — multi-country, handled specially

    # Remote/uninhabited — may not have DB entries
    "ANT": "AQ",  # Antarctica
    "HBI": None,  # Howland-Baker Is. (US minor outlying)
    "PHX": None,  # Phoenix Islands (Kiribati)
    "WAK": None,  # Wake Island (US minor outlying)
    "LIN": None,  # Line Islands (Kiribati)
    "MCS": None,  # Marcus Island (Japan)
    "SCS": None,  # South China Sea
    "SGE": "GS",  # South Georgia
    "SSA": "GS",  # South Sandwich Is.
    "HMD": "HM",  # Heard-McDonald
    "KEG": "TF",  # Kerguelen → French Southern Territories
    "CRZ": "TF",  # Crozet → French Southern Territories
    "ASP": "TF",  # Amsterdam-St.Paul → French Southern Territories
    "MPE": "ZA",  # Marion-Prince Edward Is. → South Africa
    "MAQ": "AU",  # Macquarie Is. → Australia
    "ATP": "NZ",  # Antipodean Is. → New Zealand
    "KER": "NZ",  # Kermadec Is. → New Zealand
    "TDC": "SH",  # Tristan da Cunha → Saint Helena territory
    "SEL": "PT",  # Selvagens → Portugal

    # Pacific islands
    "BIS": "PG",  # Bismarck Archipelago → Papua New Guinea
    "NWG": "PG",  # New Guinea → Papua New Guinea (+ Indonesian Papua handled separately)
    "SOL": "SB",  # Solomon Islands
    "SCZ": "SB",  # Santa Cruz Is. → Solomon Islands
    "SCI": "PF",  # Society Is. → French Polynesia
    "TUA": "PF",  # Tuamotu → French Polynesia
    "MRQ": "PF",  # Marquesas → French Polynesia
    "TUB": "PF",  # Tubuai Is. → French Polynesia
    "CRL": "FM",  # Caroline Is. → Federated States of Micronesia
    "MRN": "GU",  # Marianas → Guam (also CNMI but Guam is the DB entry most likely)
    "MRS": "MH",  # Marshall Islands
    "GGI": "ST",  # Gulf of Guinea Islands → São Tomé and Príncipe
    "WSA": "EH",  # Western Sahara

    # European islands
    "TUE": "TR",  # Türkiye-in-Europe → Turkey (it's the European part)
}

# Caribbean multi-territory TDWG codes
CARIBBEAN_MULTI = {
    "LEE": ["AG", "AI", "BL", "GD", "KN", "LC", "MF", "MS", "VC", "VG", "VI"],  # Leeward Is.
    "WIN": ["BB", "DM", "GD", "LC", "MQ", "VC", "TT"],  # Windward Is.
    "SWC": ["AW", "BQ", "CW", "SX"],  # Southwest Caribbean (ABC islands etc.)
}

# NWG special: spans both Papua New Guinea and Indonesian Papua
NWG_EXTRA_INDONESIA = ["ID-PA", "ID-PB"]  # Papua, West Papua


def load_tdwg_codes(dist_path):
    """Extract unique TDWG L3 codes + area names from the distribution CSV."""
    codes = {}
    with open(dist_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="|")
        for row in reader:
            code = row.get("area_code_l3", "").strip()
            name = row.get("area", "").strip()
            if code and code[0].isupper():  # skip lowercase dupes / empty
                codes[code] = name
    return codes


def load_existing_mapping(json_path):
    """Load existing tdwg_to_places.json as a dict keyed by tdwg_code."""
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return {entry["tdwg_code"]: entry for entry in data}


def load_places_db(db_path):
    """Load place data from SQLite. Returns (countries, subdivisions_by_country, all_codes)."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    # Load all countries
    countries = {}
    for row in conn.execute("SELECT id, code, name FROM place WHERE type = 'country' ORDER BY code"):
        countries[row["code"]] = {"id": row["id"], "name": row["name"]}

    # Load all subdivisions grouped by parent country
    subs_by_country = {}
    for row in conn.execute("""
        SELECT p.code, p.name, parent.code as parent_code
        FROM place p
        JOIN place_hierarchy ph ON ph.place_id = p.id
        JOIN place parent ON parent.id = ph.parent_id
        WHERE p.type IN ('state', 'province')
        ORDER BY p.code
    """):
        parent = row["parent_code"]
        if parent not in subs_by_country:
            subs_by_country[parent] = []
        subs_by_country[parent].append(row["code"])

    # All known place codes
    all_codes = set()
    for row in conn.execute("SELECT code FROM place"):
        all_codes.add(row["code"])

    conn.close()
    return countries, subs_by_country, all_codes


def make_country_entry(country_code, subs_by_country):
    """Make places list for a country: all subdivisions with precision 'country'."""
    if country_code in subs_by_country:
        return [{"code": sub, "precision": "country"} for sub in sorted(subs_by_country[country_code])]
    else:
        # Country without subdivisions - just map to the country code directly
        return [{"code": country_code, "precision": "country"}]


def make_subdivision_entry(sub_codes, precision="exact"):
    """Make places list from explicit subdivision codes."""
    return [{"code": code, "precision": precision} for code in sorted(sub_codes)]


def generate_mapping(tdwg_codes, existing, countries, subs_by_country, all_codes):
    """Generate the full mapping. Returns (result_list, report)."""
    result = {}
    report = {"preserved": [], "matched": [], "unmatched": [], "warnings": []}

    for tdwg_code, tdwg_name in sorted(tdwg_codes.items()):
        # Preserve existing entries byte-for-byte
        if tdwg_code in existing:
            result[tdwg_code] = existing[tdwg_code]
            report["preserved"].append(tdwg_code)
            continue

        # Check hardcoded lookups in priority order

        # 1. Multi-country codes
        if tdwg_code in MULTI_COUNTRY:
            places = []
            for cc in MULTI_COUNTRY[tdwg_code]:
                places.extend(make_country_entry(cc, subs_by_country))
            result[tdwg_code] = {"tdwg_code": tdwg_code, "tdwg_name": tdwg_name, "places": places}
            report["matched"].append(f"{tdwg_code} ({tdwg_name}) → multi-country: {MULTI_COUNTRY[tdwg_code]}")
            continue

        # 2. Sub-country regions
        if tdwg_code in SUB_COUNTRY:
            sub_codes = SUB_COUNTRY[tdwg_code]
            if not sub_codes:
                # Empty list means "use parent country" — need to figure out which
                # For OGA, KZN → Japan; AND, NCB, LDV → India
                parent_map = {
                    "OGA": "JP", "KZN": "JP",
                    "AND": "IN", "NCB": "IN", "LDV": "IN",
                }
                if tdwg_code in parent_map:
                    cc = parent_map[tdwg_code]
                    places = make_country_entry(cc, subs_by_country)
                    result[tdwg_code] = {"tdwg_code": tdwg_code, "tdwg_name": tdwg_name, "places": places}
                    report["matched"].append(f"{tdwg_code} ({tdwg_name}) → {cc} country-level (no specific subdivision)")
                else:
                    report["unmatched"].append(f"{tdwg_code} ({tdwg_name}) — empty sub_country list, no parent")
                continue

            # Check if it's a "map to country" shortcut (e.g., Russian regions → "RU")
            if len(sub_codes) == 1 and len(sub_codes[0]) == 2:
                cc = sub_codes[0]
                places = make_country_entry(cc, subs_by_country)
                result[tdwg_code] = {"tdwg_code": tdwg_code, "tdwg_name": tdwg_name, "places": places}
                report["matched"].append(f"{tdwg_code} ({tdwg_name}) → {cc} country-level")
                continue

            # Mixed: check for country codes vs subdivision codes
            country_codes = [c for c in sub_codes if len(c) == 2]
            subdivision_codes = [c for c in sub_codes if len(c) > 2]

            places = []
            # Handle any country-level codes
            for cc in country_codes:
                places.extend(make_country_entry(cc, subs_by_country))

            # Handle subdivision codes - verify they exist in DB
            valid_subs = [s for s in subdivision_codes if s in all_codes]
            missing_subs = [s for s in subdivision_codes if s not in all_codes]
            if missing_subs:
                report["warnings"].append(f"{tdwg_code}: subdivision codes not in DB: {missing_subs}")

            places.extend(make_subdivision_entry(valid_subs))
            if places:
                result[tdwg_code] = {"tdwg_code": tdwg_code, "tdwg_name": tdwg_name, "places": places}
                report["matched"].append(f"{tdwg_code} ({tdwg_name}) → {len(places)} subdivisions")
            else:
                report["unmatched"].append(f"{tdwg_code} ({tdwg_name}) — no valid subdivision codes found")
            continue

        # 3. Direct country mapping
        if tdwg_code in DIRECT_COUNTRY:
            cc = DIRECT_COUNTRY[tdwg_code]
            if cc in countries or cc in all_codes:
                places = make_country_entry(cc, subs_by_country)
                result[tdwg_code] = {"tdwg_code": tdwg_code, "tdwg_name": tdwg_name, "places": places}
                report["matched"].append(f"{tdwg_code} ({tdwg_name}) → {cc}")
            else:
                report["unmatched"].append(f"{tdwg_code} ({tdwg_name}) → {cc} NOT IN DB")
            continue

        # 4. Island territories
        if tdwg_code in ISLAND_TERRITORIES:
            cc = ISLAND_TERRITORIES[tdwg_code]
            if cc is None:
                # Check Caribbean multi-territory
                if tdwg_code in CARIBBEAN_MULTI:
                    places = []
                    for island_cc in CARIBBEAN_MULTI[tdwg_code]:
                        if island_cc in countries:
                            places.extend(make_country_entry(island_cc, subs_by_country))
                        else:
                            report["warnings"].append(f"{tdwg_code}: island country {island_cc} not in DB")
                    if places:
                        result[tdwg_code] = {"tdwg_code": tdwg_code, "tdwg_name": tdwg_name, "places": places}
                        report["matched"].append(f"{tdwg_code} ({tdwg_name}) → Caribbean multi: {CARIBBEAN_MULTI[tdwg_code]}")
                    else:
                        report["unmatched"].append(f"{tdwg_code} ({tdwg_name}) — no Caribbean islands found in DB")
                else:
                    report["unmatched"].append(f"{tdwg_code} ({tdwg_name}) — remote/uninhabited, no DB entry expected")
                continue

            if cc in countries:
                places = make_country_entry(cc, subs_by_country)
                result[tdwg_code] = {"tdwg_code": tdwg_code, "tdwg_name": tdwg_name, "places": places}
                report["matched"].append(f"{tdwg_code} ({tdwg_name}) → {cc} (island territory)")
            elif cc in all_codes:
                result[tdwg_code] = {"tdwg_code": tdwg_code, "tdwg_name": tdwg_name,
                                     "places": [{"code": cc, "precision": "country"}]}
                report["matched"].append(f"{tdwg_code} ({tdwg_name}) → {cc} (territory code)")
            else:
                report["unmatched"].append(f"{tdwg_code} ({tdwg_name}) → {cc} NOT IN DB (island territory)")
            continue

        # 5. Fallback: try name matching
        match = name_match(tdwg_name, countries)
        if match:
            places = make_country_entry(match, subs_by_country)
            result[tdwg_code] = {"tdwg_code": tdwg_code, "tdwg_name": tdwg_name, "places": places}
            report["matched"].append(f"{tdwg_code} ({tdwg_name}) → {match} (name match)")
        else:
            report["unmatched"].append(f"{tdwg_code} ({tdwg_name}) — no match found")

    # Special handling for NWG (New Guinea) — add Indonesian Papua provinces
    if "NWG" in result:
        existing_codes = {p["code"] for p in result["NWG"]["places"]}
        for papuan_code in NWG_EXTRA_INDONESIA:
            if papuan_code not in existing_codes and papuan_code in all_codes:
                result["NWG"]["places"].append({"code": papuan_code, "precision": "country"})

    return result, report


def name_match(tdwg_name, countries):
    """Try to match a TDWG area name to a country name."""
    # Normalize for comparison
    tdwg_lower = tdwg_name.lower().strip().rstrip(".")

    # Direct name match
    for code, info in countries.items():
        if info["name"].lower() == tdwg_lower:
            return code

    # Common name variations
    name_aliases = {
        "eswatini": "SZ",
        "türkiye": "TR",
        "türkiye-in-europe": "TR",
    }
    if tdwg_lower in name_aliases:
        return name_aliases[tdwg_lower]

    return None


def main():
    print("=" * 70)
    print("TDWG L3 → Gallformers Places Mapping Generator")
    print("=" * 70)

    # Load data
    print(f"\nLoading TDWG codes from {DIST_CSV}...")
    tdwg_codes = load_tdwg_codes(DIST_CSV)
    print(f"  Found {len(tdwg_codes)} unique TDWG L3 codes")

    print(f"\nLoading existing mapping from {EXISTING_JSON}...")
    existing = load_existing_mapping(EXISTING_JSON)
    print(f"  Found {len(existing)} existing entries")

    print(f"\nLoading places from {PLACES_DB}...")
    countries, subs_by_country, all_codes = load_places_db(PLACES_DB)
    print(f"  Found {len(countries)} countries, {sum(len(v) for v in subs_by_country.values())} subdivisions")

    # Generate mapping
    print("\nGenerating mapping...")
    result, report = generate_mapping(tdwg_codes, existing, countries, subs_by_country, all_codes)

    # Write output
    output_list = [result[code] for code in sorted(result.keys())]
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(output_list, f, indent=2, ensure_ascii=False)
        f.write("\n")

    # Print report
    print(f"\n{'=' * 70}")
    print("REPORT")
    print(f"{'=' * 70}")
    print(f"\nTotal TDWG codes in WCVP: {len(tdwg_codes)}")
    print(f"Preserved existing:       {len(report['preserved'])}")
    print(f"Newly matched:            {len(report['matched'])}")
    print(f"Unmatched:                {len(report['unmatched'])}")
    print(f"Total in output:          {len(result)}")

    if report["warnings"]:
        print(f"\n--- WARNINGS ({len(report['warnings'])}) ---")
        for w in sorted(report["warnings"]):
            print(f"  ⚠  {w}")

    if report["unmatched"]:
        print(f"\n--- UNMATCHED ({len(report['unmatched'])}) ---")
        for u in sorted(report["unmatched"]):
            print(f"  ✗  {u}")

    if report["matched"]:
        print(f"\n--- NEWLY MATCHED ({len(report['matched'])}) ---")
        for m in sorted(report["matched"]):
            print(f"  ✓  {m}")

    print(f"\nOutput written to {OUTPUT_JSON}")


if __name__ == "__main__":
    main()
