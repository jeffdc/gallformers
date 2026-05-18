---
status: raw
tags: [design]
created: 2026-05-18
updated: 2026-05-18
epic: source-ingestion
---

# Curator-built descriptions from bucketed evidence prose

## Goal

Curator builds the species description by selecting from a list of evidence prose chunks. Pipeline surfaces well-organized raw material with relevance signals; pipeline does not synthesize description prose.

## Why

The current `description` EvidenceCell asks the LLM for "a free-text morphological description… quote the most relevant sentence as evidence." In practice this produces a single quote, narrowly scoped to gall morphology, and frequently mis-attributed across dual-generation species (A. quercushirta agamic and sexgen records both received the same sexgen gall-description string in the Nicholls run). Even when correct, a one-quote field cannot cover the diagnosis / biology / distribution / comparisons that go into a real description.

Description is a synthesis task; the rest of the pipeline is extraction. Synthesis belongs with the curator. The pipeline's job is to surface relevant raw material in a form that makes selection fast.

## Pipeline-side design

**Remove `GallRecord.description`** entirely. Drop the field from the schema, the section of the extract-facts prompt, and the substring-gate handling. Bump `SCHEMA_VERSION`.

**Enrich `ProseParagraph`** with fields derived from existing pipeline output:

```
char_start, char_end       offsets into ReviewSource.normalized_text — UI deep-linking
is_mention                 span_id ∈ candidate.mention_span_ids
is_cited                   span_id appears in any Evidence.block_id in this record
cited_by_fields            field paths citing this span, e.g. ["gall_traits.color"]
name_occurrences           case-insensitive count of candidate.gall_maker_mention in text
relevance                  "high" | "medium" | "low"
```

The structural signals (char offsets, is_mention, name_occurrences) populate at evidence_pack time. The citation-derived signals (is_cited, cited_by_fields, relevance) populate in extract_facts when the GallRecord is built — at that point both the prose pack and the scrubbed LLM citations are in hand, and ProseParagraph leaves extract_facts fully populated for downstream stages to pass through. (Originally scoped to assemble.py; moved to extract_facts.py during implementation for cleaner data-flow locality.)

**Bucket rule** (deterministic, in `extract_facts.py` with named constants):

```
HIGH    if is_cited
MEDIUM  if (is_mention OR name_occurrences >= 1) AND len(text) >= 80
LOW     otherwise
```

Length floor (80) demotes heading and table-row fragments out of MEDIUM. The rule lives in one function; tuning is local and transparent.

No new LLM stages. No content-pattern regex. All new signals derive from output already produced by `find_candidates` (mentions), `extract_facts` (citations), and the candidate name itself.

## UI-side design

The Elixir review workspace renders a chunk-picker per species: progressive disclosure starting at HIGH, expandable to MEDIUM and LOW, document order preserved, include/exclude toggles, live description draft (concatenation of selected chunks, curator-editable), source-context view using char offsets into `ReviewSource.normalized_text`. The existing description rendering is removed.

### Sibling-removal cleanup (precondition)

Per-generation records are discrete species in pipeline and app. Remove all same-name sibling collation and merge logic:

- `lib/gallformers_web/live/admin/ingestion_review_live/presenter.ex`: delete `collate_species_entries/1` (lines 210–232); drop `sibling_ids: []` from `species_entry_review_view/1` (line 203). Each entry passes through ungrouped.
- `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex`: delete `merge_sibling_data/2`, `merge_unique_by/3`, `merge_trait_reviews/2`, `merge_description_prose/2`, `merge_evidence_prose/2` (lines 659–729) and `save_sibling_entries/3` (lines 932–945). Strip `sibling_ids` from `load_workspace_for_entry/2`, `save_current_workspace/2`, and the `skip_species` event.

The sidebar lists each generation as its own row (e.g. `Acraspis quercushirta (agamic)`, `Acraspis quercushirta (sexgen)`). The existing `Enum.sort_by(..., & &1.extracted_name)` clusters them adjacent. No DB-schema change — sibling-ness was purely Presenter-derived.

### Bundle importer + DB

`lib/gallformers/ingestions/bundle_importer.ex`:

