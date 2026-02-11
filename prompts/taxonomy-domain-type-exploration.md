# Exploration: Taxonomy Domain Type

## Context

The gallformers codebase has a missing abstraction at the heart of its taxonomy system. The current code constructs, deconstructs, and passes around plain maps representing the "Family → Section (optional) → Genus" hierarchy in at least 6 different shapes across 12+ locations. This proliferation is a classic symptom of an unmodeled domain type — exactly the problem described in CLAUDE.md Principle #6:

> "A species name isn't a string — it has internal structure. When a domain concept has structure, model it as a struct/type."

The `TaxonName` module already solved this for species names. Now we need to do the same for the taxonomy lineage itself.

## The Problem in Detail

### What exists today

The core taxonomy data is always some combination of:
```
family (name + id) → section (name + id, optional) → genus (name + id)
```

But this is represented as **bare maps** in at least these shapes:

| Shape | Keys | Where Used |
|-------|------|------------|
| Core FSG | `genus, genus_id, section, section_id, family, family_id` | Tree, SpeciesLink, Forms |
| New genus | Same + `genus_is_new: true`, IDs are nil | Form init for new species |
| Disambiguation | `requires_disambiguation: true, possible_families: [...]` | Multi-family genus lookup |
| Resolution wrapper | `taxonomy: map, genus_is_new: bool, family_id, section_id, possible_families` | Bridge between lookup and form state |
| Batch minimal | `genus, family` (names only, no IDs) | Bulk query optimization |
| Reclassify adapter | `%{id: id}` or `%{id: id, name: name}` | Reshaping for ReclassifyLive component |

### Where the maps are constructed

1. **`Tree.build_taxonomy_from_genus/1`** — 3-way pattern match on parent type (nil/section/family), preloads parent chain
2. **`SpeciesLink.build_taxonomy_map/2`** — Same 3-way pattern match, but from join query results (avoids extra preload)
3. **`SpeciesLink.lookup_taxonomy_for_new_species/1`** — Constructs partial maps for new/ambiguous genera
4. **`SpeciesLink.resolve_taxonomy_for_species/2`** — Wraps lookup result in a normalized container
5. **`ReclassifyHelpers`** — Ad-hoc reconstruction when resolving genus disambiguation in forms

### Where the maps are consumed

- Both admin forms (`gall_live/form.ex`, `host_live/form.ex`) — via `taxonomy && taxonomy.genus_id` nil-guarded access
- `taxonomy_genus_family_row` component — expects `:taxonomy` map attr with `:genus` and `:family` keys
- `genus_disambiguation_modal` component — expects `:possible_families` list of maps
- `ReclassifyLive` component — receives genus/family as separate `%{id:, name:}` maps
- `Galls.compute_undescribed_lock/2` — accesses `taxonomy.genus`
- `Galls.has_unknown_genus?/1` — accesses `taxonomy.genus`

### Concrete pain points

1. **Duplicated construction logic** — The 3-way parent pattern match (nil/section/family) is implemented twice (`Tree` and `SpeciesLink`), producing the same map shape via different data paths.
2. **Nil-safety boilerplate** — Forms use `taxonomy && taxonomy.field` everywhere because the map can be nil.
3. **No validation** — Nothing prevents constructing a map with `family: "Cynipidae"` but `family_id: nil`, or other incoherent states.
4. **Shape ambiguity** — Is `taxonomy.genus` a display name like `"Unknown (Cynipidae)"` or a raw name like `"Unknown"`? Depends on which construction path was used.
5. **Adapter functions** — `ReclassifyHelpers` exists largely to reshape one map format into another.

## Historical Context

The V1 app (TypeScript/Next.js) had an `FSG` type (Family-Section-Genus) that bundled this data with behavior. The name was poor but the concept was right: taxonomy lineage is a first-class domain concept that deserves a type with:
- Defined structure (what fields exist and their types)
- Construction guarantees (can't build an incoherent one)
- Behavior (display name, is_placeholder?, has_section?, etc.)

## Your Task

Explore the design space for a proper taxonomy lineage type. This is a **design exploration**, not an implementation task. The goal is a concrete proposal that can be reviewed and refined before any code is written.

### Questions to Investigate

1. **What should this type be called?** `TaxonomyLineage`? `TaxonLineage`? `Lineage`? Something else? It represents the path from family down to genus for a single species.

2. **Should it be a struct or a set of related structs?** One struct with optional section fields, or a struct that contains optional nested structs?

3. **How does it relate to the existing `Taxonomy` schema?** The `Taxonomy` schema represents a single node (one family, one genus, one section). The new type represents a *path* through the tree. Should it wrap `Taxonomy` structs or hold extracted data?

4. **What about the "new genus" and "disambiguation" states?** These are currently represented as variant maps. Should they be:
   - Separate types entirely?
   - States within the lineage type (e.g., `%Lineage{genus_id: nil, genus_is_new: true}`)?
   - A tagged union / sum type pattern?

5. **Where should construction live?** Currently `Tree` and `SpeciesLink` both build the map. With a struct, there should be one canonical constructor. Which module owns it?

6. **What behavior should the type carry?** Candidates:
   - `display_genus/1` — returns "Unknown (Family)" or just genus name
   - `has_section?/1`
   - `placeholder_genus?/1`
   - `to_map/1` — for backward compat during migration
   - `from_genus/1` — constructor from a Taxonomy genus record

7. **What's the migration path?** We can't change everything at once. How do we introduce this type incrementally without breaking existing code?

### What to Examine

Read these files to understand the current state:
- `lib/gallformers/taxonomy/tree.ex` — `build_taxonomy_from_genus/1` (lines 263-302)
- `lib/gallformers/taxonomy/species_link.ex` — `build_taxonomy_map/2` (lines 182-215), `lookup_taxonomy_for_new_species/1` (lines 229-285), `resolve_taxonomy_for_species/2` (lines 295-330)
- `lib/gallformers_web/live/admin/reclassify_helpers.ex` — adapter functions
- `lib/gallformers_web/live/admin/gall_live/form.ex` — how taxonomy assigns are used
- `lib/gallformers_web/live/admin/host_live/form.ex` — same
- `lib/gallformers_web/components/form_components.ex` — `taxonomy_genus_family_row` and `genus_disambiguation_modal`
- `lib/gallformers/taxonomy/taxon_name.ex` — reference for how a domain type was done well in this project

Also read CLAUDE.md for architectural principles (especially #6 and #7) and CODING_STANDARDS.md for patterns.

### Deliverable

A design document covering:
1. **Proposed type(s)** — struct definition(s) with typespecs
2. **Constructor functions** — how instances are created from different data sources
3. **Behavior functions** — what the type can do
4. **Where it lives** — module placement within the taxonomy context
5. **Migration strategy** — how to introduce it incrementally
6. **Trade-offs** — what gets simpler, what gets more complex, any risks
7. **Relationship to TaxonName** — these two types together model the full "identity" of a species in the taxonomy tree

Do NOT write implementation code. Write a design proposal with example signatures and usage patterns.
