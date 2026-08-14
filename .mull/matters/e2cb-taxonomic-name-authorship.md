---
status: planned
created: 2026-07-28
updated: 2026-08-12
epic: admin
relates: [91cf]
blocks: [2cb2]
---

# Taxonomic name authorship

## Goal

Implement GitHub #559: associate a taxonomic author citation with each exact accepted species name and deprecated scientific synonym, display it in identity-bearing UI, prevent silent omission on future edits, and provide a safe path to resolve the existing backlog.

## Current state and scale

`species` and `alias` currently store only `name`. The extraction pipeline already preserves `authority`, and the WCVP mirror exposes `taxon_authors`.

As measured in the local data on 2026-07-28:

- 6,065 species: 2,259 plants and 3,806 galls.
- 2,356 galls are described; 1,450 are undescribed or genus placeholders.
- 2,663 aliases are scientific and 1,088 are common.
- 2,025 plants have a WCVP ID. The current mirror has matching rows for 1,995 and nonblank authorship for 1,983.
- Exact-name WCVP matching can propose authorship for about 422 existing scientific aliases.
- Existing ingestion rows contain 91 extracted authority values, 81 linked to a species.

## Decisions

### Name ownership

Authorship belongs to the exact nomenclatural name or combination, not to a genus or to the biological concept independently of its name. Add the same fields to the two existing name owners rather than introducing a new normalized taxon-name model:

- `species.authorship :text`
- `species.authorship_status`
- `alias.authorship :text`
- `alias.authorship_status`

This is the smallest complete model consistent with the current architecture. A companion or normalized taxon-name table would add joins and a disruptive migration without a requirement that justifies it.

### Resolution states

Allowed statuses are:

- `missing`: eligible and still actionable.
- `known`: a nonblank citation is present.
- `unresolved`: an admin investigated but could not verify a reliable citation.
- `not_applicable`: the record is not a formally published scientific name requiring authorship.

Database checks enforce that `known` has nonblank `authorship` and all other statuses have `NULL` authorship. Citations are preserved exactly except for trimming outer whitespace.

Existing described species and scientific aliases migrate to `missing`. Undescribed galls, genus placeholders, common aliases, and `former_undescribed` aliases migrate to `not_applicable`. Alias eligibility includes `scientific` and the nomenclatural WCVP alias types planned by matter `91cf` (`synonym`, `misapplied`, `illegitimate`, `invalid`, `orthographic`, and `artificial_hybrid`); only `common` and `former_undescribed` are ineligible. Eligibility that depends on `gall_traits.undescribed` is centralized in domain logic because it crosses tables and cannot be a safe row check on `species`.

No new provenance columns are needed. WCVP evidence remains traceable through `host_traits.wcvp_id`, and LLM evidence remains in `source_ingestion_species`. Manually entered citations are not source-attributed at field level; admins may rely on existing species-source links, but this design does not require or imply a specific supporting source.

### Write policy

Creating or editing an eligible species or alias requires resolution: either a citation with status `known`, or an explicit `unresolved` choice. Existing `missing` records cannot pass through the relevant admin save flow without being resolved. Ineligible records remain `not_applicable` and do not show the authorship input.

Gall and host forms place an **Author citation** field beside the scientific name and provide an **Unable to verify** control. The shared alias editor shows the same controls only for eligible scientific/synonym types. Changing an alias from an ineligible type to an eligible type requires resolution. Alias creation must use the canonical Alias changeset rather than bypassing it.

WCVP host selection pre-fills `taxon_authors`. WCVP refresh stages an authorship difference in the existing review flow rather than silently replacing a value.

### Rename and reclassification policy

A species rename or genus reclassification changes the exact nomenclatural combination and must participate in the same resolution workflow. The shared rename/reclassify modal requires a citation or explicit unresolved state for the new eligible name. When the old name is retained as a scientific alias, it carries the old accepted name's authorship and status; the new accepted name receives the newly reviewed resolution. A move that leaves a gall undescribed sets the new name to `not_applicable`.