- Accept schema 1.5.0 wherever version compatibility is checked.
- `extract_species_attrs/2:95-99` reads `record["description"]` into `description_prose`. With 1.5.0 the field is gone — set `description_prose = ""` on import. The DB column stays as the destination for the curator-built draft.
- `build_evidence_prose/1` and `normalize_evidence_paragraph/1` (lines 132+) currently keep only `span_id`/`page`/`text`. Extend to also carry `char_start`, `char_end`, `is_mention`, `name_occurrences`, `is_cited`, `cited_by_fields`, `relevance`. `SourceIngestionSpecies.evidence_prose` is jsonb — no migration needed for this.
- Persist `review_artifact["source"]["normalized_text"]` onto the `SourceIngestion` row.

New migration: add `normalized_text :text` column to `source_ingestions`. No backfill — no 1.5.0 artifacts have been imported yet.

### Workspace layout

In `workspace.ex` render: delete the standalone `evidence_prose_section/1` (lines 494–553). Its role is absorbed by the picker. Section order becomes Identity → Hosts → Aliases → Traits → **`WorkspaceDescription`** → action bar. The right-side source-text drawer is unchanged for now; a follow-up may switch it to `normalized_text` too.

`handle_params/3` loads `SourceIngestion.normalized_text` alongside the review_view and threads it through to `WorkspaceDescription` as an assign.

### `WorkspaceDescription` live_component (rewritten end-to-end)

Filename unchanged (`workspace_description.ex`); contents replaced.

**Assigns**

- `selection` — `MapSet` of selected `span_id`s
- `disclosure_level` — `:high | :medium | :all`, default `:high`, cumulative
- `mode` — `:keep | :append | :replace`, only meaningful when existing gall, default `:replace`
- `draft` — current draft text
- `draft_dirty` — bool; flips true on first textarea keystroke
- `edit_open` — bool; preview-vs-textarea toggle
- `context_span_id` — non-nil while view-in-context modal is open
- pass-throughs: `evidence_prose`, `normalized_text`, `existing_gall`

**Events** (phx-target=@myself)

`toggle_chunk(span_id)`, `set_disclosure(level)`, `open_edit`, `close_edit`, `update_draft` (textarea blur), `regenerate_draft`, `open_context(span_id)`, `close_context`, `set_mode(mode)`.

**Messages back to parent**

`{:description_updated, %{selection, draft, mode, dirty}}` on any change; parent merges into workspace state and marks the workspace dirty.

**Initial selection on load**

If `review_payload.description_review.selected_span_ids` is present, use it. Otherwise default to span_ids where `relevance == "high" OR is_cited == true` — cited paragraphs are load-bearing regardless of bucket. Draft is the document-order concatenation of selected chunks joined with `\n\n`, unless `draft_dirty` was persisted true, in which case the saved draft is used verbatim.

**Edit-dirty UX**

Chunk checkboxes and the "Regenerate from picks" button carry `phx-confirm="You've edited the draft. Discard your edits and regenerate from chunks?"` when `draft_dirty` is true. No prompt when clean — toggles live-recompute the draft.

**Disclosure**

Cumulative segmented control: `[● High N]  [○ + Medium N]  [○ + All N]`. No bulk actions in v1; revisit once curator has used the primary UI.

**Layout sketch**

```
┌─ Description ────────────────────────────────────────────────┐
│ Draft preview (12 chunks · 870 chars)        [Edit draft ▸]  │
│   The gall is sub-ovoid, 2 mm long…                          │
│   Galls observed on Quercus alba, Q. macrocarpa…             │
│                                                              │
│ Pick chunks                                                   │
│  Show:  [● High 12]  [○ + Medium 8]  [○ + All 43]            │
│                                                              │
│ [✓] p.3  S_0021   mention · cited: traits.color              │
│     The gall is sub-ovoid, 2 mm long…    view in context ↗   │
│ [✓] p.3  S_0024   cited: hosts[0].scientific_name            │
│     Galls observed on Quercus alba…      view in context ↗   │
│ [ ] p.4  S_0031                                              │
│     Sexual generation adults emerge…     view in context ↗   │
│                                                              │
│ ── existing gall only ───                                    │
│ Apply as: ○ Keep current  ○ Append  ● Replace                │
└──────────────────────────────────────────────────────────────┘
```

### View-in-context modal

