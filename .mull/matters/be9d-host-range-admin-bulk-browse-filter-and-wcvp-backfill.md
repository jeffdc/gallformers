---
status: refined
created: 2026-03-06
updated: 2026-03-11
epic: admin
relates: [b9e5, 2dc1, f6d4, 383e, 0df8, 600a, 7157, 91cf, c52c, 154b]
needs: [f6d4]
---

# Host range admin — bulk browse, filter, and WCVP backfill

Permanent admin page for browsing hosts and managing range data in bulk. Own page in the admin section, not a tab on existing hosts list.

## Problem

Two categories of hosts need range attention:
1. **No range data** (~542 hosts) — the host admin form blocks saving without range, but backfilling one-by-one isn't feasible
2. **Stale NA-only ranges** — hosts added when gallformers was North America-only have incomplete/incorrect ranges for their actual global distribution

This is ongoing work. WCVP does weekly updates. Plant taxonomy and ranges change constantly.

**Out of scope:** Genus-level hosts (spp/sp, ~101) — separate problem, separate matter.

## Architecture

### 1. Enriched WCVP artifact DB (offline pipeline)

Independent task that downloads Kew CSVs and builds a read-only sqlite DB. Runs locally (manual initially, automated eventually). Artifact pushed to S3, app on prod pulls it down.

**Key change from current build_db:** Store ALL data from both CSVs. No filtering by taxon_status, taxon_rank, or TDWG region. The DB is a faithful sqlite mirror of the CSVs.

**`wcvp_names` table — all 31 columns:**
- All taxon_status values: Accepted, Synonym, Misapplied, Orthographic, Unplaced, Invalid, Illegitimate, Artificial Hybrid, Local Biotype
- All taxon_rank values: Species, Subspecies, Variety, Form, Genus, plus ~25 historical/obscure ranks
- Synonym→accepted links via `accepted_plant_name_id` — enables SQL-based matching, replaces the CSV-scan Matcher pipeline
- New fields: `lifeform_description`, `geographic_area`, `climate_description`, `infraspecific_rank`, `infraspecies`, `first_published`, `parent_plant_name_id`, `ipni_id`, `basionym_plant_name_id`, hybrid fields, publication fields, etc.

**`wcvp_distributions` table — all 11 columns:**
- Keep extinct and doubtful records (filter at query time)
- Retain `continent_code_l1`, `region_code_l2` for coarser geographic grouping

**`meta` table:**
- `built_at` timestamp — written by build pipeline, read by app to compare against `wcvp_synced_at`

**Indexes:** `taxon_name` (NOCASE), `genus`, `family`, `accepted_plant_name_id`, `taxon_status`, `plant_name_id` on distributions. Refine once all query patterns are known.

**Build pipeline simplifies to:** download CSVs → dump everything into sqlite → add indexes → push to S3. The Reader module's filtering functions become unnecessary.

### 2. Prod-side state (main DB)

**`host_traits` gets two new fields:**
- `range_confirmed` (boolean, default false) — "an admin is happy with this host's range"
- `wcvp_synced_at` (datetime, nullable) — "when we last pulled WCVP data for this host"

**`host_range` gets `distribution_type`** — native/introduced distinction (matter f6d4, already planned, must land first)

No `source` field on host_range — admin confidence (`range_confirmed`) matters more than provenance.
No `wcvp_match_type` or `wcvp_reviewed` — the wcvp_id link either exists or it doesn't, and `range_confirmed` covers "has a human looked at this."

### 3. Bulk admin page

**Purpose:** Triage and dispatch tool. Not a detail editor. Heavy lifting happens either in bulk (sync/confirm) or in the individual host form.

**Default filter:** Show hosts where `NOT range_confirmed` OR `wcvp_synced_at IS NULL` OR `wcvp_synced_at < wcvp_db.built_at`. All overridable in the UI.

**List view columns:**
- Species name (link to host form)
- Family / Genus
- Range count (number of places)
- WCVP link status (has wcvp_id or not)
- Last synced
- Confirmed (yes/no)

**Filter dimensions:**
- Range status: confirmed / unconfirmed
- WCVP sync status: never synced / stale / current
- Has range data / no range data
- Family, genus, name search
- Has WCVP match / no WCVP match

**Individual host actions:**
- Click through to host edit form for detail work
- No inline diff preview, no WCVP matching/linking on this page

**Bulk actions:**
- Select hosts via checkboxes
- "Sync selected from WCVP" — confirmation dialog: "Update range data for N hosts from WCVP? (M hosts have no WCVP match and will be skipped)" → progress → summary
- "Confirm selected" — mark range_confirmed for selected hosts

**WCVP match computation is lazy** — not pre-computed for the full list. Match status comes from whether `wcvp_id` exists in host_traits.

**Bulk sync is synchronous in the LiveView** — one transaction per host, process via `send(self(), {:sync_next, remaining})`. Updates progress assigns after each host. UI stays responsive. No background job infrastructure needed. If admin navigates away, it stops.

**One transaction per host** — releases the write lock between each host so reads aren't blocked. Each host sync is small/fast. Total wall clock for large batches is seconds, not minutes.

### 4. Host form integration

Existing per-host WCVP features stay. Additional context shown:
- If `range_confirmed` is TRUE:
  - WCVP sync button still available if admin wants to check for updates
  - Last sync timestamp visible; shows "never synced with WCVP" if null
- If `range_confirmed` is FALSE:
  - If `wcvp_synced_at` is null or < WCVP DB timestamp: suggest they could update from WCVP
  - If `wcvp_synced_at` >= WCVP DB timestamp: say nothing, leave up to them
- Admin can always sync regardless of status — we inform, never block

### 5. Reconciliation flow retirement

The current reconcile → JSON reports → ReconciliationLive viewer → apply pipeline is fully replaced by the bulk admin page. Dead code to remove:
- `mix gallformers.wcvp.reconcile`
- `mix gallformers.wcvp.apply`
- `mix gallformers.wcvp.backfill_ids` (superseded by bulk sync)
- `Wcvp.Reporter`
- `Wcvp.Reports`
- `Wcvp.Matcher` (matching moves to SQL queries against enriched wcvp.sqlite)
- `ReconciliationLive`
- `priv/repo/data/reconciliation/` reports directory
- `Wcvp.Reader` — evaluate; may be replaced by simpler sqlite import in build_db

### 6. b9e5 relationship

Leave b9e5 as-is for now. Goal is that the new UI makes it unnecessary. Once the bulk admin page ships and proves out, b9e5 can be closed.

## Sequencing

1. **f6d4** — `distribution_type` on `host_range` (already planned, must land first)
2. **Enriched artifact DB** — rebuild `build_db` to store all CSV data, add `meta` table
3. **Prod-side state migration** — `range_confirmed` and `wcvp_synced_at` on `host_traits`
4. **Host form updates** — show sync status, range_confirmed context
5. **Bulk admin page** — the new page with filters, list, bulk actions
6. **Reconciliation flow removal** — clean up dead code
7. **Close b9e5** if no longer needed

## Related matters

- f6d4 — Gall range region filter (native/introduced on host_range) — prerequisite
- b9e5 — Bulk WCVP range backfill (CLI pipeline) — may be absorbed
- 2dc1 — TDWG L3 mapping precision improvement — improves range quality, independent work
- 7932 — Host plant data sourcing for Central/South America
