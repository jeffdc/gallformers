---
status: planned
created: 2026-02-18
updated: 2026-02-25
epic: platform
docs: ['']
relates: [9ad7]
---

# Codebase refactoring analysis

Detailed codebase analysis identifying refactoring candidates by impact score. Covers function inventories, dependency maps, Ecto/LiveView audits, test coverage gaps, and cross-form duplication analysis.

> Analysis performed 2026-02-09. Line counts and function counts may have drifted. Re-run scoring before beginning work.

## Scoring Methodology

Five dimensions: lines of code, commit frequency, function count, cross-file references, avg function length.

## Ranked Candidates

### Tier 1: High impact, clear architectural path

| # | File | Lines | Fns | Refs | Why it hurts |
|---|------|-------|-----|------|--------------|
| 1 | `taxonomy.ex` | 1996 | 122 | 21 | Largest file, most commits/functions. Owns tree ops, reclassification, species cascades, search helpers. Should only own the tree. |
| 2 | `admin/gall_live/form.ex` | 1884 | 86 | 0 | Complex admin form with traits, hosts, undescribed logic all in one LiveView. |
| 3 | `species.ex` | 845 | 45 | 40 | Highest coupling (40 refs). Everything depends on it. |

### Tier 2: Large and painful, needs design work

| # | File | Lines | Fns | Refs | Why it hurts |
|---|------|-------|-----|------|--------------|
| 4 | `admin/host_live/form.ex` | 1296 | 53 | 0 | Highest avg fn length among LiveViews. |
| 5 | `id_live.ex` | 1308 | 106 | 0 | 106 functions in a single LiveView. |
| 6 | `form_components.ex` | 1267 | 19 | 3 | 19 functions averaging 66 lines each. |

### Tier 3: Moderate but coupled

| # | File | Lines | Fns | Refs | Why it hurts |
|---|------|-------|-----|------|--------------|
| 7 | `admin/images_live.ex` | 1424 | 36 | 0 | Large + high churn. |
| 8 | `admin/form_helpers.ex` | 601 | 46 | 11 | 11 refs — shared form utilities. |

## Context Cost Analysis

A typical "edit gall admin" task loads ~6,600 lines (gall form + taxonomy + species + form_helpers + form_components). Target: ~2,000-3,000 lines.

## Problem Patterns

1. **God Modules** — taxonomy.ex owns too much. Should only own tree, delegate species cascades to Galls/Plants.
2. **Monolithic LiveViews** — gall/host/id forms combine rendering, events, data loading, and business logic.
3. **Hub Coupling** — species.ex has 40 cross-file references. Planned peer contexts (Galls/Plants) would distribute this.

## Gall Form Deep Dive

11 function groups, 47 public functions, 39 event handlers. Key issues:
- **State init duplication**: 4 functions set ~30 overlapping assigns (~200 lines of near-duplicates)
- **Reclassify modal**: 313 lines (16% of file), 16 functions — self-contained feature that should be a LiveComponent
- **Transaction orchestration**: save_gall/3 runs Repo.transaction with 6+ context calls — belongs in Galls context
- **Business logic leakage**: resolve_taxonomy_for_gall, compute_undescribed_lock, save_filter_changes all belong in contexts
- **Inline search filter**: searches all species then filters to galls in LiveView instead of using existing taxoncode parameter

Untested: create flow, save (both new/edit), delete, reclassify happy path, alias add/remove. 29 tests total, none verify data persistence.

## Host Form Deep Dive

33 public functions, 27 event handlers. Same structural problems as gall form plus:
- No PubSub subscription (gall form has it, host form doesn't)
- maybe_update_section is business logic in LiveView
- Invalid host ID crashes instead of graceful redirect (unlike gall form)

39 tests total. Same gaps: save, delete, reclassify happy path all untested.

## Cross-Form Duplication: ~716 lines duplicated between gall and host forms

| Pattern | Gall Lines | Host Lines | After Extract |
|---------|-----------|-----------|---------------|
| Reclassify modal | ~313 | ~273 | ~100 (LiveComponent) |
| Alias management | ~45 | ~45 | ~45 (shared module) |
| Taxonomy resolution | ~52 | ~52 | ~55 (context fn) |
| Genus disambiguation modal | ~38 | ~39 | ~40 (component) |
| Genus/Family row template | ~45 | ~46 | ~46 (component) |
| State init duplication | ~200 | ~150 | ~50 each |
| Save alias changes | ~9 | ~11 | ~12 (context fn) |

Net reduction estimate: ~1,000 lines removed (combined ~3,180 → ~2,180), shared infra ~350 lines.

## Species Context Deep Dive

27 public functions, 18 private. Highest coupling in codebase (40 refs).

**Ecto issues**: 8 functions return maps instead of structs. 5 of 10 schema associations never used as preloads. "alias_species" junction table string appears in 7 queries (association exists but unused). FTS5 raw SQL is justified.

**Functions that don't belong**: get_images_for_species → Images context. enrich_with_common_names_and_counts → presentation helper. sanitize_fts_query → Search context.

**Gall-specific logic in Species**: delete_species hardcodes Galls.delete_gall_traits call. enrich splits by taxoncode.

**Search consolidation**: 3 search entry points (search_species, search_species_by_name, search_species_like) could unify into one with opts.

**Dead code candidates**: list_species/0 (only test), get_abundance/1 (only test), search_species_like/2 (no external callers).

## Species Domain Type (Exploratory)

Early-stage exploration of modeling Species as a proper domain type. Three options considered: protocol, two separate structs with shared functions, or shared embedded struct. Not ready for implementation. Depends on Lineage work. Key question: how much shared structure between Gall and Plant warrants a formal type?

## Deep-Dive Prompt Template

A prompt template for analyzing additional candidates exists — ask if needed for the next file to analyze.
