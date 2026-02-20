# Place Reference — Canonical Map Coverage

Generated from `priv/gallformers.sqlite` place table, cross-referenced against
`build_boundaries.sh` COUNTRIES, STATE_COUNTRIES, and subunit arrays.

## Summary

| Category | Count |
|----------|-------|
| Countries in DB | 55 |
| Countries covered by build script | 55 |
| **Missing from build script** | **0** |
| Countries with subdivisions (STATE_COUNTRIES) | 26 |
| Total subdivision places in DB | 446 |

## Known Code Mismatches (DB vs Natural Earth)

These DB subdivision codes don't match Natural Earth's `iso_3166_2` values.
The features exist in tiles under different codes — no geometry is missing.

| DB Code | DB Name | NE Code | NE Name | Notes |
|---------|---------|---------|---------|-------|
| CO-DC | Bogota | CO-CUN | Cundinamarca | NE treats Bogota as part of Cundinamarca |
| PE-LMA | Lima Province | PE-LIM | Lima | NE uses PE-LIM for both Lima and Lima Province |

## ~~Missing Countries~~ (RESOLVED)

All countries are now covered. KNA, LCA, TTO, VCT were added to the COUNTRIES array.

~~These countries exist in the database but have NO geometry in the tiles:~~

| DB Code | Name | Alpha-3 | Parent |
|---------|------|---------|--------|
| KN | Saint Kitts and Nevis | KNA | Caribbean |
| LC | Saint Lucia | LCA | Caribbean |
| TT | Trinidad and Tobago | TTO | Caribbean |
| VC | Saint Vincent and the Grenadines | VCT | Caribbean |

All four are Caribbean island nations in `admin_0_countries` (standard NE layer).

## Countries — Full Cross-Reference

Legend:
- **Source**: `admin0` = ne_10m_admin_0_countries, `subunit` = ne_10m_admin_0_map_subunits, `admin1` = ne_10m_admin_1_states_provinces
- **Tile layers**: `countries` = appears in countries layer, `subdivisions` = appears in subdivisions layer
- **subdivided**: Has STATE_COUNTRIES entry (admin-1 subdivision tiles generated)

### North America

| DB Code | Name | Alpha-3 | Source | Tile Layers | Subdivided |
|---------|------|---------|--------|-------------|------------|
| CA | Canada | CAN | admin0 | countries, subdivisions | yes |
| GL | Greenland | GRL | admin0 | countries, subdivisions* | no |
| MX | Mexico | MEX | admin0 | countries, subdivisions | yes |
| PM | Saint Pierre and Miquelon | SPM | admin0 | countries, subdivisions* | no |
| US | United States | USA | admin0 | countries, subdivisions | yes |

*Non-subdivided countries should appear in subdivisions layer via non_subdivided.geojson merge.

### Central America

| DB Code | Name | Alpha-3 | Source | Tile Layers | Subdivided |
|---------|------|---------|--------|-------------|------------|
| BZ | Belize | BLZ | admin0 | countries, subdivisions | yes |
| CR | Costa Rica | CRI | admin0 | countries, subdivisions | yes |
| GT | Guatemala | GTM | admin0 | countries, subdivisions | yes |
| HN | Honduras | HND | admin0 | countries, subdivisions | yes |
| NI | Nicaragua | NIC | admin0 | countries, subdivisions | yes |
| PA | Panama | PAN | admin0 | countries, subdivisions | yes |
| SV | El Salvador | SLV | admin0 | countries, subdivisions | yes |

### Caribbean