- Uses the existing `<.modal>` from `core_components`.
- Size: `max-w-[90vw]` width, body ~80vh with internal scroll.
- Source: `SourceIngestion.normalized_text` (full document — NOT `evidence_prose`).
- Body: `<pre class="whitespace-pre-wrap font-mono text-sm">` rendering the entire `normalized_text`, with the slice `[char_start, char_end]` wrapped in `<mark>` for highlight.
- On open: small JS hook scrolls the `<mark>` into view, centered.
- Header: page number, span_id, cited-by chips. Footer: close.

### Parent workspace state extension

Add three keys to the workspace map; `description_prose` keeps its existing role:

```elixir
description_prose: "...",                # → species_source.description on commit
description_selection: ["S_0021", ...],  # selected span_ids in document order
description_mode: "replace",             # only meaningful with existing gall
description_draft_dirty: false           # has curator hand-edited the draft?
```

`review_payload.description_review` extends to persist `selected_span_ids`, `mode`, `draft_dirty`. The existing `edited` flag stays (preserves the completion gate at `source_ingestion_species_review.ex:389`) and flips true on first toggle, edit, or mode change.

`collect_workspace_attrs/2` in `workspace.ex:947` and `normalize_source_ingestion_species_review/2` in `source_ingestion_species_review.ex:135` are extended to round-trip the new keys.

### Reusable-component policy

No new entries to `core_components` / `ui_components` for v1 — chunk cards, the sticky preview pane, and the cumulative disclosure control all live inline inside `WorkspaceDescription`. If any becomes a reuse candidate later, lift it then; do not pre-abstract.

## Out of scope

- **Anaphoric description spans** (paragraphs using "it" / "this species") with no mention and no citation. These fall into LOW. Similarly, paragraphs that use only the abbreviated form ("A. quercushirta") rather than the full mention name will have `name_occurrences=0` and may also drop to LOW. If experience shows this misses too much real content, consider an LLM re-ranker over LOW spans, or counting sibling-name substrings — but only with evidence from real curation.
- **Field guides and terse catalogs.** Different failure mode (cross-species contamination in evidence_pack, find_candidates misses on table cells, etc.). Separate matter.
- **Bulk-select actions** in the picker. Deferred until curator has used the primary UI.
- **Switching the right-side source-text drawer to `normalized_text`.** Follow-up; the drawer keeps its legacy source for this change.

## Decision log

- **Rejected: a closed-vocab `kind` taxonomy** (description / synonymy / specimens / heading / …). Overfit to taxonomic-treatment-style papers; would not generalize across field guides, regional notes, historical monographs.
- **Rejected: a new LLM classification stage.** Existing signals (citations + mentions + length) plausibly suffice. Adding complexity to a pipeline whose complexity is already being questioned is the wrong direction without evidence the simpler approach fails.
- **Rejected: negative instruction in the prompt** ("do not produce a synthesized description"). The Instructor-bound response schema constrains output shape; redundant negative instructions add noise. The schema is the contract.
- **Deferred: extending `extract_facts` to emit per-span relevance.** Would couple extraction with curation prep and risk degrading extraction. Revisit if the deterministic rule misses important spans in practice.
- **Rejected: sibling collation in the workspace.** With generation-aware candidate splitting, agamic and sexgen records are discrete species in both pipeline and app. The same-name grouping in `Presenter.collate_species_entries/1` and the merge fan-out in `workspace.ex` are obsolete and removed as a precondition for the picker.
- **Rejected: windowed view-in-context (±N chars around the chunk).** Reviewer needs surrounding document structure (headings, neighboring treatments) to validate a chunk; a narrow window is more annoying than helpful. Full `normalized_text` in a wide modal with scroll-to-highlight.
- **Rejected: modal source for view-in-context = `evidence_prose`.** The picker already shows those chunks; the modal exists specifically to surface text *outside* the curated subset.
- **Rejected: on-toggle "overwrite manual edits silently" or "warning banner + manual regenerate button".** Phoenix `phx-confirm` prompts are used elsewhere in the app; consistent with that pattern. Prompt fires on toggle and on regenerate when `draft_dirty`.

## Coordination

Schema lives in `services/source-ingestion/src/ingest/schemas.py` and is consumed by the Elixir review workspace. The pipeline-side schema (1.5.0) has landed in the working tree; new artifacts have not yet been produced. Both sides land on the same branch (`alpha-ui`) so the importer + UI are ready when the next pipeline run completes.

Sequencing within the UI work (single branch, separable commits):

