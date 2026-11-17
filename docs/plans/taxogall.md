# Taxogall: Galls and Facts, released

## Operating principles

- **The long-term goal is a self-curating system** (Jeff, 2026-11-15). Gallformers' data curation should detect anomalies, propose fixes, and ask a human to review and approve. When a decision is close, choose the option that moves toward that.
- **One source of truth** (Jeff, 2026-11-15). Each thing is written down in one place and pointed to from everywhere else. This plan doesn't repeat the domain doc or the overview doc.

## What this plan delivers

Gallformers today treats everything as a species. Taxogall replaces that with Galls, Facts and Sources, in place on the `taxogall` branch, and cuts production over to it.

- **The domain** (what a Gall, Fact, Source, Relationship, Trait and the rest are, and how they relate): `docs/domain/domain-model.md`. It records the domain language as it's worked out; it doesn't describe the software.
- **How Gallformers works, and how that differs from the old site**, for curators, developers and agents: a Gallformers overview doc, still to be written (see *Design work still to do*).
- **Import contract:** `priv/import/` and `docs/import/producer-guide-background.md`. Source intake procedure: `runbooks/source-intake.md`.
- The 2026-11-12 audit of where the code stands: `docs/plans/2026-11-12-history-audit/` (local, gitignored, until it's folded in).

## Build approach

A new back-end, built whole on `taxogall`, replaces the old one in place. There is no facade and no dual-write.

- **Why:** the back-end changes so much that it is a rewrite. About 80% of today's UI is admin, which the new model replaces anyway. The public 20% changes little. Old and new never run side by side: there is one rehearsed cutover.
- **New:** the domain core (Galls, taxa, Sources and Facts, import, read models, audit), and ranges and places, rebuilt on PostGIS (rule 11). **Reused as it is:** auth and users, Oban, S3 storage and images, search infrastructure, maintenance mode and deploy.
- **The UI first** (Jeff, 2026-11-14). The whole UI is accounted for against what Gallformers needs, and what's missing is built early against the back-end interfaces, stubbed where they don't exist yet. Jeff judges the plan's completeness by using the screens.
- **Branch drift** is handled by merging `main` into `taxogall` regularly. Production hotfixes land on `main` and flow over.
- **Rejected:** building alongside the old system (a separate Postgres schema, duplicate public page modules behind a route flip, or empty tables shipped dark to main). That doubles every public page until cutover and puts schema churn into production migrations.

## One write path (Jeff, 2026-11-12)

The architecture rule every phase follows:

- **For any data, exactly two ways in:** one editing screen in the UI, and the import. Both call the same underlying code to validate, write and read it. No second editing screen, and no second code path.
- **A Fact edit is an ingestion.** A curator's edit under the Gallformers Source is a small package of that Source through the same code path as a paper's import, with the same rules. It applies immediately if it is valid.
- **Manual editing is one of two things:** correcting how an accepted Source was read, under that Source's authority and at its date; or a change under Gallformers' authority.
- **A Gallformers curator can do anything under the Gallformers Source**, including changing a Gall's Inducer, generation and descriptions, creating a Gall, and setting a range to "only here".
- **Plant taxonomy is Facts**, managed like the rest of the taxonomy, with POWO/WCVP and iNaturalist as Sources (Jeff, 2026-11-16).
- **Replay is mechanical.** Every write goes through its one path, so replay re-applies the same writes in order. No per-kind replay code.

## Audit (core architecture)

Audit is a layer underneath everything else, so new code doesn't have to think about it beyond naming who is acting. Today the database itself records every insert, update and delete on a tracked table (Carbonite triggers), against the transaction's actor and operation, and refuses a write to a tracked table that names no actor. 46 tables are tracked; the Source records and Host ranges are not. Whether the layer is complete, and whether code ever has to do more than name the actor, is design work (below).

## Design principles (Gallformers' owned taxonomy)

Adam and Jeff (2026-10-03/04): taxonomic Facts need Source attribution just as gall Facts do. The curation burden exists whether the work goes into iNat or into Gallformers. Doing it internally keeps it under our control and open to LLM tooling.

**Architecture.** There is a taxonomy system (taxa, names, authorship, rank, placement, synonymy, taxonomic acts and their history) and a gall system (Galls, Traits, Relationships, ranges, gall aliases). They share Sources and Fact attribution, history, audit and import. The contract between the two systems is stable taxon IDs, referenceable at any rank. Nothing else crosses. Both systems are black boxes behind Phoenix contexts, enforced by `boundary`. Sources–Facts and audit are shared building blocks, not peers. Hot cross-boundary reads go through published read models, such as the ID tool walking taxon ancestry or search across Inducer names. Writes that span the boundary compose into one transaction (`Ecto.Multi`).

**Rules:**

1. **Plants:** Gallformers is not an authority on plants. Plant names, synonymy, placement, common names and Host ranges are Facts from POWO/WCVP or iNaturalist, in the same taxonomy structure; a curator's correction is a Gallformers statement (Jeff, 2026-11-16). Open: whether the curator gate applies to POWO/WCVP statements, and how a database Source's releases are dated.
2. **Taxon origin:** *curated* (the whole Gall Community: Inducers, Inquilines, Parasitoids and every other member, and the rare gall-forming plant; Jeff, 2026-11-15) or *imported* (plants from POWO/WCVP or iNaturalist). iNaturalist also backs the import of non-plant taxonomy (genera, sections, families and above).
3. **Isolation:** taxonomy knows nothing about Galls. The gall system knows taxa only by ID and through the taxonomy API. The UI may hide the separation.
4. **IDs:** there is one shared ID sequence for Galls and all taxa, continuing today's species sequence. Galls keep their species IDs (`/gall/:id`) and plants keep theirs (`/host/:id`). Inducer and higher taxa get new IDs, with a crosswalk for the old higher-taxon IDs. Why: image paths are `gall/{species_id}/…` for galls and plants alike, and `Images.Audit` parses them.
5. **Taxonomic Facts** on curated taxa are sourced to the literature. A curator's acceptance gates them (see *Taxonomy as Facts*). Taxonomic acts (rename, move, merge, split) are sourced and keep history.
6. **Change events are synchronous, with the dependency inverted.** Taxonomy calls registered "taxon changed" listeners inside its own transaction. If the gall side can't accept a change, the taxonomy change fails. The exception is Gall names: a rename that follows from a taxonomy change is a proposal a curator reviews, and a name collision flags the proposal instead of failing the change. Only expensive derived work (search indexing, read-model refresh) runs async.
7. **Sources–Facts:** Gallformers is a Source. Observations are never Sources; a Source's statement cites them. Attribution (whose authority) is separate from audit (who changed it).
8. **Relationships** are owned by the gall system, and every Relationship happens in a Gall. Types and qualifiers are a system-level fixed list (15 kinds), changed only by a database update. Hyperparasitism is derived, not stored. Alternate generations are explicit, and mismatches are flagged.
9. **Traits belong to the Gall** and never vary by Host (Jeff, 2026-11-15).
10. **Gall names** are derived from the Inducer plus name parts stored on each Gall (form, generation, Host), overridable and unique. Undescribed Galls use a stored descriptor. A rename that follows from a taxon rename is reviewed by a curator before it takes effect, because the Gallformers code is derived from the name and ties existing iNat observations to Galls.
11. **Ranges** (Jeff, 2026-11-16; decision log, items d178 and 7128):
    - **Places:** ISO places, TDWG regions and named areas, with PostGIS boundaries; any place resolves to the leaf places it covers.
    - **Host ranges** are Facts on the plant (native or introduced), WCVP's in its own regions.
    - **Predicted range:** the Hosts' native range, narrowed by a Gall's *only within* and *absent from* Facts (per Gall, by place). An introduced region counts only with evidence.
    - **Observed range:** occurrence Facts, a point (with uncertainty, date and cited observation) or a place only. Points map to places through PostGIS.
    - **The ID tool and place pages** use predicted and observed, and say why a Gall matched. An observed place counts even while it conflicts with a restriction; the conflict goes to a curator.
    - **No Gall without a range:** every Gall has a Host and every Host a range.
    - The screens and curation are still open (item 7128).
12. **Editorial data** (Jeff, 2026-11-16): a Gall's name parts, ID notes, photos, and the Gallformers code (only on undescribed Galls) are editorial, as are keys, articles, the glossary and users. Generation and abundance are Facts. The data-complete flags, a Gall's lead Source, and curator notes on Facts and taxa are dropped.

**Sources–Facts mechanics:**

- A Fact stands on its own. Sources attach to it with a stance (confirm or deny).
- Standing follows the most recently authored Source with a stance, never the import order. Same-date conflicts go to a curator.
- Corrections and later revisions are newer Sources. A retraction cancels all of a Source's stances, and the Source stays visible, marked.
- Standings: current, withdrawn, superseded, retracted, unsupported (hidden).
- Each Fact kind has a natural key. An attribution carries its stance, quote and page hint, `name_as_written` for each taxon the Source names, cited Observations, and statement text.
- Any Source may state any Fact. Sources never reference each other formally. Delete is only for data added by mistake or testing.
- **There are two Gallformers Sources** (Jeff, 2026-11-14). **Gallformers legacy data** holds the old site's data and is undated, so every dated statement from any other Source, Gallformers included, overrides it; a Fact supported only by legacy data shows as unconfirmed. **Gallformers** holds the curators' own statements; each is dated by its change (timestamped, since several happen a day), and a newer Gallformers change replaces Gallformers' earlier word on the same Fact.

**Taxonomy as Facts (before release):**

- The literature is the authority, gated by a curator. A Source's taxonomic statement competes by the Source's date, but counts only once a curator accepts it. A curator who doesn't follow a paper declines it with a reason.
- A question arises only when an unaccepted statement is newer than the latest accepted one for that taxon. Accepting a statement closes open questions about the same taxon from older papers as history.
- Taxonomy questions don't hold a Source's approval. Name-resolution questions do.
- Today's tree comes in as Gallformers legacy data, so the backscan can correct it.
- The tree tables stay what every page reads. They are rewritten from the accepted statements in the same transaction, and a rebuild-and-compare check guards them.
- An accepted split asks, per Gall, which daughter induces it. An accepted lump moves B's Galls to A.

**Generation groups:** a generation is a stage of the Inducer's life cycle that induces a clearly different Gall. Groups of values (heterogony, seasonal, rust stages, aphid life cycle) are a system list mapped to taxa. The Inducer's nearest mapped ancestor decides which groups apply to a Gall.

**Scale is not a risk.** About 4×10³ Galls × ~90 Facts each ≈ 3.6×10⁵ Facts, and 6–7×10⁵ attributions. Realistically ~10⁶ rows, with a generous ceiling of ~10⁷.

**Outside scope:** plant taxonomy as a field of work, Relationships not tied to a Gall, owning Observations, and a phylogeny view.

## The old site's data and the Gallformers notes

- **All of the old site's data comes over as Gallformers legacy data** (Jeff, 2026-11-15). Its Facts go in as packages of Gallformers legacy data through the same import path as any paper. Only what isn't a Fact is copied directly, each kind through its one writer: Gall skeletons (ID, name, Gallformers code, URL, images, editorial data), plants with their ranges, Sources as records, keys and other non-Fact data.
- **What happens to each existing Source** is decided in its own phase, before any migration work.
- **The old notes are sorted by code** (Jeff, 2026-11-12): deterministic, repeatable code splits them into undescribed-Gall descriptions, pure ID notes, and other (to be worked out once we see them). Nothing is imported blindly.
- **Undescribed-Gall notes are processed as Sources** (Jeff, 2026-11-15), adding Facts as normal. They may or may not confirm what's already held from legacy data. How to date those Facts needs analysis, and is a task of its own.
- **Pure ID notes are editorial:** an ID Notes field on the Gall, attached to no Source.
- **The old site's curated places in a Host's introduced range** come over as legacy occurrence Facts (Jeff, 2026-11-16).
- **The old season tags are dropped**; Sources supply season under its new definition (Jeff, 2026-11-12).

## Cutover (Jeff, 2026-11-12)

- Real data is built on preview, then in production, never on a developer's machine. Sources are processed into a migrated production copy on preview.
- At cutover, production is migrated fresh and preview's work is replayed onto it, so the live site stays editable while Sources are processed.
- Replay is rehearsed onto a separate database early, in the Preview environment phase, and the whole cutover is rehearsed until boring.
- Merging `taxogall` into `main` deploys to production at once, so the cutover runbook guards against an accidental merge or manual deploy.

## Design work still to do

Each of these is decided before the work that depends on it; each becomes an item in its phase.

- **The fate of each existing Source** (its own phase).
- **The full UI accounting** (its own phase).
- **The Gallformers overview doc:** how Gallformers works, for curators, developers and agents, and how it differs from the old site.
- **Ranges: the screens and curation** (the model was settled 2026-11-16; item 7128).
- **How a curator produces a Source package and gets it into the system.**
- **Audit:** confirm the layer is complete and that code only names its actor.
- **The old public API's fate,** early: whether anyone uses it, and whether to disable it in production until release.
- **The taxonomy API:** a separate design session, learning from prior art such as iNaturalist's curation of swaps, splits and merges (Jeff, 2026-11-15).
- **One unified approach to editing:** first a shared understanding of how editing should work (Jeff's answer on the Fact inspector, 2026-11-15: probably not every edit through the inspector).
- **Dating the Facts from undescribed-Gall notes:** an analysis.

## When the plan is done

Production runs on the new back-end and the old system is retired:

- **Every existing Source has been dealt with** as its phase decides, and the Sources to be processed have been processed on preview and approved or denied by curators.
- **The Gallformers notes have been handled** as above, before release.
- **Public taxon pages for non-plant taxa, the Gall merge workflow and iNat taxon IDs are done** (Jeff, 2026-11-15: before release, not after).
- **The cutover has been rehearsed until boring** (timing, the replay, rollback). Production has been cut over in a maintenance window, the verification suite passes against production, and `taxogall` is merged to `main`.
- **After release:** the old tables and `species_id` columns are dropped. The domain docs, `CLAUDE.md` and runbooks describe the new model. Records left with no Facts have been reviewed for removal.

**Release gates** (from the 2026-10-06 success criteria, now checked before cutover):

- ID-tool parity with today on a sample of real queries. The expected differences: introduced places count only with evidence, Hosts' ranges come from WCVP, and Galls gain observed places.
- 100% Fact–Source coverage: every Fact comes from a Source's package, or from Gallformers legacy data for what no Source holds.
- Jeff's judgement that old vs new looks similar, with much better data.
- Trial metrics: agreement with the database, error attribution, quote verification rate, cost per Source.

## Why this order

- **Decisions first comes first** (Jeff, 2026-11-16): the decisions that shape more than one phase, or that Jeff has prioritised, are settled before any building. Every other phase waits for it, except **The UI**, whose accounting runs alongside it, since Jeff judges the plan by using the screens.
- **Review cleanup, Housekeeping, Import at scale and Public site, settled** follow Decisions first and can run side by side.
- **One write path waits for Decisions first, the review cleanup and the UI.** The cleanup gives it one decision shape and one carry-out to build on; the UI defines the interfaces it fills in.
- **The existing Sources are decided before any migration work** (Jeff, 2026-11-14), in Decisions first.
- **Migration through the import** needs one write path (the import is the one writer for Facts).
- **One editor** connects the UI to the one write path, then the full audit runs. **Gall relationships** follow it, since they're edited through it.
- **Gallformers notes** need one write path: ID notes become an editorial field and the notes' Facts go in as packages.
- **Preview environment** needs one write path for its replay rehearsal.
- **Process Sources on preview** needs one write path, the migration through the import, the import at scale and preview.
- **Rehearse and cut over** needs everything that changes what reaches production.
- **After release** waits for the cutover. The old tables stay until then, because the migration reads them.

## After release (scope)

- Drop the old tables (the `species`-centric model), the `species_id` column on `image`, and the `host_range` table. Track the Source records in the audit layer (today they aren't).
- Replace `docs/domain/general.md` and `docs/domain/admin-domain-reference.md`. Update `CLAUDE.md` and the runbooks that assume the old tables (e.g. `runbooks/restore-deleted-gall.md`).
- Review records left with no Facts for removal, old genus-level Hosts included, once most Sources are processed. Fix wrong Host ranges on the Host.
- Deferred features: search and the API over Source terms, and the PDF page view.
- Follow-on work outside this plan: phenology, data completeness scoring, notifications, interoperability (Darwin Core, GBIF, Wikidata), DNA barcodes, iNat integration, GallOnt trait vocabulary, a host-family filter, a mobile-first ID tool, and out-of-range records as Host-range proposals. The public API's future (including API v2 parity) follows from its design item above.

Sources: matters 50ff, 8567, f923, d3b0, b5bd (M0, M5–M7), and Jeff's decisions of 2026-11-12, 11-14 and 11-15 (mull decision log).
