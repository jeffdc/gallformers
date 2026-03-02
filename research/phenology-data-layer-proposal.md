---
status: raw
created: 2026-03-02
updated: 2026-03-02
epic: 1-foundation
relates: [5c56]
---

# Phenology data layer

Add phenological observation data as a native data layer in gallformers. Observations track when galls appear at specific locations, enabling phenology visualization on gall pages and a standalone phenology explorer. Data comes from two sources: literature (historical records from published papers) and iNaturalist (ongoing, with automated import and admin review).

## Motivation

Phenology data currently lives in a separate SQLite database maintained outside gallformers. This creates a sync problem: when species get renamed, merged, or split in gallformers, the phenology database has to be manually updated to match. By making observations a native table with a foreign key to species, taxonomic operations cascade automatically. The merge/split design (5c56) handles observations the same way it handles every other FK — no special phenology sync logic needed.

There's also an existing R Shiny app (gallphen.org) that visualizes this data. Replacing it with a built-in gallformers page eliminates a separate deployment, puts phenology data where users are already looking (on the gall's page), and enables filtering by gall traits that the Shiny app can't access.

## Data model

### Observations table

Each row is one phenological observation of a gall at a specific place and time.

```
phenology_observations
  id              INTEGER PRIMARY KEY
  species_id      INTEGER NOT NULL  → species(id) ON DELETE CASCADE
  host_species_id INTEGER           → species(id) ON DELETE SET NULL
  source_type     TEXT NOT NULL      -- 'literature' or 'inat'
  inat_id         INTEGER           -- iNaturalist observation ID (unique, nullable)

  -- Raw fields (from source, always overwritten on re-import)
  raw_phenophase  TEXT               -- phenophase as reported by source
  raw_date        TEXT               -- observation date
  raw_latitude    REAL
  raw_longitude   REAL

  -- Processed fields (set by auto-categorization or admin, preserved across re-imports)
  phenophase      TEXT               -- admin-reviewed phenophase
  date            TEXT NOT NULL
  doy             INTEGER NOT NULL   -- day of year
  latitude        REAL NOT NULL
  longitude       REAL NOT NULL
  site            TEXT
  state           TEXT
  country         TEXT

  -- Computed phenology values
  seasind         REAL               -- season index (fraction of annual daylight hours)
  acchours        REAL               -- accumulated daylight hours

  -- Provenance
  source_url      TEXT               -- gallformers source URL or literature link
  page_url        TEXT               -- specific page (e.g., BHL page link)

  -- Metadata
  inserted_at     TEXT NOT NULL
  updated_at      TEXT NOT NULL
```

The species_id FK means merge/split operations from 5c56 handle observations automatically:
- **Merge (B → A)**: B's observations stay on B. B is frozen but its data (including observations) remains intact. A's page can optionally show "including observations from synonym B" in the phenology tab.
- **Split (A → A + B)**: Observations are cloned to B along with everything else. Admin trims observations from both sides during the diverge step — same workflow as trimming hosts or images.
- **Delete**: CASCADE removes observations. The existing "deleted with observations" safety check applies.

### Raw vs processed fields — implicit correction rules

Instead of a separate correction rules table, the raw/processed split encodes corrections implicitly:

- **Raw fields** are always overwritten from the source on each re-import (iNat API refresh)
- **Processed fields** are set once — either by auto-categorization or by admin decision — and preserved across re-imports
- When raw and processed **agree**: observation is clean
- When raw and processed **disagree**: an admin correction is in effect (e.g., raw_phenophase="Adult" but phenophase="developing")
- When raw **changes** and now differs from processed: flag for re-review (the upstream data changed, admin should check if their correction still applies)
- When raw changes and now **matches** processed: correction is no longer needed, clear the flag

This means "always reclassify this observation's phenophase from Adult to developing" isn't stored as a rule — it's stored as the fact that `raw_phenophase = 'Adult'` and `phenophase = 'developing'`. The disagreement is the rule. No grammar to design, no rule engine to maintain.

