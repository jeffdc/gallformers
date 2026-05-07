---
status: planned
tags: [design]
created: 2026-05-07
updated: 2026-05-07
epic: ingestion
---

# Species review workspace redesign

## Species Review Workspace Redesign

Replaces the current basic review form (`workspace.ex`) with a full workspace editor. Same route (`/admin/ingestion-review/:id/review`), same backend schema, richer UI and interaction model. Design based on high-fidelity React prototype (2026-05-07).

Relates: fa48 (original UI design), a4fe (apply review decisions)

### Core UX Model

**Identity is the gate.** Five sections: Identity, Hosts, Aliases, Traits, Description. Sections 2–5 locked until identity resolves to "existing" (mapped to catalog gall) or "new" (will be created later).

**Three identity states:**
- `null` — unresolved. Suggested match shown if auto-match found, but reviewer must explicitly "Accept & map" (no auto-selection). Typeahead search + "Treat as new" available.
- `existing` — mapped to catalog gall. Sections show merge views (current gall data alongside extracted).
- `new` — treated as new species. Sections show extracted data only.

**Draft vs. Commit:**
- "Save draft" → action: "save", writes review_payload, status becomes in_progress
- "Commit" → action: "save" with decision set, status becomes mapped/pending/skipped. Full "complete" action deferred.
- "Skip" → action: "save" with decision: "skip", status becomes skipped, auto-advances

### Architecture

**Single LiveView, section LiveComponents.** Parent `workspace.ex` owns top bar, sidebar, state. Each section (Identity, Hosts, Aliases, Traits, Description) is a LiveComponent. Source text drawer is a LiveComponent toggled by parent.

**Existing gall data loading.** On identity resolve to "existing", parent loads mapped gall's current data via a new presenter function and passes it to sections as `existing_gall` assign (`nil` when identity is `null` or `new`).

### Key Decisions

1. Traits use multi-select from controlled vocab. Extracted text is read-only evidence.
2. Draft saves reuse existing review_payload column, distinguished by status.
3. Commit uses "save" action initially. Full "complete" action (create-on-commit) deferred — backend already supports it.
4. Identity never auto-selects. Suggested match requires explicit "Accept & map".

### Deferred

- Evidence fragment system — chips render but inert. Drawer shows raw text without highlights.
- Full create-on-commit — backend path exists but UI uses "save" action only initially.
- Cmd-S save, auto-advance keyboard shortcut.

---

## Implementation Plan

**Goal:** Replace the existing workspace form with a full section-based review workspace using LiveComponents, identity gating, and merge views.

**Architecture:** Single parent LiveView (`workspace.ex`) rewritten to manage state and coordinate section LiveComponents. Each section is a self-contained LiveComponent that receives data via assigns and sends decisions back to the parent via `send/2` messages. Existing gall data loaded on identity resolution and passed down.

**Tech Stack:** Phoenix LiveView, LiveComponents, Tailwind CSS, existing component library (badge, button, typeahead, multi_select).

### Task 1: Backend — Existing gall data loader for merge views

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/presenter.ex` (add function)
- Test: `test/gallformers_web/live/admin/ingestion_review_live/presenter_test.exs` (create if needed, or add to workspace_test.exs)

**Behavior:**
Add `Presenter.load_existing_gall_data(species_id)` that assembles everything needed for merge views into a single map:
- Hosts: from `Galls.HostAssociations.get_hosts_for_gall(species_id)` → `[%{host_species_id, host_name}]`
- Aliases: from `Species.get_aliases_for_species(species_id)` → `[%{id, name, type}]`
- Traits (current filter values): from `Galls.get_gall_filter_values(species_id)` → `%{colors: [...], shapes: [...], ...}`
- Description: from `SpeciesSources` if a description exists for this species

Returns `%{hosts: [...], aliases: [...], traits: %{...}, description: "..."}` or `nil` if species_id is nil.

Also add `Presenter.load_suggested_match(extracted_name)` that searches for an exact match in the gall catalog without auto-selecting. Returns `%{id, name, authority, family, summary}` or `nil`. Uses `Species.search_species_by_name/3` for exact match, then enriches with host count, alias count, trait count for the summary line.

**Testing:**
- `load_existing_gall_data/1` returns hosts, aliases, traits, description for an existing gall with data
- `load_existing_gall_data/1` returns empty collections for a gall with no associations
- `load_existing_gall_data/1` returns nil for nil species_id
- `load_suggested_match/1` finds exact name match
- `load_suggested_match/1` returns nil when no match

### Task 2: Parent LiveView shell — state model, sidebar, top bar

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex` (rewrite render + state management)
- Modify: `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs`

