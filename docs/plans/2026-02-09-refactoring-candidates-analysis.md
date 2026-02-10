# Refactoring Candidates: Full Codebase Analysis

> **Date**: 2026-02-09
> **Purpose**: Initial codebase-wide analysis identifying refactoring candidates by impact score.
> This is the raw data behind `docs/refactoring-candidates.md`.

## Motivation

When working on core areas (taxonomy, gall admin, etc.), 60-70% of context window is consumed
just reading in relevant files. This signals missing abstractions and modules that own too much.

## Scoring Methodology

Five dimensions measured per file:

| Metric | What it measures | How measured |
|--------|-----------------|-------------|
| **Lines of code** | Raw size / context cost | `wc -l` |
| **Commit frequency** | Churn / how often we touch it | `git log --name-only` (all time) |
| **Function count** | Cognitive surface area | `grep -c 'def\|defp'` |
| **Cross-file references** | Coupling / blast radius | `grep -rl ModuleName lib/` |
| **Avg function length** | Per-function complexity | lines / function count |

## Raw Data: Lines of Code (top 40)

```
1996 lib/gallformers/taxonomy.ex
1884 lib/gallformers_web/live/admin/gall_live/form.ex
1424 lib/gallformers_web/live/admin/images_live.ex
1308 lib/gallformers_web/live/id_live.ex
1296 lib/gallformers_web/live/admin/host_live/form.ex
1267 lib/gallformers_web/components/form_components.ex
1110 lib/gallformers_web/live/admin/image_audit_live.ex
1075 lib/gallformers_web/live/admin/article_live/form.ex
 983 lib/gallformers_web/components/data_display_components.ex
 861 lib/gallformers_web/components/core_components.ex
 845 lib/gallformers_web/live/gall_live.ex
 845 lib/gallformers/species.ex
 782 lib/gallformers_web/live/host_live.ex
 767 lib/gallformers_web/components/ui_components.ex
 747 lib/gallformers/galls.ex
 725 lib/mix/tasks/gallformers/update_prod_db.ex
 689 lib/gallformers_web/components/layouts.ex
 666 lib/gallformers_web/live/admin/gall_host_live.ex
 601 lib/gallformers_web/live/admin/form_helpers.ex
 561 lib/gallformers_web/live/admin/species_source_live/add_from_source.ex
 558 lib/gallformers/search.ex
 555 lib/gallformers_web/live/admin/taxonomy_live/index.ex
 509 lib/gallformers/galls/identification.ex
 497 lib/gallformers/sources.ex
 485 lib/gallformers_web/live/admin/gall_live/undescribed.ex
 460 lib/gallformers/plants.ex
 458 lib/gallformers/images.ex
 446 lib/gallformers_web/live/admin/species_source_live/quick_find.ex
 429 lib/gallformers_web/live/search_live.ex
 419 lib/mix/tasks/smoke_test.ex
 381 lib/gallformers_web/live/admin/section_live/form.ex
 378 lib/gallformers_web/schemas/api_schemas.ex
 369 lib/gallformers/storage.ex
 359 lib/gallformers/ranges.ex
 351 lib/gallformers_web/live/admin/taxonomy_live/form.ex
 346 lib/gallformers_web/live/about_live.ex
 338 lib/gallformers_web/live/home_live.ex
 312 lib/gallformers_web/live/analytics_live.ex
 312 lib/gallformers/analytics.ex
```

## Raw Data: Commit Frequency (top 30)

