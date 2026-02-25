---
status: planned
effort: 1-2 days
created: 2026-02-13
updated: 2026-02-25
epic: cynipid
docs: ['']
---

# Generation field for gall traits

Design doc: docs/plans/2026-02-06-generation-field-design.md

## Background

Many cynipid wasp galls are labeled with `(agamic)` or `(sexgen)` in their species names — describing alternation of generations where a single wasp species produces two morphologically different galls in alternating sexual and asexual generations. Currently encoded only as name text, not queryable or filterable.

## Already done

- Search ranking: "agamic"/"sexgen" queries show glossary definitions first
- Glossary tooltips on gall pages for parenthetical generation terms

## Implementation

Add `generation` column to `gall_traits`:

```sql
generation TEXT CHECK (generation IN ('agamic', 'sexual'))
```

- `'agamic'` — asexual generation
- `'sexual'` — sexual generation
- `NULL` — unknown/not applicable

Auto-populate from existing name suffixes: `(agamic)` → agamic, `(sexgen)`/`(sexual)` → sexual. Species names unchanged.

### What this enables

1. ID tool filter for generation (like existing Detachable filter)
2. Structured display on gall detail pages
3. Queryable, auditable data

### Data landscape

| Metric | Count |
|--------|-------|
| Total Cynipidae galls | 1,352 |
| Tagged with generation | 871 |
| Cynipidae without generation tag | 481 |
| Paired (both generations known) | 73 species (146 rows) |
| Unpaired agamic-only | 545 |
| Unpaired sexual-only | 180 |

All 871 generation-tagged galls are Cynipidae. No other family currently uses this terminology.

## Open questions (need community input)

- **Seasonal generations** (22 entries, mostly Cecidomyiidae): spring/summer/autumn — same field or separate?
- **Host-specific forms** (12 entries, mostly Aphididae): on-malus/on-ulmus — different concept, maybe link to host instead
- **Plant-part variants** (7 entries, all Asphondylia): bud/leaf snap — could use existing plant part in gall_traits
- **Other/unique** (9 entries): inquilines, rust stages, pathovars — likely leave as-is

Full design doc: docs/plans/2026-02-06-generation-field-design.md


---

## Full Design Document

# Generation Field Design: Structured Data for Alternation of Generations

