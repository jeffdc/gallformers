# Source ingestion service — agent rules

This service runs a multi-stage LLM pipeline that turns gall-literature PDFs into structured bundles. Cached stage outputs let re-runs skip work. Stale caches are the worst kind of bug — silent, hard to diagnose, expensive to discover after the fact. The rules below exist to prevent them.

## Cache invalidation discipline

Each cache-eligible stage writes a sidecar `<artifact>.cache.json` containing a key dict. On the next run, the stage rebuilds the same key from current inputs and compares. Match → reuse artifact. Mismatch → re-run.

Cache keys include:

- `schema_version` — the bundle-wide constant in `src/ingest/schemas.py`.
- `stage_version` — per-stage `STAGE_VERSION` constant declared in the stage module.
- `prompt_sha256` — SHA of the prompt file (for LLM stages).
- Upstream input hashes (`eligible_sha`, `input_sha`, `evidence_pack_sha`, …).
- Stage-specific config (`model`, `n_samples`, `agreement_threshold`, …).

### The rule — when stage outputs would change, bump `STAGE_VERSION`

**If you change a stage's code in a way that would produce different output for the same inputs, you MUST bump that stage's `STAGE_VERSION` constant.** This is the only signal that tells the cache layer that previously-stored artifacts are no longer valid for the new code.

Requires a bump:

- Dedup / grouping logic changes (e.g., new dedup key).
- Output-shape changes the stage performs in code (not via Pydantic schema).
- Filter / threshold / normalization rule changes.
- Post-processing changes (scrubbing, ID assignment, sample-vote logic, …).
- Any change you'd describe in a PR as "the stage now does X differently."

Does NOT require a bump:

- Doc / comment / docstring edits.
- Refactors that provably preserve outputs (extracting a helper, renaming a local).
- Logging additions and error-handling that doesn't change the success path.
- Type-hint changes with no runtime effect.

### Automatic invalidation paths (don't double-bump)

These already invalidate caches on their own — no `STAGE_VERSION` bump needed for these alone:

- **Prompt text changes** — picked up via `prompt_sha256` automatically.
- **Pydantic schema changes** (new field on `Candidate`, `GallRecord`, etc.) — bump `SCHEMA_VERSION` in `src/ingest/schemas.py` instead; that invalidates every stage's cache pipeline-wide.
- **Upstream-content changes** — the per-stage input hashes propagate downstream automatically.

A change that does both (e.g., new prompt AND new dedup logic) only needs the bump *for the code part*. The prompt SHA handles the prompt part.

### When in doubt, bump

A stale-cache bug is much harder to debug than an unnecessary re-run. If you're not sure whether a change would invalidate outputs, bump. The cost of an extra re-run is small; the cost of trusting stale data is large.

### How to bump

Each stage module declares its version near the top, in this form:

```python
# Stage version. Bump when stage-code changes alter outputs for the same inputs.
STAGE_VERSION = "1.0.0"
```

Bump the semver number. Patch-bump for narrow logic tweaks; minor-bump for output-shape changes; major-bump for behavior-class changes (e.g., one-candidate-per-species → one-candidate-per-(species,generation)).

### Stages currently using STAGE_VERSION

- `src/ingest/metadata.py`
- `src/ingest/find_candidates.py`
- `src/ingest/extract_facts.py`
- `src/ingest/verify_claims.py`

When a new cache-eligible stage is added, give it a `STAGE_VERSION` and wire it into the cache key in `src/ingest/pipeline.py`.
