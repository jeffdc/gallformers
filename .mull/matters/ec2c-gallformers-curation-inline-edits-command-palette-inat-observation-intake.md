---
status: raw
created: 2026-11-06
updated: 2026-11-09
epic: taxogall
---

# Gallformers curation: inline edits, command palette, iNat observation intake

How Gallformers curation works once the system is live (50ff step 1a): Gallformers' own statements of Fact, made by curators. Not how the current notes get in (that's 20e5).

## Invariant (Jeff, 2026-11-06)

Every Gallformers edit goes through the same Fact process as Source intake: statements credited to the Gallformers Source → resolve names → questions where ambiguous → preview of the Facts it changes → apply (audited, replayed). Taxonomy included: placements, names, synonymies of non-plant taxa are Facts (8567, 2026-11-06), credited to the Source the curator follows, not to Gallformers (a Gallformers taxonomic statement is a rare exception; f923); editorial, not Facts: Gall naming and plant data. The UI may differ from intake; the back end may not.

Core to build once: a **change set** — a small Gallformers batch (statements, evidence, author) that is drafted, resolved, previewed with the Facts view, and applied. Front ends fill it.

## Decided (Jeff, 2026-11-06)
- **Inline edits on the pages, not bespoke edit screens.** A curator turns on **Edit** on a page; off, it's the public page as anyone sees it. On, each Fact gets its actions (withdraw, correct, note) and each category an "add" with the existing pickers. One page serves visitors and curators.
- **Change tray.** Edits collect in a tray that follows the curator across pages ("3 changes … Review and apply"). Review opens the Facts preview for just those changes (new / already held / in conflict). Evidence is asked once per change set: an observation, a Source, or "my judgement" with a reason. A single obvious edit can be applied straight from the tray.
- **Conflicts with a Source:** the curator's edit wins, with a reason required. The preview names what it supersedes ("This supersedes Weld 1959's 'spring'"); an observation link or a citation counts as a reason, "my judgement" alone doesn't. No second-curator sign-off.
- **Add from observation:** paste an iNat observation (on a Gall page, or into ⌘K); proposed edits go into the tray, the observation as their evidence.
  - Automatically: a recorded occurrence for its place (iNat's state/province → our place), dated as seen (never a season Fact); the Gall is the page's Gall, or chosen among the Inducer's Galls.
  - The Host: read the "Host Plant ID" observation field, and plant names in the observation's note (description), matched through the same plant resolution as intake and offered to confirm. Neither → the curator provides it.
  - Photos: the existing iNat image import (`GallformersWeb.Admin.InatImportComponent`) offered as a choice — take the observation's images or not. Images stay editorial.
- **⌘K command palette for everyone.** Replaces the header's search box; a visible search field in the header opens it (phones too). Everyone: search across Galls, Hosts, taxa, Sources, places and articles, keyboard-navigable; shortcuts into the ID tool ("Galls on Quercus alba", "… in Virginia"). Signed-in curators also: "Edit this page", "Add from observation…", "Review: <Source>", "Sources to review", "Facts for this Source".
- **Held:** typed prose commands turned into a change set by a small LLM — neat; revisit only if inline editing proves harder than expected (cost would be tiny; the preview guards against a wrong parse).
- **Everything about a Gall is editable on its page** (Jeff, 2026-11-06): its Facts (through the change set) and its editorial fields (name override, abundance, completeness, images, the Gallformers note text, default Source, and the rest).
- **Editorial edits go in the same tray** (Jeff, 2026-11-06): listed beside Fact edits as "editorial: no evidence needed", applied with the same Review and apply (audited, no Facts preview). Curators needn't know which fields are Facts. Exception: changing a Gall's **Gallformers code** asks for confirmation (it anchors iNat links and outside references), as Gall renames do.
- **Plant pages are editorial** (Jeff, 2026-11-06; 8567): name, synonyms and range edited in place as editorial edits in the tray, not Facts; no Facts preview or evidence. Inducer and other non-plant taxon pages edit their taxonomy (placement, accepted name, synonyms with authorship, rank, common names) as Facts credited to the Source the curator follows ("Based on which Source?"; f923), in phase 2; until then the taxonomy admin edits the tree as today. Their Galls are edited on the Galls' own pages.
- **"Based on" note on plant edits** (Jeff, 2026-11-06): an edit that departs from WCVP (a synonym WCVP lacks, a range from a regional flora) may carry an optional "based on" note ("per Flora of North America", "iNat treats these as one species"), kept in the audit history and shown on the plant's page so the next curator knows why it differs from WCVP. Not evidence in the Fact sense; offered only on edits that depart from WCVP.
- **Roles** (Jeff, 2026-11-06): **admin** (curator) does everything designed here, including deleting Galls and taxa; **superadmin** adds only trait categories (the vocabulary) and users. Changing a Gallformers code without confirmation is never possible, for anyone.
- **Deleting a Gall or taxon (any admin) MUST keep the hard-won safeguards** (Jeff): show the impact first, apply the rules that can block a delete, and make the admin really sure. On `main` that is `Gallformers.Taxonomy.get_deletion_impact/1` (`lib/gallformers/taxonomy/reclassification.ex`: per rank — family and genus cascade, intermediate, a section that can't be deleted until its species are reclassified), the cascade-delete modal in `lib/gallformers_web/components/form_components.ex` (~line 1090–1200: what will be deleted, what blocks it), the taxonomy admin's delete flow (`taxonomy_live/form.ex`, `index.ex`), and the Gall form's type-to-confirm delete (`gall_live/form.ex`: deletes uploaded images from storage; "deleted by another user"). Taxogall's taxonomy edit page has a type-to-confirm modal; check it against main's impact and blocking rules and port what's missing, adapted to the new model (a Gall's or taxon's Facts and the Sources behind them, Galls named after a taxon, child taxa, images).
- **Restating Gallformers' position** (Jeff, 2026-11-06): where a newer Source's statement has replaced Gallformers' (recency wins: Gallformers' positions dated when made, the old data at cutover), a curator can **Restate Gallformers' position** — a new Gallformers statement dated now, reason required (same rule as any conflicting edit); readers see both and the reason. Offered on the review Facts page (conflict rows, before approval), on Gall pages with Edit on (a Fact shows the earlier Gallformers statement it replaced), but not for taxonomic disagreements, where the curator declines the paper instead (f923).
- **What a newer Source may change without a curator** (Jeff, 2026-11-06): ordinary Facts (Hosts, Traits, range…) follow recency when its package is approved — the Facts page has shown each conflict, so approving accepts them. **Taxonomic changes always need a curator's yes:** a newer Source's placement, synonymy or name change stays a question ("Follow the Source" accepts it; "Keep the current position" declines it with a reason, recorded on the Source's statement, no Gallformers statement written; f923), so the tree never moves just because a long package was approved. For taxonomy, Restate is only for a position no paper supports.
- **Tray persistence and concurrency** (Jeff, 2026-11-06, agreed): the tray is saved with the curator's account (survives sessions and devices), private to its author until applied, with a reminder when it's been left a while. No locks: Review recalculates the preview against current data and flags anything another curator changed since ("Adam changed this Gall's Hosts since you started: review again"); editorial fields get the same check; a page with Edit on may show "Adam has unapplied changes here".
- **Persistent chrome for outstanding changes** (Jeff): while a curator has unapplied changes, a persistent indicator shows on every page (public pages included when signed in) with the count and Review / Discard.
- **Review edits vs the tray** (agreed): edits on the review Facts page correct what the Source says (package edits, applied with approval); anything Gallformers itself states goes into the tray, even when started from the review page.
- **One change set per curator** (Jeff, 2026-11-06): the tray is the change set; every edit adds to it; no second set while one is open. A quick unrelated fix is handled inside it: any single item can be reviewed and applied alone, and its evidence set per item (evidence is asked once per set but can differ for any item). Discard clears the tray, after a confirmation.

## Open

- Taxon pages beyond the basics: splits and merges of non-plant taxa as Facts credited to the Source they follow (phase 2, f923). (Deletes: settled below.)
- Inline editing of the Gallformers note text once notes are split into Facts and commentary (`20e5`).


## Delete safeguards: main vs taxogall (audit, 2026-11-06)

- **main:** taxa delete with an itemised impact preview and cascades (family and genus delete everything under them, S3 images included; an intermediate collapses into its parent; a section with species is blocked); Galls and Hosts delete too (type-to-confirm, images removed from storage, orphaned aliases cleaned, "already deleted" and "deleted by another user" handled, deletions broadcast to other admin screens).
- **taxogall today:** a taxon deletes only when nothing refers to it — any child taxon, Fact, attribution name, Gall relationship or Host qualifier, generation group, batch statement, image or range row blocks it (`Taxa.references/1` reads every non-cascading FK to `taxa`); rechecked under a tree lock; type-to-confirm; audited and replayed. **Galls can't be deleted at all.** No impact preview (the block lists "N rows of <table> (<column>)", not the Galls/Facts/Sources); no cascade or collapse; no "already deleted" / "deleted by another user"; no broadcast; no delete from the taxonomy list.
- **Gaps:** taxon IDs held only in JSON (queue item subject/proposal/decision, package statement edits) aren't checked, so a taxon referenced only there can be deleted.
- **For the design (with phase 2):** settled in "Deletes" below (Jeff, 2026-11-06).


## Deletes (Jeff, 2026-11-06)

- **Delete and merge are separate operations.** **Delete** is for a record that should never have existed (a test entry, a duplicate typed by mistake, a misspelled genus, an empty placeholder): allowed only when nothing from a real Source rests on it (only legacy-data Facts and Gallformers statements). Main's impact preview and type-to-confirm carry over; audited, replayed, restorable (`runbooks/restore-deleted-gall.md`). **Merge** is for the same thing recorded twice (two Galls found to be one, an undescribed Gall that is a known one, a duplicate plant): every Fact with its Sources' attributions moves to the surviving record; the old name becomes an alias; the old id and Gallformers code redirect (iNat links and outside references keep working).
- A blocked delete says why and what to do instead ("3 Facts from Weld 1959 rest on this Gall: merge it into the right Gall, or correct where Weld's statements were attached").
- **Cascades are all or nothing.** Deleting a family or genus deletes everything under it (species, their Galls, images) only if every record passes the delete rule; the impact preview lists everything; any blocker blocks the whole delete, named with what to do ("Andricus foo has 4 Facts from Weld 1959: merge it or move it first").
- **Collapses re-place the children.** Deleting an intermediate rank (subfamily, tribe, subgenus) moves its children to its parent; for non-plant taxa that placement is recorded as a Gallformers statement with the delete's reason (correcting Gallformers' own entry error, one of the rare exceptions); an accepted paper placing a child elsewhere still wins.
- **Main's other safeguards carry over:** a plant section with species can't be deleted until they're moved; images are removed from storage; "already deleted" and "deleted by another user" are handled; other admin screens are told of the deletion.
- **References held in JSON count.** Taxon (and Gall) ids held only in queue items or package statement edits are references: a decided item's reference is cleaned up with the delete, an open item's blocks it.
- **What a Gall merge does** (the curator picks the survivor): Facts move with their attributions; the same Fact on both combines its Sources; a single-valued disagreement follows recency, a same-date tie is a curator question. Editorial: name, code, completeness, abundance, default Source are the survivor's (the absorbed name becomes an alias, its code redirects); all images move over (removable after); if both have a Gallformers note, the absorbed one is appended under a heading ("From the merged X gall") as a new version; other Galls pointing at the absorbed one (an alternate generation) are re-pointed. A merge preview shows all of it first; type-to-confirm, as for delete.
- **Plant merges** follow the same shape editorially: synonyms combine, Host Facts move over, the range is the survivor's unless the curator edits it.
- Non-plant taxa: a merge is a synonymy, a Source's act a curator accepts (phase 2, f923); a hand merge is the rare Gallformers exception. Plants merge editorially. Gall merges are editorial (Gall identity is Gallformers').

