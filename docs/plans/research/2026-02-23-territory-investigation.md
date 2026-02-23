# Natural Earth Territory Investigation

Date: 2026-02-23

## Purpose

Determine which Natural Earth (NE) 10m layer contains each overseas/dependent territory,
so we know which extraction pattern to use in `build_boundaries.sh`.

## Categories

- **Category A** — Found in `admin_0_countries` with its own ADM0_A3 code. Just add to the COUNTRIES array.
- **Category B** — Found only in `admin_0_map_subunits` (not in admin_0_countries). Needs SUBUNIT extraction with SU_A3 code mapping.
- **Category C** — Found only in `admin_1_states_provinces` as a subdivision of a parent country. Needs custom extraction block filtering by adm0_a3 + name/iso_3166_2.

> Note: Many territories appear in multiple layers. The category reflects the *simplest*
> extraction approach. If a territory is in admin_0_countries, use Category A even if it
> also appears in subunits/admin-1.

## Results by Sovereign Nation

### France

| Territory | Alpha-3 | Alpha-2 | Primary Layer | Category | SU_A3 | Notes |
|-----------|---------|---------|---------------|----------|-------|-------|
| French Guiana | GUF | GF (NE: FR-973) | subunits only | **B** | GUF | Not in admin_0_countries. ADMIN=France, ADM0_A3=FRA |
| Guadeloupe | GLP | GP (NE: FR-971) | subunits only | **B** | GLP | Not in admin_0_countries. ADMIN=France, ADM0_A3=FRA |
| Martinique | MTQ | MQ (NE: FR-972) | subunits only | **B** | MTQ | Not in admin_0_countries. ADMIN=France, ADM0_A3=FRA |
| Reunion | REU | RE (NE: FR-974) | subunits only | **B** | REU | Not in admin_0_countries. ADMIN=France, ADM0_A3=FRA |
| Mayotte | MYT | YT (NE: FR-976) | subunits only | **B** | MYT | Not in admin_0_countries. TYPE=Disputed |
| New Caledonia | NCL | NC | countries | **A** | NCL | Also in subunits and admin-1 |
| French Polynesia | PYF | PF | countries | **A** | PYF | Also in subunits and admin-1 |
| Wallis and Futuna | WLF | WF | countries | **A** | WLF | Also in subunits and admin-1 |
| Saint Barthelemy | BLM | BL | countries | **A** | BLM | Also in subunits and admin-1 |
| Saint Martin | MAF | MF | countries | **A** | MAF | Also in subunits and admin-1 |
| Fr. Southern Territories | ATF | TF | countries | **A** | -- | Multiple subunits (JUI, FSA, EUI, BSI, TEI, GOI). Subunit ISO_A2 all -99 |

**Key finding**: The five French overseas departments (GUF, GLP, MTQ, REU, MYT) are NOT in
admin_0_countries -- they are subunits of France. Their NE ISO_A2 values use the FR-xxx
regional code format, not standard ISO alpha-2. For SUBUNIT_ALPHA2 mapping, use the
standard ISO codes: GF, GP, MQ, RE, YT.

### United Kingdom

| Territory | Alpha-3 | Alpha-2 | Primary Layer | Category | SU_A3 | Notes |
|-----------|---------|---------|---------------|----------|-------|-------|
| Gibraltar | GIB | GI | countries | **A** | GIB | TYPE=Disputed |
| Saint Helena | SHN | SH | countries | **A** | -- | Multiple subunits: SHT (Tristan da Cunha), SHS (St. Helena), BAC (Ascension) |
| Pitcairn Islands | PCN | PN | countries | **A** | PCN | |
| British Indian Ocean Ter. | IOT | IO | countries | **A** | IOT | Also has IOD (Diego Garcia NSF) overlay subunit |
| Falkland Islands | FLK | FK | countries | **A** | FLK | TYPE=Disputed |
| South Georgia | SGS | GS | countries | **A** | -- | Two subunits: SGG (S. Georgia), SGX (S. Sandwich Is.) |
| Bermuda | BMU | BM | countries | **A** | BMU | |
| Cayman Islands | CYM | KY | countries | **A** | CYM | |
| Turks and Caicos | TCA | TC | countries | **A** | TCA | |
| British Virgin Islands | VGB | VG | countries | **A** | VGB | |
| Anguilla | AIA | AI | countries | **A** | AIA | |
| Montserrat | MSR | MS | countries | **A** | MSR | |

**Key finding**: All UK territories are in admin_0_countries. Straightforward Category A.

### Netherlands