**Behavior:**
Rewrite `workspace.ex` as the orchestrating shell. Remove all inline form sections (they move to components in later tasks). Keep the mount/handle_params lifecycle.

**New state model:**
```
assigns:
  review_view        — from Presenter (ingestion metadata, species list)
  species_entries    — flat list ordered by position (no grouping)
  current_id         — id of species being viewed
  selected_species   — the SourceIngestionSpecies record for current_id
  workspace          — workspace state map from SourceIngestionSpeciesReview.workspace!
  existing_gall      — %{hosts, aliases, traits, description} or nil (loaded on identity resolve)
  suggested_match    — %{id, name, ...} or nil (loaded on mount per species)
  filter_options     — %{colors: [...], shapes: [...], ...} from Galls.get_all_filter_options() (loaded once on mount)
  drawer_open        — boolean
  source_text        — full extracted text string
  saved_at           — timestamp string or nil
```

**Sidebar:** Flat list of species entries ordered by `position`. Each row: zero-padded position, italic name, authority, state mark. Active row highlighted with left border. Header shows "Species in source" + count. Footer shows keyboard hint. Progress counter in top bar area.

**Top bar:** Breadcrumb (Ingestions / source_id / Species review), source title + authors + year, progress bar (completed + skipped fills), save state indicator, source text drawer toggle button.

**Section rendering:** For now, render placeholder divs for each section that will be replaced by LiveComponents in subsequent tasks. Show "Locked" state for sections 2-5 when identity is unresolved.

**Handle_info handlers:** Stub handlers for messages that section components will send:
- `{:identity_resolved, resolution, mapped_species}` — loads existing_gall, updates workspace
- `{:identity_reset}` — clears existing_gall, re-locks sections
- `{:host_decision, index, action}` — updates host review in workspace
- `{:alias_toggled, index, accepted}` — updates alias in workspace
- `{:trait_updated, name, selected_values}` — updates trait in workspace
- `{:description_updated, mode, text}` — updates description in workspace

**Testing:**
- Mounts and renders flat sidebar with species entries in position order
- Auto-selects first unreviewed entry
- Clicking sidebar entry switches selected species
- Progress counter reflects completed/skipped counts
- Top bar shows source title and breadcrumb
- Drawer toggle opens/closes (initially closed)

### Task 3: Identity section LiveComponent

**Files:**
- Create: `lib/gallformers_web/live/admin/ingestion_review_live/workspace_identity.ex`
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex` (wire in component)
- Modify: `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs`

**Behavior:**
LiveComponent with three render states based on `workspace.species_review.decision`:

**State 1 — Unresolved with suggestion (`decision == nil`, `suggested_match != nil`):**
- Shows extracted name + authority + mention count
- Green suggestion card: matched gall name, authority, family, summary (host/alias/trait counts)
- "Accept & map" primary button
- Below: "Not the right match? Search a different gall · Treat as new species"

**State 2 — Unresolved, searching (`decision == nil`, suggestion rejected or absent):**
- Typeahead input with magnifier icon
- Results list: italic name, authority, family, host count, alias count, "map →" on hover
- "or" separator
- "Treat as new species" dashed-border tile with explanatory subtext

**State 3 — Resolved (`decision == "mapped"` or `"new"`):**
- Compact summary: green "Mapped · existing" or purple "Treated as new" pill
- Species name + authority + family + summary
- "Change..." ghost button
- If mapped name differs from extracted: "+alias" warning pill on "Extracted as <name>" line

**Communication with parent:**
- "Accept & map" → `send(self(), {:identity_resolved, :existing, species_summary})`
- "map →" in typeahead → same as above with selected species
- "Treat as new" → `send(self(), {:identity_resolved, :new, nil})`
- "Change..." → `send(self(), {:identity_reset})`

**Typeahead:** Reuse existing `.typeahead` component. Search event handled within the component via `handle_event`. Calls `Species.search_species_by_name(query, "gall", 10)`.

**Testing:**
- Renders suggestion card when suggested_match present
- "Accept & map" resolves identity to existing and sends message to parent
- "Search a different gall" opens typeahead
- Typeahead returns results and "map →" resolves identity
- "Treat as new" resolves identity to new
- Resolved state shows correct pill (existing vs new)
- "Change..." resets identity to unresolved
- "+alias" pill shown when mapped name differs from extracted name

### Task 4: Hosts section LiveComponent

**Files:**
- Create: `lib/gallformers_web/live/admin/ingestion_review_live/workspace_hosts.ex`
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex` (wire in component)
- Modify: `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs`

