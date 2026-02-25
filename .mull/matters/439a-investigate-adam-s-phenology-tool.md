---
status: raw
effort: 1-2 days
created: 2026-02-14
updated: 2026-02-25
epic: cynipid
docs: ['']
relates: [85c0]
---

# Investigate Adam's phenology tool

GitHub: https://github.com/Megachile/Phenology

Goals:
- Get it primed for use with Claude Code (CLAUDE.md, documentation, etc.)
- Understand what it does and how it works
- Evaluate the codebase quality and architecture
- Propose a path forward: fold into gallformers codebase vs. integrate at some level

## Product exploration (2026-02-16)

Phenology data is one dimension of a larger cynipid product vision for Gallformers. iNat observations serve as a foundational data layer feeding three dimensions: phenology timing, fine-grained range, and abundance signal. Combined with existing host associations and future adult anatomy data, this enables:

1. Enriched species profiles — location-aware, temporally-aware pages
2. Collection/field planning — when and where to find target species
3. Field trip optimization — what's active near me on a given date
4. Improved gall-first ID — phenology as a filter to narrow candidates
5. New organism-first ID pathway — adult anatomy (via keys) + phenology + host narrows to species without seeing a gall

Keys play a dual role: navigation for users AND structured anatomy data source. Building adult cynipid keys and building the anatomy dataset are the same effort.

Scope is cynipid-only for now. Patterns could extend to other groups later.

Design doc: docs/plans/2026-02-16-cynipid-phenology-product-vision.md

## Product Vision

Gallformers evolves from a static reference into a location-aware, temporally-aware species resource for cynipid gall wasps. Users can plan field work, understand what's active near them, and — as anatomy data matures — identify adult wasps without seeing a gall.

### Data Foundations

A single foundational data layer — iNaturalist observations — feeds multiple product dimensions:

| Dimension | What it provides | Status |
|-----------|-----------------|--------|
| Phenology | When each species/generation/phenophase is active at a given latitude | Available (Phenology tool) |
| Fine-grained range | Actual occurrence points, not broad geographic labels | Available (iNat observations) |
| Abundance signal | Observation density as a proxy for commonality in an area | Available (iNat observations) |
| Host associations | Which plants a species is found on | Available (Gallformers core data) |
| Adult anatomy | Structured morphological traits of adult wasps | Future — see Keys connection |

### Use Cases

1. **Enriched species profiles** — Activity windows by phenophase/generation at user's latitude, occurrence map, seasonal context
2. **Collection and field planning** — Predicted date ranges for rearing-viable galls at a given latitude
3. **Field trip optimization** — All species with predicted activity overlapping user's date and location
4. **Gall-first ID (improved)** — Phenology as additional filter in existing ID workflow, weighting candidates by plausible activity
5. **Organism-first ID (new)** — Identify adult cynipid without seeing its gall, combining phenology + host + adult anatomy. Each dimension alone is broad, but intersection can be razor sharp (e.g., wingless adult on Q. garryana in February = one species)

### Keys as dual-role

Keys serve as both navigation (walk user through couplets) and data source (couplets encode structured anatomy data). Building adult cynipid keys and building the anatomy dataset are the same effort.

### Scope

Cynipid-only. Generation alternation creates distinct phenological patterns, phenology dataset exists, adult ID is a real unmet need (many unidentified iNat observations of wasps). Patterns could extend to other groups later.

### Open Questions

- **Data boundary**: Where does Adam's curation/modeling end and Gallformers' consumption begin?
- **Update cadence**: Real-time vs periodic sync affects architecture significantly
- **Abundance methodology**: Raw observation counts are noisy — what normalization needed?
- **Anatomy data collection**: Manual from literature, iNat photos, expert contribution, or combination?
- **Geographic scope**: Phenology tool has best coverage in North America — interaction with hemisphere expansion?


---

## Full Vision Document

# Cynipid Phenology & iNat Integration — Product Vision

## Problem

Gallformers today is a reference database: it tells you what a gall looks like, what species makes it, and what host it grows on. This is valuable but static. Users who want to *find* galls — researchers planning collection trips, people trying to rear wasps, naturalists hunting rare species — get no help with the questions "when?" and "where, specifically?"