1. Sibling-removal cleanup (no schema dependency; lowest risk).
2. Bundle importer + migration for schema 1.5.0 (`normalized_text` column, new ProseParagraph fields, drop description ingestion).
3. New `WorkspaceDescription` component + view-in-context modal + removal of `evidence_prose_section/1` in `workspace.ex`.
4. Persistence wiring (`review_payload.description_review` extension, `collect_workspace_attrs/2` and normalize updates).

## Implementation status

Pipeline-side: complete on branch `alpha-ui` (uncommitted). SCHEMA_VERSION bumped 1.4.0 → 1.5.0. All 193 tests pass; ruff lint clean on touched files. Pre-existing pyright errors in `scripts/build_example_bundle.py` fixed in the same change set.

UI-side: design captured (this matter, 2026-05-18). No new bundle artifacts produced yet — picker will be exercised against the first re-imported 1.5.0 bundle. Next: docket the matter and decide whether to start with the cleanup commit or write an implementation plan first.


## Implementation Plan

**Goal:** Replace the LLM-generated description string with a curator-built chunk-picker workspace section, sourced from the new structural signals on `ProseParagraph` (schema 1.5.0).

**Architecture:** Single branch (`alpha-ui`), commits ordered so each step is independently shippable: sibling-removal cleanup → DB migration + schema field → importer for 1.5.0 → new LiveView component (chunk picker + draft + view-in-context modal) → persistence round-trip. The picker is a `live_component` inside the existing `Workspace` LiveView; state changes flow through `handle_info` messages to the parent, identical to the pattern already used by `WorkspaceIdentity`, `WorkspaceHosts`, `WorkspaceTraits`.

**Tech Stack:** Elixir / Phoenix LiveView, Ecto + Postgres, Tailwind. One small LiveView JS hook for scroll-to-mark in the modal.

---

### Task 1: Sibling-removal in Presenter

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/presenter.ex` — delete `collate_species_entries/1` (lines 210–232); drop `sibling_ids: []` from `species_entry_review_view/1` (line 203); replace the `collate_species_entries(...)` call with `Enum.reject(&(&1.extracted_name in [nil, ""]))` so empty-name filtering is preserved.
- Test: `test/gallformers_web/live/admin/ingestion_review_live/presenter_test.exs`

**Behavior:**
Species entries pass through ungrouped — each generation appears as its own row. No `sibling_ids` on the returned view structs. Status is each entry's own; cross-group reconciliation removed.

**Testing:**
- Two entries with the same `extracted_name` but different generation suffixes (`"X (agamic)"`, `"X (sexgen)"`) appear as two separate items.
- Entries with nil/empty `extracted_name` are still filtered out.
- Returned items have no `sibling_ids` key (assert via `Map.has_key?/2`).

**Notes:**
- Existing tests that assert sibling grouping must be rewritten or deleted.

### Task 2: Sibling-removal in Workspace LiveView

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex`
  - Delete `merge_sibling_data/2`, `merge_unique_by/3`, `merge_trait_reviews/2`, `merge_description_prose/2`, `merge_evidence_prose/2` (lines 659–729).
  - Delete `save_sibling_entries/3` (lines 932–945).
  - `load_workspace_for_entry/2` (line 632): drop the `sibling_ids` lookup, the `sibling_views` load, the merge call, and `Map.put(:sibling_ids, ...)`.
  - `save_current_workspace/2` (line 917) and `skip_species` event (line 99): drop the `save_sibling_entries(...)` call.
- Test: `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs`

**Behavior:**
Workspace loads and saves a single entry at a time. No fan-out to same-name entries.

**Testing:**
- Loading the workspace for an entry with a same-name companion in the source does NOT merge that companion's hosts/traits/aliases/prose.
- Saving the workspace updates only the current entry; companions retain their prior status.
- Skipping is local.

**Notes:**
- Depends on Task 1 (Presenter no longer emits `sibling_ids`).
- This task is mechanically separable and can land as the first commit.

### Task 3: DB migration — `normalized_text` column

**Files:**
- Create: `priv/repo/migrations/20260518100000_add_normalized_text_to_source_ingestions.exs`

**Behavior:**
Adds a nullable `:text` column `normalized_text` to `source_ingestions`. No backfill (no 1.5.0 artifacts imported yet).

```elixir
def change do
  alter table(:source_ingestions) do
    add :normalized_text, :text
  end
end
```

### Task 4: SourceIngestion schema field