## Deletes and merges: back end as built (2026-11-06)

All in `Gallformers.Import` unless stated. Subjects are `{:gall, id} | {:taxon, id}`.

- `deletion_impact(subject)` → `{:ok, impact} | {:error, :not_found}`. `impact`: `%{subject: %{type, id, name, (rank, kingdom)}, operation: :delete | :cascade | :collapse | :blocked, deletable, galls: [%{id, name}], taxa: [%{id, name, rank}], children, parent, facts: [%{fact_id, kind, about, rests_on, text, sources}], sources: [%{id, title, name, own, facts}], images: [%{id, path, owner}], notes: [%{gall_id, versions}], legacy_citations: [%{gall_id, source}], cleanup: [%{kind, count, text}], blockers: [blocker]}`. A blocker: `%{kind, record, record_name, source, count, text, action}`; kinds `:source_facts`, `:source_names`, `:waiting_terms`, `:host_qualifier`, `:generation_group`, `:section_has_species`, `:has_children` (plant merge), `:open_question`, `:package_under_review`. Text and action are ready to show ("2 Facts from Weld 1959 rest on X" / "To delete it, merge it into the right Gall, or correct where Weld 1959's statements were attached.").
- Operation by rank: family, genus, species and below cascade (everything under them, Galls named after them); other ranks collapse into the parent (non-plant sections included); an empty plant section collapses, one with species is blocked.
- `record_deletion(actor, subject)` → `{:ok, %{impact, storage_errors: [{path, reason}]}}`, `{:error, :not_found}` (already deleted, or by another user), `{:error, {:blocked, [blocker]}}`. Rechecked under the tree lock; audited; replayed; images removed after commit.
- `merge_preview(spec, actor)` (the real merge, rolled back) and `record_merge(actor, spec)`, `spec` `{:gall | :plant, absorbed_id, survivor_id}` → `{:ok, result}` or `:not_found`, `:same_record`, `:not_a_plant`, `{:blocked, [blocker]}`. Gall result: `%{type: :gall, absorbed, survivor, facts: [%{from, to, kind, text, outcome: :moved | :combined | :dropped, with_gall, sources: [%{id, title, name, outcome}]}], standings, conflicts, queued, alias, redirects: %{id, code}, images, note: :appended | :moved | :kept | :none, repointed, cleanup, blockers}`. Plant result: `%{type: :plant, absorbed, survivor, synonyms, common_names, facts, standings, conflicts, queued, galls_requalified, images, range: %{dropped}, redirects: %{id}, cleanup, blockers}`.
- PubSub: `subscribe_records()` on `"catalog:records"`: `{:records_deleted, %{galls, taxa, by}}`, `{:records_merged, %{type, absorbed_id, survivor_id, by}}`.
- Redirects: `Catalog.gall_redirect(id | code) :: id | nil` (code ignores case) and `Taxa.taxon_redirect(id)`; the public Gall and plant pages should call them for unknown ids/codes.
- The taxonomy admin's existing `{:delete_taxon, …}` keeps its simple rule but now counts ids held in queue items and package edits; its edit page should move to `deletion_impact/1` and `record_deletion/2`.
- Calls made in the build: same-date ties a merge creates are package-less `:same_date_conflict` queue items (they need a page, as rename proposals have); decided queue items are scrubbed, not deleted; a decision in a package still under review blocks a delete (a merge re-points it); open rename proposals about a deleted or absorbed Gall are deleted; a Relationship between the two merged Galls is dropped; where one Source states the same Fact on both Galls, the survivor's attribution stands and gains the absorbed one's quotes and Observations (Jeff, 2026-11-06: keep both quotes); legacy citations count as legacy data, deleted or moved, never blocking (Jeff, 2026-11-06); draft tray items about a deleted record stay and show as blocked. Plant merges: species rank or below only; blocked by child taxa, a real Source's taxonomic act, or a generation group naming the absorbed plant.

