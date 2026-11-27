# Taxogall

Gallformers today treats everything as a species. Taxogall replaces that with Galls, Facts and Sources, built in place on the `taxogall` branch, and cuts production over to it. This doc is the high-level plan: goals, settled decisions, and the child plans with what each needs and where it stands. Each child plan gets its own doc in this folder when it's next, not before (Jeff, 2026-11-26: mull's detail was "nuts and way too detailed to be useful").

## Goals

- **Document gall communities.** The Gall is the hub: typed Relationships to its Inducer, Host, Inquilines, Parasitoids and the rest, and to other Galls (alternate generations). The full taxonomy can be expressed, not only down to family. We document galls, not lookalikes (Jeff and Adam to curators, 2026-11-17).
- **Every Fact traces back to its Source** (2026-11-17). Facts are never edited or deleted: a newer Fact overrides an older one, which stays in the record. Gallformers is itself a Source. Errors are corrected with new Facts under the original Source's authority.
- **Curation is review.** An LLM reads a Source into a data package, code imports and validates it, and a curator reviews it, settles conflicts and applies it. Nothing changes on the site until a curator applies it. Humans stay responsible for what goes in (2026-11-17).
- **Tools for curators:** taxonomy imported inline from POWO/WCVP and iNaturalist; iNaturalist observations imported for photos and Facts; one place to edit each piece of data, as close as possible to its public view; edits held in a change set until the curator is done, one set spanning any part of the data (2026-11-17; how it works on `taxogall` today).
- **A self-curating system is the long-term goal** (Jeff, 2026-11-15): curation detects anomalies, proposes fixes and asks a human to approve. When a decision is close, choose the option that moves toward that.
- **One source of truth** (Jeff, 2026-11-15): each thing is written in one place and pointed to from everywhere else.

Done when:

- Production runs on the new back-end, and the old system is retired.
- Every existing Source has been dealt with as decided (below), and the Sources to be processed have been processed on preview and approved or denied by curators.
- The Gallformers notes have been handled, before release.
- Public taxon pages for non-plant taxa, the Gall merge workflow and iNat taxon IDs are done before release (Jeff, 2026-11-15).
- The cutover has been rehearsed until boring (timing, replay, rollback), production has been cut over in a maintenance window, the verification suite passes against production, and `taxogall` is merged to `main`.
- The release gates pass: ID-tool parity with today on a sample of real queries (expected differences: introduced places count only with evidence, Host ranges come from WCVP, Galls gain observed places); 100% Fact–Source coverage; Jeff's judgement that old and new look similar, with much better data; trial metrics (agreement with the database, error attribution, quote verification rate, cost per Source).

## Child plans

| # | Plan | Needs | Status | Doc |
|---|---|---|---|---|
| 0 | House in order: the [cleanup plan](../cleanup/README.md), including the architecture baseline | | In progress | [cleanup](../cleanup/README.md) |
| 1 | Revisit mull's 18 phases: keep, regroup or drop each, and order what's left | 0 | Next | not yet written |

Nothing else is built until the house is in order (Jeff, 2026-11-26). Planning each child plan or phase starts by reading the [backlog](../backlog.md) for entries it should take in (Jeff, 2026-11-26). Step 1 reads each of mull's phases in detail: `git show mull:phases/<id>.md` for its title, intent and needs, `git show mull:docs/phases/<id>.md` for its doc, and its items with `git grep -l "phase: <id>" mull -- items/`. Its outcome replaces this table's later rows.

Of mull's *Decisions first* phase, four decisions are settled (below), one analysis is in review (the notes, 5352), and three are open (ranges' screens and curation, the taxonomy API, dating the notes' Facts).

## Build approach

A new back-end, built whole on `taxogall`, replaces the old one in place, with no facade and no dual-write. The back-end changes so much that it is a rewrite, about 80% of today's UI is admin, which the new model replaces anyway, and the public 20% changes little. Old and new never run side by side: there is one rehearsed cutover.

- **New:** the domain core (Galls, taxa, Sources and Facts, import, read models, audit), and ranges and places on PostGIS. **Reused as it is:** auth and users, Oban, S3 storage and images, search infrastructure, maintenance mode and deploy.
- **The UI first** (Jeff, 2026-11-14): the whole UI is accounted for against what Gallformers needs, and what's missing is built early against the back-end interfaces, stubbed where they don't exist yet. Jeff judges the plan's completeness by using the screens.
- **Branch drift:** merge `main` into `taxogall` regularly; production hotfixes land on `main` and flow over.
- **Rejected:** building alongside the old system (a separate Postgres schema, duplicate public pages behind a route flip, or empty tables shipped dark to `main`), which doubles every public page and puts schema churn into production migrations.

## Settled decisions (do not reopen)

The domain language (Gall, Source, Fact, Reading, Correction, Relationship, newer work wins, the curator gate on taxonomy) is in [domain-model.md](../domain/domain-model.md) and isn't repeated here. Where that doc is behind the decisions below (Host ranges, observed range, Traits by Host), the decisions stand; the doc is updated and organised into the doc set in the cleanup plan.

