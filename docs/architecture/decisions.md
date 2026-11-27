# Architecture decisions

Jeff's decisions that shape the system's architecture and design, newest first. Each entry says what was decided, why, and what it changes: the parts of [README.md](README.md) it shapes and the [rules](rules.md) it adds or changes. A decision is never edited after the fact; a later decision supersedes it and says so, and the old entry gains a "Superseded by" line.

Entries before 2026-11-26 were recorded when this log began, from the code, its history, mull and the old matters (read with git: AGENTS.md, "Old IDs"); their dates are when the decision was made or landed. Only decisions that shape the architecture are here. The domain decisions (what a Fact is, ranges, Sources' standings and the rest) are in the [taxogall plan](../taxogall/README.md), and mull's other decisions stay readable with git.

Template:

```
## YYYY-MM-DD: <the decision, as a sentence>

- **Why:** …
- **Changes:** … (README sections, rules added or changed)
- **Source:** commit, PR, plan doc, or mull or matter ID
```

## 2026-11-26: Settle the baseline review's findings

- **Why:** the [baseline review](reviews.md#2026-11-26-baseline) left its violations, doc conflicts and proposed rules open for Jeff.
- **Changes:**
  - S1: the Fact-owning contexts', Import's and Curation's reads of `facts` and `attributions`, `Audit.ChangeLog`'s joins and CatalogMigration's writes are accepted; the other crossings, and S4's reads of Taxa by Catalog, are fixed through the owners' APIs (backlog).
  - S10: `abundance` and `species` may be read until cutover.
  - T3: seed rows are fixtures a test may use, but never by a hard-coded ID (testing-philosophy.md updated). X3: the nonce'd theme-init script is its one exception.
  - Ten new rules: S11 (business logic never depends on the web layer), X4 (an enforced CSP with a report endpoint), X5 (rate limits on the trusted client IP), X6 (read-only mode stops every write), X7 (every writing screen behind an on_mount role guard), X8 (dev never writes to production storage), O6 (production fails loudly on a missing secret), O7 (errors reach someone; the service is open), O8 (only `main` deploys), O9 (one production machine).
- **Source:** Jeff, 2026-11-26.

## 2026-11-26: Keep an architecture baseline, and turn violations into checks

- **Why:** the system's shape lived in agents' heads and in scattered docs that had drifted (core-architecture-rules.md described checks that no longer matched the code; range-system.md and the C4 model described the old model). A baseline to review against, and checks that hold each rule at its baseline, keep it from drifting further. Gallformers adopts the model Oak Compendium set up.
- **Changes:** this folder, describing `taxogall` as built, with a note that production runs the old back-end until cutover. Rules start at their 2026-11-26 baselines; periodic reviews go in [reviews.md](reviews.md). core-architecture-rules.md's principles and enforcement became rules S1–S3, W1–W4, D1 and U3; range-system.md, elixir-architecture.md and the C4 Structurizr model were deleted.
- **Source:** Jeff, 2026-11-26; [cleanup plan](../cleanup/README.md), step 6.

## 2026-11-22: Get Sources in through a shared private bucket, with conversion on a Sprite and the LLM stages on curators' machines

- **Why:** curators beyond Jeff and Adam can help collect and convert documents now, on today's production site, while review decisions have to be made on preview. Reading runs must run on Claude subscriptions, since API billing would price Gallformers out (e90e).
- **Changes:** not yet built. The private bucket is laid out by Source (`sources/<id>/`: documents, runs, packages; 1398), versioned (a2f1), and shared by preview and production with no per-environment prefix (9285). Producers write to it through short-lived signed URLs for exact keys, issued against the curator's Gallformers token, with no AWS keys (397f, fe02). Production collects and converts documents; preview runs the reading (0db0). Conversion runs on a Fly Sprite, started by an Oban job (3615, 5ed4); the LLM stages stay on Jeff's and Adam's machines for now (6d0b, ff29).
- **Source:** item 274b and its decisions, 2026-11-17 to 11-22.

## 2026-11-16: Keep the public API, released as `/api/v3`

- **Why:** the old public API has real users.
- **Changes:** not yet built. `/api/v3` (3.0.0) on the new back-end; `/api/v2` answers 410 at release.
- **Source:** Jeff, 2026-11-16; 3c4f.

## 2026-11-12: One write path

- **Why:** two ways to write the same data drift apart, and replay has to re-apply every write mechanically.
- **Changes:** for any data, exactly two ways in, its one editing screen and the import, calling the same code to validate, write and read it. A curator's edit is a small package under the Gallformers Source, held in the curator's change set until applied (`Gallformers.Curation`). Rule S5. Not yet built in full; it is a taxogall phase.
- **Source:** Jeff, 2026-11-12; `git show mull:docs/plans/taxogall.md`, "One write path".

## 2026-11-12: Build real data on preview and replay it onto production at cutover

- **Why:** real data must never be built on a developer's machine, and the live site has to stay editable while Sources are processed.
- **Changes:** Sources are processed into a migrated production copy on preview. At cutover production is migrated fresh and preview's work replayed onto it from the replay log (`Release.export_replay_log/0`, `Release.replay_log/1`); replay is rehearsed until boring. Sources created on preview are numbered from a reserved range (f525). Merging `taxogall` into `main` deploys at once, so the runbook guards against an accidental merge or deploy.
- **Source:** Jeff, 2026-11-12; `git show mull:docs/plans/taxogall.md`, "Cutover".

## 2026-11-09: Guardrails that fail the build or block the commit

- **Why:** from 2026-11-06 to 11-08 agents' work outran its plans: duplicate code (two WCVP searches, two iNat searches, two question UIs on one back end) and replacements left half done. AGENTS.md already said "Search Before You Write", and it was broken anyway.
- **Changes:** a duplicate-code ratchet with a shrink-only baseline (S9); retirements (S8); one owner per capability (`SingleEntryPoint`, S7); a commit gate that blocks a commit without a passing fresh-context review of the staged tree (O3), made harness-neutral the same day (a14188c2); AGENTS.md kept short.
- **Source:** Jeff, 2026-11-09; matter c800; 237092f1.

## 2026-11-06: One design system for the public site and the admin, held by a conformance test

- **Why:** the site and the admin had drifted into many local styles (1,850 off-system findings), and a denser, consistent UI was needed for curation.
- **Changes:** `docs/design-system/` as the authority on the look (DESIGN.md points to it): tokens, light and dark, a component catalog, a living style guide at `/dev/design-system`. A conformance test fails on new off-system styling (U2). README, Front end and design system.
- **Source:** matter bc0d; 15015087.

## 2026-10-25: Audit is a database layer, through Carbonite

- **Why:** a Repo-level audit misses bulk writes, raw SQL and cascades; triggers record every row change and commit or roll back with it. Code should only have to name who is acting.
- **Changes:** Carbonite triggers on each new table, declared in the migration that creates it; every audited transaction names its actor and operation, and the database refuses a write that doesn't (S6). The audit schema stays out of the public snapshot. Attribution (whose authority) is separate from audit (who changed it). README, Data.
- **Source:** matter ede2 (rewritten in matter 9449, Task 1); eb5286d5.

## 2026-10-24: Build the new back-end in place on `taxogall`, with no facade and no dual-write

- **Why:** the back-end changes so much that it is a rewrite; about 80% of the UI is admin, which the new model replaces anyway. A facade over today's tables only pays off if old and new run side by side, and they meet only at one rehearsed cutover.
- **Changes:** the new contexts (Taxa, Catalog, Facts, Import, Curation, Audit) built whole on `taxogall`; auth, Oban, storage, images, search and deploy reused. The old tables stay, read by the catalog migration, until release (S10). Building alongside the old system (a separate schema, duplicate pages behind a route flip, empty tables shipped dark) is rejected.
- **Source:** Jeff, 2026-10-24 (matter 36ca dropped); matter 8567, "Build approach".

## 2026-10-05: Cross-system change events are synchronous, with the dependency inverted

- **Why:** a taxonomy change the gall side can't accept should fail at once and get a real resolution, not leave the gall system breaking its own constraints. At Gallformers' scale even bulk changes are fast; async would add idempotency, ordering and staleness bugs for no benefit.
- **Changes:** taxonomy defines a "taxon changed" interface and calls listeners registered in application config inside its own transaction, so its code never references the gall system. Only expensive derived work (the ID tool's index) runs async, on Oban. README, Runtime ("Events inside a transaction").
- **Source:** Jeff, 2026-10-05; matter 8567, qualification 6.

## 2026-10-04: Two systems, taxonomy and galls, as black boxes behind Boundary

- **Why:** taxonomic Facts need Source attribution as gall Facts do, and the curation burden exists whether it goes into iNaturalist or Gallformers; doing it internally keeps it under Gallformers' control and open to LLM tooling.
- **Changes:** a taxonomy system and a gall system sharing Sources and Facts, history, audit and import, behind Phoenix contexts enforced by Boundary. The contract between them is stable taxon IDs at any rank; nothing else crosses. Hot cross-system reads go through published read models; writes that span them compose into one transaction. Rule S4. README, Code structure.
- **Source:** Adam and Jeff, 2026-10-03/04; matter 8567.

## 2026-04-21: Durable background work runs on Oban

- **Why:** the analytics rollup GenServer failed silently in production after the move to Postgres (crashes stopped its rescheduling, a large transaction timed out); work with no persistence has no retries and no visibility.
- **Changes:** Oban (open source, on the main Postgres database), its dashboard at `/admin/jobs`; the rollup became a cron worker. AGENTS.md's rule (D3). README, Runtime.
- **Source:** matter dd3a; 44536335.

## 2026-03-24: Enforce the architecture with Boundary and custom Credo checks

- **Why:** agents produce code that compiles and passes tests but breaks the architecture's intent: calling internal modules, reversing documented decisions, duplicating instead of finding. Only deterministic checks that fail the build hold against that.
- **Changes:** every context declares `use Boundary` with its dependencies, checked by `mix compile --warnings-as-errors` (S2); existing crossings recorded as `dirty_xrefs`. Custom Credo checks for the web layer and test quality in `dev/credo/checks/` (S3, T3, T4, T6). Today all but `SingleEntryPoint` only report.
- **Source:** matter 8757; a047fa25.

## 2026-03-16: Move the database from SQLite to PostgreSQL on Fly

- **Why:** recurring SQLite incidents in production (six or more in five weeks: write-lock outages, out-of-memory crashes); the single-writer limit couldn't be worked around.
- **Changes:** self-managed Fly Postgres in the same region as the app; three instances (local, preview, production); a baseline migration generated from the Ecto schemas, replacing `structure.sql`; backups by `pg_dump` to S3 on a schedule; Litestream removed; built big-bang on an integration branch and cut over in place. The WCVP database stayed SQLite then and has since moved to Postgres too. README, Runtime and Data.
- **Source:** matter 4474; f25f2518 (#531); cutover closed 2026-03-25.

## 2026-01-21: Gallformers v2 is a Phoenix LiveView monolith

- **Why:** one language, one build system and one mental model (server state), with real-time UI built in, against a Svelte or HTMX front end over a Go API.
- **Changes:** the v2 Phoenix code was promoted to the repository root; v1's last commit is the tag `archive/v1-final`.
- **Source:** `docs/research/V2_STACK_COMPARISON.md`; b7f1868d.