## UI design and build (design-system worktree, 2026-11-06)

Worked through with Jeff on the `design-system` worktree (details in its matter `bc0d`).

- **Command palette: built.** Search and go anywhere, on every page, public and admin (`GallformersWeb.PaletteLive`, rendered once from the root layout outside the page's live session; `GallformersWeb.Palette`; the `Palette` hook). Keys `/` and `s` (not ⌘K: browsers bind it; `/` overrides Firefox's quick find on our pages, as GitHub does). The empty palette shows the fixed Go to list, plus curators' commands (Edit this page, Sources to review, Changes). Typing gives Go to shortcuts into the ID tool ("Galls on *Quercus alba*", "… in Virginia"), then results by kind and "See every result". The header's search box became the trigger. Still to come with their targets: Add from observation…, Review: <Source>.
- **Changes and the dashboard: built.** `Gallformers.Audit.ChangeLog` (web: `Catalog.changes/1`): curators' changes from the audit trail, grouped and worded down to each Fact. The admin dashboard leads with Sources to review, then recent changes; `/admin/changes` adds search and filters. Every Gall, taxon and Fact in a change links **View** (its public page at `#fact-<id>`) and **Edit** (the same page with `?edit`). No flag/discuss feature: mistakes are corrected through Edit; the team talks on Discord.
- **Edit mode on the Gall page: designed (mockup `/dev/mockups/gall-edit/:id?edit`).**
  - Edit toggle in the page header (`?edit`); an "Editing" notice.
  - Editorial panel: completeness, abundance, code, name parts.
  - The Inducer and each Host as a row with its Sources and Withdraw / Correct… / Note… (three text buttons, Jeff); Add a host.
  - Each Trait value a chip with ✕ withdraw (Sources on hover), "+ Add" per Trait; Add a common name.
  - The change tray: a bar pinned at the foot (count, the changes, Discard, Review and apply).
  - Review and apply: each change with its status (New / Already held: <Sources> / Supersedes <Sources>: a reason is needed / Editorial: no evidence needed / asks for confirmation), taken out singly, evidence asked once (observation, Source, or my judgement with a reason).
