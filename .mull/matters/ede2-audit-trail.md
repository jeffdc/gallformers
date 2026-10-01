---
status: raw
effort: 5 days
created: 2026-02-13
updated: 2026-09-13
epic: admin
relates: [ec68, 5c56]
needs: [ec68]
---

# Audit trail

## Goal and approved scope

Provide a durable, queryable history of who changed curated Gallformers data, what changed, and when, including deleted records and cascading relationship changes. This is the administrative change-history safety net, not biological evidence provenance or a general undo system.

## Verified current state

- lib/gallformers/repo.ex uses Ecto.Adapters.Postgres; mix.exs has Ecto/Postgrex but no mutation-audit library. Gallformers.Images.Audit checks S3/DB consistency, not historical changes.
- Bulk writes are ordinary curated-data operations: ranges.ex replaces range relations with delete_all/insert_all; galls.ex mutates morphology joins directly; images.ex and sources.ex use update_all. Raw SQL also appears in data migrations.
- The PostgreSQL baseline retains extensive CASCADE and SET NULL actions. RESTRICT protects some taxonomy edges, not every deletion. Deleting a species can remove traits, images, hosts, sources, aliases, taxonomy links and ranges without separate Repo.delete calls.
- Several important identities are composite keys, not one integer entity_id. gall_traits/host_traits use species_id; range, taxonomy/alias and morphology junctions use multiple columns.
- Login already stores local db_user_id plus the Auth0 identity and display name, but admin mounts/events, async image imports, jobs and CLI writes do not consistently carry a stable actor. Existing uploader/lastchangedby strings are not a history or a unique identity.
- .github/workflows/db-snapshot.yml publishes a dump using an explicit exclusion list. Adding a private audit schema without revising that export risks leaking deleted/internal content and editor attribution.
- runbooks/restore-deleted-gall.md documents bounded operator recovery from a private backup plus separately retained S3 versions. Database history alone cannot restore media bytes.

## Proposed Core Architecture Decision

Use **Carbonite's PostgreSQL trigger-backed audit trail**, rather than ex_audit or a new handwritten trigger framework. Its documented transaction metadata, JSONB row changes, composite-key configuration and Ecto.Multi integration match this application. Documentation reviewed: Carbonite 0.17.0; confirm the selected release against the project's Ecto/PostgreSQL versions during implementation (Carbonite requires PostgreSQL 13+).

Why not retain ex_audit: its documented Repo wrappers do not automatically cover bulk APIs and arbitrary SQL, and a Repo-only boundary is insufficient for database-driven relationship changes. PostgreSQL triggers run for ordinary row writes and FK CASCADE/SET NULL effects and commit or roll back with the mutation.

Use the library's transaction/change tables in its dedicated audit schema, not a second application versions table. One audit transaction records trusted metadata for the corresponding database transaction; its changes record affected table, complete primary-key identity, operation and row data. Enable **store_changed_from: true** for every tracked table so updates preserve replaced values, including the first edit after auditing is enabled. Insert/delete events preserve the inserted/deleted row. Do not introduce Erlang-term blobs or a competing custom session-setting attribution channel.

## Coverage contract

Maintain an explicit migration-owned allowlist of curated tables, using actual database identities rather than assuming every Ecto schema exposes id:
- Biological/nomenclatural records: species, taxonomy, gall_traits, host_traits, alias, source and species_source.
- Relationships: gallhost, alias_species, taxonomy_alias, species_taxonomy, host_range, gall_range and all nine morphology joins (gall_alignment, gall_cells, gall_color, gall_form, gall_plant_part, gall_season, gall_shape, gall_texture, gall_walls).
- Curated vocabulary/geography: abundance, glossary, place, place_hierarchy, alignment, cells, color, form, plant_part, season, shape, texture and walls.
- Editorial/media metadata: articles, keys, image and content_images.

Exclude users/profile synchronization, operational site_settings, page_views/daily rollups, Oban internals, ingestion staging/candidate/status tables and the separate imported WCVP reference database. Excluding the WCVP mirror does NOT exclude its accepted changes to curated host/range tables. Likewise, accepted ingestion writeback into curated tables is audited, even though transient extraction/review artifacts are not.

Future curated tables, including any approved gall/taxon/provenance split, must declare their audit coverage and key configuration in the same migration that introduces them. This matter neither approves nor depends on implementing that proposed split first. Audit row history remains separate from 2cb2/7fda's queryable evidence for accepted biological assertions.

## Actor attribution and atomicity

