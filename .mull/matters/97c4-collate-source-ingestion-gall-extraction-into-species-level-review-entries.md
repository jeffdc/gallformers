---
status: planned
created: 2026-05-03
updated: 2026-05-06
epic: ingestion
---

# Collate source-ingestion gall extraction into species-level review entries

## High-Level Design

This matter is about changing the source-ingestion review workflow from a record-centric review model to a species-centric review model.

The current workflow reaches a persisted review state after automated processing completes, but the review experience still reflects extracted records too directly. In real sources, one gall species is often mentioned multiple times across the document, sometimes with overlapping or redundant passages. Treating each mention as an independent review row creates too much noise and does not match how a human curator thinks about the task.

The design goal is to align the review workflow with the user's unit of thought: species.

### User Workflow

The workflow should be split into two distinct experiences.

1. Ingestion Overview
2. Species Review Workspace

These are different tasks and should not be collapsed into one screen.

### 1. Ingestion Overview

This screen exists to answer:
- what happened during processing
- what was discovered
- does the extraction look good enough to continue

The user should be able to submit a source and then wait for backend processing to complete without being drawn into intermediate review work. Processing may be slow, but the UI should make that clear up front and show understandable stage progress so the user knows the system is working.

Once processing is complete, the user needs a quick way to assess extraction quality before deciding whether to proceed or abandon the automated path and process the source manually.

The overview should therefore present:
- source metadata summary
- an at-a-glance summary of discovered species and related extracted data
- obvious warnings or anomalies
- the full extracted text of the source, always available for reference

At this stage, the user's main decision is whether the output is good enough to continue.

If the extraction looks acceptable, the user should then create or map the source to an existing source record.

### 2. Species Review Workspace

After the user decides to proceed, the workflow should shift into a different mode focused on moving through the source species-by-species.

The user should not have to think about raw extracted mentions, backend rows, or how the pipeline stored intermediate data. The review unit should be one species in the source.

For each species, the workspace should present a consolidated view of the extracted evidence, including:
- name
- authority information
- possible aliases detected from the source
- a summary of extracted traits
- hosts
- relevant source text fragments supporting those fields

The purpose of this screen is to let the user create or update a gall species and any missing hosts based on the source as a whole.

The end goal for each species review is a completed species record with accurate:
- accepted name or mapped name
- aliases
- hosts
- trait values
- supporting prose/description as needed

The user would then repeat that process for the next species in the source.

### Core Product Principle

The system should optimize for the human review unit, which is species, not extracted mention.

That means repeated mentions of the same species in a source should not become separate top-level review tasks by default. Multiple passages may contribute evidence to one species review, and some passages may be redundant or not useful. That is acceptable. The important outcome is a cohesive species-level review experience.

### Evidence Expectations

Evidence should remain accessible throughout the workflow, but it should support the species-level review experience rather than dominate it.

The user should be able to:
- see a consolidated species view first
- inspect supporting source text when needed
- refer back to the full extracted document at any point during review

The user should not be forced to review every extracted passage independently if the real task is to curate one species entry from many overlapping mentions.

### Example Implication

A source may mention one species in several separate passages, with partial overlap, redundant observations, or repeated host information. In that situation the system should support one cohesive species review task, not a separate task for every mention. The extracted passages are evidence for the species, not necessarily independent review objects.

### Scope Of This Matter

This matter should stay at the high-level product and workflow design first.

The next design discussion should focus on:
- how the ingestion overview should summarize extraction quality
- what the species review workspace should feel like from a navigation and interaction perspective
- whether grouping should happen entirely before review or whether the review UI should expose grouping/splitting controls when extraction quality is mixed

Implementation details, storage refactors, grouping algorithms, and schema decisions are intentionally deferred until the product direction is locked.


## Workflow Decisions

The high-level design is now tightened into a more exact workflow.

### Domain framing

For this workflow:
- a gall is a species
- a host is a species
- a gall may map to one or more hosts
- a gall may map to one or more sources
- a source may map to one or more species

This workflow is specifically about ingesting gall literature. Hosts matter as secondary data inside that literature, but they are not the primary review object.

