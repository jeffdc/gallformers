# Taxogall: Galls and Facts, released

## The picture

Gallformers today treats everything as a species. Taxogall replaces that, in place, on the `taxogall` branch, and cuts production over to it.

- **Galls** are catalog entries (two generations are two Galls). Everything known about a Gall (its Hosts and other Relationships, Traits, range, recorded occurrences, common names, descriptions) is a **Fact**, attributed to the Sources that confirm or deny it. Gallformers is a Source too.
- **Taxonomy is Facts too** (Jeff, 2026-11-06). Names, authorship, placements, synonymies, ranks and splits are Facts credited to the Sources that make them. Gallformers states a taxonomic Fact only as a rare exception: an undescribed Gall's Inducer, or a position no paper supports. The tree is whatever the current taxonomic Facts say.
- **Editorial, not Facts:** Gall naming (derived names with stored name parts: form, generation, Host qualifier) and plant data (names, synonymy, ranges). WCVP makes plant input easier, and curators edit plants freely. Gallformers is not a system of record for plants. The Host relationship (host of) is still a Fact.
- **Every change goes through one Fact process.** Sources arrive as LLM-produced packages against a validated contract (`priv/import/`). Curators settle questions and approve. Gallformers' own edits go through the same process. Decisions are logged and replayed at cutover.
- **The pipeline is the migration** for everything that lives in Sources. Existing Sources are re-processed into the new model before release. Only what can't come out of a Source migrates directly: Gall skeletons (ID, name, Gallformers code, URL, images, editorial data), the skeletal taxonomy, Hosts with their ranges, curators' range exceptions, Sources as records, keys and other non-Fact data.

Domain language: `docs/domain/domain-model.md`. It records the domain language as it is being worked out. It is not a description of the software, so don't use it to explain the current code. Import contract: `priv/import/` and `docs/import/producer-guide-background.md`. Source intake procedure: `runbooks/source-intake.md`.

## Build approach

A new back-end, built whole on `taxogall`, replaces the old one in place. There is no facade and no dual-write.

- **Why:** the back-end changes so much that it is a rewrite. About 80% of today's UI is admin, which the new model replaces anyway. The public 20% changes little. Old and new never run side by side: there is one rehearsed cutover, and the data migration runs as a separate step from a production copy.
- **New:** the domain core (Galls, taxa, Sources and Facts, import, read models). **Reused as it is:** auth and users, Oban, S3 storage and images, WCVP/POWO plant ranges, places and maps, search infrastructure, maintenance mode and deploy.
- **Branch drift** is handled by merging `main` into `taxogall` regularly. Production hotfixes land on `main` and flow over.
- **Rejected:** building alongside the old system (a separate Postgres schema, duplicate public page modules behind a route flip, or empty tables shipped dark to main). That doubles every public page until cutover and puts schema churn into production migrations.

## Design principles (Gallformers' owned taxonomy)

Adam and Jeff (2026-10-03/04): taxonomic Facts need Source attribution just as gall Facts do. The curation burden exists whether the work goes into iNat or into Gallformers. Doing it internally keeps it under our control and open to LLM tooling.

**Architecture.** There is a taxonomy system (taxa, names, authorship, rank, placement, synonymy, taxonomic acts and their history) and a gall system (Galls, Traits, Relationships, ranges, gall aliases). They share Sources and Fact attribution, history, audit and import. The contract between the two systems is stable taxon IDs, referenceable at any rank. Nothing else crosses. Both systems are black boxes behind Phoenix contexts, enforced by `boundary`. Sources–Facts and audit are shared building blocks, not peers. Hot cross-boundary reads go through published read models, such as the ID tool walking taxon ancestry or search across Inducer names. Writes that span the boundary compose into one transaction (`Ecto.Multi`).

**Rules:**

