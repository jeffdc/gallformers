---
status: raw
created: 2026-10-24
updated: 2026-11-06
epic: taxonomy
relates: [8567, 9449, 3272, 803b, a856, 2c8c, d213, f14c, 20e5, bc0d]
---

# Taxogall: program overview and punchlist

The top-level matter for **taxogall**: what we're building, what's done, and the order to release. Read this first; follow a link only for detail.

## The picture

Gallformers today treats everything as a species. Taxogall replaces that, in place, on the `taxogall` branch:

- **Galls** are catalog entries (two generations are two Galls). Everything known about them — Hosts and other relationships, Traits, range, recorded occurrences, common names, descriptions — is a **Fact**, attributed to the Sources that confirm or deny it. Gallformers is a Source too.
- **Taxonomy is Facts too** (Jeff, 2026-11-06): names, authorship, placements, synonymies, ranks and splits are Facts credited to the Sources that make them (Gallformers only as a rare exception; `f923`); the tree is whatever the current taxonomic Facts say. Editorial, not Facts: Gall naming (derived names, `86e7`) and plant data (names, synonymy, ranges; WCVP to ease input, curators edit freely; not a system of record for plants).
- **Every change goes through one Fact process:** Sources arrive as LLM-produced packages against a validated contract (`priv/import/`), curators settle questions and approve; Gallformers' own edits use the same process. Decisions are logged and replayed at cutover.
- **The pipeline is the migration** for everything that lives in Sources: existing Sources are re-processed into the new model before release.

Key references: domain language `docs/domain/domain-model.md`; design and rules `8567`; back-end schema `9449`; migration plan (M0–M8) `b5bd`; import contract `294c` + `priv/import/` + `docs/import/producer-guide-background.md`.

## Done (all committed on `taxogall`, not merged)

- **Import contract and producer** (`294c`): JSON schemas, validator (Python and Elixir), producer and checker guides, the `services/import-producer` pipeline (phases 2–6), golden regression set of five Sources. Contract now carries common-name Hosts, hedge topics, one-sentence dispute positions.
- **New back-end, phase 1** (`9449`): Sources–Facts with standing, audit (Carbonite), taxonomy storage (tree editorial in phase 1; Sources' taxonomic acts already recorded as Facts), gall system, importer (Oban, private bucket, Host names before the gall batch, replay log), data migration rehearsed on a production copy.
- **Public pages and API on the new back-end** (`803b`), and the derived Gall names (`86e7`).
- **Admin, review and vocabulary** (`a856`, `6611`, `d213`, `f14c`): Source review by steps (Names, Galls, Disputes, Traits, Hedges) with a step bar and Approve; questions with recommendations, follow-ups and notes; the Source's passage and full text beside the questions; trait vocabulary in the database (`leaf` a real value; terms under one or several values; agreement rules); Gall comparison with conflicts; common-name Hosts with sections; synonym split/move; grouped disputes; a **Facts page** previewing what approval writes, with edits; Source ingested/updated dates; public Source page lists the Source's Facts; taxonomy admin, Gall page and Source editor.
- **Trial data:** five Sources re-run with the current guides ($44.86) and delivered locally; 10 trial notes.

## Order to release (Jeff, 2026-11-06)

1. **a) How the admin works** — Jeff and Claude. Gallformers curation (`ec2c`): every edit through the intake's Fact process (taxonomy credited to the Source it follows); inline edits on the pages, a ⌘K command palette for everyone, and making edits from a pasted iNat observation (typed prose commands held). Also open in `f14c`: fewer clicks per decision, layout and density. Status (2026-11-06): palette and changes built (design-system worktree); the change-set back end built on taxogall (`Gallformers.Curation`, interface in ec2c); Edit mode and the tray UI next, in the design-system worktree.
   **b) Design system** — Jeff with another agent, applied to the app (`bc0d`); runs in parallel.
2. **Merge the two branches.** Done 2026-11-06 (`e078704f`): the design system, Edit mode on the Gall page and the tray are on taxogall; one agent again. Remaining UI items: bc0d "Handoff" / "Handoff update" and ec2c.
3. **Phase 2 (`f923`) and the remaining gaps,** in the new design system. Status 2026-11-07: phase 2 Tasks 1–10 built and merged; the species page built (`803b`); curation findings fixed (`ec2c`); design components built (`bc0d`). Also built 2026-11-07: Undo of a decided question, the admin corrections page for a Source's applied Facts, WCVP authorship for plants (merges `c028806e`, `f70efdce`, `f035ecc0`; cleanup `90a55ef0`). Step 3's gaps are done; next are Jeff's review of the build, f14c ergonomics, then step 4 (notes).
   - Phase 2: placements, accepted names and synonymies drive the tree from current Facts (`8567`). Today's direct tree edits become Facts credited to the Source the curator follows (`f923`): the taxonomy admin's edits, and review decisions that change the tree (split or move a synonym, create a plant or taxon, a Source's name read in its own sense).
   - The admin per 1a; Undo of a decided question (rule agreed, `f14c`); the admin corrections page for a Source's applied Facts (`f14c`); WCVP authorship for plants.
4. **Gallformers notes** (`20e5`, "Current thinking" section): undescribed Galls keep current-data Facts and their notes as text; described notes' patterned statements by code; the judgement minority by chunked LLM or curator; notes split into Facts and commentary.
5. **Process Sources into a copy of production** (Jeff and Adam, on the preview server, `f465`). Before scaling:
   - cost levers (about $9 a Source today; one checker instead of two ≈ −22%; a cheaper model for checking and responding);
   - the missed-names check (names a Source prints that nothing uses; back end built, `Import.UnusedNames`; showing it on the review Source page remains; `d213`);
   - reference answers rebuilt in format 4 from reviewed packages;
   - where the producer runs at scale (subscription, API account, or a server job);
   - curator onboarding: rewrite `docs/domain/admin-onboarding.md`; walk Adam through it.
6. **Cut over and retire the old system** (`b5bd` M5–M6): rehearse until boring, including timing on preview and the replay log (all decision kinds, Fact and term edits, tree edits as Facts); re-run the catalog migration against production data; rollback rehearsal.

**After release** (`b5bd` M7): drop the old tables; replace `docs/domain/general.md` and `admin-domain-reference.md`; update `CLAUDE.md` and runbooks; review items left with no Facts for removal (old genus Hosts included); fix wrong Host ranges on the Host. Deferred features: search and API over Source terms, the PDF page view. Later matters: `1832` taxon pages, `3e8c` gall merges, `e1d2` iNat taxon IDs, `439a` phenology, `7cde` completeness, `4389` notifications, `29dc` interoperability, `1374` DNA barcodes, `8ba0` iNat integration, `eb47` GallOnt, `67c9` host-family filter, `74de` API v2, `32a5` mobile ID, `3272` out-of-range records as Host-range proposals.

## Open

- Scope of the curated taxonomy; Traits that vary by Host (`8567`).
- Notes: whether undescribed notes' "observed in…" become occurrence Facts; the judgement notes by LLM or curator; whether a note's taxonomic position becomes a Gallformers taxonomic Fact (`20e5`).
- Production bugs found along the way (on `main`, fixed on their own branches): `2c8c`.