### Stage 1: Submission and duplicate gate

Duplicate handling belongs before the expensive processing pipeline.

The system should perform the lightweight duplicate checks immediately after submission and before deeper extraction/LLM work. This is already conceptually close to the current behavior and should remain an early gate.

Possible outcomes:
- no likely duplicate, so processing continues automatically
- likely duplicate, so the user resolves the duplicate question first
- confirmed duplicate, so this ingestion path stops
- rejected duplicate, so processing continues

The important product point is that duplicate review is not part of downstream species review. It is an early cost-control and source-resolution gate.

### Stage 2: Automated processing

Once the ingestion clears the duplicate gate, backend processing should run end-to-end without further user involvement.

The UI should make progress visible and understandable, but the user should not be expected to intervene during this phase.

### Stage 3: Ingestion overview and source decision

After automated processing completes, the user lands on an ingestion overview screen.

This screen exists to answer:
- what source metadata was found
- what gall species appear to have been found
- whether hosts and traits were extracted meaningfully
- whether the result looks good enough to continue

This is the decision gate for whether automated processing was good enough to justify curation.

To proceed beyond this stage, the user must either:
- map the ingestion to an existing `Source`, or
- create a new `Source`

At exit from this stage:
- the `Source` exists in the database
- the ingestion is tied to that `Source`
- future source-facing views should be able to show a source and all ingestions that contributed to it

### Stage 4: Species review workspace

After the source decision, the user enters a separate species review workspace.

This should use a master-detail model.

The master list contains the gall species detected in the source. The detail pane is the review workspace for one gall at a time. The user may select any gall in any order.

The review unit is one gall species in one source.

The master list should stay minimal at first. The main row content needed at a glance is just the species name.

### Stage 5: Per-gall review workflow

For a selected gall, the first required task is identity resolution:
- map to an existing gall species, or
- acknowledge that this is a new gall species

After identity is resolved, the remaining sections should not be forced into a fixed sequence. They should all be readily available in the same workspace.

Those sections are:
- aliases
- hosts
- traits
- supporting source text fragments

The behavior differs depending on whether the gall is new or existing:
- for a new gall, the user is accepting or declining detected aliases, hosts, and traits
- for an existing gall, the user is merging detected aliases, hosts, and traits with existing data

"Merging" here means the user decides what is authoritative.

This is also the stage where the species-source mapping is created. That mapping must include the source text fragment or fragments the user chooses to include as supporting evidence.

### Evidence model

Evidence should support review, not dominate it.

The system should preserve extracted fragments and present them so the user can choose which ones to include. If all candidate fragments are available, the review UI can display them and let the user select the ones worth keeping as part of the source linkage.

The consolidated species-level view comes first, but supporting fragments must remain inspectable and selectable.

### Persistence outcome per gall

When a gall review is completed, the following may be written:
- `Gall`
- new `Host` species, if any
- `GallHost` mappings
- gall traits
- `Species-Source` mapping from the selected `Source` to the gall
- the chosen supporting source fragments for that mapping
- ingestion review state indicating that this gall has been processed for this source ingestion

### Gall-level review states

Gall review state should stay intentionally simple:
- `unreviewed`
- `completed`
- `skipped`

There is no durable partial-completion state. A gall is only effectively in progress while the user is actively working on it. If they abandon in-progress edits, that temporary work can be lost.

### Source-level aggregate states

Source review state should also stay simple:
- `in_progress`
- `complete`

A source becomes `complete` when all gall species for that ingestion are either `completed` or `skipped`.

### Core workflow summary

The tightened workflow is:
1. submit source
2. run duplicate gate before expensive processing
3. run automated processing end-to-end
4. show ingestion overview for triage
5. require source mapping or source creation to proceed
6. enter species review workspace
7. let the user review any gall species in any order
8. for each gall, resolve identity first, then work across aliases, hosts, traits, and evidence
9. persist gall/source/host/trait/source-linkage outcomes as each gall is completed
10. mark the source complete when all galls are completed or skipped

### What remains open

This matter is still intentionally pre-implementation.