**Files:**
- Modify: `lib/gallformers/ingestions/source_ingestion.ex` — add `field :normalized_text, :string` to the schema block (around line 128), include in any cast list that should round-trip it.

**Behavior:**
Field round-trips through Ecto.

**Testing:**
Indirectly covered by the importer test in Task 5 (write + read via `Repo`).

### Task 5: Bundle importer for schema 1.5.0

**Files:**
- Modify: `lib/gallformers/ingestions/bundle_importer.ex`
  - Add 1.5.0 to the accepted schema-version set wherever version compatibility is enforced.
  - `extract_paper_attrs/1` (line 60): add `normalized_text: unwrap_value(Map.get(source, "normalized_text"))`.
  - `extract_species_attrs/2:95-99`: drop the `record["description"]` read; set `description_prose: ""`.
  - `build_evidence_prose/1` + `normalize_evidence_paragraph/1` (lines 132–155): widen the kept-fields list to also carry `char_start`, `char_end`, `is_mention`, `name_occurrences`, `is_cited`, `cited_by_fields`, `relevance`. Tolerate missing fields (older bundles) by defaulting.
- Test: `test/gallformers/ingestions/bundle_importer_test.exs`
- Create fixture: a minimal 1.5.0 `review_artifact.json` test fixture under `test/support/fixtures/` (or wherever existing importer tests draw fixtures).

**Behavior:**
- Importing a 1.5.0 bundle persists `source.normalized_text` onto the `SourceIngestion` row.
- Per-record `description_prose` is `""` after import.
- Per-paragraph `evidence_prose` entries carry all new structural and citation fields.
- Older-version bundles either continue to work with sensible defaults or are rejected — match the existing compatibility policy.

**Testing:**
- `import_bundle/2` with a 1.5.0 fixture: `SourceIngestion.normalized_text` equals the fixture's `source.normalized_text`.
- `description_prose` is `""` after import regardless of any legacy `description` field.
- A persisted `ProseParagraph` map includes the seven new fields with the fixture's values.
- Older-version bundle: matches existing compatibility behavior (either rejects cleanly or defaults missing fields without crashing).

**Notes:**
- Depends on Tasks 3 + 4.
- Extend, don't replace, the existing `bundle_importer_test.exs` 1.1.0 / 1.4.0 paths.

### Task 6: Load `normalized_text` into the Workspace

**Files:**
- Modify: `lib/gallformers/ingestions.ex` — confirm `get_source_ingestion!/1` (or whichever accessor `handle_params/3` uses) returns the column. If a dedicated accessor exists, ensure it selects `:normalized_text`.
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex` — in `handle_params/3` (line 32), assign `:normalized_text` on the socket from the loaded `SourceIngestion`.
- Test: `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs`.

**Behavior:**
`normalized_text` is available as a top-level socket assign for the new component.

**Testing:**
- After mount/handle_params for a source whose `SourceIngestion.normalized_text` is set, the `:normalized_text` assign is non-nil and equals the column value.

### Task 7: Remove the standalone `evidence_prose_section/1`

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex`
  - Delete `evidence_prose_section/1` and `evidence_paragraph/1` private template functions (lines 494–553).
  - Remove `<.evidence_prose_section ...>` from the render template (line 341).

**Behavior:**
The standalone "Source text" panel is gone from the workspace; its role is taken over by the new `WorkspaceDescription` (Tasks 8–11).

**Testing:**
- Workspace render no longer contains `id="workspace-section-evidence"`.

**Notes:**
- Land in the same commit as Tasks 8–11 (or just after) to avoid a transient UI gap.

### Task 8: New `WorkspaceDescription` — chunk picker + draft preview

**Files:**
- Rewrite: `lib/gallformers_web/live/admin/ingestion_review_live/workspace_description.ex` (existing file, contents replaced end-to-end).
- Create: `test/gallformers_web/live/admin/ingestion_review_live/workspace_description_test.exs`.