1. **Plants:** Gallformers is not an authority on plants. Plant taxa start from POWO/WCVP and live in the same taxonomy structure. Curators adjust them editorially (audit log, no Facts), including host ranges.
2. **Taxon origin:** *curated* (gall formers and associates, including the rare gall-forming plant) or *POWO-imported* (plants).
3. **Isolation:** taxonomy knows nothing about Galls. The gall system knows taxa only by ID and through the taxonomy API. The UI may hide the separation.
4. **IDs:** there is one shared ID sequence for Galls and all taxa, continuing today's species sequence. Galls keep their species IDs (`/gall/:id`) and plants keep theirs (`/host/:id`). Inducer and higher taxa get new IDs, with a crosswalk for the old higher-taxon IDs. Why: image paths are `gall/{species_id}/…` for galls and plants alike, and `Images.Audit` parses them. With one sequence, paths, the audit and URLs don't change.
5. **Taxonomic Facts** on curated taxa are sourced to the literature. A curator's acceptance gates them (see *Taxonomy as Facts* below). Taxonomic acts (rename, move, merge, split) are sourced and keep history.
6. **Change events are synchronous, with the dependency inverted.** Taxonomy calls registered "taxon changed" listeners inside its own transaction. If the gall side can't accept a change, the taxonomy change fails. The exception is Gall names: a rename that follows from a taxonomy change is a proposal a curator reviews, and a name collision flags the proposal instead of failing the change. Only expensive derived work (search indexing, read-model refresh) runs async.
7. **Sources–Facts:** Gallformers is a Source. Observations are never Sources; a Source's statement cites them. Attribution (whose authority) is separate from audit (who changed it).
8. **Relationships** are owned by the gall system, and every Relationship happens in a Gall. Types and qualifiers are a system-level fixed list, changed only by a database update. Hyperparasitism is derived, not stored. Alternate generations are explicit, and mismatches are flagged.
9. **Gall names** are derived from the Inducer plus name parts stored on each Gall (form, generation, Host), overridable and unique. Undescribed Galls use a stored descriptor. A rename that follows from a taxon rename is reviewed by a curator before it takes effect, because the Gallformers code is derived from the name and ties existing iNat observations to Galls.
10. **Ranges:** a Gall's potential range is the union of its Hosts' ranges (native and introduced, genus-level Hosts included). It is computed, not stored. The only stored adjustments are range Facts (exclusion, and "only"), stated by Sources or by Gallformers. There are no inclusions: a Gall recorded where no Host grows is a statement about a Host's range. Missing data is not absence: a Gall with no range data must still show in every region.
11. and 12. (import is never curated afterwards; every write is a pipeline batch) are superseded by the unified edit model below.

**The unified edit model** (Jeff, 2026-11-07; replaces rules 11 and 12):