```
28 lib/gallformers/taxonomy.ex
25 lib/gallformers_web/live/gall_live.ex
20 lib/gallformers_web/live/admin/gall_live/form.ex
20 lib/gallformers/species.ex
19 lib/gallformers_web/live/admin/images_live.ex
16 lib/gallformers_web/live/host_live.ex
16 lib/gallformers_web/live/admin/host_live/form.ex
15 lib/gallformers_web/router.ex
15 lib/gallformers/images.ex
14 lib/gallformers_web/live/id_live.ex
14 lib/gallformers_web/live/home_live.ex
12 lib/gallformers_web/live/admin/dashboard_live.ex
12 lib/gallformers_web/live/about_live.ex
12 lib/gallformers_web/components/form_components.ex
12 lib/gallformers/hosts.ex
 9 lib/gallformers_web/live/admin/taxonomy_live/form.ex
 8 lib/gallformers_web/live/admin/taxonomy_live/index.ex
 8 lib/gallformers_web/live/admin/form_helpers.ex
 8 lib/gallformers_web/controllers/api/gall_controller.ex
 8 lib/gallformers/search.ex
 7 lib/gallformers_web/live/genus_live.ex
 7 lib/gallformers_web/live/admin/source_live/form.ex
 7 lib/gallformers_web/live/admin/article_live/form.ex
 7 lib/gallformers_web/components/layouts.ex
 7 lib/gallformers_web/components/core_components.ex
 7 lib/gallformers/id_tool.ex
 7 lib/gallformers/analytics.ex
 6 lib/gallformers_web/live/search_live.ex
 6 lib/gallformers_web/components/data_display_components.ex
 6 lib/gallformers/sources/source.ex
```

## Raw Data: Function Count (top 30)

```
122 lib/gallformers/taxonomy.ex
106 lib/gallformers_web/live/id_live.ex
 86 lib/gallformers_web/live/admin/gall_live/form.ex
 66 lib/gallformers/galls/identification.ex
 55 lib/gallformers_web/live/admin/article_live/form.ex
 53 lib/gallformers_web/live/admin/host_live/form.ex
 46 lib/gallformers_web/live/admin/form_helpers.ex
 45 lib/gallformers/species.ex
 44 lib/gallformers/filter_fields.ex
 42 lib/gallformers_web/live/explore_live.ex
 41 lib/gallformers/galls.ex
 40 lib/gallformers_web/live/admin/image_audit_live.ex
 38 lib/mix/tasks/smoke_test.ex
 38 lib/gallformers/sources.ex
 36 lib/gallformers_web/live/admin/images_live.ex
 33 lib/gallformers_web/live/search_live.ex
 33 lib/gallformers_web/live/gall_live.ex
 33 lib/gallformers/galls/summary.ex
 32 lib/gallformers_web/live/host_live.ex
 32 lib/gallformers_web/live/admin/taxonomy_live/form.ex
 32 lib/gallformers/storage.ex
 31 lib/gallformers_web/live/admin/gall_live/undescribed.ex
 30 lib/mix/tasks/gallformers/update_prod_db.ex
 30 lib/gallformers/images.ex
 28 lib/gallformers_web/live/admin/taxonomy_live/index.ex
 28 lib/gallformers_web/components/core_components.ex
 27 lib/gallformers/plants.ex
 26 lib/gallformers/search.ex
 26 lib/gallformers/articles.ex
 24 lib/mix/tasks/audit/schema_fields.ex
```

## Raw Data: Cross-File References (key modules)

```
 40 lib/gallformers/species.ex (Gallformers.Species)
 21 lib/gallformers/taxonomy.ex (Gallformers.Taxonomy)
 18 lib/gallformers/images.ex (Gallformers.Images)
 13 lib/gallformers/plants.ex (Gallformers.Plants)
 11 lib/gallformers_web/live/admin/form_helpers.ex (GallformersWeb.Admin.FormHelpers)
 11 lib/gallformers/galls.ex (Gallformers.Galls)
  3 lib/gallformers_web/components/form_components.ex (GallformersWeb.FormComponents)
  0 lib/gallformers_web/live/id_live.ex (GallformersWeb.IDLive)
  0 lib/gallformers_web/live/admin/images_live.ex (GallformersWeb.Admin.ImagesLive)
  0 lib/gallformers_web/live/admin/host_live/form.ex (GallformersWeb.Admin.HostLive.Form)
  0 lib/gallformers_web/live/admin/gall_live/form.ex (GallformersWeb.Admin.GallLive.Form)
```

