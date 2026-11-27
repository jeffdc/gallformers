# Architecture reviews

One entry per periodic review of the code against [README.md](README.md) and [rules.md](rules.md), newest first. A review records what it checked and what it found. Each finding ends in one of: **fix** (work to do, with where it's tracked), **accept** (an exception, with the reason, noted in rules.md), **new rule** (added to rules.md with its check, and a decision in [decisions.md](decisions.md)), or **open** (waiting for Jeff).

## 2026-11-26: Baseline

The first review. The whole of `taxogall` (bd3c5061) was mapped by four read-only agents to write README.md and set each rule's baseline: the contexts, their tables and the dependencies from `mix xref` and Boundary; the web layer; runtime, infrastructure and delivery; and every existing check with the documented rules no check covers. The old architecture docs (core-architecture-rules.md, elixir-architecture.md, range-system.md, the C4 model) were checked against the code, their true parts moved into the new docs, and they were deleted.

The bugs found go in the [backlog](../backlog.md) (Jeff, 2026-11-26: all of them, and future phases are planned with the backlog in hand); a finding below that is tracked there says "backlog". Doc drift outside this folder is fixed in [cleanup step 10](../cleanup/README.md).

### Rule violations

Each is counted in its rule's baseline in rules.md.

1. **S1, contexts reach into each other's tables**, in about 90 places. The largest groups: Import queries the schemas of Facts (`import.ex:2516-2517`, `import/facts_view.ex:233,326,596,708,770`, `merge.ex:542`, `preview.ex:595,766,771,794`, `source_corrections.ex:191,444,571-613`, `taxonomy_queue.ex:574,897`, `taxonomy_statements.ex:464`, `fact_history.ex:197`), Taxa (`curation_notes.ex:96`, `deletion.ex:217`, `facts_view.ex:441-442,769,824-826`, `merge.ex:161,400`, `preview.ex:688`, `taxonomy_statements.ex:414,562-568`, `taxonomy_edits.ex:113,120`, `undo.ex:545`, `taxonomy_carry_over.ex:438`), Catalog (`curation_notes.ex:79`, `deletion.ex:216`, `facts_view.ex:381,383,422,456`, `merge.ex:160`, `preview.ex:793`, `source_corrections.ex:612`), Sources and Places. Catalog's read models query Facts, Taxa, Images, Places and Sources (`catalog/read_models/current.ex`, `browse.ex:152`, `gall_page.ex:217-218`, `species_sources.ex:89-102`, `site.ex:185,228,241,283,296,312`, `potential_range.ex:77,140,188,275,323`, `api.ex:220`; `catalog.ex:294,674`, `identify.ex:108,332,334`, `records.ex:201`, `split_inducers.ex:76,107`, `vocab/term_usage.ex:26`). Curation queries Catalog and Facts (`curation/from_observation.ex:218`, `review.ex:239,249,250`). `Audit.ChangeLog` joins about fifteen tables of other contexts in raw SQL (`audit/change_log.ex:273,372,412`), and Curation, Import and Taxa read Carbonite's tables directly. Search, Images, Ranges and Taxa (`taxa/lump.ex:137`, `taxa/sync.ex:162,174,502`) have a few each. Many are reads of Facts by the read models and the import, which may be accepted as the design: the Fact kinds' schemas belong to Catalog and Taxa but point at `facts`. **Accept** (Jeff, 2026-11-26): the Fact-owning contexts', Import's and Curation's reads of `facts` and `attributions` (to become Facts exports), `Audit.ChangeLog`'s joins, and CatalogMigration's writes until cutover. **Fix: backlog** for the rest: Carbonite's tables read outside Audit, Import's queries on Taxa, Catalog, Places and Sources, and Search, Images, Ranges and Catalog's reads of other contexts. Listed in rules.md, S1.
2. **S4, Catalog reads Taxa's tables** rather than its API in about six places (rules.md, S4). **Fix: backlog** (Jeff, 2026-11-26).
3. **S6, the content admins write unaudited.** Glossary, articles and keys are written with no actor, their tables aren't tracked, and their screens sit in the plug-only admin scope with no on_mount guard. `source`, `host_range` and `image` aren't tracked either; the taxogall plan already lists confirming the audit layer as design work. **Fix: backlog** (the content admins); the rest is the taxogall plan's.
4. **S10, the old tables are read outside the catalog migration**: `ranges.ex:138` reads `species` on every Host range write, and `abundance` is read in five places in Catalog and Taxa. **Accept until cutover** (Jeff, 2026-11-26): abundance becomes a Fact, and the old tables are dropped after release.
5. **D3, non-durable work**: image variants, the iNat photo import and key PDFs run in an unsupervised `Task.start`; a restart loses them, and variant generation sleeps 5s waiting for the CDN (`images.ex:212`). **Fix: backlog.**
6. **X1, three unguarded `String.to_atom`** (`admin/powo_diff_review.ex:450,451`, `catalog_migration/old.ex:14`). **Fix: backlog**, after checking whether their input can come from a client.
7. **X2 and X3**: `review_components.ex:821` interpolates text into `raw/1`; six inline `on*=` handlers that the nonce CSP will block once it is enforced (CODING_STANDARDS.md:330 recommends the pattern `range_editor.ex:588` uses). **Fix: backlog.**
8. **T3 and T6**: `TestsOwnTheirData` is turned off in 35 test files; 62 routes use literal seed IDs; `FlashOnlyAssertions` was never registered (matter b016). **Fix: backlog** (Jeff, 2026-11-26): turn `TestsOwnTheirData` back on file by file, look seed rows up instead of hard-coding their IDs, and register `FlashOnlyAssertions` once its candidates pass.

### Gaps in the checks

Rules that are stated but held by nothing, or held only locally. Each is **fix: backlog** ("Close the gaps in the checks from the 2026-11-26 architecture review"), unless Jeff decides otherwise.

1. **8 of the 9 custom Credo checks only report** (`exit_status: 0`): `NoRepoInWeb`, `NoTransactionOutsideContext`, `NoEctoQueryInLiveView`, `NoMockingLibraries`, `NoHardcodedIds`, `NoBareTruthinessAssert` (about 13 findings), `TestsOwnTheirData`; `FlashOnlyAssertions` isn't registered. core-architecture-rules.md said they fail the build. The four at zero could be made to fail today.
2. **CI never runs on `taxogall`**: `ci.yml` triggers only on pushes to `main` and PRs into it, so O1's checks hold on this branch only when an agent runs `make done-checks`.
3. **`deps.unlock --unused` can't fail**: it rewrites `mix.lock`; `--check-unused` is the checking form.
4. **`format_check` covers only `lib/` and `test/` `.ex`/`.exs`**, so a formatting change in `.heex`, `config/`, `dev/` or migrations passes.
5. **Sobelow, `deps.audit` and `hex.audit` never run**, though they are dependencies. X1–X3 have no check.
6. **Boundary's blind spots** (S1, S2): associations and type atoms, raw SQL and string table names, the root-boundary `Galls.*`, and the config-wired listeners. A check that flags a context's string table names and foreign schemas in queries would cover most of S1.
7. **Credo doesn't lint `dev/`, and the conformance test doesn't scan `dev/gallformers_web` or `assets/js`.**
8. **The router tests use hand-listed paths.** No test walks the router to check that every admin route has a role guard, that `/api/v2` is GET only, or that dev routes need `dev_routes`. There is no CSP test.
9. **The commit gate is local**: installed per clone, skipped by `--no-verify`, and nothing in CI checks a review was recorded.
10. **Rules at zero that a one-line check would lock in**: S3's three checks (make them fail), T4's `NoMockingLibraries`, T5 (`Process.sleep`, 1), D4, X1 for new code, U4 (the baseline files only shrink).
11. **Stale exclusions and comments in `.credo.exs`**: `sitemap_controller.ex` is excluded from two checks it no longer breaks; the comment at `:118` says `TestsOwnTheirData` is disabled, but it is enabled; `ModuleDoc` is both enabled and disabled.

### Proposed rules

Patterns the code follows or assumes that no doc states. **New rule**, all ten (Jeff, 2026-11-26): S11, X4–X8 and O6–O9 in rules.md, in this order: 1 → S11, 2 → X6, 3 → X7, 4 → X4, 5 → X5, 6 → O6, 7 → O7 (the service left open), 8 → X8, 9 → O8, 10 → O9. The bug behind each is in the backlog.

1. **Business logic never depends on the web layer.** Holds today: the only edges are the Application starting the endpoint and telemetry, and the design-system baseline mix task.
2. **Read-only mode stops every write.** Today `EnforceReadOnly` blocks only the admin pipelines' HTTP requests: public Edit mode, the tray's apply and already-connected admin sockets keep writing.
3. **Every screen that writes sits behind an on_mount role guard.** The content admins and the Oban and LiveDashboard mounts have plug gates only; `UsersLive` doesn't re-check its role in its handler.
4. **The CSP is enforced, with a report endpoint.** It is report-only and collects nothing; iNat photo hosts are missing from `img-src`.
5. **Rate limits key on the trusted client IP.** The API limiter reads the first `x-forwarded-for` entry, which a client sets, ignoring the endpoint's `fly-client-ip`.
6. **Production fails loudly on a missing secret.** Only `DATABASE_URL` and `SECRET_KEY_BASE` raise; Auth0 and S3 are silently optional, and `PHX_HOST` defaults to `example.com`.
7. **Errors reach someone.** No error tracking; the downdetector only sees the home page.
8. **Dev never writes to production storage.** Dev doesn't set `s3_enabled: false`, so with `S3_PUT_*` keys in the environment its uploads go to the production images bucket, unprefixed.
9. **Only `main` deploys to production.** `deploy.yml`'s manual trigger has no branch guard, so a manual run on `taxogall` would deploy it.
10. **One machine.** The rate limiter and SiteSettings' cache assume it, but `fly.toml` sets no maximum; DNSCluster is started with no query.

### Doc drift

1. **The old architecture docs**: core-architecture-rules.md (checks "fail the build"; checks in `lib/credo/checks/`, actually `dev/credo/checks/`; a `SpeciesNameOwnership` check that doesn't exist; "three known dependency cycles", now none), range-system.md (the old `gall_range` and exclusion model, `/admin/gallhost`, confirmation on the Gall), elixir-architecture.md (contexts `Species`, `Taxonomy`, `Hosts` that don't exist) and the C4 model (SQLite, Litestream, iad). **Fixed** in this change: their true parts moved here, and they were deleted. `lib/gallformers/ranges.ex` pointed at range-system.md; it now points here.
2. **CODING_STANDARDS.md**: `SpeciesNameOwnership` and the `Gallformers.Taxonomy.*` modules; schemas under `lib/gallformers/species` and `taxonomy`; the legacy palette (`text-gf-maroon`, `bg-cadet-blue`) that the conformance test bans, and `text-red-500` in an example; `<Layouts.app>`; says Dialyzer runs in `mix precommit` (as do AGENTS.md's "precommit passes" and the README's "run all checks"), but only `make done-checks` and CI run it. **Fix: cleanup step 10.**
3. **AGENTS.md against testing-philosophy.md**: AGENTS.md says to add a test case as seed rows; testing-philosophy.md says tests never use seed data (T3). **Fixed** (Jeff, 2026-11-26): AGENTS.md's rule stands; seed rows are fixtures a test may use but never by a hard-coded ID. testing-philosophy.md and T3 say so.
4. **CODING_STANDARDS.md against foundations.md**: no inline `<script>`, but foundations.md documents the theme-init script (X3). **Accept** (Jeff, 2026-11-26): it carries the CSP nonce and must run before the page paints; X3's one exception.
5. **testing-philosophy.md**: names `Gallformers.S3.request/1` (it is `Gallformers.Storage.S3`) and `make test-prod-data-e2e` (no such target). **Fix: cleanup step 10.**
6. **The design-system README** says the system is being built on a `design-system` branch; components.md says every component module is imported into every template (five aren't) and lists `range_map` under the wrong module. **Fix: cleanup step 10.**
7. **Runbooks, the top-level README and `infra/README.md`**: production is in ewr, not iad; the VM is 1GB; Postgres is self-managed, not "Managed"; Oban's queues are `default`, `maintenance`, `import`, `catalog`; backups exist (`db-snapshot.yml`), though two docs say TBD or TODO and point to a missing `docs/backup-setup.md`; `services/usda_plants` doesn't exist; the workflows aren't named "V2"; the public dump drops `users` rather than nulling it; `infra/README.md` doesn't cover the private bucket, the site's distribution, DNS or the Lambda. **Fix: cleanup step 10.**
8. **Comments in code and config**: `application.ex:55` says the entrypoint sets `RUN_MIGRATIONS` (nothing does); `Dockerfile.preview` and `fly.preview.toml` describe a baked-in database and data that aren't there; `infra/s3.tf` describes the private bucket as planned; `runtime.exs` calls the upload key PUT-only (it can also get, list and delete); `admin/review/questions.ex:10` cites a file in gitignored `docs/plans/`. **Fix: backlog.**