| Territory | Alpha-3 | Alpha-2 | Primary Layer | Category | SU_A3 | Notes |
|-----------|---------|---------|---------------|----------|-------|-------|
| Aruba | ABW | AW | countries | **A** | ABW | TYPE=Country (constituent country of NL) |
| Curacao | CUW | CW | countries | **A** | CUW | TYPE=Country (constituent country of NL) |
| Sint Maarten | SXM | SX | countries | **A** | SXM | TYPE=Country (constituent country of NL) |
| Caribbean Netherlands | BES | BQ | subunits only | **B** | NLY | Not in admin_0_countries. ADM0_A3=NLD, SU_A3=NLY (not BES!) |

**Key finding**: BES (Caribbean Netherlands / Bonaire, Saba, Sint Eustatius) uses SU_A3=NLY
in Natural Earth, not BES. The ISO_A3 field contains BES but the subunit code is NLY.
Need to use SU_A3=NLY for extraction and map the output to alpha-2 BQ.

### United States

| Territory | Alpha-3 | Alpha-2 | Primary Layer | Category | SU_A3 | Notes |
|-----------|---------|---------|---------------|----------|-------|-------|
| Guam | GUM | GU | countries | **A** | GUM | |
| American Samoa | ASM | AS | countries | **A** | ASM | |
| Northern Mariana Islands | MNP | MP | countries | **A** | MNP | |
| US Minor Outlying Islands | UMI | UM | countries | **A** | -- | 9 subunits (JQI, DQI, FQI, HQI, WQI, MQI, BQI, LQI, KQI). All ISO_A2=-99 |
| Puerto Rico | PRI | PR | countries | **A** | PRI | admin-1 iso_3166_2=US-PR (listed under US) |
| US Virgin Islands | VIR | VI | countries | **A** | VIR | |

**Key finding**: All US territories are in admin_0_countries. UMI has many tiny subunits
but the countries-level geometry should combine them.

### Denmark

| Territory | Alpha-3 | Alpha-2 | Primary Layer | Category | SU_A3 | Notes |
|-----------|---------|---------|---------------|----------|-------|-------|
| Faroe Islands | FRO | FO | countries | **A** | FRO | |
| Greenland | GRL | GL | countries | **A** | GRL | TYPE=Country (constituent country of DK) |

### Australia

| Territory | Alpha-3 | Alpha-2 | Primary Layer | Category | SU_A3 | Notes |
|-----------|---------|---------|---------------|----------|-------|-------|
| Norfolk Island | NFK | NF | countries | **A** | NFK | |
| Christmas Island | CXR | CX | subunits only | **B** | CXR | Grouped under IOA (Indian Ocean Territories), ADM0_A3=IOA |
| Cocos (Keeling) Islands | CCK | CC | subunits only | **B** | CCK | Grouped under IOA (Indian Ocean Territories), ADM0_A3=IOA |
| Heard/McDonald Islands | HMD | HM | countries | **A** | HMD | |

**Key finding**: CXR and CCK are NOT standalone entries in admin_0_countries. They are
subunits of the composite "Indian Ocean Territories" (IOA) entry. Their admin-1 entries
also have broken iso codes (iso_a2=-1, iso_3166_2=-99-X14~/X15~).

### New Zealand

| Territory | Alpha-3 | Alpha-2 | Primary Layer | Category | SU_A3 | Notes |
|-----------|---------|---------|---------------|----------|-------|-------|
| Cook Islands | COK | CK | countries | **A** | COK | |
| Niue | NIU | NU | countries | **A** | NIU | |
| Tokelau | TKL | TK | subunits only | **B** | TKL | Not in admin_0_countries. ADM0_A3=NZL, ADMIN=New Zealand |

### Norway

| Territory | Alpha-3 | Alpha-2 | Primary Layer | Category | SU_A3 | Notes |
|-----------|---------|---------|---------------|----------|-------|-------|
| Svalbard and Jan Mayen | SJM | SJ | subunits only | **B** | NSV | SU_A3=NSV (not SJM!). ADM0_A3=NOR |
| Bouvet Island | BVT | BV | subunits only | **B** | BVT | ADM0_A3=NOR |

**Key finding**: SJM uses SU_A3=NSV in Natural Earth. Need to extract by SU_A3=NSV and
map output to alpha-2 SJ.

### China

| Territory | Alpha-3 | Alpha-2 | Primary Layer | Category | SU_A3 | Notes |
|-----------|---------|---------|---------------|----------|-------|-------|
| Hong Kong | HKG | HK | countries | **A** | HKG | TYPE=Country |
| Macau | MAC | MO | countries | **A** | MAC | TYPE=Country |

### Portugal (admin-1 subdivisions)

| Territory | ISO 3166-2 | Primary Layer | Category | Notes |
|-----------|------------|---------------|----------|-------|
| Azores | PT-20 | admin-1 only | **C** | Subdivision of PRT |
| Madeira | PT-30 | admin-1 only | **C** | Subdivision of PRT |