The next product-level design work should focus on:
- the shape of the ingestion overview screen
- the feel of the species master-detail workspace
- how supporting fragments should be displayed and selected
- what exact source/species mapping records and evidence objects should look like once implementation planning begins


## Ingestion Overview: source handoff decision

The ingestion overview should not recreate the full source admin screen.

A `Source` requires:
- title
- author(s)
- publication year
- license
- license link when needed
- reference link
- citation (MLA)

That is effectively the full source-admin data-entry surface, so rebuilding it inside the ingestion overview would make the overview too heavy and would duplicate existing source-management UI.

### Source actions from the overview

The overview should support two different source actions:

1. Match existing source
2. Create new source

#### Match existing source

Matching to an existing source is small enough to keep inline on the overview screen.

The user should be able to search for a source, select it, and attach it to the ingestion without leaving the ingestion flow.

#### Create new source

Creating a new source should use the normal existing source screen rather than a rebuilt ingestion-specific form.

The ingestion overview should send the user into the normal source screen with ingestion-derived values preloaded. The source screen should make it clear that the user is in the ingestion flow and will be returned there after save.

After the new source is saved:
- the new `Source` is attached to the ingestion
- the user is returned to the ingestion overview
- the user can then continue into species review from the overview

### Resulting overview responsibility

This means the ingestion overview is responsible for:
- showing the extracted source metadata preview
- showing whether the required source fields appear complete enough for creation
- letting the user inspect the extracted text as needed
- routing the user to either inline source matching or normal source creation
- acting as the gate into species review once a source is attached

It is not responsible for replacing the full source admin editing experience.


## Ingestion Overview: screen contents

The ingestion overview is a quick assessment screen for the success of the pipeline and the readiness of the source to enter species review.

At a minimum, it should show:
- all extracted source metadata relevant to source creation and mapping
- a list of extracted galls
- a per-gall summary of extracted hosts, traits, and aliases
- processing outcome
- source action state
- full extracted text
- warnings and missing-data indicators

### Source metadata block

The overview should show the extracted source metadata directly on the page so the user can quickly assess whether the source information is good enough to proceed.

This includes at least the fields needed for source creation:
- title
- author(s)
- publication year
- license
- license link when needed
- reference link
- citation

This block is for inspection and confidence-building inside the ingestion flow. It does not replace the normal source screen for new-source creation.

### Extracted galls block

The overview should show the list of galls extracted from the source.

This list should be organized around species, not raw extracted mentions.

Each gall row should be expandable.

At the collapsed level, the user should be able to scan the species names quickly. On expand, the row should reveal the extracted summary for that species, including:
- aliases
- hosts
- traits

This keeps the screen scannable while still letting the user judge whether the species-level extraction looks coherent before entering the full review workspace.

### Processing outcome block

The overview should include a compact pipeline outcome summary showing whether automated processing completed cleanly and whether any warnings or suspicious results should affect the user's confidence.

The purpose is not to expose internal implementation detail. The purpose is to help the user decide whether this ingestion is worth continuing.

### Source action state block

The overview should clearly show whether the ingestion currently has a source attached.

That state should make it obvious whether the next required action is:
- match to an existing source
- create a new source
- or proceed because a source is already attached

### Full extracted text

The full extracted text of the source should be directly available from the overview so the user can verify both source metadata and species-level extraction quality without leaving the ingestion flow.

### Warnings and missing-data indicators

The overview should clearly flag missing or suspicious information that could affect the decision to proceed.

Examples include:
- missing required source metadata
- sparse species extraction
- ambiguous or inconsistent species naming
- weak host or trait extraction

These indicators are part of the triage purpose of the screen.


## Species Review Workspace: shape

The species review workspace should use a master-detail layout.

### Master list

The master list should stay simple and information-dense.

Each row should show:
- the gall name
- the gall review state

The state model remains:
- `unreviewed`
- `completed`
- `skipped`

The purpose of the master list is navigation and progress visibility, not detailed editing.

### Detail pane

The detail pane is where the actual work happens.

The layout should be compact and efficient rather than oversized. The current implementation is too large, wastes too much space, and uses UI patterns that make review slower than it should be.

