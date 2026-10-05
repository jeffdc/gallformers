---
status: raw
created: 2026-10-03
updated: 2026-10-04
epic: taxonomy
relates: [1121, b5bd, e381]
---

# Taxonomy and gall systems — design and plan (owned taxonomy)

The chosen direction (2026-10-04): **Gallformers owns its taxonomy**, with every taxonomic Fact sourced, built as a separate system from the gall system and delivered in phases. This matter holds the **software design and plan**. What the domain's words mean — Gall, Observation, Source, Fact, Relationship, Traits, gall-entry boundaries — is defined in [`docs/domain/domain-model.md`](../../docs/domain/domain-model.md), which this matter defers to. Related: migration `b5bd`, import interface `e381`. The rejected iNat-mirror direction is matter `1121` (dropped, kept for history).

## Decision

Adam and Jeff (2026-10-03/04): taxonomic Facts need Source attribution like gall Facts (authorship, naming, placement, splits, lumps). The curation burden exists whether the work goes into iNat or Gallformers; handling it internally keeps it under our control and open to LLM tooling. Cost: roughly double the effort, so it's phased — ship the gall system first on today's taxonomy, then rebuild taxonomy.

## Architecture

- **Taxonomy system:** taxa, names, authorship, rank, placement, synonymy, taxonomic acts and their history.
- **Gall system:** Galls (entries), Traits, Relationships, ranges, gall aliases.
- **Shared:** Sources and Fact attribution, history, audit, import.
- **Contract:** stable taxon IDs, referenceable at any rank. Nothing else crosses.

Both systems are black boxes behind internal APIs (Phoenix contexts; `boundary` can enforce it). Four qualifications:

1. **Sources–Facts and audit are shared building blocks, not peers** — designed before the systems that use them.
2. **Hot cross-boundary reads use published read models** (the ID tool walking taxon ancestry, search across Inducer names), never the other system's tables.
3. **Some writes span boundaries** (an import creating a taxon and linking a Gall to it), so context APIs must compose into one transaction (e.g. `Ecto.Multi`).
4. **The migration isn't isolated:** today's `species` table is both Galls and taxa.

## Design rules

1. **Plants:** Gallformers is not an authority on plants. Plant taxa start from POWO and live in the same taxonomy structure; curators can adjust them, **editorially** (audit log, no Facts) — including host ranges.
2. **Taxon origin:** *curated* (gall formers and associates, including the rare gall-forming plant) or *POWO-imported* (plants).
3. **Isolation:** taxonomy knows nothing about Galls; the gall system knows taxa only by ID and through the taxonomy API; the UI may hide the separation.
4. **IDs:** each system owns its IDs; cross-system references are typed. Galls keep their species IDs (`/gall/:id`), plant taxa keep theirs (`/host/:id`); Inducer and higher taxa get new IDs from the taxonomy sequence, starting above today's highest species ID.
5. **Taxonomic Facts** on curated taxa (name, authorship, rank, placement, synonymy) are sourced — to the literature, or to **Gallformers** for its own positions. A Fact with one current value (placement, current name) has one **accepted** value chosen by a curator; others stay as reported alternatives. Taxonomic acts (rename, move, merge, split) are sourced and keep history.
6. **Change events:** taxonomy announces each act; the gall system reacts. Rename/move: derived Gall names update and the old name becomes a gall alias; overrides and name collisions go to a curator. Merge: links re-point. Split: a curator picks each linked Gall's successor.
7. **Sources–Facts layer** serves both systems: multi-valued Facts (many Hosts) and single-valued Facts with an accepted value. **Gallformers is a Source** (author "Gallformers Contributors"), cited per Gall page as today (`/gall/587?source=58`), with per-Fact links possible later. Observations are never Sources; they are cited inside a Source's statement. **Attribution** (whose authority) is separate from **audit** (who changed it); audit is agnostic to meaning.
8. **Relationships** are owned by the gall system (every Relationship involves a Gall; taxon-to-taxon ones always happen in a Gall). Meanings are in the domain doc. Design: types and qualifiers are a **system-level fixed list** (changed only by a database update, never by curators), each with direction, inverse label, and endpoint kinds. Hyperparasitism is derived, not stored. Alternate generations are explicit; the system flags mismatches (same species-level Inducer, different generations, no link; or a link between Galls whose Inducers differ).
9. **Gall names** are derived (Inducer plus qualifiers as needed for uniqueness: generation, Host, form), overridable, and unique.
10. **Ranges:** theoretical range = union of all Hosts' distributions (POWO/WCVP or curator-adjusted), genus-level Hosts included as today; the ID tool uses it. Observed range = **observational data** (Research Grade iNat Observations shown directly) plus any range Facts from Sources.
11. **Import** follows `e381`. Facts from a Source aren't curated after import; a curator who disagrees adds a Fact attributed to **Gallformers** (and can withdraw the wrong one). Re-import replaces a Source's Facts. Withdrawn Facts stay visible with reason and Source.