**Key finding**: No separate ISO alpha-3 codes. These are Portuguese provinces extracted
from admin-1 by filtering `adm0_a3=PRT` and `name=Azores` / `name=Madeira`.

### Spain (admin-1 subdivisions)

| Territory | ISO 3166-2 | Primary Layer | Category | Notes |
|-----------|------------|---------------|----------|-------|
| Ceuta | ES-CE | admin-1 only | **C** | Subdivision of ESP |
| Melilla | ES-ML | admin-1 only | **C** | Subdivision of ESP |
| Canary Islands (Las Palmas) | ES-GC | admin-1 only | **C** | Province-level, not a single region |
| Canary Islands (Tenerife) | ES-TF | admin-1 only | **C** | Province-level, not a single region |

**Key finding**: The Canary Islands are not a single admin-1 region in Natural Earth.
They are split into two provinces: "Las Palmas" (ES-GC) and "Santa Cruz de Tenerife" (ES-TF).
To get a single Canary Islands boundary, extract both and merge with ogr2ogr.

## Summary by Category

### Category A -- Add to COUNTRIES array (31 territories)

These have their own entry in admin_0_countries and can be extracted with the standard
country extraction pattern:

```
NCL PYF WLF BLM MAF ATF
GIB SHN PCN IOT FLK SGS BMU CYM TCA VGB AIA MSR
ABW CUW SXM
GUM ASM MNP UMI PRI VIR
FRO GRL
NFK HMD
COK NIU
HKG MAC
```

### Category B -- Need SUBUNIT extraction (10 territories)

These exist only in admin_0_map_subunits. Need to extract by SU_A3 code (which may
differ from ISO alpha-3) and map to the correct alpha-2 code:

| ISO Alpha-3 | SU_A3 in NE | Alpha-2 for output | Name |
|-------------|-------------|-------------------|------|
| GUF | GUF | GF | French Guiana |
| GLP | GLP | GP | Guadeloupe |
| MTQ | MTQ | MQ | Martinique |
| REU | REU | RE | Reunion |
| MYT | MYT | YT | Mayotte |
| BES | **NLY** | BQ | Caribbean Netherlands |
| CXR | CXR | CX | Christmas Island |
| CCK | CCK | CC | Cocos (Keeling) Islands |
| TKL | TKL | TK | Tokelau |
| SJM | **NSV** | SJ | Svalbard and Jan Mayen |
| BVT | BVT | BV | Bouvet Island |

**Watch out**: BES->NLY and SJM->NSV are the tricky code mismatches.

### Category C -- Need admin-1 extraction (6 territories)

These are subdivisions of their parent country in admin-1 and need custom extraction:

| Name | adm0_a3 | Filter | ISO 3166-2 | Notes |
|------|---------|--------|------------|-------|
| Azores | PRT | name='Azores' | PT-20 | |
| Madeira | PRT | name='Madeira' | PT-30 | |
| Ceuta | ESP | name='Ceuta' | ES-CE | |
| Melilla | ESP | name='Melilla' | ES-ML | |
| Canary Islands | ESP | name='Las Palmas' OR name='Santa Cruz de Tenerife' | ES-GC, ES-TF | Merge two provinces |

### Not Found

No territories from the investigation list were completely absent from Natural Earth.
All were found in at least one layer.

## Surprising Findings

1. **French DOMs use FR-xxx codes**: NE stores French overseas departments (GUF, GLP, MTQ,
   REU, MYT) with ISO_A2 values like "FR-973" instead of standard alpha-2 codes. The
   SUBUNIT_ALPHA2 mapping must use the real ISO codes (GF, GP, MQ, RE, YT).

2. **BES -> NLY mismatch**: Caribbean Netherlands has ISO_A3=BES but SU_A3=NLY in NE.

3. **SJM -> NSV mismatch**: Svalbard has ISO_A3=SJM but SU_A3=NSV in NE (NE uses the
   code for "Norway Svalbard" internally).

4. **IOA composite**: Christmas Island and Cocos Islands are grouped under a composite
   "Indian Ocean Territories" (IOA) entry in admin_0_countries. They must be extracted
   as individual subunits (CXR, CCK) from the subunits layer.

5. **Canary Islands split**: No single "Canary Islands" region exists -- it is two
   province-level entries (Las Palmas and Santa Cruz de Tenerife) that need merging.

6. **ATF / SHN / SGS / UMI have many subunits**: These composite territories have
   multiple geo-subunits in the subunits layer, but their admin_0_countries entry
   provides the combined geometry. Use Category A (countries) for simplicity.

7. **Puerto Rico admin-1 is US-PR**: In admin-1, Puerto Rico's iso_3166_2 is "US-PR"
   (under the US), but its admin_0_countries entry correctly has ADM0_A3=PRI and
   ISO_A2=PR. Use Category A.
