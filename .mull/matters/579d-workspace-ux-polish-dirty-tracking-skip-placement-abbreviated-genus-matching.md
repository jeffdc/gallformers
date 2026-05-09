---
status: raw
tags: [design]
created: 2026-05-09
updated: 2026-05-09
epic: ingestion
---

# Workspace UX polish: dirty tracking, skip placement, abbreviated genus matching

## Three UX issues in the ingestion review workspace

1. **Re-clicking commit on an already-saved gall with no changes throws "Failed to commit"** — the button should be disabled when there's nothing to save.
2. **Skip is a ghost link far from the other actions and is enabled even after the gall has been saved** — it should be a normal button in the action group, disabled once the species has any non-pending status.
3. **Abbreviated genus names ("Q. robur") in source text don't match catalog hosts** — the auto-match in the ingestion pipeline and the host typeahead both miss because the literal "Q." substring isn't in any species name.

## Design

### 1. Dirty tracking + disabled buttons

Add a `:dirty` boolean assign on `workspace.ex`.

- false on mount and on every `load_workspace_for_entry/2`.
- false after a successful `save_current_workspace/2`.
- true in every `handle_info` that mutates the workspace map: `:identity_resolved`, `:identity_reset`, `:host_decision`, `:host_mapped`, `:alias_toggled`, `:trait_updated`, `:description_updated`, `:host_created_and_mapped`. (Search-result info messages don't count.)

In `workspace_action_bar/1`:
- **Save draft** disabled when `!@dirty`.
- **Update/Create gall** disabled when `!@resolved || !@dirty`.

### 2. Skip relocation + status-aware disable

Move the Skip button out of the far-left ghost-link slot into the right-hand action group. Style as a secondary button (border, padding) so it's visible.

Disable Skip when the species `status != "pending"` — i.e. once it has any of `mapped`, `created`, `skipped`, or `complete`. Pass the species status into `workspace_action_bar/1` via the existing `species_entries`/`current_id` lookup.

### 3. Abbreviated genus matching

Modify `Species.search_species_by_name/3`. Detect the pattern `^([A-Z])\.\s+(.+)$` on the input.

- If matched: search for species where the first word of `name` starts with the captured letter AND the name ILIKE-matches the remaining whitespace-separated tokens. Postgres regex `name ~* '^<letter>'` for the first-word constraint, plus the existing multi-term ILIKE filter for the rest.
- If not matched: existing path unchanged.

Affects `assemble.ex` (pipeline auto-match) and `workspace_hosts.ex` typeahead (user search) since both go through the same function.

## Files

- `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex` — `:dirty` assign, set in mutating handlers, reset in save/load. Update `workspace_action_bar/1` signature + disabled logic. Move Skip into action group.
- `lib/gallformers/species.ex` — abbreviated-genus branch in `search_species_by_name/3`.
- `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs` — disabled-button assertions for each scenario; smart-match coverage in `test/gallformers/species_test.exs` (or wherever the existing tests live).

## Out of scope

- Multi-letter abbreviations (`Quer.`, `Q. r.`).
- Re-running auto-match on existing ingestions — they resolve when the user searches.
- Smart matching for other typeaheads (source picker, etc.).

