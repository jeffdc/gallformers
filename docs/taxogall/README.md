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

The domain's language and its settled rules are in [domain-model.md](../domain/domain-model.md) and aren't repeated here: Galls and their names, taxonomy and the curator gate, plants, taxonomic acts, Sources and Facts (newer work wins, standings, attribution, the two Gallformers Sources, what is a Fact and what is editorial), ranges, Traits and generations, and Relationships. The system as built is in [the architecture docs](../architecture/README.md). This section holds what the work needs beyond them.

**One write path** (Jeff, 2026-11-12; [decision](../architecture/decisions.md#2026-11-12-one-write-path) and rule S5, not yet built in full):

- For any data, exactly two ways in: one editing screen in the UI, and the import. Both call the same code to validate, write and read it.
- A curator's edit is an ingestion: a small package under the Gallformers Source, through the same code path and rules as a paper's import. Edits collect in the curator's change set and apply when the curator applies it (`Gallformers.Curation`).
- Manual editing is either correcting how an accepted Source was read, under that Source's authority and at its date, or a change under Gallformers' authority. A Gallformers curator can do anything under the Gallformers Source, including changing a Gall's Inducer, generation and descriptions, creating a Gall, and setting a range to "only here".
- Replay is mechanical: every write goes through its one path, so replay re-applies the same writes in order, with no per-kind replay code.

**Built, and described in the architecture docs** rather than here: the audit layer, the two systems and their isolation, synchronous change events, the ID sequence and crosswalk, a Fact's identity, and the taxon tree kept in step with the accepted Facts ([decisions](../architecture/decisions.md), [rules](../architecture/rules.md) S4 and S6, [Data](../architecture/README.md#data)). Today's taxonomy tree comes in as Gallformers legacy data.

**Dropped** (Jeff, 2026-11-16; d178): the data-complete flags, a Gall's lead Source, and curator notes on Facts and taxa. What is a Fact and what is editorial is in the domain doc.

**Ranges** (Jeff, 2026-11-16) are in the domain doc. Places get PostGIS boundaries.

**The old site's data** (Jeff, 2026-11-12 and 11-15):

- All of it comes over as Gallformers legacy data: its Facts as packages through the same import path as any paper; what isn't a Fact (Gall skeletons, plants and their ranges, Source records, keys) copied directly, each kind through its one writer. The curated places in a Host's introduced range become legacy occurrence Facts (Jeff, 2026-11-16). The old season tags are dropped.
- The old notes are sorted by deterministic, repeatable code, never imported blindly. Undescribed-Gall notes are processed as Sources; pure ID notes become the Gall's ID Notes field, attached to no Source.

**The existing Sources** (Jeff, 2026-11-17; 7a50): reprocess the scans, open, paywalled and website Sources (websites one cited page at a time), with a lookup pass for links that aren't the document; Gagné 2026 instead of 1989; Russo 2021 from an author PDF, with its excerpts as fallback; other copyright books stay as Sources with legacy citations until a manual-entry UI after release; drop the uncited Sources but one kept for its photos; merge the duplicates; replace the Sci-Hub links; keep excerpts, hidden per Gall once its package is approved; photos keep their credit.

**Getting a Source in** (Jeff, 2026-11-17 to 11-21; 274b; [decision](../architecture/decisions.md#2026-11-22-get-sources-in-through-a-shared-private-bucket-with-conversion-on-a-sprite-and-the-llm-stages-on-curators-machines)): curators collect, verify and convert documents on today's production site, so other curators can help now; conversion runs on a Fly Sprite. Jeff and Adam run the LLM stages locally on their own subscriptions against preview. Each stage writes once to the Source's folder in the shared private bucket, through signed URLs. The import contract is in `priv/import/` and [the producer guide's background](../import/producer-guide-background.md); the procedure is [source-intake.md](../../runbooks/source-intake.md).

**The old public API** (Jeff, 2026-11-16; 3c4f; [decision](../architecture/decisions.md#2026-11-16-keep-the-public-api-released-as-apiv3)): it has real users, so it's kept and released as `/api/v3` (3.0.0), with `/api/v2` returning 410 at release.

**Cutover** (Jeff, 2026-11-12; [decision](../architecture/decisions.md#2026-11-12-build-real-data-on-preview-and-replay-it-onto-production-at-cutover)): real data is built on preview, then in production, never on a developer's machine. Sources are processed into a migrated production copy on preview. At cutover, production is migrated fresh and preview's work replayed onto it, so the live site stays editable meanwhile. Replay is rehearsed early onto a separate database, and the cutover until boring. Merging `taxogall` into `main` deploys at once, so the runbook guards against an accidental merge or deploy. The old tables stay until then, because the migration reads them.

**Scale isn't a risk:** about 10⁶ rows of Facts and attributions, with a generous ceiling of 10⁷.

## Open design work

Each is settled before the work that depends on it; the phase revisit places them.

- The full UI accounting.
- A Gallformers overview: how it works, for curators, developers and agents, and how it differs from the old site. Input, from 1121's 2026-09-30 interview, for Jeff to confirm is still current (cleanup step 9): academics want to trust the data, get new findings in and search deeply ("do we have a gall matching this barcode?", "what facts come from Weld 1956?"); curators want to maintain data without a tedious, error-prone manual process; casual users (identifying a gall, following a link) already have what they need, so don't make it worse.
- Ranges: the screens and curation (7128).
- The taxonomy API, in its own design session, learning from prior art such as iNaturalist's swaps, splits and merges (Jeff, 2026-11-15; de26). What iNaturalist's code shows (the 2026-10-02 taxonomy migration research, read for 1121 and b5bd; folded in cleanup step 9): a split is automated when every daughter has an atlas (its known places), each record going to the daughter whose places it falls in, otherwise to their common ancestor; changes under vascular plants (Tracheophyta) need approval; taxon framework relationships (match, one_to_one, many_to_one, one_to_many, many_to_many, alternate_position, not_external, not_internal) record where iNaturalist departs from an outside authority such as POWO. A plant split or lump reaches every Gall on that plant (Adam, 2026-02-22, in the interview for matter 5c56): a split needs triage, fanning the Galls out to every daughter (marked unverified), substituting one default successor, or assigning them per Gall; a lump lists the affected Galls for review rather than repointing them silently. It reviews the taxonomy rules already built on `taxogall`, which wait for Jeff (Jeff, 2026-11-27, cleanup step 8; each is `git show mull:inbox/<id>.md`, with its context, alternative and code):
  - 0a09: a split question suggests a daughter from shared Hosts, as a suggestion, never bulk-accepted.
  - 894e: a split may keep A among its daughters, in its narrow sense.
  - 7883: a retracted split or lump leaves moved Galls where they are; moving them back is curator work.
  - 6453: lumping B into A declines real Sources' statements about B ("B was merged into A"), kept as history.
  - 3b7f: a revalidated name keeps outranking the old synonymy even after a later rename (the agent's reading, for Jeff to confirm; the alternative is a one-line change).
  - 4575: taxa an import creates have their name and placement accepted as created.
  - da32: a Gallformers taxonomy batch moves the tree without acceptance.
  - e8aa: a paper agreeing with the tree raises no question but stays "awaiting".
  - 91f7: a non-plant's first common name raises a taxonomy question.
  - 7031: the cutover carry-over records no curator on its acceptances.
- One shared understanding of how editing works (Jeff, 2026-11-15: probably not every edit through the Fact inspector). It reviews the curation rules already built, which wait for Jeff (Jeff, 2026-11-27; `git show mull:inbox/<id>.md`):
  - 677c: Undo refuses decisions made before decisions recorded their tree edits, accepted splits, lumps, and Trait-term decisions that changed the vocabulary.
  - 7857: any admin can undo anyone's decision.
  - dd01: a correction to a taxonomic statement awaits a curator unless "Accept it now" is ticked.
- The Gallformers notes: the categories (5352's analysis, in review) and how to date the Facts from undescribed-Gall notes (76f1); and whether the ~200 described-Gall notes that need judgement (synonymy, rulings, hedges) go to an LLM in chunks of 50–100 (about $60–90 for all, a $6–10 trial chunk first, and a change to the note package) or to a curator queue (2ac6).
- Audit: confirm the layer is complete. The Source records and Host ranges aren't tracked today.
- Plants: whether the curator gate applies to POWO/WCVP statements, and how a database Source's releases are dated.
- Vocabulary curation at scale (Jeff, 2026-11-27; 542d, 1878): Jeff and Adam adjudicating every Trait term becomes a logjam as Sources queue up, and impossible once non-English Sources are processed. Settled before Import at scale and processing Sources on preview.

## After release, and out of scope

After release: drop the old `species`-centric tables, `image.species_id` and `host_range`, and track the Source records in the audit layer; delete the old-model domain docs (`general.md`, `admin-domain-reference.md`; Jeff, 2026-11-27: the domain doc replaces them) and update the runbooks that assume the old tables; review records left with no Facts for removal, old genus-level Hosts included; a manual-entry UI for copyright books; search and the API over Source terms; the PDF page view.

Outside this plan: plant taxonomy as a field of work, Relationships not tied to a Gall, owning Observations, a phylogeny view. Follow-on ideas (phenology, data completeness, notifications, Darwin Core/GBIF/Wikidata, DNA barcodes, deeper iNat integration, GallOnt traits, a host-family filter, a mobile-first ID tool) go in the [backlog](../backlog.md) when they're live.

## Other docs

- [Domain model](../domain/domain-model.md): the domain language.
- [What we told curators, 2026-11-17](../presentations/2026-11-reboot-summary.md).
- [Architecture](../architecture/README.md): the system as built on `taxogall`, with its [rules](../architecture/rules.md), [decisions](../architecture/decisions.md) and [reviews](../architecture/reviews.md).
- [Cleanup](../cleanup/README.md): getting planning, docs and branches in order first.
- [Backlog](../backlog.md): work that belongs to no plan.
- Mull's plan, for history: `git show mull:docs/plans/taxogall.md`.