**One write path** (Jeff, 2026-11-12):

- For any data, exactly two ways in: one editing screen in the UI, and the import. Both call the same code to validate, write and read it.
- A curator's edit is an ingestion: a small package under the Gallformers Source, through the same code path and rules as a paper's import. Edits collect in the curator's change set and apply when the curator applies it (`Gallformers.Curation`).
- Manual editing is either correcting how an accepted Source was read, under that Source's authority and at its date, or a change under Gallformers' authority. A Gallformers curator can do anything under the Gallformers Source, including changing a Gall's Inducer, generation and descriptions, creating a Gall, and setting a range to "only here".
- Replay is mechanical: every write goes through its one path, so replay re-applies the same writes in order, with no per-kind replay code.

**Audit** is a layer underneath everything else: the database records every insert, update and delete on a tracked table (Carbonite triggers) against the transaction's actor, and refuses a write that names no actor. Code only names who is acting. Attribution (whose authority) is separate from audit (who changed it).

**Two systems** (Adam and Jeff, 2026-10-03/04): a taxonomy system (taxa, names, authorship, rank, placement, synonymy, taxonomic acts and their history) and a gall system (Galls, Traits, Relationships, ranges, gall aliases). They share Sources and Facts, history, audit and import, and are black boxes behind Phoenix contexts enforced by `boundary`. The contract between them is stable taxon IDs at any rank; nothing else crosses. Hot reads across the boundary go through published read models; writes that span it compose into one transaction.

- **Plants** (Jeff, 2026-11-16): Gallformers is not an authority on plants. Plant names, synonymy, placement, common names and Host ranges are Facts from POWO/WCVP or iNaturalist, in the same taxonomy structure; a curator's correction is a Gallformers statement.
- **Taxon origin:** *curated* (the whole Gall Community and the rare gall-forming plant; Jeff, 2026-11-15) or *imported* (plants, from POWO/WCVP or iNaturalist; iNaturalist also backs non-plant higher taxa).
- **Isolation:** taxonomy knows nothing about Galls; the gall system knows taxa only by ID and through the taxonomy API. The UI may hide the separation.
- **IDs:** one shared sequence for Galls and all taxa, continuing today's species sequence. Galls keep their IDs (`/gall/:id`), plants theirs (`/host/:id`), because image paths are keyed by them; Inducers and higher taxa get new IDs, with a crosswalk for the old higher-taxon IDs.
- **Taxonomic acts** (rename, move, merge, split) are sourced and keep history. Taxonomy calls registered "taxon changed" listeners inside its own transaction, and the change fails if the gall side can't accept it. The exception is Gall names: a rename that follows from a taxonomy change is a proposal a curator reviews. An accepted split asks, per Gall, which daughter induces it; an accepted lump moves the Galls.
- **Relationships** belong to the gall system, and every Relationship happens in a Gall. Their types are a fixed system list (15 kinds). Hyperparasitism is derived, not stored. Alternate generations are explicit, and mismatches are flagged.
- **Traits belong to the Gall** and never vary by Host (Jeff, 2026-11-15).
- **Gall names** are derived from the Inducer plus name parts stored on the Gall (form, generation, Host), overridable and unique; undescribed Galls use a stored descriptor.
- **Generations:** groups of values (heterogony, seasonal, rust stages, aphid life cycle) are a system list mapped to taxa; the Inducer's nearest mapped ancestor decides which apply.

**Sources and Facts**, beyond the domain doc:

- Standings: current, withdrawn, superseded, retracted, unsupported (hidden). Same-date conflicts go to a curator.
- Each Fact kind has a natural key. An attribution carries its stance, quote and page hint, `name_as_written` for each taxon the Source names, cited Observations, and statement text. Sources never reference each other formally. Delete is only for data added by mistake or in testing.
- **Two Gallformers Sources** (Jeff, 2026-11-14): *Gallformers legacy data* holds the old site's data and is undated, so every dated statement overrides it, and a Fact supported only by it shows as unconfirmed. *Gallformers* holds the curators' own statements, each timestamped by its change.
- Today's taxonomy tree comes in as Gallformers legacy data. The tree tables stay what every page reads, rewritten from the accepted statements in the same transaction and guarded by a rebuild-and-compare check.

**What is a Fact** (Jeff, 2026-11-16; d178): plant taxonomy, Host ranges, generation and abundance are Facts. A Gall's name parts, ID notes, photos and the Gallformers code (on undescribed Galls only) are editorial, as are keys, articles, the glossary and users. The data-complete flags, a Gall's lead Source, and curator notes on Facts and taxa are dropped.

**Ranges** (Jeff, 2026-11-16):

