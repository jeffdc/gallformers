---
status: raw
created: 2026-11-06
updated: 2026-11-06
epic: taxonomy
---

# Admin edit model: every Fact edit through Source ingestion

# Admin edit model: every Fact edit through Source ingestion

Jeff's direction (2026-11-06), from the admin dashboard work (bc0d). Relates to a856 (minimal admin on the new back-end), 6611 (Source-down review), 8567, bc0d. Replaces bc0d's open "save model" question for the admin.

## The rule

- **Every create, update and delete of a Fact happens only through Source ingestion.** A curator's own edit, outside any third-party Source, is ingested under the **Gallformers Source**. There is no other path that changes a Fact.
- **The edit UI will therefore be radically different from today's forms.** Where a UI still helps a curator, it produces the same thing the intake process does (Facts attributed to a Source, reviewed the same way), not a direct write.

## Two kinds of edit

1. **Tied to Facts:** taxonomy, galls, species, hosts, ranges, traits, and so on. Changed only through ingestion (a third-party Source or the Gallformers Source).
2. **Not tied to Facts:** glossary, articles, keys, vocabulary, users, site settings. These keep direct editing UIs (forms on the design system).

## Open: what and how

- Which Fact-tied edits warrant a helper UI (one that writes ingestion input rather than rows), and what it looks like.
- How a curator's Gallformers-Source edit flows: does it make a package that goes through the same review, or is a curator's own edit applied as reviewed?
- What happens to today's direct Fact-editing screens (taxonomy admin, Gall page edits, host ranges, images? Images may be the second kind).

## Consequence for the dashboard (bc0d)

The dashboard leads with the Source review queue, and below it shows recent changes with named curators. Those come from the audit trail, which records every write with its actor.


## Catching mistakes: from seeing to correcting (Jeff, 2026-11-06)

Curators question Facts recorded from a Source, by themselves or anyone. The journey:
1. **Notice the issue**, on the admin Changes page or on a public page.
2. (Optional) **Look into it** if unsure; mostly outside the app.
3. **Make the change through the normal edit process.** Fact history is append-only, so nothing is lost.

The app's job is the quick path from step 1 to step 3. Each Fact on the Changes page links out to two things: **View**, the public page where it shows (its Gall's page; a taxon's own page), and **Edit**, the edit process for that Fact (a placeholder until it exists: the Gall's admin page). Admins get the same Edit from public pages. **No flag / discuss / resolve feature and no copy-link**: the team is small and talks on Discord.

- **Changes page** (admin): every curator change from the audit trail, grouped (consecutive changes by the same curator, of the same kind, on the same Source), rich (Galls named and linked; each Fact in words: "host: Rubus ellipticus", "range exclude: Europe", "recorded in Illinois"; added / made current / superseded / withdrawn), searchable (Gall, taxon, Source or value; curator; kind; period). Import re-checks are left out. The dashboard shows the latest few under the review queue.
- **Digest** (future): an email digest of changes curators read and click through to correct.
- Built, the read is an `Audit` read model over Carbonite (transactions + changes + the Fact tables for wording). Mockup: `dev/.../mockups/changes_read.ex`.


## What exists today (research, 2026-11-06)

- **An in-app ingestion path already exists.** `Import.submit_gallformers_fragment/2` (import.ex ~2294) builds a Gallformers package (key `gallformers-<uuid>`). It skips the `review.json` gate, auto-approves when nothing is open, and applies like any package (Diff → `Catalog.assert_*`, one `Audit.transaction` per batch). Range exclusions on the admin Gall page already use it (a856 decision 6). There is no general UI for it.
- **Statements:** gall Facts `relationship | qualifier | trait | range | occurrence | alias | description`, each with stance confirm/deny and evidence (`priv/import/schema/gall.schema.json`). Taxonomy acts `name | placement | synonymy | split | common_name`.
- **Standing:** the newest `stated_on` decides; confirm → current, deny → withdrawn; a newer confirm in the same slot supersedes the others; no attributions → unsupported. A Gallformers attribution requires `statement_text` (a reason). An older Gallformers statement doesn't replace a newer one.
- **History caveat:** one attribution per Fact × Source. A later Gallformers statement on the same Fact *updates* that attribution, so the earlier Gallformers statement survives only in the audit trail (Carbonite), not as its own row.
- **Fact writes outside a package today** (would break the rule):
  - Vocabulary: moving or placing a term moves or writes Trait attributions (`Catalog.move_term_attributions`, `Import.place_term`).
  - Accepted Gall renames: assert a `former_label` alias Fact under Gallformers directly (`GallRenames.rename`).
- **Not Facts today (direct, audited):**
  - the taxonomy tree (names, placement, synonyms, common names: an editorial tree, with acts recorded only on import, `taxa.ex`);
  - plant host ranges (`host_range` table, WCVP);
  - Gall editorial columns (code, abundance, datacomplete, default Source) and name parts;
  - the Gallformers note (a document; nothing re-extracts it yet).
- **Not audited:** images (and iNat image import), glossary, articles, keys, content images.
- **Earlier decisions to reconcile:**
  - 8567 rule 12: "every write is a batch"; curator notes can become Gallformers batches via an LLM.
  - 20e5: a note edit is re-extracted, dated by the edit; curator intake is still undesigned.
  - 6611: curator intake should "feel like the same tool"; open: one package per note, and who approves.
  - 86e7: name-part edits apply directly ("they are the review").
  - e381: after import, corrections are newer Gallformers statements.


## Likely direction (Jeff, 2026-11-06)

Jeff is settling the admin edit model in a separate session. The likely decision: **inline edits on the main (public) data pages**, eliminating almost all admin pages. If so, Edit on the Changes page lands on the public page's inline editor, and View and Edit may become the same destination. The dashboard/Changes build (bc0d) waits for that decision.