The top of the detail pane should prioritize the identity and relationship data the user is most likely to act on first:
- name
- hosts
- aliases

Below that should be the traits section.

This implies a denser workspace with strong information hierarchy:
- identity and mapping decisions first
- related names and hosts immediately accessible
- traits available below without requiring large amounts of vertical scrolling before useful work can begin

### Design principle

The species workspace should optimize for fast curation, not for oversized card-based presentation.

That means:
- compact sections
- efficient use of vertical space
- fewer decorative or overly separated UI blocks
- less visual ceremony around individual extracted items
- a stronger focus on getting through species review quickly and accurately

The user should be able to move between species efficiently and make authoritative review decisions without fighting the layout.


## Species Review Workspace: interaction conventions

The species review workspace should mostly mirror the existing Gall Admin screen in its style and interaction patterns rather than inventing a separate visual language.

That means the review workspace should prefer:
- the same general admin-form style and density
- familiar section structure
- familiar control styling
- typeahead-style lookup and selection patterns where the user is mapping or merging entities

The current ingestion review UI relies too much on pill-style selection patterns where the real task is search, mapping, and curation. That should be replaced by interaction patterns closer to the Gall Admin screen.

Pills may still be useful as compact displays of accepted values, but they should not be the primary control paradigm for entity mapping.

## Species Review Workspace: source text access

The workspace needs the full extracted source text to be always available but not always visible.

The preferred model is:
- extracted snippets/fragments are shown inline where they support names, aliases, hosts, or traits
- the full extracted source text is available in a collapsible secondary panel or drawer

This panel should:
- be accessible at any time during species review
- not force the user to leave the workspace
- avoid taking permanent space when not needed
- preserve orientation better than a modal

### Fragment linking

The full-text panel should not only display the entire extracted text. It should also support jumping to relevant fragments from the current review context.

That means the user should be able to move from:
- a field or trait under review
- or a supporting fragment shown inline

into the corresponding location in the full extracted text.

This is likely to be useful and should be treated as an expected requirement rather than an optional enhancement.


## Species Review Workspace: identity-first gating

The top of the detail pane should begin with `Name`.

This is the first required decision point for a gall review.

### Name and gall mapping behavior

If the extracted gall name appears to match an existing gall exactly, the system should not silently auto-map it. The user must explicitly opt in to that mapping.

If there is no exact match, the user should be able to search for an existing gall species manually. If they map the extracted species to a different existing gall, that implies an alias relationship that must be created or reviewed as part of the workflow.

If they choose not to map to an existing gall, they are implicitly proceeding with a new gall species.

### Section order

After `Name`, the next sections should be:
- `Aliases`
- `Hosts`
- `Traits`

### Data-loading behavior after mapping

Aliases, hosts, and traits should not fully populate until the gall mapping decision is made.

This is important because the downstream review behavior depends on whether the gall is new or already exists:
- if the gall is new, the user is effectively accepting or declining the extracted values
- if the gall already exists, the system needs to compute and present deltas against the current stored data

So the species workspace should treat identity resolution as a gate for the rest of the detail view. Once mapping is resolved, the remaining sections can be populated in the correct review mode.

This keeps the workflow coherent and avoids presenting misleading or premature merge decisions before the target gall identity is known.


### Exact-match suggestion behavior

If the extracted gall name has an exact existing match, the workspace should suggest that match directly in the `Name` section.

The user should be able to accept that suggested mapping with a simple explicit action.

The important point is that the system may recommend the exact match, but the mapping is still not automatic. The user must opt in before the review proceeds in existing-gall mode.


### Rejected exact-match behavior

If the user rejects the suggested exact match, the `Name` section should immediately offer both next-step options:
- search for a different existing gall species
- treat the extracted species as a new gall

Those should be explicit parallel choices in the identity workflow rather than forcing the user through only one path.


## Aliases after mapping

Alias review behavior should depend on the resolved gall mapping.

If the gall is mapped to an existing species:
- show the current alias set for that gall
- show extracted aliases as proposed additions or conflicts against the existing set
- let the user decide what should be authoritative

If the gall is treated as a new species:
- show extracted aliases as a selectable accepted/rejected list