- **Edit scope** (Jeff): in Edit mode every part of a page is one of ✎ edit here (actions on it), ↗ edited on another page (named, linked) or ⓘ follows from other data (says from what). On the Gall page:
  - ✎ Inducer, Hosts, Traits, common names; completeness, abundance, code, name parts.
  - ↗ lineage and the Inducer's synonyms (the Inducer's taxonomy), plants' ranges, photos, the ID note, range exclusions.
  - ⓘ other generation, Season/Location/Form in the header, the Sources list, the range map, former labels.
  - The same scheme applies to every page with Edit mode.
- **Direction** (Jeff): pull the ↗ edits onto the page over time. The image manager, the range editor and the Gallformers note editor become components opened as dialogs on the page. Name parts and the Gallformers code move onto the Gall page now, with exactly their existing strict logic (`Catalog.update_name_parts/3` and its derivation and name-taken checks; `Catalog.gallformers_code_taken?/2` and the confirmation).
- **Build order** (Jeff): the back end first (the change set saved with the curator's account; the preview against current data, flagging others' changes since; apply: Fact items as a Gallformers package through `Import.submit_gallformers_fragment/2`, editorial items through the existing `Catalog` functions; single items applied alone); then Edit mode for Hosts and Traits; then the rest of the Gall page.