- Places: ISO places, TDWG regions and named areas, with PostGIS boundaries; any place resolves to the leaf places it covers.
- Host ranges are Facts on the plant (native or introduced), WCVP's in its own regions.
- A Gall's predicted range is its Hosts' native range, narrowed by its *only within* and *absent from* Facts; an introduced region counts only with evidence. Its observed range is occurrence Facts: a point (with uncertainty, date and cited observation) or a place.
- The ID tool and place pages use both and say why a Gall matched. An observed place counts even while it conflicts with a restriction; the conflict goes to a curator.
- No Gall without a range: every Gall has a Host, and every Host a range.

**The old site's data** (Jeff, 2026-11-12 and 11-15):

- All of it comes over as Gallformers legacy data: its Facts as packages through the same import path as any paper; what isn't a Fact (Gall skeletons, plants and their ranges, Source records, keys) copied directly, each kind through its one writer. The curated places in a Host's introduced range become legacy occurrence Facts (Jeff, 2026-11-16). The old season tags are dropped.
- The old notes are sorted by deterministic, repeatable code, never imported blindly. Undescribed-Gall notes are processed as Sources; pure ID notes become the Gall's ID Notes field, attached to no Source.

**The existing Sources** (Jeff, 2026-11-17; 7a50): reprocess the scans, open, paywalled and website Sources (websites one cited page at a time), with a lookup pass for links that aren't the document; Gagné 2026 instead of 1989; Russo 2021 from an author PDF, with its excerpts as fallback; other copyright books stay as Sources with legacy citations until a manual-entry UI after release; drop the uncited Sources but one kept for its photos; merge the duplicates; replace the Sci-Hub links; keep excerpts, hidden per Gall once its package is approved; photos keep their credit.

**Getting a Source in** (Jeff, 2026-11-17 to 11-21; 274b): curators collect, verify and convert documents on today's production site, so other curators can help now; conversion runs on a Fly Sprite. Jeff and Adam run the LLM stages locally on their own subscriptions against preview. Each stage writes once to the Source's folder in the shared private bucket, through signed URLs. The import contract is in `priv/import/` and [the producer guide's background](../import/producer-guide-background.md); the procedure is [source-intake.md](../../runbooks/source-intake.md).

**The old public API** (Jeff, 2026-11-16; 3c4f): it has real users, so it's kept and released as `/api/v3` (3.0.0), with `/api/v2` returning 410 at release.

**Cutover** (Jeff, 2026-11-12): real data is built on preview, then in production, never on a developer's machine. Sources are processed into a migrated production copy on preview. At cutover, production is migrated fresh and preview's work replayed onto it, so the live site stays editable meanwhile. Replay is rehearsed early onto a separate database, and the cutover until boring. Merging `taxogall` into `main` deploys at once, so the runbook guards against an accidental merge or deploy. The old tables stay until then, because the migration reads them.

**Scale isn't a risk:** about 10⁶ rows of Facts and attributions, with a generous ceiling of 10⁷.

## Open design work

Each is settled before the work that depends on it; the phase revisit places them.

- The full UI accounting.
- A Gallformers overview: how it works, for curators, developers and agents, and how it differs from the old site.
- Ranges: the screens and curation (7128).
- The taxonomy API, in its own design session, learning from prior art such as iNaturalist's swaps, splits and merges (Jeff, 2026-11-15; de26).
- One shared understanding of how editing works (Jeff, 2026-11-15: probably not every edit through the Fact inspector).
- The Gallformers notes: the categories (5352's analysis, in review) and how to date the Facts from undescribed-Gall notes (76f1).
- Audit: confirm the layer is complete. The Source records and Host ranges aren't tracked today.
- Plants: whether the curator gate applies to POWO/WCVP statements, and how a database Source's releases are dated.
- Mull's 22 unsettled inbox entries go to Jeff, into this plan, or are dropped in [cleanup step 8](../cleanup/README.md).

## After release, and out of scope

After release: drop the old `species`-centric tables, `image.species_id` and `host_range`, and track the Source records in the audit layer; replace the old-model domain docs and the runbooks that assume the old tables; review records left with no Facts for removal, old genus-level Hosts included; a manual-entry UI for copyright books; search and the API over Source terms; the PDF page view.

Outside this plan: plant taxonomy as a field of work, Relationships not tied to a Gall, owning Observations, a phylogeny view. Follow-on ideas (phenology, data completeness, notifications, Darwin Core/GBIF/Wikidata, DNA barcodes, deeper iNat integration, GallOnt traits, a host-family filter, a mobile-first ID tool) go in the [backlog](../backlog.md) when they're live.

## Other docs

- [Domain model](../domain/domain-model.md): the domain language.
- [What we told curators, 2026-11-17](../presentations/2026-11-reboot-summary.md).
- [Architecture](../architecture/README.md): the system as built on `taxogall`, with its [rules](../architecture/rules.md), [decisions](../architecture/decisions.md) and [reviews](../architecture/reviews.md).
- [Cleanup](../cleanup/README.md): getting planning, docs and branches in order first.
- [Backlog](../backlog.md): work that belongs to no plan.
- Mull's plan, for history: `git show mull:docs/plans/taxogall.md`.