This keeps alias review consistent with the broader identity-first rule: the review mode is determined only after the gall mapping decision is made.


## Hosts and traits after mapping

Hosts and traits should follow the same post-mapping review pattern as aliases.

If the gall is mapped to an existing species:
- show current stored hosts and traits
- show extracted hosts and traits as proposed additions, differences, or conflicts against the existing data
- let the user decide what is authoritative

If the gall is treated as a new species:
- show extracted hosts and traits as selectable accepted/rejected values

This keeps the review model consistent across aliases, hosts, and traits:
- new gall review is accept/decline
- existing gall review is delta/merge



## Implementation Design

### Route structure

- `/admin/ingestion-review/:id` — Ingestion Overview (existing `Show`, trimmed)
- `/admin/ingestion-review/:id/review` — Species Review Workspace (new `Workspace` LiveView)

The overview is the triage and source-decision gate. The workspace is the species-by-species curation screen. They are separate LiveViews with separate routes.

### File changes

**Modified:**
- `show.ex` — remove all workspace code (events, helpers, render section 5). Keep sections 1–4. Add expandable gall rows and "Proceed to Review" navigation link.
- `router.ex` — add workspace route

**New:**
- `workspace.ex` — `IngestionReviewLive.Workspace`, the species review master-detail page

**Unchanged:**
- `presenter.ex`, `index.ex`, all context modules (`SourceIngestionSpeciesReview`, `SourceIngestionSpeciesEntries`, `Ingestions`)

### Overview (show.ex) trimming

Remove from mount: `:workspace`, `:filter_options`, `:gall_families`

Remove all workspace event handlers: `open_gall_review_workspace`, `close_gall_review_workspace`, `change_gall_review_workspace`, `save_gall_review_workspace`, `search_workspace_species`, `select_workspace_species`, `clear_workspace_species`, `toggle_trait_value`, `search_workspace_host:*`, `select_workspace_host:*`, `clear_workspace_host:*`, `focus_source_text`

Remove all workspace helper functions: `build_workspace_state`, `merge_workspace_params`, `update_workspace*`, `toggle_workspace*`, `workspace_*`, `identity_resolved?`, trait encoding/decoding, host review helpers

Remove the workspace card (section 5) from render.

Modify the gall table:
- Remove per-row "Review Gall" buttons
- Add expandable rows showing extracted hosts/traits/aliases as a quick quality summary
- Add "Proceed to Species Review" link navigating to `~p"/admin/ingestion-review/#{id}/review"`, gated on `species_review_unlocked?`

### Workspace (workspace.ex)

Full-page master-detail layout.

**Master sidebar:** Gall names + review status badges. Clicking a gall loads it into the detail pane. No URL change — selection is an assign.

**Detail pane sections (top to bottom):**
1. Name — extracted name, authority, decision radio (mapped/new/skip), exact match suggestion, typeahead for species search, family select for new
2. Aliases — checkbox accept/decline list
3. Hosts — compact rows with typeahead per host
4. Traits — grid layout using `multi_select_dropdown` (same component as Gall Admin), not the current `multi_select` pill pattern
5. Description — textarea with extracted evidence
6. Source Text — collapsible panel with fragment linking

Sections 2–5 gated on identity resolution (decision in mapped/new).

**Actions:** Save Review, Mark Complete, Skip. "Back to Overview" link.

**Data flow:** Same as current — delegates to `Ingestions.update_source_ingestion_species_review` and `SourceIngestionSpeciesReview.workspace!/1`. All existing workspace logic moves from show.ex into workspace.ex.

### Interaction pattern changes

**Traits:** Replace `multi_select` pills with `multi_select_dropdown` in a compact 2–3 column grid matching Gall Admin density. Suggested values and evidence shown as small inline text under each dropdown, not as separate bordered cards.

**Hosts:** Compact rows with typeaheads instead of bordered cards with heavy padding.

**Aliases:** Checkbox pattern stays — appropriate for accept/decline of extracted names.

**Name:** Current radio + typeahead + exact-match suggestion pattern stays — it works well.



## Implementation Plan