**Date:** 2026-02-06
**Status:** Seeking community input
**GitHub Issues:** [#278](https://github.com/jeffdc/gallformers/issues/278), [#373](https://github.com/jeffdc/gallformers/issues/373)

## Background

Many cynipid wasp galls on gallformers.org are labeled with `(agamic)` or `(sexgen)` in their species names. These terms describe **alternation of generations** — a lifecycle where a single wasp species produces two morphologically different galls in alternating sexual and asexual generations. The agamic (asexual) generation produces a gall that looks different from the sexual generation's gall, often on different parts of the host plant.

Until now, this information has been encoded only as text appended to species names (e.g., *Callirhytis furva (agamic)*). This means:

- There's no way to filter by generation in the ID tool
- Users encountering these terms for the first time have no easy way to learn what they mean
- The data can't be queried or analyzed programmatically

## What We've Already Done

**Search ranking improvement:** Searching for "agamic" or "sexgen" now shows the glossary definitions at the top of results, rather than buried under hundreds of species entries.

**Glossary tooltips:** When `(agamic)` or `(sexgen)` appears in a species name on a gall page, it now renders as a hoverable tooltip showing the glossary definition. This gives users immediate context without navigating away.

These changes address issue [#373](https://github.com/jeffdc/gallformers/issues/373).

## Proposed: Structured Generation Field

To address issue [#278](https://github.com/jeffdc/gallformers/issues/278), we propose adding a `generation` column to the `gall_traits` table:

```sql
generation TEXT CHECK (generation IN ('agamic', 'sexual'))
```

- **`'agamic'`** — asexual generation
- **`'sexual'`** — sexual generation (currently labeled "sexgen" in names)
- **`NULL`** — unknown, not applicable, or not yet determined

### What this enables

1. **ID tool filter:** A new "Generation" filter lets users narrow results to agamic or sexual galls, just like the existing Detachable filter.

2. **Gall detail pages:** Generation is displayed as a proper field (e.g., "Generation: Agamic") alongside other gall characteristics.

3. **Data quality:** Generation becomes queryable, auditable structured data instead of text parsing.

### Data model: keeping separate rows

Each generation of a species remains as its own row in the database. *Callirhytis furva (agamic)* and *Callirhytis furva (sexgen)* stay as two separate species entries, each with their own gall traits, images, host associations, and other data. This is the right model because each generation produces a physically distinct gall — different shape, texture, location, seasonality — and the whole point of the site is identifying those distinct galls.

The existing "Related Galls" feature on gall pages already links the two generations of the same species together via name-prefix matching.

### Migration plan

The `generation` field would be auto-populated from existing name suffixes:
- `(agamic)` → `'agamic'`
- `(sexgen)` or `(sexual)` → `'sexual'`
- Everything else → `NULL`

Species names would **not** be changed — the parenthetical suffix stays in the name. Removing it is possible in the future but not necessary for this change to be useful.

### Data landscape

| Metric | Count |
|--------|-------|
| Total Cynipidae galls | 1,352 |
| Tagged with generation | 871 |
| Cynipidae without generation tag | 481 |
| Species with both generations known (paired) | 73 (146 rows) |
| Unpaired agamic-only | 545 |
| Unpaired sexual-only | 180 |

All 871 generation-tagged galls are in family **Cynipidae**. No other family currently uses the agamic/sexual terminology.

## Open Questions: Broader Parenthetical Patterns

Beyond the 871 cynipid generation entries, there are **50 other gall species** that use parenthetical suffixes in their names for different disambiguation purposes. As we formalize the generation field, we'd like community input on whether and how to handle these other patterns.

### Is the generation field Cynipidae-only?

Alternation of generations is the defining lifecycle of cynipid gall wasps, and all current agamic/sexual data is within Cynipidae. Should this field be restricted to Cynipidae, or could it be useful for other families? If other families have generation concepts, what terms would be appropriate?

### Seasonal generations (22 entries)

These are non-cynipid species (mostly Cecidomyiidae) where the same species produces different galls in different seasons. This is a related concept — one species, multiple gall forms — but the distinction is seasonal timing rather than reproductive mode.

| Species | Family | Suffixes |
|---------|--------|----------|
| *Asphondylia eupatorii* | Cecidomyiidae | (spring generation), (summer generation) |
| *Asphondylia imbricata* | Cecidomyiidae | (spring generation), (summer and autumn generation) |
| *Asphondylia monacha* | Cecidomyiidae | (spring generation), (summer generation) |
| *Asphondylia ovata* | Cecidomyiidae | (spring generation), (summer generation) |
| *Asphondylia pumila* | Cecidomyiidae | (spring generation), (summer generation) |
| *Asphondylia ratibidae* | Cecidomyiidae | (autumn generation), (summer generation) |
| *Asphondylia rudbeckiaeconspicua* | Cecidomyiidae | (spring generation), (summer generation) |
| *Asphondylia thompsonae* | Cecidomyiidae | (spring generation), (summer generation) |
| *Rhopalomyia capitata* | Cecidomyiidae | (spring generation), (summer generation) |
| *Rhopalomyia solidaginis* | Cecidomyiidae | (spring generation), (summer and autumn generations) |
| *Procecidochares atra* | Tephritidae | (spring generation), (summer and autumn generations) |

**Question:** Should seasonal generations be captured in the same `generation` field (expanding the allowed values), tracked in a separate field, or left as-is for now?

### Host-specific forms (12 entries)

Species that produce galls on different host plants, with each host producing a distinct gall form. Common in aphids with host-alternating lifecycles.

| Species | Family | Suffixes |
|---------|--------|----------|
| *Eriosoma lanigerum* | Aphididae | (on-malus), (on-ulmus) |
| *Hamamelistes spinosus* | Aphididae | (on-betula), (on-hamamelis) |
| *Hormaphis cornu* | Aphididae | (on-betula), (on-hamamelis) |
| *Prociphilus caryae* | Aphididae | (on-amelanchier) |
| *Contarinia partheniicola* | Cecidomyiidae | (on Ambrosia), (on Parthenium incanum) |
| *Eriophyes cerasicrumena* | Eriophyidae | (on-p-americana), (on-p-serotina) |
| *Gymnosporangium sabinae* | Pucciniaceae | (on Pyrus) |
| *Phytoplasma pruni* | Acheloplasmataceae | (on Trillium) |

**Question:** These are a fundamentally different concept from generation — they distinguish which host the gall appears on, not which generation of the organism produced it. Should host-specific forms eventually become structured data? If so, this might be better served by linking the species entry to its specific host rather than a generic field.

### Plant-part variants (7 entries)

Same species producing different galls on different parts of the host plant. All are *Asphondylia* (Cecidomyiidae).

| Species | Family | Suffixes |
|---------|--------|----------|
| *Asphondylia pseudorosa* | Cecidomyiidae | (bud), (leaf snap), (capitulum) |
| *Asphondylia rosulata* | Cecidomyiidae | (bud), (leaf snap) |
| *Asphondylia solidaginis* | Cecidomyiidae | (bud), (leaf snap) |

**Question:** Plant parts are already a filterable dimension in the ID tool. Could these entries simply have their plant part captured in gall_traits rather than in the species name? Or is there something more nuanced going on here?

### Other / unique cases (9 entries)

These don't fit neatly into any category:

| Species | Family | Suffix | What it might mean |
|---------|--------|--------|-------------------|
| *Tanaostigmodes howardii* | Tanaostigmatidae | (detachable bud), (integral stem) | Two gall forms distinguished by attachment and plant part |
| *Andricus notholithocarpi* | Cynipidae | (midrib gall) | Only one entry, no pair — may be disambiguating from another *A. notholithocarpi* gall |
| *Periclistus pirata* | Cynipidae | (altering Diplolepis gall) | Inquiline (lives inside another species' gall and modifies it) |
| *Unknown-cynipidae q-alba-* | Cynipidae | (deforming-pisiformis) | Unclear/legacy naming convention |
| *Cronartium quercuum* | Cronartiaceae | (telial) | Rust fungus life stage (telial = spore-producing stage) |
| *Phylloxera caryaesepta* | Phylloxeridae | (perforans) | Named variant or form |
| *Pseudomonas savastanoi* | Pseudomonadaceae | (pv nerii) | Bacterial pathovar (subspecies-level classification) |

**Question:** These seem to each have their own story. Are any of these worth formalizing, or are they one-off naming conventions that are best left as-is?

## Summary

The immediate plan is to add a structured `generation` field for cynipid agamic/sexual data and surface it in the ID tool and gall pages. The broader question — whether and how to structure the other 50 parenthetical entries — is what we'd like input on before making further changes.