Bulk genus-node renames are treated as spelling/taxonomy-label corrections: they preserve the accepted citation/status on the renamed species and copy the same old citation/status to the generated alias. They must not erase or invent authorship.

### Display policy

Extend the existing reusable `<.taxon_name>` component with optional `authorship`. The scientific name retains current italicization rules; the citation follows in roman type.

Show citations in identity contexts: public detail headings, scientific alias lists, search results, typeaheads, index tables, and admin forms/lists. Do not add them to prose or metadata where the name is only an embedded label. Missing and unresolved states do not produce public placeholder text; admin contexts show a status badge and link to the audit.

### Audit and candidates

Add a query-backed admin audit at `/admin/taxonomic-authorship`; do not create a second workflow/proposal database.

The audit has `Missing`, `Unresolved`, and `Conflicts` filters and covers eligible accepted species plus scientific aliases. Each row shows the exact name, state, linked evidence, and candidate citations. Admin actions can apply a candidate, enter a citation, mark unresolved, or reopen an unresolved record.

Candidate precedence:

1. WCVP record linked by `host_traits.wcvp_id`: deterministic.
2. Exact-name WCVP match: review required.
3. Linked `source_ingestion_species.extracted_authority`: review required.

Multiple distinct candidates form a conflict. A candidate that differs from an existing `known` value is also a conflict rather than an overwrite opportunity. The system never guesses between them.

### Deterministic backfill

An idempotent Oban maintenance worker fills only `missing` host records whose WCVP ID resolves to one nonblank citation. It never overwrites `known` or `unresolved`. Re-running is safe; status and failures are visible through the canonical `/admin/jobs` dashboard.

WCVP unavailability fails the job so Oban retries; it must not be interpreted as “no citation found.” Empty WCVP values are skipped and remain `missing`.

Exact-name WCVP and LLM/source candidates always require review. This issue consumes authority already extracted by the intake pipeline; it does not launch new LLM jobs against arbitrary linked URLs.

### Ongoing integrations

- New WCVP-backed hosts start as `known` with `taxon_authors`.
- Ingestion review offers extracted authority when linking to a `missing` species, but never overwrites an existing citation silently.
- Related matter `91cf` (WCVP synonym import) must insert imported synonyms with their WCVP authorship and `known` status in the same operation.

## Architecture boundaries

`Gallformers.Species.Authorship` owns eligibility, status transitions, audit queries, candidate merging, and apply operations. Species and Alias changesets delegate shared validation to it. WCVP and ingestion modules produce evidence candidates but cannot decide overwrite policy. The reusable display component owns typography; callers own loading and passing authorship. The audit LiveView owns review interaction; the Oban worker owns deterministic bulk application.

Stale audit actions carry the rendered `updated_at` value, reload the target, and refuse to replace a row whose timestamp or authorship state changed after render. Public rendering falls back to the current name-only output when no citation is available.

## Acceptance criteria

- Schema and database checks reject inconsistent status/value combinations.
- Described species and eligible scientific aliases cannot be created or edited without `known` authorship or explicit `unresolved` status; undescribed/placeholder/common records remain unaffected.
- Author citations render in all defined identity contexts with roman typography after the scientific name.
- The audit can filter missing, unresolved, and conflicting records and supports apply, manual entry, unresolved, and reopen transitions without stale overwrites.
- The Oban backfill is idempotent, retries WCVP failures, and never overwrites `known` or `unresolved` values.
- WCVP host creation and refresh carry authorship through their existing review semantics.
- Rename/reclassify requires resolution for the new eligible name, preserves the old citation on generated aliases, and handles undescribed names as not applicable.
- Ingestion review offers extracted authority without silently replacing existing data.
- Matter `91cf` consumes the same authorship model for imported WCVP synonyms.