**Behavior:**
LiveComponent. When identity is unresolved (`decision == nil`), renders locked state: section header with "Locked · resolve identity first" note, body hidden.

When unlocked:

**Existing mode (`decision == "mapped"`):**
- "Currently linked" group: read-only rows from `existing_gall.hosts`. Each shows green dot, italic host name, "linked" label.
- "From source" group: rows from `workspace.host_reviews`. Each shows:
  - Italic host name
  - Match quality pill: "exact match" (ok), "fuzzy match" (warn), or "no plant match" (warn) based on auto-match status from host_review
  - Note if present (e.g. "alternate sexual generation")
  - Action button: accept/decline toggle
  - Hosts already linked to existing gall get "already linked" muted pill and "no action needed" label
- Header stat: "N of M accepted"

**New mode (`decision == "new"`):**
- Only "From source" group, same behavior minus the "already linked" check

**No-match hosts (match_kind == "none"):** For now, render the WCVP callout UI (yellow background, candidate name + family + wcvp_id) but the "+ Create from WCVP" button sends `{:create_host_from_wcvp, index, wcvp_data}` to parent. Parent can handle this later — for initial ship, flash a "not yet implemented" or wire to `Plants.create_host_with_associations` if straightforward.

**Communication with parent:**
- Accept/decline → `send(self(), {:host_decision, index, "accept" | "decline"})`

**Testing:**
- Renders locked state when identity unresolved
- Unlocks and shows host list when identity resolved
- Existing mode shows "Currently linked" and "From source" groups
- New mode shows only "From source"
- Accept/decline toggles per host row
- "Already linked" hosts marked as such in existing mode
- No-match hosts show WCVP callout
- Header shows accepted count

### Task 5: Aliases and Description section LiveComponents

**Files:**
- Create: `lib/gallformers_web/live/admin/ingestion_review_live/workspace_aliases.ex`
- Create: `lib/gallformers_web/live/admin/ingestion_review_live/workspace_description.ex`
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex` (wire in components)
- Modify: `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs`

**Aliases behavior:**
Locked when identity unresolved. When unlocked:
- Existing mode: "Currently on gall" group shows existing aliases as read-only muted pills. "From source" group shows extracted aliases as checkbox list.
- Aliases that already exist on the gall: disabled checkbox + "already on gall" muted pill.
- New mode: just the checkbox list, no existing group.
- Header stat: "N of M accepted"
- Communication: `send(self(), {:alias_toggled, index, boolean})`

**Description behavior:**
Locked when identity unresolved. When unlocked:
- Existing mode: segmented control (Keep current / Append / Replace). Below: read-only current description panel (italic, muted background). Below: editable textarea.
  - "Keep current" → textarea shows existing description
  - "Append" → textarea shows existing + "\n\n" + extracted
  - "Replace" → textarea shows extracted only
  - User can freely edit the textarea regardless of mode
- New mode: just the textarea pre-populated with extracted description, no segmented control.
- Communication: `send(self(), {:description_updated, mode, text})`

**Testing:**
- Aliases: locked state, existing pills, checkbox toggles, duplicate detection, accepted count
- Description: locked state, segmented control switches content, textarea editable, new mode skips segmented control

### Task 6: Traits section LiveComponent

**Files:**
- Create: `lib/gallformers_web/live/admin/ingestion_review_live/workspace_traits.ex`
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex` (wire in component)
- Modify: `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs`

**Behavior:**
Locked when identity unresolved. When unlocked, renders a table-like grid of trait rows.

**Columns (existing mode):** Trait | Current | Extracted | Result | Actions
**Columns (new mode):** Trait | Extracted | Result | Actions

**Per-row:**
- "Trait" cell: human label (e.g. "Shape") + monospace key (e.g. `shape`)
- "Current" cell (existing only): current filter values as comma-joined text, or em-dash if none
- "Extracted" cell: raw LLM text from `trait_review.raw_evidence` joined, or suggested values text. Read-only.
- "Result" cell: multi-select using filter options from `filter_options[trait_key]`. Pre-populated with `trait_review.selected_values` (which default to current values for existing, or suggested values for new).
- "Actions" cell: decline/restore toggle. Decline clears the result selection. Restore re-populates from defaults.