## What Relationships need from the taxonomy API

| Need | Taxonomy API |
|---|---|
| Endpoint taxon exists and is active | exists / active |
| "Host of" needs a plant; Inducers generally aren't plants | kingdom / group |
| Competing Inducer candidates map to the shared higher taxon | common ancestor |
| "All Galls induced by anything in genus X" | ancestry / descendants (read model) |
| Derived Gall names | current names |
| Merges and splits re-point endpoints | change events |

## Phases

1. **Gall system, on today's taxonomy.** Split Galls from species; Relationships and Sources–Facts; a **taxon identity layer** (one stable taxon ID per existing `species` row and `taxonomy` node, wrapping today's tables) so Galls can link to any rank. Build shared parts generically. Ship.
2. **Taxonomy system,** rebuilt behind the same IDs: sourced names, authorship, placement, taxonomic acts with history, POWO import. No gall changes.

## Work ordering

| Step | What |
|---|---|
| 0a | ✅ Coupling inventory (below). |
| 0b | **Sources–Facts spike:** a multi-valued gall Fact, a single-valued taxonomic Fact with an accepted value, a withdrawal, a taxon-to-taxon Relationship in a Gall, evidence locators (`e381`), and scale. |
| 0c | **Relationship-type review**, then derive the taxonomy API from the table above. |
| 1 | **Taxonomy API facade** over today's tables + taxon identity layer + ancestry read model; route existing code through it. |
| 2 | **Sources–Facts and audit,** built from 0b. |
| 3 | **Import schema** (`e381`), validated with hand-made batches — gives the pipeline workstream a fixed target. |
| 4 | **Gall system:** split from species; Traits and Relationships as Facts; ranges; read models for ID tool, search, pages, API (migration: `b5bd`). |
| 5 | **Migration rehearsal, backscan, release** (release is sequenced with the backscan). |
| 6 | **Phase 2:** taxonomy rebuilt behind the same API. |

## Step 0a findings (2026-10-04)

Script: `docs/plans/coupling_inventory.py` (local). **The taxonomy facade is small; the gall split is the big job.**

- 75 of 271 `lib/` files touch the species/taxonomy core (31 in the web layer).
- **Species is the hub:** 8 contexts depend on it; its schema is referenced by 30 files outside its context. Registered cycles (`dirty_xrefs`): Species ↔ Taxonomy, Species ↔ Galls; web has 19 references to internal modules.
- Every context declares a `boundary` but with `exports: :all`, so nothing enforces black boxes. Switching a context to explicit exports makes the compiler list every violation — an exact work list (not yet run; needs a throwaway branch).
- **Taxonomy facade ≈ 10–15 files:** 5 query `species_taxonomy` directly, 4 use the `Taxonomy` schema, `sitemap_controller.ex` has 4 raw queries.
- **Gall split ≈ 40+ files:** 38 branch on `taxoncode`, plus 30 outside references to the `species` schema (overlapping).
- Web layer is mostly clean: raw SQL only in `sitemap_controller.ex`; coupling is at the struct level (`Image`, `SpeciesSource`, `Species`).

## Open questions

- **Rename handling:** (A) derived names update automatically, curator only for overrides/collisions; or (B) every rename reviewed first. Leaning A.
- **Scope of the curated taxonomy:** all Gall Community members (Inducers, Inquilines, Parasitoids, …) or a narrower set?
- **Traits that vary by Host:** open in the domain doc (leaning no); needs a definitive answer.

## Outside scope

- **Plant taxonomy as a field of work** — see rule 1.
- **Relationships not tied to a Gall.**
- **Owning Observations** — Gallformers references and cites them; linking Observations to each other is iNat's business.
- **A phylogeny view** — Gallformers' editorial opinion of how phylogeny is shaping up may be shown someday, possibly outside the app; durable taxon and Gall IDs keep the door open.

Earlier design-draft material (concept diagram, 28-rule list): snapshot `docs/plans/domain-model-v1-2026-10-04.md` (local). Redraw the design diagram from the domain model when design resumes.
