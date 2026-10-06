---
status: raw
created: 2026-10-03
updated: 2026-10-05
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

Both systems are black boxes behind internal APIs (Phoenix contexts; `boundary` must enforce it). Four qualifications:

1. **Sources–Facts and audit are shared building blocks, not peers** — designed before the systems that use them.
2. **Hot cross-boundary reads use published read models** (the ID tool walking taxon ancestry, search across Inducer names), never the other system's tables.
3. **Some writes span boundaries** (an import creating a taxon and linking a Gall to it), so context APIs must compose into one transaction (e.g. `Ecto.Multi`).
4. **The migration isn't isolated:** today's `species` table is both Galls and taxa.

## Design rules

1. **Plants:** Gallformers is not an authority on plants. Plant taxa start from POWO and live in the same taxonomy structure; curators can adjust them, **editorially** (audit log, no Facts) — including host ranges.
2. **Taxon origin:** *curated* (gall formers and associates, including the rare gall-forming plant) or *POWO-imported* (plants).
3. **Isolation:** taxonomy knows nothing about Galls; the gall system knows taxa only by ID and through the taxonomy API; the UI may hide the separation.
4. **IDs:** each system owns its IDs; cross-system references are typed. Galls keep their species IDs (`/gall/:id`), plant taxa keep theirs (`/host/:id`); Inducer and higher taxa get new IDs from the taxonomy sequence, starting above today's highest species ID.
5. **Taxonomic Facts** on curated taxa (name, authorship, rank, placement, synonymy) are sourced — to the literature, or to **Gallformers** for its own positions. Which value is current follows the **recency rule** (see *Sources–Facts design*); Gallformers overrides with a newer statement of its own. Taxonomic acts (rename, move, merge, split) are sourced and keep history.
6. **Change events — synchronous, with the dependency inverted** (decided 2026-10-05). Taxonomy defines a "taxon changed" interface and calls registered listeners **inside its own transaction**; the gall system registers as a listener through application wiring, so taxonomy's code never references it and the boundary rule holds. Reactions: rename/move updates derived Gall names and keeps the old name as a gall alias; merge re-points links; split creates curator tasks. **If the gall side can't accept a change (e.g. a name collision), the taxonomy change fails** — errors surface immediately and get real resolution, rather than leaving the other system violating its own constraints. Only expensive derived work (search indexing, read-model refresh) runs async, where staleness is harmless. Rationale: there are ways other than loose async coupling to protect a boundary; at Gallformers' scale even bulk changes are fast; async would add idempotency, ordering, and staleness bugs for no real benefit.
7. **Sources–Facts layer** serves both systems, as designed below. **Gallformers is a Source** (author "Gallformers Contributors"), cited per Gall page as today (`/gall/587?source=58`), with per-Fact links possible later. Observations are never Sources; they are cited inside a Source's statement. **Attribution** (whose authority) is separate from **audit** (who changed it); audit is agnostic to meaning.
8. **Relationships** are owned by the gall system (every Relationship involves a Gall; taxon-to-taxon ones always happen in a Gall). Meanings are in the domain doc. Design: types and qualifiers are a **system-level fixed list** (changed only by a database update, never by curators), each with direction, inverse label, and endpoint kinds. Hyperparasitism is derived, not stored. Alternate generations are explicit; the system flags mismatches (same species-level Inducer, different generations, no link; or a link between Galls whose Inducers differ).
9. **Gall names** are derived (Inducer plus qualifiers as needed for uniqueness: generation, Host, form), overridable, and unique.
10. **Ranges — leave as much alone as possible** (Jeff, 2026-10-05). **Potential range** = union of all Hosts' ranges (POWO/WCVP or curator-adjusted), genus-level Hosts included as today — computed, not stored, inherited through Host Facts. Adjustments are Facts: **range inclusion / exclusion** (Gall + place), stated by Sources or by Gallformers (a curator removing a region = an exclusion attributed to Gallformers). The ID tool uses the potential range with adjustments applied — effectively what it uses today. Only the adjustments are stored, which removes the bloat of today's stored gall range (mostly copies of the host union). **Observed range** (Research Grade iNat observational data) is future.
11. **Import** follows `e381`. Facts from a Source aren't curated after import; a curator who disagrees adds a **Gallformers** statement (confirming or denying). Re-import replaces a Source's attributions.
12. **Pipeline artifacts are the primary admin interface** (Jeff, 2026-10-05). Data gets in and gets fixed through trusted pipeline batches, not hand-edited forms; screens exist only where unavoidable — taxonomy, batch approve/deny (with unresolved references), and retraction. Curator corrections can follow the same path: a curator writes plain notes, an LLM turns them into a batch attributed to the Gallformers Source, and it is validated and approved like any other. Consequence: the pipeline becomes a critical system, and the quality of its output must be earned, measured, and maintained.

