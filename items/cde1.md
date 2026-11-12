---
plan: taxogall
phase: f709
title: Provision Postgres for preview and load WCVP and a production copy (with Jeff)
stage: committed
docs:
  - .mull/matters/f465-preview-postgres-setup-with-wcvp-data.md
created: "2026-11-09T20:38:18Z"
updated: "2026-11-12T02:23:22Z"
---

**Why.** Preview has no Postgres of its own. It used to share `gallformers-db`, which became production's database in the March 2026 Postgres cutover. Step 5 (process Sources into a copy of production, with Jeff and Adam) and step 6 (rehearse and cut over) both need preview to run the taxogall code on its own database, holding WCVP and a converted copy of production. Curators' decisions made there reach production only through preview's replay log (`b5bd` M0, M6), so the database is persistent staging, not a throwaway.

**What to do** (f465's list, with the specifics the repo gives):
1. **Provision a Fly Postgres app for preview.** `runbooks/postgres-cutover.md` names it `gallformers-preview-db` (production's is `gallformers-db`). Jeff provides the Fly credentials and settles the cost and size.
2. **Point the preview app at it.** Set the `DATABASE_URL` secret on `gallformers-preview`. WCVP needs no secret of its own: `config/runtime.exs` derives `Gallformers.Repo.WCVP`'s URL from `DATABASE_URL` by replacing the database name with `wcvp`. So the cluster must hold a database named `wcvp` next to the main one. `ECTO_IPV6 = "true"` is already in `fly.preview.toml`.
3. **Load WCVP.**
   - Create the `wcvp` database on the cluster (`CREATE DATABASE wcvp;` via `fly proxy`).
   - pg_restore the S3 dump artifact into it. `mix gallformers.wcvp.restore` defaults to `https://gallformers-backups.s3.amazonaws.com/public/wcvp.dump`. The command in `runbooks/wcvp.md` is `pg_restore --clean --if-exists --no-owner --no-acl -d wcvp -h localhost -p <proxy port>`.
   - WCVP isn't managed by Ecto migrations.
4. **Restore a production copy into the main database.** The latest full backup is `s3://gallformers-full-backups/<date>/gallformers.dump` (how `make download-db` finds it). See `runbooks/restore-database.md`.
   - The production copy includes private tables such as `users` (personal details), and loading it onto a Fly machine sends it to a service other than Anthropic. Jeff's standing rule: say what is being sent and where, and wait for his OK.
5. **Deploy taxogall to preview, then convert.** `make preview` runs `fly deploy --config fly.preview.toml`, and the schema migrations run at boot (`docker-entrypoint-preview.sh`). Then run the catalog migration as its own step, never at boot (`b5bd` M0): `fly ssh console -a gallformers-preview`, then `bin/gallformers eval "Gallformers.Release.migrate_catalog()"`.
   - It is strict: it stops with nothing written on any pending curated decision or duplicate taxon key.
   - It starts WCVP (plant authorship is one of its steps) and the private storage.
   - Time it; `b5bd` M5 wants production-like timing from preview.
6. **Update the runbooks** with what was actually done (item 37cb holds the runbook work: one preview runbook, or the scattered sections brought up to date). Tick or rewrite "Provision `gallformers-preview-db`" in `runbooks/postgres-cutover.md`.

**Things to settle with Jeff while doing it** (the matters don't cover them):
- How preview's database is backed up. Its replay log is the only carrier of curator decisions to production, until it is exported at cutover.
- Whether the converted copy is refreshed from a newer production dump before the backscan starts. After curators start, a refresh would wipe their work unless the replay log is exported and replayed first.

**Done when** gallformers-preview.fly.dev runs taxogall against its own Postgres:
- `wcvp_names` is populated in its `wcvp` database;
- the main database holds a production copy converted by a clean strict `Release.migrate_catalog()` (report printed, every reconciliation line balanced);
- it is ready for step 5's curators (Jeff and Adam) to work on.

From matter f465. Needs Jeff: Fly credentials and cost. Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.

Before Model v2 this item needed 37cb. Items have no needs now; order work with needs between phases.
