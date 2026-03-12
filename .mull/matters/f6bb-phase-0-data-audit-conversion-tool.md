---
status: done
created: 2026-03-11
updated: 2026-03-12
epic: postgres
blocks: [f654]
needs: [4474]
parent: 4474
---

# Phase 0: Data audit + conversion tool

## Goal

Local Postgres with real gallformers data, bootstrappable from Ecto migrations. Plus: any changes to the current production site needed to support the migration.

## Step 0: Site operations features (on main, against current SQLite site)

### Auth0 operator role

- New Auth0 role: `"operator"` — assigned only to Jeff
- `Auth0User.operator?/1`, `Accounts.operator?/1` — same pattern as superadmin
- `RequireOperator` plug — same pattern as RequireSuperAdmin
- `:operator` pipeline in router

### Site settings infrastructure

- DB table `site_settings`: `key` (string, unique), `value` (text, JSON-encoded), timestamps
- `Gallformers.SiteSettings` context: `get/1`, `get/2` (with default), `set/2`
- Typed convenience: `banner_enabled?/0`, `read_only?/0`, `banner_text/0`
- `:persistent_term` cache loaded on app start, invalidated via PubSub on `set/2`

### Maintenance banner

- Rendered in root layout when `banner_enabled?()` is true
- Shows `banner_text()` content
- Visible to all users (public + admin)
- Same z-index/positioning pattern as existing `preview_deploy` banner

### Read-only mode

- `EnforceReadOnly` plug in `:admin` and `:superadmin` pipelines
- When `read_only?()` is true, halts with maintenance message
- Exempts `/admin/ops` so operator can always toggle it off
- Public routes unaffected

### Ops admin page

- LiveView at `/admin/ops` behind `:operator` pipeline
- Controls: banner text, banner toggle, read-only toggle
- Nav link visible to superadmin users

### Testing

- Context unit tests: SiteSettings CRUD, caching, JSON round-trip
- Plug tests: EnforceReadOnly blocks admin, allows ops page, allows public
- Plug test: RequireOperator
- LiveView test: ops page toggle behavior
- Banner rendering test in layout

## Steps 1–4 (on Postgres branch, after Step 0 ships)

### 1. Baseline migration
- Branch, swap main Repo adapter to Postgres
- Write a single migration that creates all tables from Ecto schemas
- Replaces `structure.sql` as the schema bootstrap
- Verify: `mix ecto.create && mix ecto.migrate` produces a complete, empty Postgres schema

### 2. Schema diff
- Dump actual prod SQLite schema
- Dump the Ecto-generated Postgres schema
- Compare — identify everything in SQLite not captured by Ecto schemas
- Expected: FTS5 virtual table, check constraints, indexes, triggers
- Decide per difference: port, replace with Postgres equivalent, or drop

### 3. Data audit
- Script checking every column in prod SQLite against Ecto-declared types
- Known risks: boolean strings, empty strings for NULL, type mismatches
- Output: mismatch report with counts

### 4. Conversion tool
- Data-only — schema from Ecto migrations
- Reads local SQLite, writes local Postgres
- Handles type coercions from step 3
- Repeatable, fast enough to run casually
