# WCVP Live Lookup Design

## Problem

Adding new host plants requires manually entering taxonomy, range, and external identifiers. WCVP (World Checklist of Vascular Plants) has authoritative data for all of this, but the current reconciliation pipeline is batch-only — it produces reports for bulk review, not real-time lookups during data entry.

A second consumer (the oaks site) needs the same WCVP lookup capability, so the solution must be shareable across apps.

## Decision Record

Key decisions made during design:

- **Local CSV over POWO API** — POWO has an undocumented API (`powo.science.kew.org/api/1/`) but no stability guarantees. Local data is faster and more reliable.
- **Pre-filtered dataset** — Full WCVP is 434MB / 3.4M rows. Filtering to Western Hemisphere accepted species reduces to ~81MB / 156K names + 648K distribution rows. The TDWG-to-places mapping already defines the region filter.
- **SQLite artifact on S3 over in-process ETS** — Avoids memory pressure on the main app, keeps the build step off production, and enables sharing between gallformers and the oaks site via S3.
- **SQLite over API sidecar** — Two apps downloading a shared file is simpler than both depending on a third service. No new infrastructure to deploy or monitor.
- **host_traits table** — WCVP/POWO IDs are host-specific. Follows the established Class Table Inheritance pattern from `gall_traits`. Provides a natural home for future host-specific attributes.
- **All-or-nothing conflict resolution** — When refreshing an existing host from WCVP, show the diff and let the admin accept all changes or cancel. No per-field cherry-picking.

## Architecture

```
                          S3
                    ┌─────────────┐
  Build Pipeline    │ wcvp.sqlite │    Gallformers App
  (local / CI)      └──────┬──────┘    ┌──────────────────┐
                           │           │  Repo.WCVP       │
  WCVP CSV ──filter──►     │◄──download─│  (read-only)     │
             build SQLite   │           │                  │
             upload         │           │  Wcvp context    │
                           │           │  search/lookup   │
                           │           └──────────────────┘
                           │
                           │           Oaks App
                           │           ┌──────────────────┐
                           │◄──download─│  Repo.WCVP       │
                           │           │  (read-only)     │
                           │           └──────────────────┘
```

## Component 1: Build Pipeline

A mix task that produces the WCVP SQLite artifact:

**Input**: Raw WCVP CSVs (`wcvp_names.csv`, `wcvp_distribution.csv`) from Kew's SFTP server, plus the existing `tdwg_to_places.json` region filter.

**Process**:
1. Stream names CSV, keep only accepted species with rank Species/Variety/Subspecies
2. Stream distribution CSV, collect plant_name_ids that have native distribution in mapped TDWG regions
3. Intersect: keep only names that appear in the filtered distribution set
4. Write to SQLite with two tables and indexes

**Output**: `wcvp.sqlite` uploaded to `s3://gallformers-assets/wcvp/wcvp.sqlite`

**WCVP SQLite schema**:

```sql
CREATE TABLE wcvp_names (
  plant_name_id TEXT PRIMARY KEY,
  taxon_name TEXT NOT NULL,
  family TEXT NOT NULL,
  genus TEXT NOT NULL,
  species TEXT NOT NULL,
  taxon_authors TEXT,
  powo_id TEXT
);

CREATE INDEX idx_wcvp_names_taxon_name ON wcvp_names(taxon_name);
CREATE INDEX idx_wcvp_names_genus ON wcvp_names(genus);
CREATE INDEX idx_wcvp_names_family ON wcvp_names(family);

CREATE TABLE wcvp_distributions (
  plant_name_id TEXT NOT NULL,
  area_code_l3 TEXT NOT NULL,
  PRIMARY KEY (plant_name_id, area_code_l3),
  FOREIGN KEY (plant_name_id) REFERENCES wcvp_names(plant_name_id)
);
```

**Reuses**: `Gallformers.Wcvp.Reader` for CSV parsing and filtering. `Gallformers.Wcvp.Tdwg` for the region filter.

**Refresh cadence**: Manual or scheduled CI. Weekly WCVP updates from Kew happen on Mondays.

## Component 2: Secondary Ecto Repo

A read-only Ecto repo `Gallformers.Repo.WCVP`:

- Configured per environment (`priv/data/wcvp.sqlite` in dev, `/data/wcvp.sqlite` on Fly)
- Read-only mode, no WAL, no migrations
- Started under the supervision tree but tolerant of missing file — app boots without it

**Refresh module** (`Gallformers.Wcvp.Refresh`):

```
refresh() ->
  1. Repo.WCVP.stop()
  2. Download from S3 to temp file
  3. Atomic move temp file -> target path
  4. Repo.WCVP.start_link()
  -> {:ok, :refreshed} | {:error, reason}
```

Admin WCVP features show as disabled when the repo is not started.

## Component 3: Wcvp Context

Public API in `Gallformers.Wcvp`:

- `search(query, opts)` — fuzzy name search, returns list of WCVP name records with distribution. Supports `limit` option.
- `get(plant_name_id)` — exact lookup by WCVP ID, returns name + full distribution codes.
- `available?()` — returns whether the WCVP repo is started and queryable.
- `refresh()` — delegates to the refresh module.

Results are plain maps (not Ecto schemas) since the WCVP DB has no changesets or lifecycle.

## Component 4: Schema Changes

**Migration**: Create `host_traits` table following the `gall_traits` Class Table Inheritance pattern:

```sql
CREATE TABLE host_traits (
  species_id INTEGER PRIMARY KEY,
  wcvp_id TEXT,
  powo_id TEXT,
  FOREIGN KEY (species_id) REFERENCES species(id)
);

CREATE INDEX idx_host_traits_wcvp_id ON host_traits(wcvp_id);
CREATE INDEX idx_host_traits_powo_id ON host_traits(powo_id);
```

**Ecto schema**: `Gallformers.Plants.HostTraits` with `belongs_to :species` and `species_id` as primary key.

**Species schema**: Add `has_one :host_traits` association.

**Backfill**: One-time task uses existing reconciliation match data to populate `wcvp_id`/`powo_id` for hosts already matched to WCVP names.

## Component 5: Admin UX

### Host Creation

New optional step before the existing form. Admin sees a WCVP search field (`.typeahead` component). Selecting a result pre-populates:

- Species name (from `taxon_name`)
- Family and genus (creating taxonomy records if needed)
- Range/places (TDWG codes mapped through `Gallformers.Wcvp.Tdwg`)
- `wcvp_id` and `powo_id` on the host_traits record

The admin reviews and edits before saving. Skipping the WCVP lookup works exactly as today.

### Host Update

"Refresh from WCVP" button on the host edit form. Looks up by `wcvp_id` (stored in host_traits) or falls back to name match. Shows a summary diff:

> **WCVP has different data:**
> - Range: +3 places, -1 place
> - Family: no change
>
> [Apply Updates] [Cancel]

All-or-nothing: apply overwrites range and taxonomy in a single transaction.

### Graceful Degradation

When WCVP data is unavailable (`Wcvp.available?()` returns false):
- Search field and refresh button render as disabled
- Tooltip explains "WCVP data not available"
- No errors, no broken pages

## S3 Layout

```
s3://gallformers-assets/wcvp/
  wcvp.sqlite                    # current version
  wcvp-YYYY-MM-DD.sqlite         # dated archives (optional, for rollback)
```

## What This Design Does Not Include

- Automated weekly refresh (can be added later as a CI scheduled job)
- Synonym resolution at lookup time (the build step only includes accepted names)
- POWO API integration (local data only)
- Changes to the oaks site (it will use the same S3 artifact with its own Repo.WCVP)