For literature observations, raw and processed are identical (no upstream source that changes).

### Blacklist table

```
phenology_blacklist
  id              INTEGER PRIMARY KEY
  inat_id         INTEGER NOT NULL UNIQUE  -- iNaturalist observation ID
  species_id      INTEGER           → species(id) ON DELETE CASCADE
  reason          TEXT
  inserted_at     TEXT NOT NULL
```

Rejected iNat observations go here so they aren't re-imported on the next fetch cycle.

## iNaturalist import pipeline

### Automated fetch

A scheduled job (GenServer or Oban) runs at a configurable interval (daily or weekly):

1. For each gall species with an iNat taxon code, fetch recent RG observations with phenology annotations
2. Skip observations already in phenology_observations (by inat_id) or phenology_blacklist
3. Auto-categorize each new observation:
   - Match to species by iNat taxon ID → gallformers inatcode
   - Compute season index from latitude + DOY
   - Check plausibility bounds against existing data (IQR fences + data range constraint)
   - Auto-accept observations that pass all checks
   - Flag observations that fail any check for admin review
4. Insert accepted observations with both raw and processed fields set to the same values
5. Queue flagged observations for admin review

### Admin review interface

Admin page for reviewing flagged observations. For each flagged observation:
- Photo thumbnail from iNat
- Map pin showing location
- Flag reason (out of season, ambiguous species match, missing phenophase, etc.)
- Predicted phenophase (based on season index vs existing distribution)
- Actions: accept (with optional field overrides), reject (add to blacklist), skip

Bulk actions:
- Accept all with predicted phenophase
- Set phenophase/generation for all visible, then accept
- Open batch in iNaturalist Identify (filter-based URL with relevant params)

Two-click confirmation on all bulk/destructive actions.

### Plausibility checking

Two-layer bounds for detecting outlier observations:
- IQR fences (2.5x multiplier) for baseline
- Data range + buffer constraint for species with 30+ observations (catches outliers that IQR alone misses when distributions are tight)
- Minimum half-width of 0.05 SI to avoid rejecting observations in narrow but valid windows

## Literature CSV import

### Motivation

New phenology data from published papers will continue to appear. Currently this requires manual SQL or script-based insertion. A dedicated admin page makes literature import self-service, with validation and duplicate detection so bad data doesn't slip in.

### Import flow

Admin page with a guided multi-step process:

1. **Format guide**: Shows the expected CSV format with column names, types, and examples. Downloadable template CSV. Documents conventions (phenophase vocabulary, date formats, how to specify coordinates, how to reference gallformers sources).

2. **Upload + parse**: Admin uploads a CSV. Parser validates:
   - Required columns present (species name or gallformers code, date, latitude, longitude, phenophase)
   - Date formats parseable
   - Coordinates within reasonable bounds
   - Phenophase values match the controlled vocabulary
   - Species names resolve to existing gallformers species (by name match or gallformers_code)
   Reports errors per row with suggested fixes (e.g., "row 12: phenophase 'adult' — did you mean 'Adult'?", "row 30: 'Andricus quercuscalifornicus' not found — did you mean 'Andricus quercuscalifornicus (agamic)' (id=1234)?").

3. **Duplicate detection**: Flags rows that appear to match existing observations based on species + date + coordinates (within a small tolerance). Shows the existing observation alongside the proposed import so the admin can decide: skip, replace, or add anyway.

4. **Preview + confirm**: Shows a summary table of all rows that will be imported, color-coded by status (clean, auto-fixed, skipped duplicate). Admin reviews and confirms. Season index and accumulated hours are computed automatically on import.

5. **Import**: Inserts accepted rows into phenology_observations with source_type='literature'. Raw and processed fields are set identically (no upstream source to track changes from).

### Source attribution

Each literature import should reference a gallformers source (the `source` table). The CSV can include a source URL or source ID column. If the source doesn't exist yet, the import flow prompts the admin to create it first — keeping source management in the existing gallformers workflow rather than duplicating it.