| DB Code | Name | Alpha-3 | Source | Tile Layers | Subdivided |
|---------|------|---------|--------|-------------|------------|
| AG | Antigua and Barbuda | ATG | admin0 | countries, subdivisions* | no |
| AI | Anguilla | AIA | admin0 | countries, subdivisions* | no |
| AW | Aruba | ABW | admin0 | countries, subdivisions* | no |
| BB | Barbados | BRB | admin0 | countries, subdivisions* | no |
| BL | Saint Barthélemy | BLM | admin0 | countries, subdivisions* | no |
| BM | Bermuda | BMU | admin0 | countries, subdivisions* | no |
| BQ | Caribbean Netherlands | BES | admin1 | countries, subdivisions* | no |
| BS | Bahamas | BHS | admin0 | countries, subdivisions* | no |
| CU | Cuba | CUB | admin0 | countries, subdivisions | yes |
| CW | Curaçao | CUW | admin0 | countries, subdivisions* | no |
| DM | Dominica | DMA | admin0 | countries, subdivisions* | no |
| DO | Dominican Republic | DOM | admin0 | countries, subdivisions | yes |
| GD | Grenada | GRD | admin0 | countries, subdivisions* | no |
| GP | Guadeloupe | GLP | subunit | countries, subdivisions* | no |
| HT | Haiti | HTI | admin0 | countries, subdivisions | yes |
| JM | Jamaica | JAM | admin0 | countries, subdivisions | yes |
| **KN** | **Saint Kitts and Nevis** | **KNA** | **MISSING** | **none** | no |
| KY | Cayman Islands | CYM | admin0 | countries, subdivisions* | no |
| **LC** | **Saint Lucia** | **LCA** | **MISSING** | **none** | no |
| MF | Saint Martin | MAF | admin0 | countries, subdivisions* | no |
| MQ | Martinique | MTQ | subunit | countries, subdivisions* | no |
| MS | Montserrat | MSR | admin0 | countries, subdivisions* | no |
| PR | Puerto Rico | PRI | admin0 | countries, subdivisions* | no |
| SX | Sint Maarten | SXM | admin0 | countries, subdivisions* | no |
| TC | Turks and Caicos Islands | TCA | admin0 | countries, subdivisions* | no |
| **TT** | **Trinidad and Tobago** | **TTO** | **MISSING** | **none** | no |
| **VC** | **Saint Vincent and the Grenadines** | **VCT** | **MISSING** | **none** | no |
| VG | British Virgin Islands | VGB | admin0 | countries, subdivisions* | no |
| VI | United States Virgin Islands | VIR | admin0 | countries, subdivisions* | no |

### South America

| DB Code | Name | Alpha-3 | Source | Tile Layers | Subdivided |
|---------|------|---------|--------|-------------|------------|
| AR | Argentina | ARG | admin0 | countries, subdivisions | yes |
| BO | Bolivia | BOL | admin0 | countries, subdivisions | yes |
| BR | Brazil | BRA | admin0 | countries, subdivisions | yes |
| CL | Chile | CHL | admin0 | countries, subdivisions | yes |
| CO | Colombia | COL | admin0 | countries, subdivisions | yes |
| EC | Ecuador | ECU | admin0 | countries, subdivisions | yes |
| FK | Falkland Islands | FLK | admin0 | countries, subdivisions* | no |
| GF | French Guiana | GUF | subunit | countries, subdivisions* | no |
| GS | South Georgia & SSI | SGS | admin0 | countries, subdivisions* | no |
| GY | Guyana | GUY | admin0 | countries, subdivisions | yes |
| PE | Peru | PER | admin0 | countries, subdivisions | yes |
| PY | Paraguay | PRY | admin0 | countries, subdivisions | yes |
| SR | Suriname | SUR | admin0 | countries, subdivisions | yes |
| UY | Uruguay | URY | admin0 | countries, subdivisions | yes |
| VE | Venezuela | VEN | admin0 | countries, subdivisions | yes |

## Non-Subdivided → Subdivisions Layer (FIXED)

Entries marked with `subdivisions*` are non-subdivided countries that appear in the
subdivisions layer via the non_subdivided.geojson merge in step 3b of build_boundaries.sh.

**Previous bug**: tippecanoe's `--read-parallel` flag splits input at newline boundaries.
jq's default pretty-printed output caused large multi-line features (Greenland, French
Guiana, etc.) to be silently truncated. **Fix**: use `jq -c` (compact output, one line
per feature) so `--read-parallel` can safely split the file.

## Subdivision Coverage

All 26 STATE_COUNTRIES have matching subdivision records in the DB.
Total subdivision records: 446 (types: state, province).

| Country | DB Code | Subdivision Count |
|---------|---------|-------------------|
| Argentina | AR | 24 |
| Belize | BZ | 6 |
| Bolivia | BO | 9 |
| Brazil | BR | 27 |
| Canada | CA | 13 |
| Chile | CL | 16 |
| Colombia | CO | 33 |
| Costa Rica | CR | 7 |
| Cuba | CU | 17 |
| Dominican Republic | DO | 32 |
| Ecuador | EC | 24 |
| El Salvador | SV | 14 |
| Guatemala | GT | 22 |
| Guyana | GY | 10 |
| Honduras | HN | 18 |
| Haiti | HT | 10 |
| Jamaica | JM | 14 |
| Mexico | MX | 32 |
| Nicaragua | NI | 17 |
| Panama | PA | 12 |
| Peru | PE | 26 |
| Paraguay | PY | 19 |
| Suriname | SR | 10 |
| United States | US | 51 |
| Uruguay | UY | 19 |
| Venezuela | VE | 25 |
