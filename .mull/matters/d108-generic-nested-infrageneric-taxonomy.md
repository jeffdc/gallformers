---
status: planned
created: 2026-08-12
updated: 2026-08-12
epic: taxonomy
blocks: [2cb2]
---

# Generic nested infrageneric taxonomy

## Goal

Replace the Section-specific layer below Genus with an arbitrary-depth, single-lineage infrageneric taxonomy. Support an ordered rank catalog initially containing Subgenus, Section, Subsection, Series, Subseries, and Complex. Preserve the current Family-to-Genus hierarchy while making rank metadata and recursive tree operations reusable for a later higher-order normalization.

## Decisions

- Use one canonical lineage, following the iNaturalist-style parent tree. A species has exactly one immediate taxonomic placement; overlapping non-taxonomic groupings are out of scope and would be a separate association concept.
- Keep `taxonomy` as the node table. Convert `type = section` to `type = infrageneric`, with `rank` from a centralized ordered catalog.
- Add nullable `species.taxonomic_parent_id` referencing a genus or infrageneric node. Unclassified species may remain null.
- Remove `species_taxonomy` after all reads and writes move to the direct parent. Do not leave compatibility fields, aliases, or duplicate domain implementations.
- Keep upper types (`family`, `intermediate`, `genus`) in this phase. Higher-order ranks such as Order and Class are explicitly deferred.
- Future-proof the work through a central rank catalog and generic ancestry, descendant, movement, validation, and counting operations. A later project can normalize the upper hierarchy without revisiting species placement.

## Hierarchy and invariants

Allowed edges are family at root; above-genus intermediate under family or a broader intermediate; genus under family or intermediate; infrageneric under genus or a broader infrageneric node. Infrageneric rank level must be strictly finer than its parent. Reject self-parenting, cycles, invalid node classes, and moves that violate rank ordering. Keep non-placeholder `(name, parent_id)` uniqueness.

`Lineage` becomes `{family, intermediates, genus, infragenerics}` with both lists ordered root-to-leaf. There is no permanent `section` field; callers find nodes by rank when necessary.

## Migration

1. Add nullable `species.taxonomic_parent_id`.
2. Abort with affected IDs unless legacy data has at most one genus and one section per species, each section has a genus parent, and linked section/genus ancestry agrees.
3. Convert Sections to infrageneric nodes with rank Section.
4. Backfill the species parent to its linked Section when present, otherwise its linked Genus; preserve null for unclassified species.
5. Add FK and index, cut all application reads/writes over, then drop `species_taxonomy`.

The migration must not silently choose among malformed legacy links.

## Core behavior

- Derive a species lineage recursively from its direct parent.
- Creation and reclassification update one parent FK.
- Moving an infrageneric node moves its entire node/species subtree.
- Descendant species counts use recursive node traversal and count direct species placements without duplication.
- Deleting an infrageneric node collapses it upward atomically: reparent child nodes and directly attached species to its parent, then delete. Reject collapse if new edges violate rank order.
- Family and genus cascade deletion remain destructive but discover all descendants generically.

## Application surfaces

- Taxonomy admin supports generic infrageneric nodes, rank selection, valid parent selection, and reparenting selected child nodes/species during creation.
- Replace the Section membership page with a generic infrageneric species manager.
- Replace the host form Section dropdown with a lineage-aware taxonomic placement picker. Direct placement under Genus remains valid.
- Use a generic public LiveView with canonical ID-plus-slug rank URLs such as `/section/123-lobatae` and `/complex/456-quercus-rubra`.
- Preserve old name-only Section URLs as redirects when uniquely resolvable; ambiguous names must not resolve arbitrarily.
- Search and sitemap become rank-aware.
- Add generic `/api/v2/infragenerics` and `/api/v2/infragenerics/:id` endpoints. Retain Section-filtered API paths for one documented deprecation window, backed by the generic implementation.
- Formatting is rank-aware. The scientific-name portion of Complex labels is italicized while the rank label remains roman.

## Delivery stages

1. Central rank catalog, edge/cycle validation, and generic recursive queries.
2. Database migration and legacy-data preflight.
3. Core lineage, placement, movement, count, deletion, and reclassification cutover.
4. Admin, public pages, URLs, search, and sitemap.
5. Generic API, temporary Section API compatibility, removal of obsolete Section code, and junction-table cleanup.

## Acceptance criteria

- Arbitrarily deep Genus-to-Species paths resolve root-to-leaf.
- Invalid rank edges and cycles are rejected.
- Migration maps Section-linked, Genus-only, and unclassified species correctly and aborts malformed legacy data.
- Classified species have exactly one immediate placement.
- Moving a node preserves its full subtree; collapsing it reparents child nodes and direct species atomically.
- Recursive counts include species at every depth without duplicates.
- Existing Section URLs redirect and canonical rank URLs resolve.
- Generic and Section compatibility APIs agree for Section records.
- Production-data invariants validate one coherent lineage per classified species.
- Smoke scenario succeeds through create, browse, move, reclassify, collapse, public page, and API for `Family → Genus → Section → Complex → Species`.

## Deferred

Higher-order taxa above Family. The intended later direction is a fully rank-driven taxon tree, but no Order/Class/etc. schema, UI, route, or migration is included here.
