---
status: raw
created: 2026-11-04
updated: 2026-11-09
epic: taxogall
relates: [bc0d]
---

# Review flow after first live use: ergonomics, new Hosts, density, Facts preview

Jeff's notes after using the review pages live (2026-11-04), on the d213 build:

1. **Ergonomics.** Approving a Host mapping takes three clicks (open the row, pick the option, Decide). The flow through each item should be smooth: the information the curator needs visible, nothing else distracting, the options clear and up front, minimal clicking to decide and move on to the next item.
2. **A Host neither Gallformers nor WCVP holds.** InfluentialPoints 2026's "Rubus villosus var. frondosus" is really Rubus frondosus, which is in neither Gallformers nor WCVP (yet). Today the only options are to map to an existing plant or leave the Host out. Needs a way to create a new Host; a link to the Host creation page (`/admin/taxonomy/new`) opening in a new tab may be enough. To discuss.
3. **Layout and density.** Seen live, the screens need another pass on layout, information density and flow, beyond the mockups.
4. **A Facts preview.** A page showing every change the Source would make (its Facts), separate from the questions; an optional step before approval, but a curator can't be confident in the data without at least glancing at it. It must allow edits. Example: the InfluentialPoints Aphis rubifolii Source maps the whole genus Rubus as a Host of Aphis rubifolii's Gall; that may or may not be right, and today it can't be seen before approving. Design to discuss.

Facts: no dry run of a package's Facts exists today; apply runs in a transaction (ApplyGall/ApplyTaxonomy), so a preview could run apply in a rolled-back transaction and collect what it would write. The edit shapes exist for some cases (drop a statement, host_taxon_id, trait categories).


## Decisions (Jeff, 2026-11-04)

- 1 (ergonomics) and 3 (layout, density): Jeff is gathering concrete ideas and will come back; both probably need design-system updates, which are welcome.
- 2 (a Host in neither Gallformers nor WCVP): a "Create a new plant ↗" link on Host questions, opening `/admin/taxonomy/new` in a new tab, prefilled with the name (and genus); the question's plant search then finds the new plant. Enough for now.
- 4 (Facts page):
  - Grouped by Gall, then each Gall's Facts by category (Inducer, Hosts, Traits, range, description…); information-dense. New styles in the design system are fine.
  - Always accessible and obvious (in the step bar and on the overview); looking at it is optional.
  - It shows what applying would write given the answers so far, and changes as questions are answered (a dry run of the apply with the current decisions).
  - It says when the Source is not ready for approval because questions are outstanding, and shows what waits on them.
  - Edits, starting simple: drop a Fact; change a Host; change a Trait's value; a note. Jeff will see what more he needs as he works with it.
  - Marks each Fact new, already held by Gallformers, or in conflict with what Gallformers holds.


## The Source's Facts after approval (Jeff, 2026-11-04)

- The public Source page keeps what it shows now and gains a view very like the Facts page: the Source's Facts, grouped by Gall then by category. Read-only.
- An admin page that edits a Source's applied Facts is debatable, but seems needed to correct errors made in the original ingestion. Proposed semantics: a correction is not an edit of the Fact itself (a Fact can hold several Sources' attributions); the curator withdraws the Source's attribution where the Source didn't say it, and asserts what it did say, both audited and replayed. To settle with Jeff.
- One Facts view component, three uses: the pre-approval preview (editable), the public Source page (applied Facts, read-only), the admin Source page (applied Facts, corrections). The data shape for a Source's applied Facts should match the preview's.

- Agreed (Jeff, 2026-11-04): corrections withdraw the Source's attribution where it didn't say it and assert what it did say, never editing a Fact shared by other Sources. Order: the review Facts page (preview, editable) and the public read-only Source Facts view first; the admin corrections page after Jeff has used the review Facts page for a while.


## Review queue and the Sources list (Jeff, 2026-11-04)

The review pages (`/admin/review`) are a special place for ingestions in progress, but their link to the Source as a Source in the system (`/admin/sources`, the public `/sources/:id`) is tenuous. Each Source needs an ingestion/update date, shown on the admin Sources list and on the public Source page.

Data today: batches record `applied_at`; packages have no applied date of their own; legacy Sources (carried over from the old data) have no ingestion record at all.

Proposal (to settle with Jeff):
- Two dates per Source, derived, not typed: **Ingested** (when its first package was applied) and **Updated** (its latest applied package, or a curator correction to its Facts). Legacy Sources say "From the original Gallformers data".
- The admin Sources list gains: Ingested, Updated, and a status column linking to review when a package is in progress ("Being reviewed: 12 questions left").
- The admin Source page links to its review pages, and the review pages link back to the Source.
- The public Source page shows "Added to Gallformers <date> · updated <date>".

- Settled (Jeff, 2026-11-04): "Updated" reflects when the Source's data was last edited, a curator correction included. Sources from the old data show a placeholder, not a date.