- Follow the existing reviewed_by_id convention: use the local Accounts.User ID as stable human identity, with the chosen display-name snapshot for historical presentation. Preserve attribution when a profile is renamed/deleted; history must not cascade with user or entity deletion. Do not copy whole sessions, tokens, role claims, email fallbacks or profile biographies into transaction metadata.
- Metadata also identifies the operation and execution origin. A user-triggered asynchronous action retains its initiating/reviewing human while separately identifying the worker/task; a scheduled operation has an explicit named system actor. Do not guess a human from a shared database login or a content author field.
- Resolve the trusted actor at the actual execution root and pass it explicitly across LiveView/async/job/CLI boundaries. Backfill stable IDs for old authenticated sessions through existing account/session helpers; keep development bypass and test actors explicitly synthetic.
- Insert Carbonite transaction metadata **inside the same checked-out database transaction, before the first audited write**. Use Carbonite.insert_transaction or Carbonite.Multi.insert_transaction through a small Gallformers.Audit integration boundary. Integrate with existing context transactions; nested operations must reuse the intended metadata without changing actors or confusing SQL Sandbox ownership.
- A Plug or process-dictionary value alone is not the design: later LiveView events, spawned processes, pooled connections and Oban retries have different lifetimes. Serialize minimal actor/operation metadata for durable work and preserve it across retries; do not keep a database transaction open across remote API/S3 calls just to carry attribution.
- Direct SQL, imports, migrations and operator repairs of audited tables must explicitly register audit transaction metadata. Carbonite rejects otherwise unaudited writes; also validate the required actor/operation metadata at the database boundary so an empty metadata row is not an attribution bypass. Do not add a permissive unknown-actor fallback. Label system/maintenance operations truthfully and record the database role as execution context where useful.
- Failed transactions leave neither committed domain changes nor committed audit changes. This is a history of committed mutations, not failed attempts, reads, logins or security events. History grouping does not make S3 calls or several separate commits atomic.
- Retain the earlier requirement for a reason on explicit destructive curated-record deletion. Extend the existing delete confirmations and validate at the mutation boundary; propagate the root reason to cascade effects. Routine relationship replacement/unlinking should carry its operation context, not prompt separately for each internal DELETE. Import/maintenance reasons are explicit operator/system context.

## History browser

Add a read-only /admin/audit surface behind the existing admin authorization rules, including connected LiveView authorization. All admins may browse; there is no public history endpoint, audit mutation API or restore button.

Provide server-side pagination and filters for date, actor, record type/identity and operation. Show transaction summaries with their related row changes and readable before/after values. Support both surrogate and composite keys, and records that no longer exist. Use stored identity/labels when a live entity link is unavailable; changes to key columns must remain discoverable from their old as well as new identity.

Reuse existing table, input, pagination and layout components. Render historical text safely as escaped data or through an existing approved sanitizer, never as arbitrary executable HTML. Avoid loading entire histories or large document payloads into the list view; load details on demand. No new visual component pattern is authorized by this plan.

## Retention, privacy and recovery boundaries

- Keep history indefinitely in the private database and full private backups. Do not enable Carbonite purge/outbox processing, archival infrastructure or broad JSONB indexes without an actual requirement; use its record/transaction indexes and add only measured query indexes.
- Normal application/admin paths must treat recorded history as append-only. Verify deployed database-role protections against accidental alteration and prevent runtime audit bypass; do not market this as tamper-proof against a privileged database owner. No compliance ledger or external immutable archive is in scope.
- Exclude the complete audit schema/data from every public snapshot/export. Also remove audit-trigger dependencies attached to exported curated tables: excluding the audit schema alone may leave an unrestorable public archive. Produce and restore-test a standalone public dump without disabling auditing on the production source database. Keep the audit schema and its metadata in private backups.
- Carbonite does not capture per-row history for TRUNCATE. Disallow TRUNCATE on audited tables for runtime workflows rather than silently presenting incomplete coverage; DDL, trigger disabling, whole-database restores and privileged maintenance are separately controlled operator actions, not row-audit guarantees.
- History begins at activation. Do not invent pre-activation edits or actors, and do not import a synthetic baseline as if it were real user changes. The first update's before values and future deletion snapshots still preserve the affected preexisting record.
- No generic restore/revert helper, soft deletion, media-version retention redesign or automatic cascade reconstruction. Existing recovery procedures remain operator-only and retain their documented limitations; no history row proves that an S3 object is recoverable.

## Implementation plan

**Goal:** Deliver complete curated-data mutation capture and an admin-readable history without bypasses, public-data leakage or a new restore system.

**Architecture:** Carbonite owns PostgreSQL capture/storage. Gallformers.Audit owns trusted operation metadata and bounded read queries; existing contexts retain domain mutation responsibility and existing components provide the UI.

**Tech stack:** PostgreSQL, Carbonite, Ecto/Ecto.Multi, Phoenix LiveView and Oban for existing durable jobs.

### 1. Capture contract and transactional integration

Files: mix.exs; lib/gallformers/audit.ex (new); priv/repo/migrations/20260913120000_add_audit_trail.exs (new); test/gallformers/audit_test.exs (new).