**Goal:** Split the ingestion review show page into two separate LiveViews — an Overview for triage/source-decision and a Workspace for species-by-species curation.

**Architecture:** Create a new `Workspace` LiveView at a new route. Trim the existing `Show` LiveView down to the overview. Move all workspace logic (events, helpers, state) from Show into Workspace. Replace trait `multi_select` pills with `multi_select_dropdown` grids matching Gall Admin density. No context-layer changes — `SourceIngestionSpeciesReview`, `SourceIngestionSpeciesEntries`, `Ingestions`, and `Presenter` stay unchanged.

**Tech Stack:** Phoenix LiveView, existing form components (`multi_select_dropdown`, `typeahead`, `radio_group`), Tailwind CSS grid utilities.

### Task 1: Add workspace route and create skeleton LiveView

**Files:**
- Modify: `lib/gallformers_web/router.ex` (add workspace route inside superadmin scope)
- Create: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex`

**Behavior:**
Add route `live "/ingestion-review/:id/review", Admin.IngestionReviewLive.Workspace, :review` inside the existing superadmin scope, after the Show route.

Create a minimal `Workspace` LiveView that:
- Mounts with the source ingestion ID from params
- Loads the review view (via `Presenter.source_ingestion_review_view!/1`) for the master list data
- Loads source text (via `Ingestions.source_ingestion_full_text/1`)
- Loads filter options and gall families (needed for trait/species work later)
- Assigns the current user and db user ID from session
- Auto-selects the first unreviewed species entry (or first entry if all reviewed)
- Renders a placeholder page with the master sidebar listing gall names and a "Back to Overview" link

**Testing:**
- Route resolves to Workspace LiveView with correct action
- Mount loads review view and species entries
- Redirects or errors gracefully if ingestion ID is invalid

**Notes:**
The workspace route must be inside the same superadmin scope as the existing ingestion-review routes (router.ex line 153-155). The initial skeleton only needs mount + handle_params + a basic render — detail pane content comes in later tasks.

### Task 2: Trim show.ex — remove all workspace code

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/show.ex`

**Behavior:**
Remove everything workspace-related from Show:

Mount — remove assigns: `:workspace`, `:filter_options`, `:gall_families`, `:source_text_focus`

Event handlers — remove all of: `open_gall_review_workspace`, `close_gall_review_workspace`, `change_gall_review_workspace`, `save_gall_review_workspace`, `search_workspace_species`, `select_workspace_species`, `clear_workspace_species`, `toggle_trait_value`, `focus_source_text`, and all `search_workspace_host:*`, `select_workspace_host:*`, `clear_workspace_host:*` handlers.

Helper functions — remove all of: `build_workspace_state`, `merge_workspace_params`, `update_workspace`, `update_workspace_assign`, `update_workspace_species_search`, `update_workspace_host_search`, `toggle_workspace_trait_value`, `finalize_workspace_save`, `workspace_update_attrs`, `workspace_alias_candidates`, `workspace_saved_message`, `workspace_trait_options`, `workspace_trait_selected_values`, `trait_value_options`, `merge_trait_option_values`, `trait_label`, `trait_suggested_text`, `trait_evidence_text`, `encode_trait_value`, `decode_trait_value`, `toggle_string_in_list`, `normalize_indexed_form_values`, `update_host_review_search`, `toggle_trait_review_value`, `identity_resolved?`, `default_species_review_aliases`, `exact_species_match_candidate`, `species_summary`, `maybe_default_species_review_decision`, `normalize_species_review_selection`, `normalize_host_review_selection`, `nested_param`, `parse_optional_integer`.

Render — remove the entire workspace `.card` block (the `:if={@workspace}` card, roughly lines 738-1181).

Imports/aliases — remove `FormComponents.alias_collision_warning` import, and aliases only used by workspace code: `Galls`, `Species`, `Taxonomy`.

The module attribute `@detachable_options` and `@trait_filter_keys` are workspace-only — remove them.

**Testing:**
- Show page compiles with `--warnings-as-errors`
- Overview still renders all 4 sections (submission detail, duplicate review, source review, gall table)
- No references to removed workspace assigns or events remain