## Sources–Facts design (0b, 2026-10-05)

1. **A Fact stands on its own.** Sources attach to it with a **stance**: confirm or deny. One statement from two Sources is one Fact with two attributions.
2. **Recency rule:** a Fact's standing is set by the **most recently authored** Source with a stance on it — never import order. For single-valued Facts (placement, current name, detachable, …) the newest confirmed value is current; there is no curator "accepted" marker. Curators override with a newer Gallformers statement. Same-date conflicts go to a curator.
3. **Corrections and later revisions** are newer Sources. **A retraction** is a status on the original Source ("retracted, per notice X, date") that cancels all its stances; the Source stays visible, marked. Expressions of concern are display-only.
4. **Standings:** *Current* (shown) · *Withdrawn* — newest stance denies (shown, marked) · *Superseded* — a newer value replaced it (shown as history) · *Retracted* — its support was retracted (shown, marked) · *Unsupported* — re-import dropped it (hidden; audit keeps it).
5. **Storage:** a central `facts` table (ID, kind, precomputed standing); each system owns typed detail tables keyed by Fact ID; attributions reference the Fact ID with a real foreign key. Hot reads use the stored standing.
6. **Identity:** each kind has a natural key (Host = Gall + host taxon; Trait = Gall + Trait + value; Range adjustment = Gall + place + include/exclude; Placement = taxon + parent). **Relationship qualifiers are separate Facts** about the Relationship, independently sourced.
7. **An attribution carries:** stance; locator (required for imported literature); optional short quote; **structured cited Observations** (provider + ID); **statement text** (required for Gallformers). The authorship date comes from the Source (Sources need one — today only `pubyear` exists; each Gallformers statement is its own dated entry). Who made the entry is audit.

**Scale (Fermi, checked against the production copy):** ~4×10³ Galls × ~90 Facts each ≈ 3.6×10⁵ Facts; × ~1.5–2 Sources per Fact ≈ 6–7×10⁵ attributions; taxonomic Facts add ~2–3×10⁴. Realistic ~10⁶ rows, generous ceiling ~10⁷. Production already holds 1.08 million `host_range` rows. **Scale is not a risk; the spike was dropped.** The rule cases become acceptance tests, written first, in step 2.

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
| 0b | ✅ Sources–Facts design (above). Spike dropped: scale isn't a risk. |
| 0c | ✅ **Relationship-type review** (domain doc); the taxonomy API follows from the table above. |
| 1 | **Taxonomy facade** over today's tables: ancestry read model, explicit `boundary` exports, the taxon-changed listener; route existing code through it. Ships to **main** as a behavior-preserving PR. Plan below. |
| 2 | **Sources–Facts and audit,** built from the 0b design, acceptance tests first: two Sources confirming one Host; a denial arriving in both orders; a placement superseded; a retraction; re-import dropping a Fact; a qualifier denied while its Relationship stands; a Gallformers override citing Observations. |
| 3 | **Import schema** (`e381`), validated with hand-made batches — gives the pipeline workstream a fixed target. |
| 4 | **Gall system:** split from species; **taxon identity layer** (moved here from step 1, 2026-10-05: Inducer taxa only exist once galls split and agamic/sexgen pairs merge, and nothing reads taxon IDs before then); Traits and Relationships as Facts; ranges; read models for ID tool, search, pages, API (migration: `b5bd`). |
| 5 | **Migration rehearsal, backscan, release** (release is sequenced with the backscan). |
| 6 | **Phase 2:** taxonomy rebuilt behind the same API. |

## Step 0a findings (2026-10-04)

