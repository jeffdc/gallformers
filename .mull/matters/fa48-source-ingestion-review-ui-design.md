---
status: active
created: 2026-03-22
updated: 2026-05-01
epic: ingestion
relates: [7fda, 7c67]
---

# Source ingestion review UI design

## Source Ingestion Review — UI Design

Design from collaborative session 2026-03-22.

### Information Hierarchy

- **Landing page** contains zero or more source uploads
- **Source** contains 1 or more gall species
- **Gall** contains zero or more hosts, traits, and descriptive text

### Screen 1: Landing Page (`/admin/ingestion-review`)

Work queue dashboard — "here's your stuff, here's where things stand."

**Header:** Title + "New Source" button (always visible, secondary to the list)

**Filters:** By user (default: current user), completion status (default: hide complete)

**Table:**

| Title | Species | Status | Uploaded | By |
|-------|---------|--------|----------|----|
| Clickable link | "2 galls, 3 hosts" | "1 of 2 complete" | Mar 19 | Jeff |

Clicking a row navigates to the source detail page.

**New source entry — two input modes:**
- **URL field** — paste a URL, fetch text via trafilatura
- **File upload** — accepts .pdf, .docx, .txt via dropzone

**Processing flow (same for all input types):**
1. Extract text (free — PDF via pymupdf4llm, URL via trafilatura, docx via pandoc, txt passthrough)
2. Preprocess (free, deterministic cleanup)
3. Hash the preprocessed text (content-based dedup, input format irrelevant)
4. Check for duplicates against `source_ingestions.content_hashes` + heuristic title match
5. If potential dupe → prompt: "This looks like [existing title]. Use that instead?" Confirming stores the new hash on the existing record and redirects. Denying continues.
6. If no dupe → run LLM steps via Oban workers (with stage progress indicator)
7. On completion → create `source_ingestion` record, redirect to source detail page

Upload progress needs improvement over PoC — LiveView socket upload pauses when browser tab is backgrounded. Consider direct-to-S3 upload or regular HTTP upload for production.

### Screen 2: Source Detail Page (`/admin/ingestion-review/:id`)

**Source section (top, must be resolved before gall work begins):**
- Article metadata displayed: title, authors, year (from extraction)
- Source lookup: typeahead auto-populated with article title. Map to existing or create new.
- Until source is mapped or created, the gall list below is disabled/locked.

**Gall list (unlocked once source exists):**

| Species | Hosts | Match | Status |
|---------|-------|-------|--------|
| *Meskea dyspteraria* Grote | 2 hosts | Matched | Pending |

Click a row → opens gall modal.

When all galls are marked complete → ingestion status automatically flips to complete, drops off the active work queue on the landing page.

### Screen 3: Gall Modal (full-screen overlay)

The gall modal is a focused workspace for processing one gall at a time. The mental model: processing a checklist where each item requires a deep dive. Sense of progress (checking items off) plus focused tool for the hard work.

**All-or-nothing save.** User works on everything, then commits it all. No partial processing — save it all or abandon it all. Dirty state tracking warns before dismissing unsaved changes (same pattern as other admin pages).

**Save execution:** Operations run sequentially (not a single DB transaction, but a user-level atomic action). On failure: report the error in plain language, let the user re-decide. Specific error handling:
- Duplicate taxa (race condition: someone else created it) → inform user, switch from "create" to "map"
- Orphaned taxa (FK failures) → inform user, re-present creation flow
- Duplicate alias → skip silently, already correct
- Duplicate species_source link → treat as success
- Deleted species (FK gone) → inform user: "Species X no longer exists, please re-map"
- Trait conflicts → last write wins (same as rest of admin)

**Section 1: Species**
- Extracted name + authority displayed
- Auto-match result shown (name + alias search)
- If matched: show match with confirmation
- If no match: inline typeahead to map to existing, or create new
- Creation uses unified species API (matter 881c) — genus/family auto-resolution with disambiguation modal fallback
- If mapped to a different name → alias created on save (extracted name → existing species as scientific synonym, following full reclassify logic including genus implications)

**Section 2: Hosts**
- List of extracted hosts, each with:
  - Name + authority
  - Auto-match status (name + alias search)
  - Map/create controls (same pattern as gall species)
  - Alias creation for name mismatches on save

**Section 3: Traits**

| Trait | Current | Proposed | Raw | Final |
|-------|---------|----------|-----|-------|
| color | red, brown | brown, **yellow** | "spotted with brown and yellow" | [dropdown: red, brown] |

- **Current:** existing DB values if species is matched. Plain text.
- **Proposed:** LLM suggestions. Values already in Current shown plain. New values shown **bold/highlighted**. Clicking a bold value adds it to Final (single click transfer).
- **Raw:** extracted source text fragment for that trait. Reference for why the LLM proposed what it did.
- **Final:** multi-select dropdown from controlled vocabulary for that trait. Single-value traits (detachable) use single-select. Defaults to Current values (if present), or Proposed values that map cleanly to controlled vocab (if no Current). User can also populate by clicking bold Proposed values.

For multi-value traits: Final defaults to Current (conservative, don't override). New values in Proposed are highlighted to make them easy to spot and transfer with a click.

**Section 4: Gall Description**
- The full extracted prose block that applies to this gall species (editable textarea for cleanup of extraction artifacts)
- Becomes `species_source.description` on save
- Note: pipeline needs improvement to extract the complete gall-relevant prose block rather than just a brief description snippet (tracked in matter 7fda)

**Section 5: Full Source Text**
- Collapsible/expandable, read-only
- Entire assembled article text for reference and validation
- User can cross-check extraction against the original if they suspect the LLM missed something

### Dependencies

- **c836** (prerequisite) — Allow genus/family creation during reclassification
- **881c** (prerequisite) — Unified species creation/reclassification API
- **7fda** (relates) — Pipeline improvements: gall-level prose extraction, Oban integration, S3 storage

### Deferred Decisions

- Source creation: inline form vs new tab (depends on scope of 881c unified API)
- Upload mechanism: direct-to-S3 vs LiveView socket (production performance concern)
- Pipeline operationalization: Oban worker design, S3 artifact storage (tracked in 7fda)
