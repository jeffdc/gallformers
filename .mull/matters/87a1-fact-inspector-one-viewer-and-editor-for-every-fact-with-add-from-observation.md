---
status: raw
created: 2026-11-07
updated: 2026-11-07
epic: taxogall
relates: [d3b0, ec2c, bc0d]
---

# Fact inspector: one viewer and editor for every Fact, with Add from observation

# Fact inspector: one viewer and editor for every Fact

Designed with Jeff on 2026-11-07 ("I think we have our design"). The design and its rationale live in `d3b0` (sections "The Fact inspector", rounds two and three) and `ec2c` ("Add from observation in the Fact inspector"); this matter is the build. The mockup is `dev/gallformers_web/dev/mockups/fact_inspector_live.ex`, routed at `/dev/mockups/fact-inspector/:id` (`?edit` for editing; try Galls 5076 and 1411). It reuses the Facts-panel mockup's data and tray (`FactEditMock.gall_panel/1`, `authority_tray`, `review_dialog`).

## The idea

The Fact viewer and the Fact editor are one thing. A page reads as it does for everyone; every Fact-backed value (Inducer, each Host, Trait value, range place, common name) is a `fact_ref`. Selecting it opens the `fact_inspector` beside the page: who says so, and in Edit mode, what you can do about it. No edit forms in the page body, no verb on every row, no second copy of the Facts to edit in.

## Decided

- **Readers get the inspector.** Provenance on demand is "every claim has a Source" made visible. One component for readers and curators.
- **Placement:** in the rail's place on wide screens (sticky), a bottom sheet on phones.
- **`fact_ref`:** a dotted underline (decoration-line-strong, darkening on hover), the value selected on `bg-sky-soft`; hover text "Who says so?". The underline alone isn't discoverable, so readers get a dismissible hint at the top of the page: "Underlined values show the Sources that state them. Select one to see who says so." (Remember the dismissal per browser.)
- **Inspector, top to bottom:** the kind ("Host"), the value large, "A Host of <Gall>", the standing (Holds · Stated by N Sources; Unconfirmed when only Gallformers' undated original data states it), then **Who says so**.
- **One block per Source, the same template for each:** "**{Source}** says so" (or "says it isn't so") · its date, its words as written, up to two quotes (serif, the rest counted), and the actions that belong to that Source.
- **Gallformers is one of the Sources, pinned first in both modes,** then the others newest first. The old site's data reads as Gallformers' own undated statement ("original data, undated"), per `d3b0`'s merge of the legacy Source into the Gallformers Source.
- **Edit mode actions sit in their Source's block.** Gallformers' block: Change…, Deny…, Add a note…; when Gallformers hasn't stated the Fact, its block reads "Gallformers hasn't stated this" and adds Confirm…. Each opens a short form in the panel (the value where needed, "Why": an observation's link, a paper, a reason) and goes to the tray as a Gallformers change.
- **Fixing a reading is a level deeper,** since it is rarer than Gallformers changes: "Found an error in a Source reading?" reveals "Fix our reading…" on every other Source's block; its form asks "What {Source} actually says", under that Source's authority at its date, with no Gallformers position.
- **Adding:** one Add per group (Add a host, Add a place, Add a common name, + Add per Trait); in Edit mode the Traits not recorded are each an add ("+ color"). Add opens the inspector on a new Fact with the same statement step.
- **One tray,** grouped by authority, as `d3b0` designed it.

## Add from observation (in the inspector)

- "Add from observation…" (page header in Edit mode; the command palette) opens the inspector's observation state, not a modal. Paste a link or number; it reads the observation (`Curation.from_observation/3`).
- **The card:** thumbnail, link, identified as, seen when and where, observer, and the quality grade as a chip.
- **A taxon other than the Gall's Inducer: warn, don't block,** unmissably, naming the observation's taxon and linking its Gall (`proposal.gall.candidates`). The current dialog lets this through silently: an Aphis rubifolii observation pasted on Diplolepis rosae offered "recorded in Indiana" for D. rosae.
- **Not Research Grade: allowed, made clear,** in the panel and in the statement's "based on" line ("based on iNaturalist observation 318135694 (Needs ID)").
- **What it shows:** each proposal ticked, tagged New or Already held (the observation adds evidence), its reason below; while ticked, previewed on the page where it would land, marked "proposed". A missing Host is asked for in the panel.
- **Photos go through the tray** as editorial items (not saved at once as today); the panel notes when the Gall already has photos from that observation.
- One commit: "Add N to your tray", each Fact a Gallformers statement based on the observation.
- After apply, the Fact's inspector shows Gallformers' statement "based on iNaturalist observation …" with its thumbnail and grade.

## To build

- **Components** (catalog entries in `docs/design-system/components.md`, status Proposed): `fact_ref`, `fact_inspector`. The inspector's states: a Fact (read, edit), a new Fact, an observation.
- **Data:** the inspector's statement lines (Source, date, stance, words as written, quotes, counts or awaiting or declined) as the mockup builds them in `FactEditMock.statement_lines/2`; move that into a real read model. The Gall page's Facts and their keys from `Import.facts_for_gall/1` and the attribution keys `ec2c` uses (`{:host, id}`, `{:trait, trait, value}`, `{:alias, name}`, `{:occurrence, place_id}`, `{:range, adj, place_id}`).
- **Writes:** every action through the change set (`Gallformers.Curation`) and one ingestion path (`d3b0` rules 2–3); fixing a reading as a package of that Source (`d3b0`).
- **Shared pickers:** the one plant search for Add a host and Change (the `d3b0` audit found six), the place picker, the Trait value picker.
- **Replaces:** the Gall page's Edit-mode sections (Hosts rows with Withdraw / Correct / Note, the Trait chips and selects, Add a common name), its read-only Facts panel as the place to edit (it becomes the full record: history, withdrawn, superseded), and `GallformersWeb.ObservationIntake`'s modal. Then taxon and rank pages and a Source's own page, with the same inspector.
- **Done already:** `Gallformers.INaturalist.Observation` carries `quality_grade` (parsed from iNaturalist's `quality_grade`), with a test.

## Open

- **The domain term "Reading"** (proposed in `d3b0` round three; needs Jeff's confirmation before `docs/domain/domain-model.md`): it removes the collision with **Correction**, which the domain model defines as a Source's published erratum. If adopted: the tray's group "Readings fixed: <Source>", and the code's "correction" for this act renamed.
- The phone sheet must scroll the selected value into view above itself.
- Not designed yet: a Fact's history (withdrawn, superseded) in the inspector; a disputed Fact (Sources disagreeing) and what the standing line says; the editorial fields' in-place editing; the Inducer (taxonomy, edited on the taxon's page with the same inspector).
- "Already held" for an occurrence should match on place ID (the mockup matches the place name).
- From the palette with no Gall given: open on the Gall the observation suggests, or ask.