Script: `docs/plans/coupling_inventory.py` (local). **The taxonomy facade is small; the gall split is the big job.**

- 75 of 271 `lib/` files touch the species/taxonomy core (31 in the web layer).
- **Species is the hub:** 8 contexts depend on it; its schema is referenced by 30 files outside its context. Registered cycles (`dirty_xrefs`): Species ↔ Taxonomy, Species ↔ Galls; web has 19 references to internal modules.
- Every context declares a `boundary` but with `exports: :all`, so nothing enforces black boxes. Switching a context to explicit exports makes the compiler list every violation — an exact work list (run 2026-10-05, below).
- **Taxonomy facade ≈ 10–15 files:** 5 query `species_taxonomy` directly, 4 use the `Taxonomy` schema, `sitemap_controller.ex` has 4 raw queries.
- **Gall split ≈ 40+ files:** 38 branch on `taxoncode`, plus 30 outside references to the `species` schema (overlapping).
- Web layer is mostly clean: raw SQL only in `sitemap_controller.ex`; coupling is at the struct level (`Image`, `SpeciesSource`, `Species`).

**Exact count (experiment 1, 2026-10-05, branch `taxogall`).** Temporarily set `Gallformers.Taxonomy` to `exports: []`, removed the Taxonomy suppressions from other boundaries' `dirty_xrefs`, and force-compiled; then reverted.

