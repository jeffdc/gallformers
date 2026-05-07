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
- "Save draft" → writes review_payload + status `in_progress`
- "Commit" → writes review_payload + status `mapped`/`created`, auto-advances to next unreviewed
- "Skip" → status `skipped`, auto-advances

### Architecture

**Single LiveView, section LiveComponents.** Parent `workspace.ex` owns top bar, sidebar, state. Each section (Identity, Hosts, Aliases, Traits, Description) is a LiveComponent. Source text drawer is a LiveComponent toggled by parent.

**Existing gall data loading.** On identity resolve to "existing", parent loads mapped gall's current data:
- `Galls.get_gall_filter_values(species_id)` → current traits
- `Galls.HostAssociations.get_hosts_for_gall(species_id)` → current hosts
- `Species.get_aliases_for_species(species_id)` → current aliases
- `SpeciesSource` description if available

Passed to sections as `existing_gall` assign. `nil` when identity is `null` or `new`.

### Section Details

**Identity:** Three render states. Suggested match card with "Accept & map" button. Typeahead search when no match or rejected. Resolved summary with "Change..." button. "Treat as new" tile. Never auto-map.

**Hosts:** Two groups when existing: "Currently linked" (read-only) and "From source" (accept/decline per row). Match quality pills. No-match hosts show WCVP create callout via `Plants.quick_create_host_from_wcvp`. New mode: only "From source".

**Aliases:** Existing as read-only pills. Extracted as checkbox list. Duplicates marked "already on gall" disabled.

**Traits:** Per-trait rows. "Extracted" column shows LLM free text as read-only evidence. "Result" column is multi-select from controlled vocabulary (reusing `multi_select` component with filter field options). Pre-populated with current values when existing. Reviewer reads extraction, picks matching vocab values.

**Description:** Existing mode: segmented control (Keep/Append/Replace), read-only current panel, editable textarea. New mode: just textarea.

### Sidebar & Navigation

Flat per-species list ordered by position (replaces current grouped-by-name). Position number, italic name, authority, state mark (completed/in_progress/skipped/unreviewed). Active row highlighted. Progress counter.

Keyboard: J/K species navigation, Esc closes drawer, `/` focuses search. `phx-window-keydown` on parent.

### Styling

Tailwind throughout, consistent with existing admin. Reuse `badge`, `button`, `typeahead`, `multi_select`, `card` components. Design prototype's warm-paper palette is reference, not pixel-perfect target.

### Schema Changes

None. Existing `review_payload` JSONB + status enum support all states. `SpeciesReview.decision` gains `"new"` value alongside `"mapped"` and `"skip"`.

### Deferred

- **Evidence fragment system** — chips render but inert. Drawer shows raw text without highlights. Structurally ready for future fragment anchoring.
- **Full create-on-commit** — "New" unlocks sections for curation but commit persists review payload only. Actual gall creation separate.
- **Cmd-S save shortcut**
- **Auto-advance keyboard shortcut**

### Key Decisions

1. Traits use multi-select from controlled vocab (not single string values). Extracted text is read-only evidence, not the editable value.
2. Draft saves reuse existing review_payload column, distinguished by status field. No new columns.
3. "Treat as new" deferred — persists review payload, actual gall creation happens separately.
4. Identity never auto-selects. Suggested match shown but requires explicit "Accept & map".