## Public phenology visualization

### Per-gall phenology tab

Each gall's public page gets a "Phenology" tab showing its observation data. This replaces the per-species view in the current Shiny app.

**Chart: DOY vs Latitude scatter plot**
- X-axis: Date (displayed as calendar months, Jan–Dec)
- Y-axis: Latitude (degrees N)
- Points colored by generation (blue = sexual, red = agamic, black = unknown)
- Points shaped by phenophase (circle = developing, triangle = maturing, square = dormant, star = oviscar, cross = perimature)
- Season index rendered as reference curves overlaid on the DOY chart (not as an axis — SI isn't meaningful to users, but the curves show where "equivalent phenological time" falls across latitudes)
- Optional: linear regression lines showing predicted emergence/rearing windows by latitude

**Filters:**
- Generation (sexual / agamic / all)
- Phenophase (multi-select)
- Date range
- Latitude/longitude bounds

**Data source attribution:**
- Literature observations cite their source
- iNat observations link back to the original observation

### Standalone phenology explorer

A dedicated page for cross-species phenological analysis. Users can:

- Search/select one or more species to compare
- Filter by date range, latitude/longitude bounds
- Filter by gall traits: shape, texture, detachability, host plant, plant part, alignment
- (Future) Filter by inducer traits: insect family, generation pattern
- Toggle between DOY and season-index-adjusted views
- Download filtered data as CSV

This replaces the current Shiny app entirely and adds trait-based filtering that the Shiny app can't do (since it doesn't have access to the gall trait data).

## Data migration

### Existing data

The current phenology database contains:
- ~14,000 literature observations across ~489 species
- ~20,000 iNaturalist observations
- All species already mapped to gallformers IDs

Migration is a one-time import:
1. Match each observation's gall_id to the corresponding gallformers species_id via the existing gf_id mapping
2. Import literature observations with raw = processed (no upstream source to track)
3. Import iNat observations with raw = processed (establishing baseline)
4. Import blacklist entries

### Species coverage

Current data coverage across ~3,200 gall species:
- ~29 well-covered (50+ observations, 3+ phenophases)
- ~474 seeded (1–49 observations)
- ~2,685 empty (no observations yet)

The automated import pipeline will gradually fill in coverage over time.

## Interaction with merge/split (5c56)

### Merge: observations stay with frozen species

When B merges into A, B's observations remain attached to B (which is frozen but intact). Options for display:

- A's phenology tab shows only A's observations by default
- Toggle to include observations from synonyms (B) — query follows merged_into_id chain
- This preserves provenance: you can always see which observations were originally attributed to which name

### Split: clone + admin triage

When A splits into A + B, observations are cloned to both (same as images, hosts, etc.). Admin then reviews the observation lists on both species and removes observations that don't belong on each side. The admin review UI for splits should show the DOY-latitude chart for both species side by side so the admin can visually identify which observations cluster with which species.

### Host merge/split

When a host plant is merged or split, observations aren't directly affected (they point at gall species, not hosts). The host_species_id on observations is informational and uses ON DELETE SET NULL, so host merges don't cascade destructively.

## Implementation sequence

Suggested ordering, each as a separate PR:

1. **Schema + context**: Migration adding phenology_observations and phenology_blacklist tables. Ecto schemas. Context module with CRUD operations and import logic. Season index computation in Elixir.
2. **Data migration**: One-time import of existing phenology data from the current SQLite database.
3. **Literature CSV import**: Admin page for uploading new literature data with validation, duplicate detection, and guided fixes.
4. **Admin review UI**: LiveView admin page for reviewing flagged iNat observations, bulk actions, iNat Identify links.
5. **Automated import**: Scheduled job for fetching new iNat observations, auto-categorization, plausibility checking.
6. **Public gall page tab**: Phenology tab on each gall's species page with DOY-latitude chart.
7. **Phenology explorer**: Standalone page with cross-species comparison and trait filtering.