## Build status (2026-11-04)

- Done: "Create a new plant ↗" on Host questions (prefilled New Taxon page in a new tab); Source dates (Ingested / Updated, placeholder for old data) on the admin Sources list, admin Source page and public Source page, with review ↔ Source links; review pages titled once, in the layout's title bar (breadcrumb there).
- Done: Facts preview back end — `Import.preview_package/2` (approval's apply in a rolled-back transaction; Facts grouped by Gall then category, each new / held / conflict / waiting / dropped; readiness and what holds it), fact edits (drop, Host, Trait values, note; table `package_statement_edits`, replayed, undoable), `facts_for_source/1` in the same shape. 0.25–1 s per preview on the real packages.
- In progress: the review Facts page and the public Source page's read-only "What this Source says".
- Deleted (Jeff OK, 2026-11-04): 62 orphan folders in tmp/private_storage/gallformers-private/sources/935–996 left by preview runs before a fix.

- Done (2026-11-04): the review Facts page (`/admin/review/sources/:id/facts`, also per package): readiness line linking to the steps that hold approval; filter chips (new / held / conflict / waiting / dropped); taxonomy changes, then Galls with their Facts by category in two columns; each Fact a dense row with its status, quote and passage on demand, and edits (drop, Host, values, note) with Undo; recomputed in the background after each edit. "Facts · optional" in the step bar and a link on the overview. The public Source page gains a read-only "What this Source says" in the same component (`facts_components.ex`). Current step label in the step bar fixed (the global link colour beat `text-white`). Precommit clean at 3,260 tests.
- Finding: the genus Rubus Host of Aphis rubifolii's Gall comes from the "Gallformers legacy data" Source (933), not from InfluentialPoints; InfluentialPoints states only species and variety Hosts. The correction belongs to the legacy data (the admin corrections page, later).
- Noise to chase: Postgrex "client exited" errors logged (not failing) in names_step_test and trait_terms_test, from database work outliving the test.


## Other decisions (Jeff, 2026-11-05)

- Genus-level Hosts in the old data: nothing now. Once most Sources are processed, what is left with no Facts gets reviewed for removal.
- Missing authority: plants get authorship from WCVP (we hold the data); Gallformers' own taxa are updated as Sources come in (when a Source gives a species' name and authority, the record is updated).
- Undo of a decided question: instinct is yes, but the hard cases (a change lands, someone changes something related, then an undo) need thought before any design.
- Confirmed: a "lower leaf AND upper leaf" search also finds a leaf-only Gall; in Gall comparisons bud vs stem is a conflict and petiole is not leaf; a passage runs to the next heading.
- Housekeeping: drop the unused `vocab_requests` table (after Jeff's design-system work lands, to avoid clashing with it). Recorded, not now: the API and site search don't use Source terms; the PDF page view.

- Undo rule (Jeff, 2026-11-05: acceptable): Undo of a decided question is allowed only while nothing depends on it: the Source isn't approved yet, and nothing the decision changed (a synonym added, a plant created, a name split) has been edited since, per the audit log. Otherwise Undo says why ("… was edited by … since") and points to the taxonomy admin. Not yet built.


## Built 2026-11-07

- **Undo of a decided question** (`Import.Undo`, `undo_decision/2`; merge `c028806e`, refined in `90a55ef0`): allowed while the Source isn't approved and nothing the decision changed has been changed since (Carbonite); otherwise says who changed what and when, linking to the taxonomy admin or the Gall. Reverses what the decision did (synonym or plant added, name split or moved, sense synonym, kept trait words, rename, split answer — exactly what it moved — taxonomy acceptance or decline via reopen) and reopens the item with its notes; replay kind `:queue_decision_undone`. Refused: accepted splits, lumps, questions closed as history, trait-term decisions that changed the vocabulary, decisions made before decisions recorded their tree edits. Any admin may undo anyone's decision.
- **Admin corrections page** (`/admin/sources/:id`, `Import.SourceCorrections`; merge `f70efdce`): the Source's applied Facts with Correct ▾ (withdraw; change Host, Trait value, parent, accepted taxon) and a required note; never edits a Fact; a corrected taxonomic statement awaits a curator unless "Accept it now"; corrections listed, move Updated, replay. Sources over 300 gall Facts (the legacy data, ~44,000) are corrected one Gall at a time via a search. Shares `fact_editor` with the review Facts page.
- **WCVP authorship for plants** (`Ranges.WcvpAuthorship`; merge `f035ecc0`): fills blank plant name authorship from WCVP (linked record, else unique name+rank, narrowed by synonymy; ambiguous left blank and listed); in the catalog migration, `mix gallformers.wcvp.authorship`, `Release.backfill_wcvp_authorship/0`; follows WCVP relinks; shown on plant pages; editable in plant Edit mode.
