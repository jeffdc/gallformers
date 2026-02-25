# Admin Reconciliation UI — Design

**Date**: 2026-02-20
**Status**: Approved
**Matter**: 7932 (Host plant data sourcing)

## Goal

Surface WCVP reconciliation reports in the admin UI. Phase 1 is read-only visibility; phase 2 (future) adds triage workflows.

## Architecture

**Data source**: Read JSON report files directly from `priv/repo/data/reconciliation/YYYY-MM-DD/`. No database tables needed for phase 1.

**Backend**: A context module (`Gallformers.Wcvp.Reports`) that:
- Lists available runs (date-stamped directories)
- Parses JSON files into structs
- Returns summary counts without loading full reports

## Components

### Dashboard Card

Add a "WCVP Reconciliation" card to the existing admin dashboard showing:
- Last run date (most recent directory)
- One-line summary: "2,106 matched · 186 mismatches · 227 unmatched · 1,717 range updates"
- Link to `/admin/reconciliation`

### Dedicated Page (`/admin/reconciliation`)

**Run selector** — dropdown of available date-stamped runs.

**Summary cards** — one per report type with count and description.

**Report sections** — expandable, each rendered as a searchable/sortable table:

| Report | Columns | Notes |
|--------|---------|-------|
| Taxonomy mismatches (186) | GF name, WCVP accepted name, mismatch_type, detail | Grouped by type |
| Not in WCVP (227) | GF name, family, genus, closest match | Full table |
| Range updates (1,717) | GF name, current count, new places count, expandable detail | Full table |
| US/CA not in GF (17,406) | WCVP name, family, distribution | Paginated |
| Hemisphere not in GF (343K) | Count + download link only | Too large for table |

**Download links** — raw JSON for each report.

## Phase 2 (Future)

Import report data into database tables to enable:
- Marking items as reviewed/skipped/applied
- Tracking triage progress across sessions
- Filtering by action status