## Raw Data: Average Function Length (key files)

```
66 avg lines/fn (19 fns, 1267 lines) lib/gallformers_web/components/form_components.ex
24 avg lines/fn (53 fns, 1296 lines) lib/gallformers_web/live/admin/host_live/form.ex
21 avg lines/fn (86 fns, 1884 lines) lib/gallformers_web/live/admin/gall_live/form.ex
18 avg lines/fn (45 fns,  845 lines) lib/gallformers/species.ex
18 avg lines/fn (41 fns,  747 lines) lib/gallformers/galls.ex
16 avg lines/fn (122 fns, 1996 lines) lib/gallformers/taxonomy.ex
13 avg lines/fn (46 fns,  601 lines) lib/gallformers_web/live/admin/form_helpers.ex
12 avg lines/fn (106 fns, 1308 lines) lib/gallformers_web/live/id_live.ex
```

## Ranked Candidates

### Tier 1: High impact, clear architectural path

| # | File | Lines | Commits | Fns | Refs | Avg Fn | Why it hurts |
|---|------|-------|---------|-----|------|--------|--------------|
| 1 | `taxonomy.ex` | 1996 | 28 | 122 | 21 | 16 | Largest file, most commits, most functions. Owns too much — tree ops, reclassification, species cascades, search helpers |
| 2 | `admin/gall_live/form.ex` | 1884 | 20 | 86 | 0 | 21 | Second largest. Complex admin form with trait editing, host management, undescribed gall logic all in one LiveView |
| 3 | `species.ex` | 845 | 20 | 45 | 40 | 18 | **Highest coupling** (40 refs). Touched as often as gall form. Every context depends on it |

### Tier 2: Large and painful, needs design work

| # | File | Lines | Commits | Fns | Refs | Avg Fn | Why it hurts |
|---|------|-------|---------|-----|------|--------|--------------|
| 4 | `admin/host_live/form.ex` | 1296 | 16 | 53 | 0 | 24 | **Highest avg fn length** among LiveViews. Large admin form, similar structure to gall form |
| 5 | `id_live.ex` | 1308 | 14 | 106 | 0 | 12 | 106 functions in a single LiveView — massive event handler surface |
| 6 | `form_components.ex` | 1267 | 12 | 19 | 3 | 66 | Only 19 functions but averaging 66 lines each — massive component functions |

### Tier 3: Moderate but coupled

| # | File | Lines | Commits | Fns | Refs | Avg Fn | Why it hurts |
|---|------|-------|---------|-----|------|--------|--------------|
| 7 | `admin/images_live.ex` | 1424 | 19 | 36 | 0 | 39 | Large + high churn. Image management UI |
| 8 | `admin/form_helpers.ex` | 601 | 8 | 46 | 11 | 13 | Moderate size but **11 refs** — shared form utilities that many admin LiveViews depend on |

## Problem Patterns

### 1. God Modules
`taxonomy.ex` (1996 lines, 122 fns) owns tree operations, reclassification, species cascades,
and search helpers. Per architecture plan: taxonomy should only own the tree and delegate
species cascades to owning contexts (Galls, Plants).

### 2. Monolithic LiveViews
`gall_live/form.ex`, `host_live/form.ex`, `id_live.ex` combine rendering, event handling,
data loading, and business logic in one module. Can extract into:
- Component modules (render + local events)
- Helper modules (data loading, transformation)
- Context functions (business logic currently inline)

### 3. Hub Coupling
`species.ex` has 40 cross-file references — everything depends on it. The planned architecture
(Species as thin shared module, Galls/Plants as peer contexts) would distribute this.

## Context Cost Analysis