**Notes:**
This is mostly deletion. Keep `source_text` in Show since the overview has a "Full Extracted Text" panel inside the Source Review card. Keep `parse_integer_param` since it is used by non-workspace event handlers. Verify compilation after removal to catch any missed references.

### Task 3: Add expandable gall summary and review navigation to overview

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/show.ex` (render changes)
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/presenter.ex` (expand species entry view model)

**Behavior:**
Enhance the Gall Review card on the overview:

**Presenter changes:** Expand `species_entry_review_view/1` to include summary data from the extraction payload for the expandable view:
- `extracted_aliases` — list of alias strings
- `extracted_hosts` — list of `%{name, authority}` maps
- `extracted_trait_names` — list of trait name strings that have data

These are read-only summaries for the overview; they don't need the full workspace-level detail.

**Render changes:**
- Remove per-row "Review Gall" buttons from the table
- Replace the flat table with expandable rows: collapsed shows gall name + status, expanded shows aliases/hosts/traits summary as compact lists
- Add a "Proceed to Species Review" link/button below the table that navigates to `~p"/admin/ingestion-review/#{@review_view.id}/review"`, visible only when `@review_view.species_review_unlocked?` is true
- When `species_review_unlocked?` is false, show the existing alert ("Associate a source to enable gall review")

**Testing:**
- Presenter includes extraction summary fields in species entry view
- Overview renders expandable gall rows with correct summary data
- "Proceed to Species Review" link appears only when source is attached
- Link navigates to the workspace route

### Task 4: Workspace master-detail layout with gall selection

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex`

**Behavior:**
Build the full master-detail layout structure:

**Master sidebar:**
- List of gall species from `review_view.species_entries`
- Each row shows: gall name (or "Unnamed gall"), authority, status badge
- Active gall highlighted with border/shadow
- Click fires `select_gall` event that loads the workspace data for that gall
- Progress summary at top: "N remaining, M reviewed"

**Detail pane:**
- Header: gall name, position, "Back to Overview" link
- Form wrapper with `phx-change` and `phx-submit` bindings
- Action buttons at bottom: Save Review, Mark Complete, Clear Selection
- Placeholder sections for Name/Aliases/Hosts/Traits/Description/Source Text (filled in subsequent tasks)

**Gall selection:**
- `handle_event("select_gall", ...)` loads workspace state via `Ingestions.source_ingestion_species_review_workspace!/1` and `build_workspace_state/1`
- Move `build_workspace_state/1` from show.ex into workspace.ex
- Auto-select first unreviewed gall on mount (enhance from Task 1)

**Testing:**
- Master list renders all species entries with correct names and statuses
- Clicking a gall loads its workspace data into the detail pane
- Active gall is visually highlighted in sidebar
- Progress counts are correct

### Task 5: Workspace detail pane — identity resolution and aliases

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex`

**Behavior:**
Move identity resolution and alias review from show.ex into the workspace detail pane.

**Name section:**
- Show extracted name and authority
- Alias collision warning (import `alias_collision_warning` from FormComponents)
- Radio group: mapped / new / skip
- Exact-match suggestion with accept button (when candidate exists and decision is not skip)
- Typeahead for species search (when decision is "mapped")
- Family select dropdown (when decision is "new")
- Reviewer notes textarea

**Aliases section (gated on identity_resolved?):**
- Checkbox list of alias candidates
- Each checkbox shows alias name + "Save as scientific synonym on completion"

**Event handlers to move/recreate:**
- `search_workspace_species` → species typeahead search
- `select_workspace_species` → accept a species mapping
- `clear_workspace_species` → clear species mapping
- `change_gall_review_workspace` → form change handler (species_review params portion)

**Helper functions to move:**
- `exact_species_match_candidate/1`
- `species_summary/1`
- `workspace_alias_candidates/1`
- `default_species_review_aliases/2`
- `identity_resolved?/1`
- `maybe_default_species_review_decision/2`
- `normalize_species_review_selection/1`

**Testing:**
- Name section renders extracted name and authority
- Radio group changes decision state
- Exact match suggestion appears for matching names
- Typeahead searches gall species and selects correctly
- Family select appears only for "new" decision
- Aliases section hidden when decision is "skip"
- Alias checkboxes toggle accepted_aliases list