Verification must cover the domain eligibility/status matrix, forms, alias type transitions, component typography, query propagation to identity contexts, audit precedence/conflicts/actions/stale updates, worker idempotency/failure behavior, and ingestion integration. The end-to-end smoke check creates or edits representative gall, host, scientific alias, and common alias; verifies public and search rendering; enqueues the worker; and confirms results through the audit and `/admin/jobs`.

## Non-goals

- Normalizing all accepted and synonym names into a new taxon-name table.
- Persisting a second provenance model.
- Automatically trusting exact-name or LLM-derived matches.
- Launching fresh LLM extraction against every linked source.
- Showing unresolved placeholders on public pages.

## Implementation shape

Implementation is one feature with eight reviewable slices, each ending in focused verification, warnings-as-errors compilation, and `mix precommit` before commit:

1. **Schema and invariants** — add `authorship`/`authorship_status` to `species` and `alias`; implement `Gallformers.Species.Authorship`; classify existing rows and add database checks.
2. **Admin write cutover** — thread eligibility through Species/Galls/Plants aggregate writes; make canonical Alias changesets mandatory; extend gall/host forms, AliasHandlers, and the shared alias editor.
3. **Rename/reclassify** — require resolution for new eligible combinations, copy the old accepted citation/status to generated aliases, preserve resolution during bulk genus-label corrections, and cover rollback behavior.
4. **Display/query propagation** — extend `<.taxon_name>` with optional authorship and an italic-name suffix slot; add separate authorship fields to Species/Galls/Plants/Search/tree/relation projections; update public detail/search/browse, admin identity lists, and API entities without changing bare `name`, URLs, sorting, or matching.
5. **WCVP integration** — add batch ID and exact-name authorship APIs returning explicit unavailable errors; prefill new WCVP hosts; stage refresh differences in `PowoDiffReview` rather than overwriting.
6. **Audit and worker domain** — add `Species.Authorship.Audit` for query-backed missing/unresolved/conflict entries and stale-safe transitions; add an idempotent Oban maintenance worker using 200-row ID-cursor jobs and batch WCVP lookups.
7. **Audit UI** — add `/admin/taxonomic-authorship`, dashboard navigation, evidence/candidate review actions, manual/unresolved/reopen transitions, pagination, and the bulk enqueue control linked to `/admin/jobs`.
8. **Ingestion and end-to-end cutover** — offer already-extracted authority during source linking without overwriting known/unresolved state; rebuild the test DB, run the complete suite, browser-smoke every record class plus rename/search/backfill/audit, then perform gated cleanup and close the matter.

Key implementation contracts:

- `Authorship.validate(changeset, eligible?: boolean, require_resolution?: boolean)` owns normalization and status/value checks.
- `Wcvp.Lookup.authorships_by_ids/1` and `authorship_candidates_by_names/1` return `{:ok, map}` or `{:error, :unavailable}`; absence is not conflated with repository failure.
- `Authorship.Audit.list/2` returns paginated species/alias entries. Apply, unresolved, and reopen transitions require the rendered value/status/timestamp snapshot and reject stale conditional updates.
- `Authorship.BackfillWorker` processes WCVP-linked missing plants after an ID cursor in batches of 200, conditionally updates only `missing`, and enqueues the next cursor.
- Reclassification accepts the new citation/status only when the exact name changes; generated aliases receive the old citation/status.
- Display maps carry authorship separately. No caller concatenates it into `name`.

The implementation must use LSP references before changing exported Species/Taxonomy APIs. Focused tests cover the status matrix, aggregate writes, form visibility/enforcement, alias drafts, rename transactions, component typography, query propagation, WCVP error semantics, audit candidate precedence/conflicts/stale actions, worker idempotency, and ingestion opt-in. Final proof is `mix precommit`, `mix compile --warnings-as-errors`, the complete test suite after `make test-db`, and a browser smoke through forms, public/search/browse rendering, rename, audit, backfill, and `/admin/jobs`.