## Change-set interface (settled, Jeff, 2026-11-06)

Split agreed with Jeff: **the ingestion agent builds the change-set back end** (store, preview, apply: it's ingestion); **the design-system worktree builds the UI** on it (the tray bar, Edit mode on pages, Review and apply). This section is the contract both sides build against; field and function names may still be refined by the back end, but the shapes and behaviours are fixed. Settled from the UI agent's hand-off, with the ingestion agent's review.

**Scope now:** Gall pages (Fact items, notes, editorial fields) and plant pages (editorial). **Not yet:** taxon items (phase 2, f923: their evidence must be a Source, "my judgement" only as the rare exception; until then the taxonomy admin edits the tree as today); Add from observation (a later call, below); images and the Gallformers note text (later editorial items).

**Context:** a new `Gallformers.Curation` context. Every call takes the curator's `%Actor{}` (admin); a set is private to its author until applied.

**Storage:** its own tables, `change_sets` (one open set per user; evidence) and `change_set_items` (stable bigint ids; kind, subject, key, spec, per-item evidence, what the item saw when added, status). A set becomes a Gallformers package only on apply: drafts change constantly, a package's files are fixed once written. Drafts are not replayed (they aren't data until applied) and must stay out of the public database snapshot; the applied packages and editorial edits are audited and replayed as today.

