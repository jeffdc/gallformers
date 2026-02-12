# Mutation Testing Report

**Date**: 2026-02-12
**Branch**: reclassify-taxa
**Test database**: Copy of production (`priv/gallformers.sqlite`)

## Summary

**13 mutations tested, 13 detected. No test gaps found.**

All mutations across invariant tests, write operation tests, and E2E tests were
successfully caught. The test suite is robust against the classes of bugs tested.

### Baseline Failures (pre-existing in production data)

3 invariant tests fail on the current production database. These are real data
issues, not test bugs:

| Test | Issue |
|------|-------|
| no species has a section link without also having a genus link | 194 species (all Quercus) have section links but no genus link |
| every gall family has exactly one Unknown genus | Santalaceae (gall) is missing its Unknown genus |
| no alias record exists without at least one alias_species link | 2 orphaned aliases: "Bud Gall Wasp (unisexual generation)", "Fake plastic tree" |

## Part A: Invariant Test Mutations (Database Corruption)

Tests: `test/prod_data/invariants_test.exs`

| Mutation | Description | New Failures | Tests That Caught It |
|----------|-------------|:---:|----------------------|
| A1 | Delete one species_taxonomy row | 2 | "every species has at least one row in species_taxonomy", "every species has exactly one genus link" |
| A2 | Insert orphaned species_taxonomy (999999, 999999) | 1 | "every species_taxonomy row points to a valid species_id and taxonomy_id" |
| A3 | Delete one gall_traits row | 1 | "every gall species has exactly one gall_traits row" |
| A4 | Set one genus parent_id = id (self-reference) | 2 | "no taxonomy record has parent_id pointing to itself", "every genus has a parent_id pointing to a family" |
| A5 | Add two former_undescribed aliases to one species | 1 | "no species has more than one alias of type former_undescribed" |

## Part B: Write Test Mutations (Code Changes)

Tests: `test/prod_data/write_operations_test.exs` (15 tests, 0 baseline failures)

| Mutation | Description | New Failures | Tests That Caught It |
|----------|-------------|:---:|----------------------|
| B1 | Skip `rename_for_genus_change` call in `reassign_species_taxonomy` | 3 | "reclassify gall to different existing genus in same family" (alias assertion), "reclassify gall to genus in different family" (alias assertion), "reclassify undescribed gall from Unknown genus to real genus" (alias assertion) |
| B2 | Replace `SpeciesLink.update_species_genus` with `:ok` no-op | 6 | "reclassify gall to different existing genus in same family" (genus link), "reclassify gall to genus in different family" (genus link), "reclassify described gall TO Unknown genus" (genus link), "reclassify species that has a section link" (section cleanup), "reclassify with invalid species_id" (error type changed), "reclassify undescribed gall from Unknown genus to real genus" (genus link) |
| B3 | Remove `"section"` from type filter in `update_species_genus` | 2 | "reclassify species that has a section link removes section" (section count), "species with genus AND section links removes both old links" (section count) |
| B4 | Skip `force_undescribed_if_placeholder` call | 1 | "reclassify described gall TO Unknown genus" (undescribed flag) |
| B5 | Skip species rename loop in `update_genus_with_species_sync` | 2 | "rename a genus with species cascades to all species" (name prefix), "genus rename alias type is scientific" (alias existence) |
| B6 | Skip `delete_species_for_cascade` in genus cascade delete | 2 | "cascade delete genus" (FK constraint error), "get_deletion_impact matches actual deletions" (FK constraint error) |

### B6 Note

B6 failures manifested as `Ecto.ConstraintError` (FK violation trying to delete
the genus while species still reference it) rather than assertion failures on
species counts. The mutation is still detected, but the failure mode is
incidental rather than intentional. The tests would benefit from an explicit
"species are deleted" assertion before the genus deletion step, though the
current behavior is sufficient since the FK constraint makes the operation fail
regardless.

## Part C: E2E Test Mutations (Browser Tests)

Tests: `test/prod_data/e2e/` (19 tests, 0 baseline failures)

| Mutation | Description | New Failures | Tests That Caught It |
|----------|-------------|:---:|----------------------|
| C1 (=B1) | Skip `rename_for_genus_change` | 3 | "reclassify gall to different genus in same family changes genus and creates alias" (alias count), "reclassify gall to genus in different family changes family and genus, creates alias" (alias count), "reclassify host to different genus changes host genus and creates alias" (alias count) |
| C2 (=B5) | Skip species rename in genus rename cascade | 1 | "renaming a genus cascades to species names and creates aliases" (name prefix) |

## Test Gaps

**None found.** All 13 mutations were detected by at least one test.

## Cross-Layer Coverage

The mutations tested at multiple layers show good defense-in-depth:

| Mutation | Write Tests | E2E Tests | Both Detect? |
|----------|:-----------:|:---------:|:------------:|
| B1/C1 (skip alias creation) | 3 failures | 3 failures | Yes |
| B5/C2 (skip genus rename cascade) | 2 failures | 1 failure | Yes |

## Observations

1. **Strong alias coverage**: Both B1 and C1 show alias creation is well-tested
   at both the context and browser layers.

2. **B2 has highest detection rate** (6 failures): Skipping the genus link update
   breaks nearly every reclassification test, confirming it's the critical
   step in the reclassification pipeline.

3. **B4 is narrowly targeted**: Only one test catches the missing undescribed
   enforcement, which is correct since it's a niche invariant (only applies
   when moving to an Unknown genus).

4. **B6 caught by FK constraints**: The cascade delete tests catch the mutation
   via database constraints rather than explicit assertions. This is adequate
   but less informative for debugging.

5. **Pre-existing data issues**: The 3 baseline invariant failures represent
   real data quality issues that should be addressed separately (Quercus section
   links without genus links, missing Santalaceae Unknown genus, orphaned aliases).
