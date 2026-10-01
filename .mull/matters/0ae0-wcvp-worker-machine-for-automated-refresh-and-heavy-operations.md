---
status: raw
created: 2026-03-17
updated: 2026-04-25
epic: platform
---

# WCVP worker machine for automated refresh and heavy operations

Dedicated temp Fly machine (or GH Action) for heavy WCVP operations:
1. Download latest CSVs from Kew
2. Process CSVs into Postgres (trim, split, pad — the heavy per-line work)
3. Write results directly to prod PG
4. Dump the wcvp database to S3
5. Write cleaned intermediate CSVs to S3
6. Terminate or go idle

Generalizes beyond WCVP to any heavy operation we don't want on the app server (bulk range syncs, analytics rollups, data imports). Good fit for Elixir/Erlang distributed processing roots.

Depends on 973c (WCVP Postgres migration) being complete first.