Meanwhile, a separate phenology tool (Adam Kranz's Phenology project) already answers "when will species X be active at latitude Y?" for cynipid gall wasps, using iNaturalist observations normalized by a Season Index metric. But it lives outside Gallformers with no integration beyond a link.

## Vision

For cynipid gall wasps, Gallformers evolves from a static reference into a location-aware, temporally-aware species resource. Users can plan field work, understand what's active near them right now, and — as anatomy data matures — identify adult wasps without ever seeing a gall.

## Data Foundations

A single foundational data layer — **iNaturalist observations** — feeds multiple product dimensions:

| Dimension | What it provides | Status |
|-----------|-----------------|--------|
| **Phenology** | When each species/generation/phenophase is active at a given latitude | Available (Phenology tool) |
| **Fine-grained range** | Actual occurrence points, not broad geographic labels | Available (iNat observations) |
| **Abundance signal** | Observation density as a proxy for commonality in an area | Available (iNat observations) |
| **Host associations** | Which plants a species is found on | Available (Gallformers core data) |
| **Adult anatomy** | Structured morphological traits of adult wasps | Future — see Keys connection below |

## Use Cases

### 1. Enriched species profiles

Species pages gain temporal and geographic depth. Instead of just "this species exists and looks like this," a cynipid profile shows:

- Predicted activity windows by phenophase and generation at the user's latitude
- Where it has actually been observed (map of occurrence points)
- How common or rare it is in different areas
- Seasonal context: "right now, this species is likely in the dormant phase at your location"

### 2. Collection and field planning

For researchers and rearers who go out *looking* for specific species:

- "When should I go to collect *Andricus quercuscalifornicus* for rearing in Michigan?" — predicted date range for rearing-viable galls at that latitude
- "What's the current phenophase of species X where I am?" — so you know what to expect in the field

### 3. Field trip optimization

Flipping the direction — starting from a time and place rather than a target species:

- "I'm going out this Saturday near Portland. What cynipid species should be active?" — all species with predicted activity overlapping the user's date and location
- "What else might I find while I'm looking for species X on these oaks?" — serendipity planning

### 4. Gall-first identification (existing pathway, improved)

Phenology as an additional filter in the existing ID workflow. When a user is trying to identify a gall, the system can weight candidates by whether they are plausibly active at the user's time and location. This doesn't replace morphological ID — it sharpens it.

### 5. Organism-first identification (new pathway)

A fundamentally new capability: identifying an adult cynipid wasp without seeing its gall. This combines:

- **Phenology** narrows the time window — what species are active now, here
- **Host association** narrows the plant — what's associated with this oak species
- **Adult anatomy** narrows the organism — wingless/winged, body color, size, etc.

Each dimension alone is broad, but the intersection can be razor sharp. Example: "a wingless adult wasp on *Quercus garryana* in February" points to one and only one species.

### Keys as both navigation and data source

Identification keys are central to the organism-first pathway. They serve a dual role:

- **Navigation**: Keys walk a user through structured decisions (couplets) to reach an identification. Combined with phenology and host filters to pre-narrow the candidate set, keys become the interface for organism-first ID.
- **Data source**: The couplets in an adult cynipid key *are* the structured anatomy data. "Is the wasp wingless or winged?" encodes a trait. Building the keys and building the anatomy dataset are the same effort.

This means the existing keys feature work has a direct line to enabling organism-first identification. The keys infrastructure is already being built.

## Scope

This vision is **cynipid-scoped**. Cynipid gall wasps are special in several ways that make this feasible:

- Generation alternation (sexual/agamic) creates distinct, predictable phenological patterns
- The phenology dataset already exists with meaningful coverage
- Adult identification is a real unmet need (many iNat observations of unidentified wasps)

The patterns established here — iNat data integration, phenology modeling, keys-as-structured-data — could extend to other gall-former groups later, but that is not in scope.

## Open Questions

- **Data boundary**: Where does Adam's curation/modeling workflow end and Gallformers' consumption begin? This depends on how the phenology tool evolves and how Adam works. Not yet decided.
- **Update cadence**: How frequently does Gallformers need refreshed phenology/iNat data? Real-time vs. periodic sync affects architecture significantly.
- **Abundance methodology**: Raw observation counts are a noisy abundance proxy. What normalization (if any) is needed to be useful rather than misleading?
- **Anatomy data collection**: How will adult anatomy traits be gathered initially? Manual entry from literature, extraction from iNat photos, expert contribution, or some combination?
- **Geographic scope**: The phenology tool currently has best coverage in North America. How does this interact with the Western Hemisphere expansion plans?
