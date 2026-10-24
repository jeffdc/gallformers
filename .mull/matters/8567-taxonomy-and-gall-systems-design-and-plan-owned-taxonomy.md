---
status: raw
created: 2026-10-03
updated: 2026-10-24
epic: taxonomy
relates: [b5bd, e381, 294c, 50ff, 9449]
---

# Taxonomy and gall systems — design and plan (owned taxonomy)

The chosen direction (2026-10-04): **Gallformers owns its taxonomy**, with every taxonomic Fact sourced, built as a separate system from the gall system and delivered in phases. This matter holds the **software design and plan**. What the domain's words mean — Gall, Observation, Source, Fact, Relationship, Traits, gall-entry boundaries — is defined in [`docs/domain/domain-model.md`](../../docs/domain/domain-model.md), which this matter defers to. Related: migration `b5bd`, import interface `e381`. The rejected iNat-mirror direction is matter `1121` (dropped, kept for history).

## Decision

Adam and Jeff (2026-10-03/04): taxonomic Facts need Source attribution like gall Facts (authorship, naming, placement, splits, lumps). The curation burden exists whether the work goes into iNat or Gallformers; handling it internally keeps it under our control and open to LLM tooling. Cost: roughly double the effort, so it's phased — ship the gall system first on today's taxonomy, then rebuild taxonomy. (Refined 2026-10-24: phase 1 builds new taxonomy storage rather than running on today's tables; see *Build approach*.)

## Build approach (Jeff, 2026-10-24)

**A new back-end, built whole on `taxogall`, replacing the old one in place. No facade.** Its schema is in `9449`.

- **Why:** the back-end changes so much that it is a rewrite. About 80% of today's UI is admin, which the new model replaces anyway (rule 12); the public 20% changes little. Old and new never have to run side by side: the plan is one rehearsed cutover with no dual-write (`b5bd` M0), and the data migration runs as a separate step from a production copy. A facade over today's tables (`36ca`, dropped) would only pay off if old and new ran together; it would refactor code the cutover deletes.
- **What's new and what's reused:** the domain core is new (galls, taxa, Sources–Facts, import, read models). Infrastructure is reused as it is: auth and users, Oban, S3 storage and images, WCVP/POWO plant ranges, places and maps, search infrastructure, maintenance mode and deploy.
- **The phases still split taxonomy work, but by feature, not by storage.** Phase 1 builds new taxonomy storage (taxa, rank, placement, names and synonyms) under today's IDs, filled by the skeleton migration (`b5bd` M2). Phase 2 adds sourced taxonomic acts with history, splits and lumps, authorship, and the POWO import on top of it.
- **Order:** new back-end → public pages re-pointed in place → new minimal admin → migration and backscan on the preview environment → cutover.
- **Considered and rejected:** building alongside the old system (a separate Postgres schema, duplicate public page modules behind a route flip, empty tables shipped dark to main) to shorten the branch's life. It doubles every public page until cutover and puts schema churn into production migrations; the branch's drift risk is modest (see *Shipping dark*). Drift is handled by merging main into `taxogall` regularly; production hotfixes land on main and flow over.
- **History:** the greenfield reset (Jeff, 2026-09-18, in the Codex-era `1121`) proposed a new domain model and target schema but never wrote the cutover plan; `b5bd` is that plan. The facade came from the 2026-10-03 phasing ("ship the gall system first on today's taxonomy") and is superseded by this section.

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
4. **IDs:** each system owns its IDs; cross-system references are typed. Galls keep their species IDs (`/gall/:id`), plant taxa keep theirs (`/host/:id`); Inducer and higher taxa get new IDs. **Decided (Jeff, 2026-10-24): one shared ID sequence** for Galls and all taxa, continuing today's species sequence, so every ID stays unique across kinds as today. Why: image paths are `gall/{species_id}/…` for galls *and* plants (`storage/images.ex:57`) and `Images.Audit` parses them; with one sequence nothing about paths, the audit or URLs changes. Old higher-taxon IDs (which collide with species IDs) get new IDs and a crosswalk. References stay typed; the shared sequence only guarantees uniqueness.
5. **Taxonomic Facts** on curated taxa (name, authorship, rank, placement, synonymy) are sourced — to the literature, or to **Gallformers** for its own positions. Which value is current follows the **recency rule** (see *Sources–Facts design*); Gallformers overrides with a newer statement of its own. Taxonomic acts (rename, move, merge, split) are sourced and keep history.
6. **Change events — synchronous, with the dependency inverted** (decided 2026-10-05). Taxonomy defines a "taxon changed" interface and calls registered listeners **inside its own transaction**; the gall system registers as a listener through application wiring, so taxonomy's code never references it and the boundary rule holds. Reactions: rename/move updates derived Gall names and keeps the old name as a gall alias; merge re-points links; split creates curator tasks. **If the gall side can't accept a change (e.g. a name collision), the taxonomy change fails** — errors surface immediately and get real resolution, rather than leaving the other system violating its own constraints. Only expensive derived work (search indexing, read-model refresh) runs async, where staleness is harmless. Rationale: there are ways other than loose async coupling to protect a boundary; at Gallformers' scale even bulk changes are fast; async would add idempotency, ordering, and staleness bugs for no real benefit.
7. **Sources–Facts layer** serves both systems, as designed below. **Gallformers is a Source** (author "Gallformers Contributors"), cited per Gall page as today (`/gall/587?source=58`), with per-Fact links possible later. Observations are never Sources; they are cited inside a Source's statement. **Attribution** (whose authority) is separate from **audit** (who changed it); audit is agnostic to meaning.
8. **Relationships** are owned by the gall system (every Relationship involves a Gall; taxon-to-taxon ones always happen in a Gall). Meanings are in the domain doc. Design: types and qualifiers are a **system-level fixed list** (changed only by a database update, never by curators), each with direction, inverse label, and endpoint kinds. Hyperparasitism is derived, not stored. Alternate generations are explicit; the system flags mismatches (same species-level Inducer, different generations, no link; or a link between Galls whose Inducers differ).
9. **Gall names** are derived (Inducer plus qualifiers as needed for uniqueness: generation, Host, form), overridable, and unique.
10. **Ranges — leave as much alone as possible** (Jeff, 2026-10-05). **Potential range** = union of all Hosts' ranges (POWO/WCVP or curator-adjusted), genus-level Hosts included as today — computed, not stored, inherited through Host Facts. Adjustments are Facts: **range inclusion / exclusion** (Gall + place), stated by Sources or by Gallformers (a curator removing a region = an exclusion attributed to Gallformers). The ID tool uses the potential range with adjustments applied — effectively what it uses today. Only the adjustments are stored, which removes the bloat of today's stored gall range (mostly copies of the host union). **Observed range** (Research Grade iNat observational data) is future. **Missing data is not absence** (2026-10-24): today a Gall with no range data appears in every region (`search.ex:491`); 1 Gall has no Host, 78 have only placeholder Hosts, and ~100 plants have no range data. A computed range must keep that behavior, or these Galls drop out of region filters.
11. **Import** follows `e381`. Facts from a Source aren't curated after import; a curator who disagrees adds a **Gallformers** statement (confirming or denying). Re-import replaces a Source's attributions.
12. **Pipeline artifacts are the primary admin interface** (Jeff, 2026-10-05). Data gets in and gets fixed through trusted pipeline batches, not hand-edited forms; screens exist only where unavoidable — taxonomy, batch approve/deny (with unresolved references), and retraction. Curator corrections can follow the same path: a curator writes plain notes, an LLM turns them into a batch attributed to the Gallformers Source, and it is validated and approved like any other. Consequence: the pipeline becomes a critical system, and the quality of its output must be earned, measured, and maintained. **Restated 2026-10-06: every write is a batch** — the interface is the import JSON Schema (or a fragment of it), so any tool, screen, human, or LLM that produces valid JSON can deliver updates; nothing depends on the LLM itself. The pipeline is an LLM with skills/docs (derived from the domain doc and `e381`) plus the validator (`294c`).

## Sources–Facts design (0b, 2026-10-05)

1. **A Fact stands on its own.** Sources attach to it with a **stance**: confirm or deny. One statement from two Sources is one Fact with two attributions.
2. **Recency rule:** a Fact's standing is set by the **most recently authored** Source with a stance on it — never import order. For single-valued Facts (placement, current name, detachable, …) the newest confirmed value is current; there is no curator "accepted" marker. Curators override with a newer Gallformers statement. Same-date conflicts go to a curator.
3. **Corrections and later revisions** are newer Sources. **A retraction** is a status on the original Source ("retracted, per notice X, date") that cancels all its stances; the Source stays visible, marked. Expressions of concern are display-only.
4. **Standings:** *Current* (shown) · *Withdrawn* — newest stance denies (shown, marked) · *Superseded* — a newer value replaced it (shown as history) · *Retracted* — its support was retracted (shown, marked) · *Unsupported* — re-import dropped it (hidden; audit keeps it).
5. **Storage:** a central `facts` table (ID, kind, precomputed standing); each system owns typed detail tables keyed by Fact ID; attributions reference the Fact ID with a real foreign key. Hot reads use the stored standing.
6. **Identity:** each kind has a natural key (Host = Gall + host taxon; Trait = Gall + Trait + value; Range adjustment = Gall + place + include/exclude; Placement = taxon + parent). **Relationship qualifiers are separate Facts** about the Relationship, independently sourced.
7. **An attribution carries:** stance; **quote** plus page hint (required for imported literature; replaces offset locators, 2026-10-06 — quotes are checkable against the stored plain text); **`name_as_written`** for each taxon the Source names (2026-10-06 — after a taxonomic split, Facts can only be re-resolved if we know the name the Source used); **structured cited Observations** (provider + ID); **statement text** (required for Gallformers). The authorship date comes from the Source (Sources need one — today only `pubyear` exists; each Gallformers statement is its own dated entry). Who made the entry is audit. **Open (2026-10-24):** the date of Gallformers statements whose text has none — the legacy ID Notes (`20e5`), legacy range exclusions, and legacy Facts if they are attributed to Gallformers (`b5bd` M0). Dated at migration, they would outrank all the literature under rule 2.
8. **Gallformers notes** (Jeff, 2026-10-24; `20e5`): each Gall's note is Gallformers' document for that Gall — shown whole as "Notes on ID and Taxonomy", never cut down to commentary. Gallformers statements are extracted from it with quotes, like any Source, through the normal pipeline (rule 12); a curator edits the note and the edit is re-extracted, each version dated by its edit. Legacy notes migrate verbatim and are processed after release.

**Scale (Fermi, checked against the production copy):** ~4×10³ Galls × ~90 Facts each ≈ 3.6×10⁵ Facts; × ~1.5–2 Sources per Fact ≈ 6–7×10⁵ attributions; taxonomic Facts add ~2–3×10⁴. Realistic ~10⁶ rows, generous ceiling ~10⁷. Production already holds 1.08 million `host_range` rows. **Scale is not a risk; the spike was dropped.** The rule cases become acceptance tests, written first, in step 4.

## What Relationships need from the taxonomy API

| Need | Taxonomy API |
|---|---|
| Endpoint taxon exists and is active | exists / active |
| "Host of" needs a plant; Inducers generally aren't plants | kingdom / group |
| Competing Inducer candidates map to the shared higher taxon | common ancestor |
| "All Galls induced by anything in genus X" | ancestry / descendants (read model) |
| Derived Gall names | current names |
| Merges and splits re-point endpoints | change events |
| Which generation groups apply to a Gall | ancestry / descendants |

## Generation groups (2026-10-24)

Jeff (2026-10-23): generation gets the full treatment ("in for a penny, in for a pound"): new schema in the gall system, replacing `0a58`'s single-column design.

- **What a generation is:** a stage of the Inducer's life cycle that induces a clearly different Gall. Repeated broods that induce the same Gall are multivoltine, not generations: one Gall, no extra generation value. (*Thecabius populimonilis* apterae induce galls like the stem mother's, Floate 2010: one Gall. *Pachypappa pseudobyrsa* apterae induce a different gall: two.)
- **Groups:** a generation group is a named set of generation values, each with a definition and the qualifier text derived Gall names use (rule 9). Values are unique across groups, so a value names its group. Each group is mapped to taxa at any rank.
- **A system list:** groups, values and mappings change only by a database update, like Relationship types (rule 8). The vocabulary generator publishes them to the contract (`traits.json`).
- **Which groups apply to a Gall:** those of its Inducer's nearest mapped ancestor (a deeper mapping overrides a higher one); if no ancestor is mapped, every group mapped below the Inducer's taxon, so a family-level undescribed cynipid Gall can still be agamic or sexual.
- **Uses:** import checks each Gall's generation against its Inducer's groups (a mismatch goes to the admin queue); derived Gall names; the ID tool's generation filter offers only the values of the groups in scope; producers choose from the group for the Inducer's taxon.
- **Initial groups** (taxa mappings a proposal, for Jeff and Adam): heterogony (agamic, sexual) → Cynipini; seasonal (spring, summer, autumn) → Cecidomyiidae, *Procecidochares*; rust stages (aecial, telial) → Pucciniales; aphid life cycle → Aphididae, Phylloxeridae, Adelgidae.
- **Aphid life-cycle values** (Jeff, 2026-10-24: every generation that induces a gall of its own, grape phylloxera's included). Generations that induce no gall (alate emigrants, sexuparae, sexuales, adelgid sistentes and progredientes) get no value.

  | Value | Also called | Definition | Example |
  |---|---|---|---|
  | fundatrix | stem mother | Hatches from the overwintering egg on the primary host and induces the primary gall. | nearly every gall aphid (Floate 2010) |
  | apterae | apterae fundatrigeniae | The stem mother's wingless offspring on the primary host, where they leave her gall to induce one of their own. | *Pachypappa pseudobyrsa*, *Thecabius gravicornis*, *T. populiconduplifolius* (Floate 2010) |
  | exules | alienicolae, virginoparae | Generations on the secondary host. | *Eriosoma lanigerum* on *Malus*; *Hamamelistes spinosus* on *Betula* |
  | gallicolae | | Phylloxerid generations that induce leaf galls. | grape phylloxera (*Daktulosphaira vitifoliae*) |
  | radicicolae | | Phylloxerid generations that induce root galls. | grape phylloxera |

- **Open:** the value name for multivoltine seasonal entries such as "summer and autumn generations"; when a taxon move carries an Inducer out of its group's subtree, whether the taxonomy change fails (rule 6) or raises a curator task.

## Phases

1. **Gall system, on new taxonomy storage.** Galls separate from taxa; Relationships and Sources–Facts; **new taxonomy tables** (one stable taxon ID per taxon at any rank: plants keep their species IDs, higher taxa and Inducers get new IDs; filled from today's data by the skeleton migration) so Galls can link to any rank. Build shared parts generically. Ship. Taxonomy storage needs (2026-10-24): a tree validator, since placement Facts settled one by one by recency can form cycles or rank inversions (acceptance test in `50ff` step 5); and names can be homonyms across kingdoms, so no globally unique name. (Revised 2026-10-24 from "on today's taxonomy … wrapping today's tables"; see *Build approach*.)
2. **Taxonomy system,** rebuilt behind the same IDs: sourced names, authorship, placement, taxonomic acts with history, POWO import. No gall changes. Phase 2 is mainly about the hard taxonomy edits — **splits and lumps**. Their mechanics can wait, but **the data they need must be captured in phase 1** (e.g. `name_as_written` on attributions). (Jeff, 2026-10-06)

## Work ordering

**The ordered punchlist now lives in `50ff`** (2026-10-24). This section keeps the reasoning and status of the original steps: 0a–3 are done (`294c` built, `b119` done, `8546` go on 2026-10-24).

**Reordered 2026-10-06** (Jeff's review): the real unknown is not code but **whether LLM output is good enough to be the input** — Adam is confident, Jeff is unsure — so the plan gets that evidence first, before the expensive work.

| Step | What |
|---|---|
| 0a | ✅ Coupling inventory (below). |
| 0b | ✅ Sources–Facts design (above). Spike dropped: scale isn't a risk. |
| 0c | ✅ **Relationship-type review** (domain doc); the taxonomy API follows from the table above. |
| 1 | **Import schema and validator** (`294c`): the `e381` format as a committed contract. |
| 2 | **Pipeline-vs-database diff** (`b119`): a one-off tool comparing pipeline JSON with today's data for the same species. **The pipeline is the migration for everything that lives in Sources;** only what can't come out of a Source migrates directly (the eight-step approach in `b5bd` M2). |
| 3 | **Pipeline trial on existing Sources — go/no-go** (`8546`). |
| 4 | **Sources–Facts and audit,** built from the 0b design, acceptance tests first: two Sources confirming one Host; a denial arriving in both orders; a placement superseded; a retraction; re-import dropping a Fact; a qualifier denied while its Relationship stands; a Gallformers override citing Observations. |
| 5 | **Gall system:** split from species; **new taxonomy storage** (Inducer taxa only exist once galls split and agamic/sexgen pairs merge); Traits and Relationships as Facts; ranges; read models for ID tool, search, pages, API (migration: `b5bd`). |
| 6 | **Migration rehearsal, backscan, release** (release is sequenced with the backscan). |
| 7 | **Phase 2:** taxonomy rebuilt behind the same API. |
| ~~floats~~ | ~~**Taxonomy facade** (`36ca`)~~ — dropped 2026-10-24 (*Build approach*). |

**Shipping dark** (steps 4's tables and importer to main, unused, to shorten `taxogall`'s life): not adopted, kept in mind. The site has been stable for months and Jeff is the main committer, so the long-lived branch's risk is modest. Confirmed 2026-10-24: the new back-end replaces the old one in place on `taxogall` (*Build approach*).

## Success criteria (2026-10-06)

- **ID-tool parity** with today on a sample of real queries.
- **100% Fact–Source coverage** — Facts arrive from the pipeline's batches, plus Gallformers data for what no Source holds (e.g. range exceptions).
- **Old vs new sanity check passes human judgement** (`b5bd` M2 step 6): similar to today, much better data.
- **Trial metrics** (`8546`): agreement with the database, error attribution (database's vs LLM's), quote verification rate, cost per Source.

## Review and admin (2026-10-06)

- **The admin UI is the schema plus the delta view.** Batch approval will honestly be a rubber stamp, so **quality must come from the system, not the reviewer**: the delta view ranks changes by risk — *confirms* an existing Fact (bulk-approve), *new* Fact, *denies or replaces* one (where attention goes) — and **sample audits** check random Facts against their quotes, tracking an error rate over time.
- **Click-through curators are effectively cut off** — an accepted cost of pipeline-first. Mitigation if needed: a small form that emits a schema fragment (rule 12).
- **Show a taxonomy change's reach before approval** (2026-10-24): how many Galls' derived names and links a rename, move or merge touches.

## Step 0a findings (2026-10-04)

Script: `docs/plans/coupling_inventory.py` (local). **The taxonomy facade is small; the gall split is the big job.** (Kept for history: the facade was dropped on 2026-10-24, *Build approach*. The counts still show what the rewrite replaces.)

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
- **Facade size: about 12–13 files**, confirming the estimate. Its plan is in `36ca`.

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