Install the compatible Carbonite release and migrations, configure every allowlisted table/key and store_changed_from, and implement the shared metadata/transaction boundary. Do not add ex_audit, wrap only individual Repo CRUD calls, or build a second audit store. Cover bulk SQL, composite-key changes, cascading deletes, SET NULL updates, missing context and transaction rollback with focused PostgreSQL-backed behavioral tests.

### 2. Migrate every supported writer before activation

Integration seams: lib/gallformers_web/plugs/require_admin.ex; lib/gallformers_web/live/admin/form_helpers.ex; custom admin forms/image and async-import handlers; lib/gallformers_web/components/form_components.ex; lib/gallformers/species.ex, galls.ex, ranges.ex, images.ex, sources.ex, articles.ex, keys.ex and taxonomy/reclassification.ex; ingestion_pipeline/worker.ex; write-capable lib/mix/tasks; affected vocabulary/geography and relationship contexts.

Pass trusted actors through all curated mutation entry points, integrate existing transactions and Ecto.Multi operations, carry context across async/retry boundaries, and add destructive-delete reasons through existing components. Inventory all bulk/raw-SQL writers, not only the examples above. No write-capable caller may be left relying on an implicit default actor.

Also update Makefile's test-db seed path, priv/repo/test_seeds.sql, test/support/data_case.ex and affected fixtures to supply explicit seed/test transaction metadata. Keep actual audit behavior active in tests; do not globally disable triggers or supply a hidden default that masks missing actor integration. Verify actor isolation between pooled connections, LiveView processes, jobs and SQL Sandbox tests.

### 3. Read-only administrator history

Files: lib/gallformers/audit.ex; lib/gallformers_web/live/admin/audit_live.ex (new); lib/gallformers_web/router.ex; lib/gallformers_web/components/layouts.ex; test/gallformers_web/live/admin/audit_live_test.exs (new, authorization/history behavior only).

Build the bounded transaction/record history queries and existing-component UI described above. Verify all-admin access and non-admin denial, grouped relation/cascade changes, deleted-record inspection, old/new values and stable actor display. Exercise the actual browser surface with representative single-record, relationship and bulk operations; no restore controls.

### 4. Safe activation and operational verification

Files: .github/workflows/db-snapshot.yml; runbooks/restore-database.md; runbooks/restore-deleted-gall.md; existing implementation/architecture documentation as affected.

Coordinate application cutover, trigger activation and public-export exclusions so neither the old application nor background/CLI writers encounter newly enforced triggers before their context migration. Use an explicit maintenance/read-only window if necessary, draining write jobs and controlling direct SQL too. Define the activation boundary; do not silently enable triggers in ignore mode and call the intervening writes audited.

Verify a private backup restores audit history and that the public archive excludes it and restores independently. Document how operator SQL registers a truthful audit transaction without disabling capture. Measure representative range-replacement/import/delete operations and history queries for latency and storage growth; tune only demonstrated problems. Never roll back an application deployment by deleting retained history.

## Acceptance and verification

- All allowlisted curated mutations are either captured with explicit actor/operation metadata or rejected; single-row, bulk, raw-SQL, FK CASCADE and SET NULL paths are covered.
- The first edit after activation shows prior values; deletes retain full recorded row data; composite keys and key changes are inspectable without conflating records.
- LiveView, asynchronous work, durable retries and operator tasks preserve truthful attribution. Two users/processes cannot inherit each other's metadata through pooling or nested transactions.
- Failed domain/audit writes roll back together. Relationship replace-all operations remain visible as the real transaction's changes rather than disappearing behind a parent-only record.
- Explicit destructive deletes require a reason, and the grouped history includes resulting relationship changes.
- Every admin can browse paginated history and deleted records; non-admins/public clients cannot. Historical text cannot execute markup/scripts.
- Private backup/restore preserves history; public snapshot/restore contains no audit data or unresolved audit-trigger dependencies.
- Tests and seed/fixture bootstrap work with real audit enforcement. Keep focused regression coverage for these failure-prone boundaries; run mix compile --warnings-as-errors or mix precommit when code is implemented, and pass precommit before any commit.
- No automatic pruning, restore UI, ex_audit compatibility layer, new public history surface or fabricated historical backfill is introduced.

## Sources and related work

- Carbonite architecture and transaction/key configuration: https://hexdocs.pm/carbonite/
- Carbonite row/before-value semantics: https://hexdocs.pm/carbonite/Carbonite.Change.html
- Carbonite migration APIs: https://hexdocs.pm/carbonite/Carbonite.Migrations.html
- PostgreSQL trigger transaction and FK-cascade behavior: https://www.postgresql.org/docs/current/trigger-definition.html
- ExAudit's documented wrapper coverage: https://hexdocs.pm/ex_audit/readme.html
- 2cb2 / 7fda: accepted-assertion evidence and possible domain-model changes, not a replacement for this audit trail.
- 5c56 / f49a: domain merge/split and taxonomic-history semantics, not generic row restoration supplied by this matter.