**Behavior:**
- Accepts assigns: `evidence_prose`, `existing_gall`, `normalized_text`, and the persisted state hydrated from `review_payload.description_review` (selection, mode, draft, draft_dirty).
- Local assigns: `selection` (`MapSet` of span_ids), `disclosure_level` (`:high | :medium | :all`, default `:high`), `draft`, `draft_dirty` (default false), `edit_open` (default false), `context_span_id` (nil), `mode` (default `:replace`).
- Initial `selection` defaults to span_ids where `relevance == "high" OR is_cited == true` when no persisted selection.
- Renders, in order: sticky draft preview, cumulative disclosure control `[● High N] [○ + Medium N] [○ + All N]`, chunk list in document order filtered by disclosure level.
- Chunk row: checkbox, page label, span_id, `mention` badge if `is_mention`, cited-by chips, paragraph text, "view in context" link.
- `toggle_chunk` event: flip span_id membership in `selection`; if `!draft_dirty`, recompute `draft` as doc-order concatenation joined by `

`; emit `{:description_updated, %{selection, draft, mode, dirty}}` to parent.
- `set_disclosure` event: switch level; `selection` and `draft` unchanged.

**Testing:**
- Default disclosure renders only HIGH chunks; switching to `:medium` shows HIGH + MEDIUM; `:all` shows everything.
- Initial `selection` includes every `relevance="high"` chunk plus every `is_cited=true` chunk regardless of relevance.
- Toggling a chunk adds/removes its span_id; draft is doc-order concatenation of selected chunks.
- Persisted `selected_span_ids` override the relevance-based default.
- `{:description_updated, ...}` is sent on every toggle.
- Chunks with non-empty `cited_by_fields` render the cited-by chips; `is_mention=true` chunks render the mention badge.

**Notes:**
- Use Phoenix LiveView 1.x `live_component` patterns; mirror the sibling files in the same directory.
- Per project CLAUDE.md: do NOT factor reusable sub-components out of this picker without asking — chunk cards, sticky preview, cumulative segmented control all stay inline for v1.

### Task 9: Edit mode + draft_dirty + confirm prompt

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace_description.ex` (continuing Task 8).
- Test: `test/gallformers_web/live/admin/ingestion_review_live/workspace_description_test.exs`.

**Behavior:**
- `open_edit` event swaps the preview into a textarea pre-filled with the current draft.
- `update_draft` event (textarea blur) updates `draft` and sets `draft_dirty = true`.
- Chunk checkboxes and the "Regenerate from picks" button carry `phx-confirm="You've edited the draft. Discard your edits and regenerate from chunks?"` ONLY when `draft_dirty` is true.
- `regenerate_draft` event recomputes `draft` from `selection` and sets `draft_dirty = false`.
- Each change emits `{:description_updated, ...}` to parent.

**Testing:**
- Editing the textarea (via `update_draft`) flips `draft_dirty` to true.
- Rendered checkbox HTML carries `phx-confirm` when `draft_dirty`; not when clean.
- `regenerate_draft` recomputes draft from selection and clears `draft_dirty`.
- After `regenerate_draft`, subsequent toggles no longer carry `phx-confirm`.

### Task 10: View-in-context modal

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace_description.ex` (continuing Tasks 8–9).
- Modify: `assets/js/app.js` (or whichever module registers LiveView hooks) — add a `ScrollHighlightIntoView` hook that, on mount, scrolls its inner `<mark>` element into view, centered.
- Test: `test/gallformers_web/live/admin/ingestion_review_live/workspace_description_test.exs`.

**Behavior:**
- "view in context" link on a chunk fires `open_context(span_id)`; component sets `context_span_id`.
- Modal (using `<.modal>` from `core_components`) opens at `max-w-[90vw]` width with body ~80vh and internal scroll.
- Body: `<pre class="whitespace-pre-wrap font-mono text-sm">` containing the entire `normalized_text`, with the slice `[char_start, char_end]` of the target chunk wrapped in `<mark>`.
- The `<pre>` (or wrapping div) carries `phx-hook="ScrollHighlightIntoView"`; on mount, JS finds the inner `<mark>` and `scrollIntoView({block: "center"})`.
- Header: page number, span_id, cited-by chips. Footer: close button → `close_context` → `context_span_id = nil`.

**Testing:**
- `open_context(span_id)` sets `context_span_id`; modal renders only when `context_span_id` is non-nil.
- Modal body contains a `<mark>` wrapping exactly the substring `String.slice(normalized_text, char_start, char_end - char_start)`.
- Header surfaces the correct page number and span_id.
- `close_context` clears `context_span_id`.

**Notes:**
- The JS hook is small but should be verified in a browser session per CLAUDE.md ("UI changes: start the dev server and use the feature in a browser before reporting the task as complete").