- **Into Taxonomy — 14 references in 8 files** (the facade's work list):
  - Contexts, 5 in 4 files: `galls.ex:106,118` and `plants.ex:58` (`TreeBuilder`); `galls/identification.ex:257` (`Tree`); `search.ex:426` (the `Taxonomy` schema).
  - Web, 9 in 4 files: `admin/reclassify_helpers.ex` (`Lineage`, `Genus`); `admin/taxonomy_live/form.ex` (`Tree` ×2, `Taxonomy` ×2); `admin/taxonomy_live/index.ex` (`Taxonomy` ×2); `genus_live.ex` (`Lineage`).
  - Plus what the compiler can't see: raw `species_taxonomy` queries (5 files) and `sitemap_controller.ex`'s 4 raw `taxonomy` queries.
- **Out of Taxonomy — 12 references in 3 files:** `taxonomy/reclassification.ex` (9), `taxonomy/species_link.ex` (1), `taxonomy/tree.ex` (2). One reaches into **Galls** (`reclassification.ex:107`), violating "taxonomy knows nothing about galls"; the other 11 reach into **Species** — species-as-taxa that move into the taxonomy system when galls split from species.
- **Facade size: about 12–13 files**, confirming the estimate.

## Step 1 plan — taxonomy facade (2026-10-05)

**Goal:** make `Gallformers.Taxonomy` a black box over today's tables, so the gall split (step 4) and the taxonomy rebuild (phase 2) change what's behind it, not its callers. **No behavior change.**

**Decisions (Jeff, 2026-10-05):** ships to **main** as an ordinary PR (branch from main, e.g. `taxonomy-facade`; then merge main into `taxogall`), keeping the long-lived branch from drifting on ~20 shared files. The taxon identity layer moves to step 4. The rule-6 listener is built now, with one real use.

**Findings that shape it:**
- Callers mostly use the context's ~60 public functions already. Leaks: the 14 internal-module references, raw `species_taxonomy` joins in `galls.ex`, `plants.ex` (3), `galls/identification.ex` (3), `search.ex`, and 4 raw `taxonomy` queries in `sitemap_controller.ex`.
- **15 recursive CTEs walk the same tree** (genus → family, family → descendants) across `taxonomy/tree.ex` (7), `taxonomy/search.ex` (2), `taxonomy/species_link.ex` (2), `galls.ex`, `plants.ex` (2). One published read model replaces them.
- Taxonomy reads gall data: `list_associated_genera`, `list_gall_families_for_host`, `list_gall_families_for_host_genus` join `gallhost`; `reclassification.ex:107` calls `Galls.force_undescribed_if_placeholder` inside its transaction. Its 11 references into `Species` are species-as-taxa and stay until step 4.
- The `Species` and `Alias` schemas' `many_to_many :taxonomies` associations are unused; drop them.

**Verification approach:** before any change, capture golden outputs from the unchanged code against the experiment DB (`gallformers_taxogall`): `Galls.get_galls_tree/1`, `get_undescribed_tree/1`, `Plants.get_hosts_tree/1`, the sitemap XML, `Search.search_taxonomy/1` for a sample of queries, and ID-tool results for a sample of genus/family/place filter combinations. Save them in `docs/plans/` (local) via a small script run with `MIX_ENV=dev PGDATABASE=gallformers_taxogall mix run`. Diff after every task; any difference is a bug.

### Task 1: Ancestry read model

- **Create:** a migration in `priv/repo/migrations/` defining two plain (non-materialized) Postgres views; `lib/gallformers/taxonomy/ancestry.ex` and `lib/gallformers/taxonomy/placement.ex` (read-only Ecto schemas over them); `test/gallformers/taxonomy/read_model_test.exs`.
- **`taxonomy_ancestry`** — one row per (node, ancestor-or-self): `taxonomy_id, ancestor_id, ancestor_type, ancestor_rank, depth` (0 = self).
- **`species_placement`** — one row per (species, node it sits under): `species_id, taxonomy_id, type, depth`, derived from `species_taxonomy` plus ancestry; distinct on (species, node), since a plant linked to both a section and its genus reaches the genus twice.
- The views are the **published shape**: in step 4 they are redefined over the new taxa tables and consumers don't change. Plain views suffice at this size (1,615 nodes, ~7k links); check with `EXPLAIN ANALYZE` on the experiment DB, and materialize only if a hot page measurably slows.
- **Tests:** a genus directly under a family; a genus under intermediates (subfamily → tribe); a section under a genus; a placeholder genus; a plant linked to genus and section (no duplicate rows); a gall linked to a genus; the self row at depth 0.

### Task 2: Taxonomy internals use the read model

- **Modify:** `taxonomy/tree.ex`, `taxonomy/search.ex`, `taxonomy/species_link.ex` — replace the recursive CTEs with joins on the views ("everything under family X" becomes `ancestor_id = X`).
- Existing tests (`test/gallformers/taxonomy_test.exs`, `taxonomy/tree_test.exs`, `taxonomy/species_link_test.exs`) must pass unchanged; golden outputs unchanged.

### Task 3: Route outside raw queries through the facade

- **Modify:**
  - `galls.ex` (`fetch_gall_tree_data`) and `plants.ex` (`fetch_host_tree_data`, the host-list family join ~line 872) — join `species_placement` instead of walking `taxonomy`.
  - `galls/identification.ex` — genus filter (~249), family filter (~257, drops `Tree.genus_ids_for_family`), placeholder-in-genus path (~422) — join `species_placement`.
  - `plants.ex` `get_genus_placeholder` (~361) and `update_species_section_link` (~714) — use `Taxonomy` API functions (add `unlink_species_from_taxonomy/2` beside `link_species_to_taxonomy/2`).
  - `search.ex` `search_taxonomy` (~426) — move the query into `Taxonomy.Search` and delegate; `search.ex` stops referencing the `Taxonomy` schema.
  - `sitemap_controller.ex` — use `Taxonomy.list_taxonomies_by_type/1` (or a lean `list_names_by_type/1` if the struct load is wasteful).
  - Drop the unused `:taxonomies` associations from `species/species.ex` and `species/alias.ex`.
- **Tests:** the existing gall/host tree, ID-tool (`test/gallformers/galls_identification_test.exs`, `test/gallformers_web/live/id_live_test.exs`), search and sitemap tests pass; golden outputs unchanged.

### Task 4: Move gall-data queries out of Taxonomy

- **Move** `list_associated_genera/2`, `list_gall_families_for_host/1`, `list_gall_families_for_host_genus/1` from `taxonomy/tree.ex` into `Galls` (they read `gallhost`), re-expressed over `species_placement`; update their callers (genus and host pages). Remove the delegates from `taxonomy.ex`.
- `count_families_for_taxoncode/1` and `count_genera_for_taxoncode/1` filter on `species.taxoncode` (species-as-taxa); they stay in Taxonomy until step 4.
- **Tests:** move the corresponding tests with the functions; golden outputs unchanged.

### Task 5: Taxon-changed listener (rule 6)

- **Create:** `lib/gallformers/taxonomy/change_listener.ex` (behaviour: `handle_taxon_change(change) :: :ok | {:error, reason}`); `lib/gallformers/taxonomy/change.ex` (event struct; first kind `:species_reassigned` with `species_id`, `from_genus_id`, `to_genus_id`, `to_placeholder?`); `lib/gallformers/galls/taxonomy_listener.ex`.
- **Modify:** `taxonomy/reclassification.ex` — replace the direct `Galls` call with `notify/1`, which calls each listener in order **inside the transaction** and rolls back on the first `{:error, _}`. Listeners come from config (`config :gallformers, Gallformers.Taxonomy, change_listeners: [Gallformers.Galls.TaxonomyListener]` in `config/config.exs`), read at runtime so tests can substitute; Taxonomy's code never names Galls. `Galls.force_undescribed_if_placeholder/2` becomes the listener's body (made private to Galls).
- The event fires at the same point as today's call (genus reassignment in Reclassification only), so behavior is identical. Renames, moves, merges and splits join later as more change kinds.
- **Tests:** reassigning a species into a placeholder genus marks its gall undescribed (existing `reclassification_test.exs` case keeps passing); a test listener returning `{:error, :collision}` makes the reassignment fail and leaves genus and name unchanged; no listeners configured → reassignment works.
- Remove `Gallformers.Galls` from Taxonomy's `dirty_xrefs`.

### Task 6: Explicit exports

- **Modify:** `lib/gallformers/taxonomy.ex` — `exports:` becomes the public types: `Taxonomy` (schema struct), `Lineage`, `Family`, `Genus`, `Intermediate`, `Section`, `Ancestry`, `Placement`, `ChangeListener`, `Change`. `TreeBuilder` is reached through a `Taxonomy.build_tree/3` delegate (it is pure display shaping).
- Web: replace `Taxonomy.Tree.get_children_for_parents/1` and `Tree.name_parent_exists?/3` in `admin/taxonomy_live/form.ex` with context functions (add `name_parent_exists?/3` to `taxonomy.ex`); `reclassify_helpers.ex` and `genus_live.ex` use the now-exported `Lineage`/`Genus`. Remove the four `Gallformers.Taxonomy.*` entries from `GallformersWeb`'s `dirty_xrefs` (`lib/gallformers_web.ex:40–43`).
- `galls.ex:765` spec and `identification.ex`'s `Tree` alias go through public names.
- **Done when:** `MIX_ENV=dev mix compile --force --warnings-as-errors` is clean with `exports:` explicit; Taxonomy's `dirty_xrefs` lists only `Species` modules (step 4 removes them); `mix precommit` passes; golden outputs unchanged on the experiment DB.

**Size:** a few focused days. Tests insert `%Gallformers.Taxonomy.Taxonomy{}` directly in many places; that's fine (tests aren't boundary-checked) and needs no change.

## Open questions

- **Taxonomy API: learn from prior art before finalizing.** iNaturalist in particular has solved taxonomy curation (swaps, splits, merges) and taxonomy queries at scale. The current API sketch (lookup and name resolution, facts about a taxon, tree operations, published read models, change events, phase-2 writes) is a placeholder until then. Not urgent.
- **Rename handling:** (A) derived names update automatically, curator only for overrides/collisions; or (B) every rename reviewed first. Leaning A.
- **Scope of the curated taxonomy:** all Gall Community members (Inducers, Inquilines, Parasitoids, …) or a narrower set?
- **Traits that vary by Host:** open in the domain doc (leaning no); needs a definitive answer.

## Outside scope

- **Plant taxonomy as a field of work** — see rule 1.
- **Relationships not tied to a Gall.**
- **Owning Observations** — Gallformers references and cites them; linking Observations to each other is iNat's business.
- **A phylogeny view** — Gallformers' editorial opinion of how phylogeny is shaping up may be shown someday, possibly outside the app; durable taxon and Gall IDs keep the door open.

Earlier design-draft material (concept diagram, 28-rule list): snapshot `docs/plans/domain-model-v1-2026-10-04.md` (local). Redraw the design diagram from the domain model when design resumes.
