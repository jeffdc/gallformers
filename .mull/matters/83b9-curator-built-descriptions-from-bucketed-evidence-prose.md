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