### Task 11: Existing-gall mode selector (keep/append/replace)

**Files:**
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace_description.ex` (continuing Tasks 8–10).
- Test: `test/gallformers_web/live/admin/ingestion_review_live/workspace_description_test.exs`.

**Behavior:**
- Segmented control `Apply as: ○ Keep current  ○ Append  ● Replace` is rendered at the bottom of the section ONLY when `existing_gall != nil and existing_gall.description not in [nil, ""]`.
- Default `mode` is `:replace`.
- `set_mode` event updates `mode`; emits `{:description_updated, ...}` to parent.
- The parent composes the final `description_prose` from `mode` + `draft` + existing description at save time (Task 12).

**Testing:**
- Control hidden when no existing description (`existing_gall == nil` or `existing_gall.description in [nil, ""]`).
- Mode change persists through component re-render and is included in the message to the parent.

### Task 12: Persistence round-trip — `review_payload.description_review`

**Files:**
- Modify: `lib/gallformers/ingestions/source_ingestion_species_review.ex`
  - `normalize_source_ingestion_species_review/2` (line 135): persist `selected_span_ids`, `mode`, `draft_dirty` on `description_review`. `edited` flips to `true` on first toggle / textarea-edit / mode-change.
  - `workspace_description_review/1` (line 507): hydrate the new fields out for the workspace map.
- Modify: `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex`
  - Extend the parent workspace map with `description_selection`, `description_mode`, `description_draft_dirty`.
  - Update the `{:description_updated, ...}` `handle_info` to thread all four fields and mark dirty.
  - `collect_workspace_attrs/2` (line 947): include the new keys; compose the final `description_prose` from `mode` + `draft` + existing description.
- Test: `test/gallformers/ingestions/source_ingestion_species_review_test.exs` (extend existing or create).
- Test: `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs` (end-to-end round-trip).

**Behavior:**
- Saving a workspace with selection + draft persists them on `review_payload.description_review`.
- Reloading the workspace rehydrates selection, mode, and `draft_dirty`; the picker renders in that state.
- Completion gate at `source_ingestion_species_review.ex:389` still passes once `edited` is non-nil (now true after any picker engagement).
- Final `description_prose` composed at save:
  - `mode = :replace` → final = draft
  - `mode = :append` → final = existing + `

` + draft
  - `mode = :keep` → final = existing (draft retained on review_payload but not used as the final value)
- Without an existing gall, `mode` is irrelevant; final = draft.

**Testing:**
- Round-trip: save with selection `["S_0021", "S_0024"]`, mode `:append`, dirty `false`; reload — fields equal.
- Completion gate accepts the review once `edited` becomes `true` (after toggle, edit, or mode change).
- Compose `description_prose`:
  - `mode = :replace` and no existing → final = draft
  - `mode = :replace` with existing → final = draft (existing discarded)
  - `mode = :append` with existing → final = `"#{existing}

#{draft}"`
  - `mode = :keep` with existing → final = existing
- The `description_review.edited` field is `false`/`nil` immediately after import (gate blocks completion) and `true` after first engagement.

**Notes:**
- Depends on Tasks 8–11 for the component side.
- The gate logic at `source_ingestion_species_review.ex:389-393` reads `description_review.edited`; preserve the existing nil-rejection behavior.

### Task 13: Manual smoke test against a re-imported 1.5.0 bundle

**Behavior:**
Once Tasks 1–12 are green:
1. Re-run the pipeline against an existing source (e.g., nicholls or kinsey-1929) to produce a 1.5.0 bundle. (Outside the scope of this branch — confirm bundle exists before proceeding.)
2. Import the new bundle via the existing admin flow.
3. Open the review workspace; pick a species with dense `evidence_prose` (≥30 chunks).
4. Verify: disclosure levels work; default selection matches `high OR is_cited`; toggles update the draft live; edit mode + confirm prompt behave; view-in-context modal renders the full `normalized_text` and scrolls the highlight into view; existing-gall mode flow composes correctly.
5. Save the draft, reload, confirm round-trip (selection, mode, draft, dirty flag all match).
6. Commit the species; confirm the description lands on `species_source.description`.

**Notes:**
- Per CLAUDE.md: type-checking and tests verify code correctness, not feature correctness. If a 1.5.0 bundle isn't available when implementation finishes, say so explicitly rather than claiming the picker is fully verified.