- Any Source may state any Fact. The literature is the usual authority.
- New Facts come in exactly two ways: ingesting a Source to approval, or editing or adding a Fact on a Fact-bearing entity (a Gall, or Gallformers' non-plant taxonomy). An edit is the ingestion of a Gallformers statement, through the same code path as a Source ingestion.
- There is one Gallformers Source. Each change is a package of it: small, timestamped and audited. The old site's data is its undated base.
- Review edits and corrections of a misreading are made under the reviewed Source's authority, at its date.
- Sources never reference each other formally. Delete is only for data added by mistake.
- All edits that can be inline are inline on the main pages, with one shared set of components, mechanics and validators. The Fact inspector is both the Fact viewer and the Fact editor.

**Sources–Facts mechanics:**

- A Fact stands on its own. Sources attach to it with a stance (confirm or deny).
- Standing follows the most recently authored Source with a stance, never the import order. Same-date conflicts go to a curator.
- Corrections and later revisions are newer Sources. A retraction cancels all of a Source's stances, and the Source stays visible, marked.
- Standings: current, withdrawn, superseded, retracted, unsupported (hidden).
- Each Fact kind has a natural key. An attribution carries its stance, quote and page hint, `name_as_written` for each taxon the Source names, cited Observations, and statement text.
- The "Gallformers legacy data" (the old site's data) is undated, so any real Source outranks it. A Fact supported only by legacy data is shown as unconfirmed.

**Taxonomy as Facts (phase 2, before release):**

- The literature is the authority, gated by a curator. A Source's taxonomic statement competes by the Source's date, but counts only once a curator accepts it. A curator who doesn't follow a paper declines it with a reason, and no Gallformers statement is written.
- A question arises only when an unaccepted statement is newer than the latest accepted one for that taxon. Accepting a statement closes open questions about the same taxon from older papers as history.
- Taxonomy questions don't hold a Source's approval. Name-resolution questions do.
- Today's tree becomes undated legacy statements at cutover, so the backscan can correct it.
- The tree tables stay what every page reads. They are rewritten from the slot winners in the same transaction, and a rebuild-and-compare check guards them.
- An accepted split asks, per Gall, which daughter induces it. An accepted lump moves B's Galls to A.
- Tree edits in the admin are credited to the Source they follow ("Based on which Source?").
- Plants are the exception: their taxonomy is editorial.

**Generation groups:** a generation is a stage of the Inducer's life cycle that induces a clearly different Gall. Groups of values (heterogony, seasonal, rust stages, aphid life cycle) are a system list mapped to taxa. The Inducer's nearest mapped ancestor decides which groups apply to a Gall.

**Scale is not a risk.** About 4×10³ Galls × ~90 Facts each ≈ 3.6×10⁵ Facts, and 6–7×10⁵ attributions. Realistically ~10⁶ rows, with a generous ceiling of ~10⁷.

**Outside scope:** plant taxonomy as a field of work, Relationships not tied to a Gall, owning Observations, and a phylogeny view.

## When the plan is done

Production runs on the new back-end and the old system is retired:

- **Every existing Source has been processed** into the production copy on preview and approved or denied by curators.
- **The Gallformers notes have been processed before release.** The notes plan says how:
  - undescribed Galls keep their current-data Facts and their notes as text;
  - described notes' patterned statements are handled by code;
  - the judgement minority goes to a chunked LLM or to a curator.

  That plan has to be reconciled with the edit model first. The edit model makes ID notes editorial records on the Gall, and processes old notes into Gallformers changes that carry the notes' own dates.
- **The cutover has been rehearsed until boring** (timing, the replay log for every decision kind, rollback). Production has been cut over in a maintenance window, the verification suite passes against production, and `taxogall` is merged to `main`.
- **After release:** the old tables and `species_id` columns are dropped. The domain docs, `CLAUDE.md` and runbooks describe the new model. Records left with no Facts have been reviewed for removal.

**Success criteria** (2026-10-06):

- ID-tool parity with today on a sample of real queries. The expected differences are Hosts' introduced ranges, and every Gall's range now being its Hosts' whole WCVP range.
- 100% Fact–Source coverage: every Fact comes from a Source's batch, or from Gallformers data for what no Source holds.
- Jeff's judgement that old vs new looks similar, with much better data.
- Trial metrics: agreement with the database, error attribution, quote verification rate, cost per Source.

## Why this order

- **Review cleanup, Housekeeping, Import at scale, Preview environment and Migration data** need nothing and can run side by side now.
- **Edit model: back end comes after Review cleanup.** The edit model moves review decisions onto Source packages: a review decision that changes the tree becomes that Source's statement. So it builds on the review's cleaned-up decision code (one decision shape, one carry-out).
- **Edit model: one editor comes after the back end** (Jeff, 2026-11-07). The edit framework comes first, then the five editors are rebuilt onto it. Once the editor is settled comes the full system audit for sub-agent messes and design-system violations.
- **Gallformers notes come after the edit model's back end.** The edit model decided that ID notes are editorial, and that old notes are processed into Gallformers changes carrying the notes' own dates. That needs the package model first.
- **Process Sources on preview** comes after three phases:
  - **the edit model's back end:** decisions made on preview reach production through preview's replay log, so they must be recorded the way the final model records them;
  - **Import at scale:** about $9 a Source today, over ~927 Sources;
  - **the Preview environment:** Sources are processed into a production copy on preview, which needs its own Postgres with WCVP.
- **Rehearse and cut over** needs everything that changes what reaches production: the leftovers and merging main (Housekeeping), the settled editor and the audit, the processed notes, the processed Sources, and the migration's data fixes. Release is sequenced with the backscan, and the notes are processed before release.
- **After release** waits for the cutover. The old tables stay until then, because the catalog migration reads them.

## After release (scope)

- Drop the old tables (the `species`-centric model) and the `species_id` columns on `image` and `host_range`. Audit the `source` table with Carbonite.
- Replace `docs/domain/general.md` and `docs/domain/admin-domain-reference.md`. Update `CLAUDE.md` and the runbooks that assume the old tables (e.g. `runbooks/restore-deleted-gall.md`).
- Review records left with no Facts for removal, old genus-level Hosts included, once most Sources are processed. Fix wrong Host ranges on the Host.
- Deferred features: search and the API over Source terms, and the PDF page view.
- Follow-on work outside this plan: public taxon pages for non-plant taxa, the Gall merge workflow, iNat taxon IDs, phenology, data completeness scoring, notifications, interoperability (Darwin Core, GBIF, Wikidata), DNA barcodes, iNat integration, GallOnt trait vocabulary, a host-family filter, API v2 parity, a mobile-first ID tool, and out-of-range records as Host-range proposals.

## Open design questions (intent)

- **Scope of the curated taxonomy:** all Gall Community members (Inducers, Inquilines, Parasitoids, …) or a narrower set?
- **Traits that vary by Host:** the domain doc leans no, but this needs a definitive answer.
- **Notes:** do undescribed notes' "observed in…" become occurrence Facts? Are the judgement notes handled by an LLM or by a curator? Does a note's taxonomic position become a Gallformers taxonomic Fact?
- **Taxonomy API:** learn from prior art (iNaturalist's curation of swaps, splits and merges) before finalizing it. Not urgent.
- **The Fact inspector:** should every Fact edit begin and end in the inspector, with the main view as presentation?

Sources: matters 50ff ('The picture', 'Order to release', 'After release', 'Open'), 8567, f923, d3b0, b5bd (M0, M5–M7).