### Task 6: Workspace detail pane — hosts and traits

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex`

**Behavior:**
Move host and trait review from show.ex into the workspace, with interaction pattern changes.

**Hosts section (gated on identity_resolved?):**
- Compact rows — each host shows extracted name, authority, decision radio (mapped/unresolved/skip), and typeahead when mapped
- Use the same `typeahead` component but with less padding/chrome than the current bordered-card pattern
- Layout: each host is a row in a list, not a standalone bordered card

**Event handlers to move:**
- `search_workspace_host:N` → host typeahead search
- `select_workspace_host:N` → accept a host mapping
- `clear_workspace_host:N` → clear host mapping

**Helper functions to move:**
- `update_host_review_search/4`
- `normalize_host_review_selection/1`

**Traits section (gated on identity_resolved?):**
- Replace `multi_select` component with `multi_select_dropdown` from FormComponents (same component Gall Admin uses)
- Layout: 2-3 column grid using Tailwind `grid grid-cols-2 xl:grid-cols-3 gap-3`
- Each trait shows: label, `multi_select_dropdown` for value selection, small text below showing suggested values and evidence
- Remove the current bordered-card-per-trait pattern

**Event handlers to move:**
- `toggle_trait_value` → value toggle (keep for multi_select_dropdown compatibility or adapt to multi_select_dropdown events)

**Helper functions to move:**
- `workspace_trait_options/2`
- `workspace_trait_selected_values/1`
- `trait_value_options/3`
- `merge_trait_option_values/2`
- `trait_label/1`, `trait_suggested_text/1`, `trait_evidence_text/1`
- `encode_trait_value/2`, `decode_trait_value/1`, `toggle_string_in_list/2`
- `toggle_trait_review_value/3`

**Notes:**
Check `multi_select_dropdown` component attrs in `form_components.ex` to ensure compatibility with the workspace's trait data shape. The Gall Admin uses it with `options`, `selected`, `search_query`, `dropdown_open`, `item_label`, `on_search`, `on_add`, `on_remove`, `on_open`, `on_close` — the workspace trait data may need adapter functions to match this interface.

**Testing:**
- Host rows render with correct extracted data
- Host typeahead search and selection works
- Trait grid renders with correct number of columns
- Trait dropdowns show canonical vocab options
- Suggested values and evidence text display below each trait
- Adding/removing trait values updates workspace state

### Task 7: Workspace detail pane — description, source text, and save actions

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex`

**Behavior:**
Complete the workspace with description review, source text access, and save/complete/skip actions.

**Description section (gated on identity_resolved?):**
- Extracted evidence shown as small text blocks above the textarea
- Editable textarea for reviewed description prose
- Evidence blocks are clickable links that focus the source text panel

**Source text panel:**
- Collapsible `<details>` element at the bottom of the detail pane
- Shows full extracted source text
- Focused fragment highlight (when user clicks "Jump to Source Text" from evidence)

**Event handlers to move:**
- `focus_source_text` → highlight a fragment in the source text panel
- `save_gall_review_workspace` → form submit handler

**Helper functions to move:**
- `merge_workspace_params/2` — form param → workspace state merge
- `workspace_update_attrs/2` — workspace state → context attrs
- `finalize_workspace_save/3` — post-save reload and flash
- `workspace_saved_message/2`
- `normalize_indexed_form_values/1`
- `nested_param/3`
- `parse_optional_integer/1`

**Save flow:**
- Save Review: persists current state, reloads workspace, stays on current gall
- Mark Complete: validates all required fields, persists, marks complete, reloads master list
- Skip action uses the save handler with decision="skip"
- After save, reload the review_view to update master list counts/statuses
- When all galls are complete/skipped, flash message indicates source review complete

**Testing:**
- Description textarea renders with current prose
- Evidence blocks display above textarea
- Source text panel is collapsible and shows full text
- Save persists workspace state and reloads
- Mark Complete validates required fields and transitions status
- Master list updates after save/complete
- Flash messages appropriate to each outcome