**Items** (the spec passed to `add_item/2`):
- **Fact item:** `%{kind: :fact, gall_id: id, action: :add | :withdraw | :correct, key: key, to: key}` (`to` only for `:correct`). Keys, as the Gall page's attribution keys: `{:inducer, taxon_id}`, `{:host, taxon_id}`, `{:trait, trait, value}` (slot traits such as season and detachable: correct replaces the value), `{:alias, name}` (common names), `{:range, :exclude | :only, place_id}`, `{:occurrence, place_id}`. Add confirms, withdraw denies, correct denies the old and confirms the new (one item to the curator). Descriptions later.
- **Note:** `%{kind: :note, gall_id: id, key: key, text: text}`: a note on a Fact, a record of its own (new `fact_notes`: fact, text, author, date), shown with the Fact, audited and replayed. Not a Gallformers statement: a confirmation dated today would change the Fact's standing. Editorial in the tray: no evidence, no Facts preview.
- **Editorial item:** `%{kind: :editorial, subject: {:gall, id} | {:plant, id}, field: field, value: value}`, plus `based_on: text` on plant edits that depart from WCVP. Gall fields: `:completeness`, `:abundance` (`Catalog.update_gall_editorial/3`), `:code` (`Catalog.gallformers_code_taken?/2`; needs confirmation), `:name_parts` (`Catalog.update_name_parts/3` with its derivation and name-taken checks), `:default_source_id`. Plant fields: name, synonyms, range (the taxonomy admin's existing functions).
- One item per Fact key (Fact and note items) or per field: adding another edit to the same one replaces it.

**Evidence** (Fact items only): `%{text: text, observations: [%{provider: "inaturalist" | "bugguide", id: id}], source_id: id | nil}`, set once on the set and overridable per item (`nil` on an item means the set's). "My judgement" is text with no observation or Source. A Source as evidence becomes a Gallformers statement dated today that **cites** that Source: contract addition `cites` on Gallformers `statement_evidence`, with `as_written` and an optional `source_id` (`priv/import/`, both validators). When the Source is brought in later, its own statement joins the same Fact.

**Calls**
- `open_set(actor)` → the curator's open set with its items, or `nil`.
- `add_item(actor, spec)` → `{:ok, item}` (id, display text, key) or `{:error, reason}` (e.g. no such Gall, an unknown trait value).
- `remove_item(actor, item_id)`, `discard(actor)` (the UI confirms first), `set_evidence(actor, evidence)`, `set_item_evidence(actor, item_id, evidence | nil)`.
- `preview(actor)` → each item with **a list of flags**, computed against current data at the call:
  - `:new`; `{:held, sources}` (already stated; applying is a no-op); `{:supersedes, statements}` (the Sources' statements it replaces, with their words and dates: "This supersedes Weld 1959's 'spring'"); `{:changed_since, user, at}` (another curator changed this Fact or field after the item was added, from the audit trail); `:needs_confirmation` (code, name parts); `:editorial`; `:needs_reason` (supersedes something and the evidence has neither text nor an observation nor a Source); `{:blocked, reason}` (a check that fails).
  - `:needs_reason` and `:blocked` stop an item from applying; `:needs_confirmation` needs the item's id in `apply`'s `confirm:` list.
- `apply(actor, opts)` and `apply_item(actor, item_id, opts)` (`opts`: `confirm: [item_id]`) → `{:ok, %{applied: [...], submitted: [...], held: [{item_id, reason}]}}`.
  - Editorial and note items apply at once (`applied`).
  - Fact items become one Gallformers package (`Import.submit_gallformers_fragment/2`; Galls and taxa given by `gallformers_gall_id` / `gallformers_taxon_id`, so no name questions) that the import worker applies: they are `submitted` and stay in the tray marked waiting until their outcome arrives. Outcome per item, broadcast: applied (the item leaves the tray), waiting for review (link to the package's review page), or held with the reason.
  - Results are per item, never all-or-nothing. `apply_item` builds a package holding only that item.
- `pending_for(actor, subject)` → the curator's items about one Gall or plant, by key, so a page in Edit mode marks "in your tray".
- `others_pending(subject)` → `[%{user, count, since}]`: other curators with unapplied items here.
- `summary(actor)` → `%{count, lines, oldest_at}` for the indicator on every page (and the "left a while" reminder).
- **Wording:** every item's display text and every flag's text come from the back end, reusing `Audit.ChangeLog`'s wording, so the tray reads like the changes page.
- **PubSub:** `"curation:user:<id>"` gets `{:change_set, :changed}` and `{:change_set, {:outcome, item_id, outcome}}`; `"curation:gall:<id>"` / `"curation:plant:<id>"` get `{:change_set, :others_changed}` when anyone's items about that subject change.

**As built (2026-11-06; refinements within the contract):**
- Each preview flag is `%{kind: atom, text: text, flag: <the tuple above>}`; each preview entry is `%{id, kind, text, subject, subject_name, key, state, flags, item}`.
- Items: `id, kind, key, subject, subject_name, text, spec, evidence, status (:draft | :submitted | :in_review), state (:in_tray | :waiting), outcome, inserted_at`. Outcomes: `:applied`, `{:waiting_review, package_id}`, `{:held, reason}`.
- `pending_for/2` returns key → list of items (a key can have a Fact item and a note). `others_pending(subject, except_user \\ nil)` leaves out the viewing curator when given.
- `:needs_reason` only when an item supersedes **another** Source's statement: replacing or withdrawing only Gallformers' own statements (the Gallformers Source, and the legacy data the migration credits) needs no reason (Jeff, 2026-11-06); the `:supersedes` flag still shows what it replaces. Possessives follow the name ("Gallformers' statement").
- `:name_parts` needs confirmation, like `:code`.
- **A held Fact still gains Gallformers' statement** (Jeff, 2026-11-06: so a Fact isn't lost if its paper is retracted): `{:held, sources}` comes with a new flag `:adds_statement` ("Adds Gallformers' statement, so the Fact keeps Gallformers' support if a Source is retracted") unless the Gallformers Source already states it with the same stance and every Observation the evidence cites. Applying submits it; Gallformers' newer statement keeps the Observations its earlier one cited, so repeat sightings (an occurrence in a known place) accumulate. Only a Fact Gallformers already states the same way is a no-op (applied, nothing written). Plant `:synonyms` and `:range` values are the full desired list.
- `add_item/2` errors: `:no_such_gall`, `:no_such_plant`, `:no_such_taxon`, `:no_such_place`, `:invalid_key`, `:no_fact`, `:unknown_field`, `:invalid_value`, `:invalid_spec`, `:waiting`.
- Subscriptions: `subscribe(actor)`, `subscribe_subject(subject)`.
- Wording lives in `Curation.Wording` (ChangeLog's phrasing) until `Audit.ChangeLog` lands on taxogall; then swap it in.
- Notes: `Catalog.FactNote` (`fact_notes`) and plant "based on" notes in `taxon_notes`, both audited, replayed and public in the snapshot; drafts private (`priv/snapshot/tables.txt`). A cited Source is stored on the attribution (`cites_as_written`, `cited_source_id`).
- Imports now honour `gallformers_taxon_id` (picked among the taxa the name matches; a mismatch is flagged `supplied_id_disagrees`) and, in a Gallformers batch without a note, `gallformers_gall_id`.

**Add from observation (built 2026-11-06):** `from_observation(actor, url_or_id, gall_id | nil)` → `{:ok, proposal}` or `{:error, :invalid_input | :not_found | :unavailable | :no_such_gall}`. It proposes; it adds nothing to the tray.
- `proposal`: `%{observation: %{id, url, taxon_name, observed_on, place_guess, observer}, inat_observation: %INaturalist.Observation{}, evidence: %{text: nil, observations: [%{provider: "inaturalist", id: id}], source_id: nil}, gall: %{gall_id: id | nil, candidates: [%{id, name, datacomplete}], why: text | nil}, items: [%{role: :occurrence | :host, spec: <add_item spec>, text, why, selected: boolean}], needs: [%{kind: :gall | :place | :host, text}], photos: [%INaturalist.Photo{}]}`.
- Occurrence spec `%{kind: :fact, gall_id: id | nil, action: :add, key: {:occurrence, place_id}, when: "2025-07-14"}` (`when` omitted with no date); Host spec `%{kind: :fact, gall_id: id | nil, action: :add, key: {:host, taxon_id}}`. With `gall_id: nil` the curator chooses among `gall.candidates` and the UI sets `gall_id` on each spec before `add_item/2`. A Gall is pre-selected when the Inducer has one Gall or the observation's "Gallformers Code" field names one.
- After `add_item/2`, attach `proposal.evidence` with `set_item_evidence/3` or `set_evidence/2`.
- Several readings of a name are separate items, only the resolver's proposal `selected`; a Host Plant ID name the tree doesn't hold offers suggestions, none selected. `needs`: at most one per kind, worded for the curator.
- Photos: pass `{:ok, proposal.inat_observation}` to `InatImportComponent` as its `fetch_result`.
- **Contract addition:** optional `when` (text) on Fact items, accepted only on `:add` of an `{:occurrence, _}` key (else `{:error, :invalid_spec}`); stored as `when_as_written` on the statement; the item reads "Add recorded in California (2025-07-14)".
- Behind it: `INaturalist` extended (observation fields, `fetch_places/1`; tests stub iNat with `Req.Test`), `Places.match_subdivision/2`, `Import.resolve_host_names/2` (intake's Host resolution).

**Behaviours already settled** (above): one change set per curator; any single item can be reviewed and applied alone; no locks (Review recalculates and flags others' changes); a conflicting edit wins with a reason, no second-curator sign-off; edits on the review Facts page correct what a Source says (package edits), while anything Gallformers itself states goes in the tray.

### UI side: what the components take (design-system worktree, 2026-11-06)

Built against this contract, with sample data, in `GallformersWeb.CurationComponents` (`edit_toggle`, `edit_scope`, `fact_row`, `change_tray`, `review_apply`) and `GallformersWeb.FactKey` (keys as strings for page events: `host:7`, `trait:season:spring`, `range:exclude:31`). One shape assumption, for the back end to confirm or adjust: **each preview flag reaches the UI as `%{kind: atom, text: String.t()}`**: `kind` one of the contract's flag names (`:new`, `:held`, `:supersedes`, `:changed_since`, `:needs_confirmation`, `:editorial`, `:needs_reason`, `:blocked`), `text` the back end's words for it ("Supersedes Weld 1959's 'spring'"). The UI picks only the look from `kind`. An item: `%{id, kind: :fact | :note | :editorial, text, flags, state: :in_tray | :waiting}`; `summary/1` as in the contract. If the back end returns the tuples instead, the UI maps them in one place; tell the UI side which.


## Live-use findings (Jeff, 2026-11-06)

Fixed 2026-11-06 (merges `222dcb2e`, `031154d9`, `9d3ec003` and the Gall page merge): 1–13; 14 merge tried by Jeff and good (2026-11-06). Left over: direct audited edits outside the tray (taxonomy admin saves) don't refresh the dashboard; `/admin/changes` doesn't update live.

1. "Last updated" on a Gall doesn't change after edits are applied.
2. Applying from the tray should leave Edit mode.
3. Add from observation is hard to find (foot of the Gall page's editorial panel).
4. Review and apply doesn't show an item's own evidence (an observation item's iNat link): show it per row; the shared evidence form applies only to items without their own, and says so.
5. A Gall's Facts can't be seen from the Gall page (with their Sources and standing).
6. The palette doesn't find "Add from observation…" when typing "observation": only Sources match; commands should match typed text.
7. The palette's text cursor sometimes jumps to the start while typing.
8. `/admin/observation`: when it says to give the Host, there's no clear way to add one; and no link to the chosen Gall (open it in Edit mode).
9. The plant page's Edit panel layout is rough: one Editorial card stacking name, an always-open add-synonym form (Synonym / Sensu / Based on / Add, labels misaligned) and a lone Range… button.
10. The taxonomy admin's edit page intro says "Each change is saved as you make it, except the Host range, which is saved with its Save button" on pages with no Host range (e.g. genus Quercus): say it only where the Host range card shows.
11. The palette doesn't show the curator's open changes.
12. The admin dashboard (and recent changes) don't update after applying; they need a manual refresh.
13. The image manager's list view needs horizontal scrolling even on a wide screen, which hides the row actions (Copy metadata, Delete…): fit the table to the panel.
14. Merge not yet tried by Jeff: ask again once these are fixed.

Look changes from the migration (bc0d): the host range view is fine; the discard dialog's wording is good; the copy-metadata panel above the table is good.

Answers (Jeff, 2026-11-06): the feature LiveComponents (`RecordRemoval`, `ObservationIntake`, `HostLive.Editor`) need no approval; the components the migration hand-built (bc0d) are approved to be built properly; f14c's ergonomics after these and the last back end.


## Add from observation in the Fact inspector (Jeff, 2026-11-07; matter d3b0)

The observation is evidence, so it opens in the Fact inspector beside the page, not a modal: paste the link; the observation's card (photo, identified as, Research Grade or not, seen, where, by, license); what it shows as proposals previewed in place on the page and listed with ticks, each New or Already held (adds the observation as evidence); a missing Host asked for in the panel; one "Add N to your tray", each with the observation as evidence. Once applied, the Fact's inspector shows Gallformers' statement "based on iNaturalist observation …".

- **Photos go through the tray** (decided): its photo is a tick, an editorial tray item, not saved at once.
- **An observation identified as another taxon than the Gall's Inducer: warn, don't block** (decided), unmissably, offering that taxon's Gall.
- **Non-Research-Grade observations are allowed, made clear** (decided): their grade shows in the panel and in the inspector's "based on" line.
- Found while testing the current dialog: an observation identified as Aphis rubifolii, pasted on the Diplolepis rosae page, gave no warning and offered "recorded in Indiana" for Diplolepis rosae.


**Captured for the build in `87a1`** (with the Fact inspector).
