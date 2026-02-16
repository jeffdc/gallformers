---
status: planned
created: 2026-02-14
updated: 2026-02-16
relates: [5b3d]
title: Separate undescribed status from data completeness (gallformers code)
docket: true
---

# Gallformers code as separate data field

Decouple the gallformers code from the species name — make it a standalone editable field on the gall admin page.

## Display Rules
- Code present + undescribed → show current undescribed blurb (code display, copy button, iNat link)
- Code present + NOT undescribed → show formerly-undescribed blurb (as today)
- No code → nothing special displayed

## Naming
- Undescribed species can have any valid name (no longer tied to the code format)
- Keep the 'name undescribed' flow as-is, but pre-populate the gallformers code field with the specific epithet (editable)

## Cleanup
- Eliminates the special 'formerly-undescribed' alias hack

## Taxonomy Placeholders (unchanged)
- Keep 'Unknown' family and 'Unknown (<family>)' genera — used for taxonomy assignment

## Validation: described status
A gall cannot be marked as described (unchecked) if:
- It is assigned to any Unknown genus
- It has no source attached (ideally one that describes the species)

## Feasibility Analysis (2026-02-14)

### Current State
- Gallformers code is NOT stored — computed on-the-fly from species name epithet
- compute_gallformers_code/3 in gall_live.ex derives it at render time
- former_undescribed alias preserves old name for code derivation after reclassification

### Change Surface
- **Migration**: Add gallformers_code to gall_traits + backfill from existing names/aliases
- **Schema/Context**: gall_traits schema, Galls context (2-3 files)
- **Admin Form**: form.ex (add field), undescribed.ex (pre-populate)
- **Public Display**: gall_live.ex (read from DB, new display conditions)
- **Alias Cleanup**: Remove former_undescribed type from reclassification.ex, species.ex, migration
- **Tests**: ~4 test files need updates

### Assessment: Medium scope, well-contained, very feasible
- Riskiest part: data migration backfill
- Most changes are simplification (stored field replaces computed derivation)
- Alias cleanup is a win — former_undescribed was a workaround

## Plan Docs
- docs/plans/2026-02-15-undescribed-completeness-separation-design.md
- docs/plans/2026-02-15-undescribed-completeness-separation-plan.md

Design doc: docs/plans/2026-02-15-undescribed-completeness-separation-design.md\nImplementation plan: docs/plans/2026-02-15-undescribed-completeness-separation-plan.md\nTriage doc: docs/plans/Triaging the state of Gall species data.md
