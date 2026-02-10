# Refactoring Candidates

> **Purpose**: Working doc tracking files that impose the highest cognitive/context cost.
> Updated: 2026-02-09
>
> **Full analysis**: [plans/2026-02-09-refactoring-candidates-analysis.md](plans/2026-02-09-refactoring-candidates-analysis.md) — raw data, all metrics, problem patterns

## Motivation

When working on core areas (taxonomy, gall admin, etc.), 60-70% of context window is consumed
just reading in relevant files. This signals missing abstractions and modules that own too much.

## Scoring Methodology

Each file is scored on five dimensions:

| Metric | What it measures | Source |
|--------|-----------------|--------|
| **Lines of code** | Raw size / context cost | `wc -l` |
| **Commit frequency** | Churn / how often we touch it | `git log --name-only` |
| **Function count** | Cognitive surface area | `grep -c 'def\|defp'` |
| **Cross-file references** | Coupling / blast radius | `grep -rl ModuleName lib/` |
| **Avg function length** | Per-function complexity | lines / function count |

## Ranked Candidates

### Tier 1: High impact, clear architectural path

| # | File | Lines | Commits | Fns | Refs | Avg Fn | Status |
|---|------|-------|---------|-----|------|--------|--------|
| 1 | `lib/gallformers/taxonomy.ex` | 1996 | 28 | 122 | 21 | 16 | **Not started** |
| 2 | `lib/gallformers_web/live/admin/gall_live/form.ex` | 1884 | 20 | 86 | 0 | 21 | Not started |
| 3 | `lib/gallformers/species.ex` | 845 | 20 | 45 | 40 | 18 | Not started |

### Tier 2: Large and painful, needs design work

| # | File | Lines | Commits | Fns | Refs | Avg Fn | Status |
|---|------|-------|---------|-----|------|--------|--------|
| 4 | `lib/gallformers_web/live/admin/host_live/form.ex` | 1296 | 16 | 53 | 0 | 24 | Not started |
| 5 | `lib/gallformers_web/live/id_live.ex` | 1308 | 14 | 106 | 0 | 12 | Not started |
| 6 | `lib/gallformers_web/components/form_components.ex` | 1267 | 12 | 19 | 3 | 66 | Not started |

### Tier 3: Moderate but coupled

| # | File | Lines | Commits | Fns | Refs | Avg Fn | Status |
|---|------|-------|---------|-----|------|--------|--------|
| 7 | `lib/gallformers_web/live/admin/images_live.ex` | 1424 | 19 | 36 | 0 | 39 | Not started |
| 8 | `lib/gallformers_web/live/admin/form_helpers.ex` | 601 | 8 | 46 | 11 | 13 | Not started |

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

## Completed Refactors

_(none yet)_