**Trait key mapping:** Use the existing `@trait_option_keys` mapping from `SourceIngestionSpeciesReview` to connect trait names to filter option keys. The parent passes `filter_options` (from `Galls.get_all_filter_options()`) to this component.

**Communication:** `send(self(), {:trait_updated, trait_name, selected_values})`

**Notes:**
- The multi_select component in `form_components.ex` handles pill-style toggles. Each trait row needs its own instance with the options filtered to that trait type.
- The `detachable` trait is a special case — it's a single boolean/string value, not a multi-select. Handle as a simple toggle or dropdown.

**Testing:**
- Locked state when identity unresolved
- Renders trait rows with correct columns for existing vs new mode
- Current values shown for existing mode
- Extracted evidence shown as read-only text
- Multi-select allows picking from controlled vocabulary
- Decline clears selection, restore brings it back
- Detachable trait renders as single-value control
- Header shows "N of M kept" count

### Task 7: Source text drawer LiveComponent

**Files:**
- Create: `lib/gallformers_web/live/admin/ingestion_review_live/workspace_drawer.ex`
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex` (wire in component)
- Modify: `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs`

**Behavior:**
Slide-in panel from the right, toggled by parent's `drawer_open` assign. Uses CSS transform for animation (Tailwind `translate-x-full` / `translate-x-0` with transition).

**Structure:**
- Scrim overlay (click closes)
- Panel: 540px wide (or full width on mobile)
- Header: "Extracted source text", filename, page count, close button
- Body: full extracted text in monospace, `whitespace-pre-wrap`
- No evidence highlighting for initial ship — just the raw text

**Communication:**
- Close button / scrim click / Esc → parent handles via existing drawer_open toggle

**Notes:**
- Evidence fragment highlighting is structurally deferred. The component accepts a `highlight` assign (nil for now) and has the DOM structure ready for future `<mark>` wrapping.
- Esc key handling is on the parent LiveView's `phx-window-keydown`.

**Testing:**
- Drawer hidden by default
- Toggle button opens drawer with source text
- Close button / scrim click closes drawer
- Source text renders in monospace

### Task 8: Save, commit, skip flow + keyboard navigation

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex` (wire up actions)
- Modify: `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs`

**Behavior:**
Wire up the three action buttons in the detail pane header and footer.

**Save draft:**
- Collects current workspace state from all sections
- Calls `Ingestions.update_source_ingestion_species_review` with action: "save"
- Updates `saved_at` timestamp
- If status was "unreviewed", becomes "in_progress"
- Flash: "Draft saved"

**Commit (Update gall / Create gall):**
- Disabled until identity resolved (button shows "Create / update" when unresolved)
- When existing: button reads "Update gall", sends action: "save" with decision: "mapped"
- When new: button reads "Create gall", sends action: "save" with decision: "new"
- On success: marks species status appropriately, auto-advances to next unreviewed species
- Auto-advance: find next entry with status "pending"/"unreviewed" in position order, switch to it. If none remain, stay on current.

**Skip:**
- Sends action: "save" with decision: "skip"
- Auto-advances to next unreviewed

**Keyboard navigation:**
- `J` / `ArrowDown`: next species in sidebar
- `K` / `ArrowUp`: previous species in sidebar
- `Escape`: close drawer
- `/`: focus search input (if identity section typeahead is visible)
- All keyboard handlers gated on `e.target.tagName not in ["INPUT", "TEXTAREA", "SELECT"]`
- Implemented via `phx-window-keydown` on the parent + JS hook for focus detection

**State collection for save:**
Build the attrs map from current workspace state to match the format `SourceIngestionSpeciesReview.update_review/3` expects:
```
%{
  "action" => "save" | "complete",
  "species_review" => %{"decision" => ..., "species_id" => ..., "accepted_aliases" => ...},
  "host_reviews" => %{index => %{"decision" => ..., "species_id" => ..., ...}},
  "trait_reviews" => %{name => %{"selected_values" => [...]}},
  "description_prose" => "..."
}
```

**Testing:**
- Save draft persists review payload and updates saved_at
- Commit with existing identity saves with mapped decision
- Commit with new identity saves with new decision
- Commit auto-advances to next unreviewed species
- Skip sets status to skipped and auto-advances
- Commit button disabled when identity unresolved
- J/K navigates species list
- Esc closes drawer