A typical "edit gall admin" task loads:
- `gall_live/form.ex` — 1884 lines
- `taxonomy.ex` — 1996 lines
- `species.ex` — 845 lines
- `form_helpers.ex` — 601 lines
- `form_components.ex` — 1267 lines
- **Total: ~6,600 lines** before touching any peripheral files

Target: reduce per-task context to ~2,000-3,000 lines by extracting focused modules.

---

## Deep-Dive Analysis Prompt

Use this prompt to analyze the next candidate from the ranked list above. Copy and give to
an agent, replacing `TARGET_FILE` with the file path.

```
# Refactoring Deep-Dive: TARGET_FILE

You are analyzing a refactoring candidate for the Gallformers project (Phoenix/Ecto/SQLite).

## Context

Read these files first:
- `CLAUDE.md` — project conventions, Ecto patterns, component rules
- `docs/plans/2026-02-09-refactoring-candidates-analysis.md` — codebase-wide scoring data
- `docs/plans/2026-02-09-taxonomy-refactor-analysis.md` — example of the output format we want

The taxonomy analysis is the gold standard for what we expect. Match its depth and structure.

## Your Task

Produce a complete analysis of `TARGET_FILE` covering these four areas:

### 1. Function Inventory

Read the file and categorize every public function (`def`) into responsibility groups.
Name the groups based on what you find — don't force-fit taxonomy's categories.

For each group, create a table with:
- Function name and arity
- Line numbers
- Whether it touches tables/schemas outside its own domain (coupling smell)
- Where it's called from (web layer, other contexts, or both)

To find callers, search for:
- `alias <ModuleName>` then `ModuleName.function_name` calls
- Direct fully-qualified calls
- Any imports from the module

### 2. Dependency Map

Trace both directions:
- **Outbound**: What does this module import/alias/call into?
- **Inbound**: What other modules call into this one? Group by layer (context, admin LiveView,
  public LiveView, controller, mix task).
- **Heaviest consumers**: Which 2-3 files call the most functions from this module?

### 3. Ecto Practices Audit

Check for these specific anti-patterns (see CLAUDE.md "Ecto & Query Patterns"):
- **Maps vs structs**: Functions using `select: %{id: t.id, ...}` instead of returning schema structs
- **Unused associations**: Schema defines `has_many`/`belongs_to`/`many_to_many` but context
  uses raw joins on string table names instead
- **N+1 queries**: `Enum.map(items, &get_thing/1)` or sequential `get_parent` calls
- **Raw SQL where Ecto would work**: Manual `fragment()` or `Repo.query()` that could use
  schema associations or standard Ecto
- **Presentation in context**: Functions returning `{name, id}` tuples or formatted strings
  that are purely for UI consumption

For each issue found, note the line numbers and what the fix would be.

If the file is a LiveView (not a context module), adapt this section:
- Instead of Ecto patterns, audit for: business logic that belongs in a context,
  data loading that could be preloads, inline queries that bypass context APIs,
  event handlers that are doing too much work.

### 4. Test Coverage

Read the corresponding test file(s) and note:
- Which functions/behaviors have tests?
- Which are untested?
- Are tests organized by responsibility group?
- Any test quality concerns (e.g., tests that test implementation rather than behavior)?

### 5. Consolidation Opportunities

Identify:
- Functions that are near-duplicates (same query, different return shape or filter)
- Functions that could be merged with an options parameter
- Functions that don't belong in this module at all (wrong context boundary)
- Dead code (defined but never called externally)

## Output Format

Write your analysis to: `docs/plans/2026-02-09-TARGET_NAME-refactor-analysis.md`
where TARGET_NAME is the short module name (e.g., `gall-form`, `species`, `host-form`).

Use the same markdown table format as the taxonomy analysis. Be specific — line numbers,
function names, caller file paths. This document will be loaded by a different agent session
that writes the refactoring plan, so it must stand alone.

Do NOT write a refactoring plan or propose solutions. Just document what exists.
```
