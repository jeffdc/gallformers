# Architectural rules

The rules the code must follow, each with its check and its baseline. Every rule here is one Jeff has stated, with its source. Rules a review proposes stay in [reviews.md](reviews.md) until Jeff adopts them; adopting one adds it here and records the decision in [decisions.md](decisions.md). Coding style (naming, docs, idioms) is in [CODING_STANDARDS.md](../../CODING_STANDARDS.md) and Credo, and the look in the [design system](../design-system/README.md), not here.

- **Check** names the automated check and where it runs: `mix precommit` (so also `make done-checks` and CI), `make done-checks` only, CI only, or a git hook. "Advisory" means the check reports but never fails (`exit_status: 0`). "Manual" means it is checked by hand in reviews until it has a check.
- **Baseline** is the count of known violations at the last review, with where they are. A check holds its rule at the baseline: it fails when the count grows, and the baseline is lowered as violations are fixed. Never raise one to pass a check (AGENTS.md).
- IDs are stable and never reused. A retired rule stays, marked retired.

Baselines as of the [2026-11-26 review](reviews.md#2026-11-26-baseline), at `taxogall` bd3c5061. Counts marked "by grep" are rough and include false positives.

## Structure

| ID | Rule | Source | Check | Baseline |
|---|---|---|---|---|
| S1 | A context owns its tables. No other module reads or writes them; others call its public functions. | docs/architecture/core-architecture-rules.md §5 (retired 2026-11-26, moved here); CODING_STANDARDS.md, Phoenix Contexts; docs/taxogall/README.md, Two systems ("black boxes behind Phoenix contexts") | Boundary checks calls to other contexts' modules, but not queries on their schemas, associations or string table names: manual | About 90 locations, listed in the [2026-11-26 review](reviews.md#rule-violations), item 1. In short: Import queries Facts, Taxa, Catalog, Sources and Places schemas (`import/facts_view.ex`, `preview.ex`, `source_corrections.ex`, `taxonomy_statements.ex`, `taxonomy_edits.ex`, `merge.ex`, `deletion.ex`, `undo.ex`, …); Catalog's read models query Facts, Taxa, Images and Places (`catalog/read_models/current.ex`, `species_sources.ex`, `site.ex`, `potential_range.ex`, `api.ex`, `catalog/identify.ex`); `Audit.ChangeLog` joins about fifteen tables of Catalog, Taxa, Facts, Places, Import and Sources in raw SQL (`audit/change_log.ex:273,372,412`); Curation, Import and Taxa read Carbonite's tables directly (`curation/audit_trail.ex:87`, `import/fact_history.ex:64,149`, `import/undo.ex:208,231,257`, `taxa/records.ex:247`); Search queries four contexts' schemas (`search.ex:130,199,219,240`); Images reads `galls` and `taxon_names` (`images.ex:439,441`); Ranges reads `taxon_ancestry` (`ranges/wcvp.ex:445`); CatalogMigration writes `keys` and `image` (`catalog_migration/keys.ex:82`, `images.ex:19-29`). |
| S2 | Every context declares its dependencies and exports in Boundary; a new cross-context call is declared first. | core-architecture-rules.md, Architectural Enforcement | Boundary compiler, `mix compile --warnings-as-errors`: precommit, CI | 0 violations, 0 cycles. 16 declared exceptions (`dirty_xrefs`), all on `GallformersWeb` (`lib/gallformers_web.ex:21-38`): Repo, SchemaFields, TaxonName, TextMatch and 12 schema or internal modules. `Gallformers.Galls` has no boundary and sits in the root, so it is unchecked. |
| S3 | The web layer reaches data only through contexts: no `Repo`, `Ecto.Query` or `Repo.transaction` in `lib/gallformers_web`. Contexts own transactions. | core-architecture-rules.md §1, §5 | `NoRepoInWeb`, `NoTransactionOutsideContext`, `NoEctoQueryInLiveView`: precommit, advisory | 0, with the health check (`health_controller.ex:21`) excluded. The LiveDashboard mount names the Repo (`router.ex:320`). |
| S4 | Two systems: taxonomy knows nothing about Galls; the gall system knows taxa only by ID and through the taxonomy API. Nothing else crosses. | docs/taxogall/README.md, Two systems (Adam and Jeff, 2026-10-03/04) | Boundary holds the first half (`Taxa` doesn't depend on `Catalog`). The second: manual. | Taxa: 0. Catalog queries Taxa's schemas and tables: `catalog/read_models/api.ex:220`, `potential_range.ex:275`, `species_sources.ex:91,93,95`, `site.ex:241,296`; associations to `Taxa.Taxon` in `catalog/facts/relationship_fact.ex:66,68` and `catalog/vocab/generation_group_taxon.ex:27`. |
| S5 | One write path: for any data, exactly two ways in (its editing screen and the import), and both call the same code to validate, write and read it. | docs/taxogall/README.md, One write path (Jeff, 2026-11-12) | Manual | Not yet built; it is a taxogall phase. Today the content admins (glossary, articles, keys) and Host ranges write outside the import. |
| S6 | Audit is a layer underneath: every write to a tracked table names its actor, and the database refuses one that doesn't. | docs/taxogall/README.md, Audit | Database: Carbonite's trigger and the `transactions_meta_attribution` CHECK | 0 on tracked tables. Not tracked: `source`, `document_items`, `host_range`, `image`, `place`, `users`, `change_sets`, `change_set_items`, `articles`, `keys`, `glossary`, `content_images`. The content admins write with no actor (`glossary_live/form.ex:33-37`, `key_live/form.ex:32-38`, `article_live/form.ex:148-150`). |
| S7 | A shared capability has one owner; everything else calls it. | AGENTS.md, Building | `SingleEntryPoint` (`.credo.exs`): precommit, enforced; a pending caller that stops calling must be removed from the list | 5 capabilities. 7 pending callers (matter b230): `ReviewLive.Answer` ×3, `TaxonomyLive.New`, `TaxonomyLive.RangeEditor`, `InatTaxonPanel`, `ReviewLive.Review`. |
| S8 | Replacing means deleting: the old module is listed in `test/support/retirements.exs` and deleted in the same change. | AGENTS.md, Building | Retirements test (fails while both old and new load): precommit | 0 entries |
| S9 | Search before you write: never write new code for something that already exists. | AGENTS.md, CRITICAL and Building | Duplicate-code ratchet (Credo `DuplicatedCode`, mass 40, `test/support/duplicate_code_baseline.json`): precommit. The commit gate's review: pre-commit hook. | 63 findings in 24 file sets; 21 findings in 10 sets in `lib/` (e.g. `review_live/{source,step,taxonomy}.ex`, `catalog/read_models/{api,search}.ex`, `review_live/facts.ex` and `source_live/facts.ex`). |
| S10 | The old tables are read only by the catalog migration. | AGENTS.md, Domain model | Manual | `ranges.ex:138` reads `species` on every Host range write; `abundance` is read by `catalog.ex:583`, `catalog/read_models/api.ex:200`, `gall_page.ex:235`, `taxa.ex:479`, `taxa/read_models/host_page.ex:101`; `mix gallformers.catalog.id_parity` runs the old ID filter. `host_range.species_id` and `image.species_id` are still written. |

## Web layer

From core-architecture-rules.md's principles (retired 2026-11-26, moved here).

| ID | Rule | Source | Check | Baseline |
|---|---|---|---|---|
| W1 | LiveViews are routers, not orchestrators: they turn events into context calls and results into assigns. | core-architecture-rules.md §1 | Manual | Not measured. Size as a proxy, web files over 1,000 lines: `admin/review/questions.ex` (3,542), `review_components.ex` (2,879), `facts_components.ex` (1,868), `review_live/loader.ex` (1,543), `form_components.ex` (1,534), `gall_live.ex` (1,441), `id_live.ex` (1,435), `review_live/answer.ex` (1,293), `domain_components.ex` (1,265), `images_component.ex` (1,230), `vocabulary_live.ex` (1,076), `article_live/form.ex` (1,040). |
| W2 | State with its own lifecycle is a LiveComponent. | core-architecture-rules.md §2 | Manual | Not measured |
| W3 | Duplication across LiveViews means a missing abstraction below them: a LiveComponent, a handler module or a context function. | core-architecture-rules.md §3 | The duplicate-code ratchet (S9) catches copies, not near-copies | See S9 |
| W4 | One function sets defaults; callers override only what differs. | core-architecture-rules.md §4 | Manual | Not measured |

## Domain and data

| ID | Rule | Source | Check | Baseline |
|---|---|---|---|---|
| D1 | Domain concepts are types, not strings: a format parsed in more than one place is an unmodelled type. | core-architecture-rules.md §6 | Manual | 17 `String.split` on names outside `Gallformers.TaxonName`: `ranges/wcvp.ex:86`, `curation/from_observation.ex:419`, `import/unused_names.ex:312`, `import/name_suggestions.ex:86`, `import/host_suggestions.ex:347,385,431,469,483`, `import/replay.ex:552`, `import/gall_matcher.ex:576,707`, `import/resolver.ex:182`, `import/synonym_decisions.ex:116`, `admin/review_live/loader.ex:896,1188,1202`. |
| D2 | Queries use Ecto, not raw SQL; input is never interpolated into SQL. | CODING_STANDARDS.md, Queries and Input Handling | Manual | 61 `Repo.query`/`SQL.query` calls in 26 `lib/` files; 38 schemaless `from(x in "table")` queries. SQL built by interpolation (of module constants and IDs, not user input): `analytics/rollup.ex:216`, `catalog_migration/trait_id_export.ex:30`, `taxa.ex:552`, `legacy_facts.ex:269`, `legacy_taxonomy.ex:52`, and the mix tasks `wcvp/build_db.ex:114,125,161`, `catalog/id_parity.ex:188`. |
| D3 | Durable, retryable or scheduled work runs on Oban; a plain GenServer or `Process.send_after/3` only where persistence and retries don't matter. | AGENTS.md | Manual | Image variants run in an unsupervised `Task.start` (`Async.run`: `images.ex:209`, `content_images.ex:167`, `storage/images.ex:231`), as do the iNat photo import (`inat_import_component.ex:305,330`) and key PDFs (`key_live/form.ex:63`). |
| D4 | S3 is reached only through `Gallformers.Storage.S3`. | CODING_STANDARDS.md, S3 Isolation | Config: `s3_enabled: false` in tests | 0 |

## Security

| ID | Rule | Source | Check | Baseline |
|---|---|---|---|---|
| X1 | Input never becomes an atom. | CODING_STANDARDS.md, Atom Creation | Manual | 6 `String.to_atom`; 3 guarded by an allowlist (`glossary_live.ex:51`, `search_live.ex:104`, `article_live/form.ex:255`), 3 not (`admin/powo_diff_review.ex:450,451`, `catalog_migration/old.ex:14`). |
| X2 | `raw/1` only on trusted HTML. | CODING_STANDARDS.md, HTML Output | Manual | 10 calls: `page_components.ex:313`, `domain_components.ex:72,134`, `data_display_components.ex:73`, `root.html.heex:41`, `review_components.ex:821,2354`, `glossary_live.ex:146`, `article_live/form.ex:678`, `filter_guide_html.ex:32`. `review_components.ex:821` interpolates its `text` unescaped; today's callers pass literals. |
| X3 | No inline scripts; no external scripts or stylesheets. | CODING_STANDARDS.md, JavaScript Interop, Asset Bundles, Things to Avoid | Manual | 2 inline scripts in `root.html.heex` (`:9` theme init, nonce'd, which foundations.md documents; `:40` JSON-LD). 6 lines with inline `on*=` handlers: `core_components.ex:56`, `admin/images_component.ex:267,407,643,696`, `taxonomy_live/range_editor.ex:588`. Swagger UI on `/api/docs` loads from cdnjs. |

## UI and design system

| ID | Rule | Source | Check | Baseline |
|---|---|---|---|---|
| U1 | All UI is built from the design system's components; never a custom inline version. One that almost fits is extended with its catalog entry; when none fits, ask Jeff with a proposed entry. | AGENTS.md, Design system; design-system README, The five rules | Manual | Not measured |
| U2 | Colour, type, spacing, radius and shadow come from the tokens. | design-system README, rule 2 | Conformance ratchet (`test/gallformers_web/design_system/conformance_test.exs`, `test/support/design_system_baseline.json`): precommit | 17 in 4 files: `design_system/conformance.ex` 10 (its own patterns), `root.html.heex` 4 (3 hex, 1 inline style), `plugs/enforce_read_only.ex` 2 inline styles, `admin/profile_live.ex` 1 radius. Not scanned: `dev/gallformers_web`, `assets/js`. |
| U3 | A domain formatting rule has one function and one component (scientific names through `<.taxon_name>` and `<.gall_name>`), with semantic markup rather than visual classes. | core-architecture-rules.md §7-9 | Manual | 90 `italic` classes in 26 web files and `<em>` in 9, by grep; not all are names. |
| U4 | Never raise the conformance baseline. | AGENTS.md, Design system | Manual: the baseline file's diff, in review | 0 |

## Tests

| ID | Rule | Source | Check | Baseline |
|---|---|---|---|---|
| T1 | Features and bug fixes start with a failing test, watched to fail for the expected reason. | AGENTS.md, CRITICAL | Manual | Not measured |
| T2 | A test that fails only sometimes has a cause; find it rather than re-running. | AGENTS.md, CRITICAL | Manual | Not measured |
| T3 | Tests create the data they assert on; they don't depend on seed IDs. | docs/testing-philosophy.md, Core belief 6; CODING_STANDARDS.md, Fixtures | `NoHardcodedIds` (literal IDs in `Repo.get`) and `TestsOwnTheirData`: precommit, advisory | `NoHardcodedIds` 0. `TestsOwnTheirData` turned off in 35 test files. 62 routes with literal seed IDs (e.g. `gall_live_test.exs:36`). AGENTS.md also says to add a test case as seed rows ([review](reviews.md#doc-drift)). |
| T4 | No mocking libraries; stub through behaviours. | docs/testing-philosophy.md, On Mocking | `NoMockingLibraries`: precommit, advisory | 0 |
| T5 | No `Process.sleep` in tests. | CODING_STANDARDS.md, Things to Avoid | Manual | 1: `articles_test.exs:256` |
| T6 | LiveView tests verify database state, not only the flash. | docs/testing-philosophy.md, Tier 2 | `FlashOnlyAssertions` exists but is not registered (`.credo.exs:118-120`) | 68 test files submit or click; not measured further |

## Delivery

| ID | Rule | Source | Check | Baseline |
|---|---|---|---|---|
| O1 | Work is finished only when `make done-checks` passes (test database rebuild, check-toolchain, `mix precommit`, Dialyzer). | AGENTS.md, Work tracking | Local only. CI runs the same checks, but only for `main` and PRs into it. | Pushes to `taxogall` get no CI run. |
| O2 | Always compile with `--warnings-as-errors`. | AGENTS.md, CRITICAL | precommit, CI | 0 |
| O3 | No commit without `mix precommit` passing and a passing review by a fresh-context reviewer; docs-only commits need no review. | AGENTS.md, CRITICAL and Before you commit | `dev/githooks/pre-commit` (the review); precommit by hand | Local per clone (`make hooks`); skipped by `--no-verify`; nothing in CI checks a review was recorded. |
| O4 | No force pushes; never push `main` or `master`. | AGENTS.md, Before you commit | `dev/githooks/pre-push`; the main ruleset on GitHub | 0 |
| O5 | Environment variables are read only in `config/runtime.exs`. | CODING_STANDARDS.md, Configuration | Manual | `config/config.exs:72`; `config/prod.exs:33` (at compile time); `config/dev.exs:9-31` (10); `config/test.exs:27-56` (8); `lib/gallformers/repo.ex:12`, `repo/wcvp.ex:18`, `application.ex:57`, `wcvp/conn.ex:17-19`, `lib/mix/tasks/gallformers/catalog/migrate.ex:77`. The Postgres connection variables come from the Nix shell, so most of these are dev and test. |

## Checks that exist

Every automated check today, and the rules it holds.

| Check | Runs | Enforces |
|---|---|---|
| `format_check` (`lib/mix/tasks/format_check.ex`) | precommit, CI | formatting of `lib/` and `test/` `.ex`/`.exs` files |
| `mix compile --warnings-as-errors` with Boundary | precommit, CI | no warnings; S2 |
| `mix credo --strict` (`.credo.exs`) | precommit, CI | style; custom checks in `dev/credo/checks/`: S3 and T3–T4 (advisory), S7 (enforced) |
| Duplicate-code test (`test/gallformers/guardrails/duplicate_code_test.exs`) | precommit, CI | S9 |
| Retirements test (`test/gallformers/guardrails/retirements_test.exs`) | precommit, CI | S8 |
| Design-system conformance test | precommit, CI | U2 |
| Router tests (`role_live_session_test.exs`, `admin_actor_test.exs`) | precommit, CI | the role and actor guards on hand-listed admin routes |
| Commit gate and pre-push tests (`commit_gate_test.exs`, `pre_push_test.exs`) | precommit, CI | that O3 and O4's hooks work |
| `mix test` | precommit, CI | behaviour |
| `assets.test` / `npm test` (Vitest) | precommit locally; CI's Assets job | the JS hooks |
| `deps.unlock --unused` | precommit, CI | nothing: it rewrites `mix.lock` rather than failing |
| `test.check_exclusions` | precommit, CI | nothing: it prints guidance |
| `mix dialyzer` | `make done-checks`, CI | types |
| `scripts/check-toolchain` | `make done-checks`, CI | the Dockerfiles match the flake |
| API version check | CI, PRs only | an API controller change bumps `API_VERSION` |
| Carbonite trigger and the attribution CHECK | the database | S6 |
| `dev/githooks/pre-commit` | local commit | O3's review |
| `dev/githooks/pre-push` | local push | O4 |
| `mix smoke_test` | after each deploy | the production site answers |
| Security Audit workflow (`hex.audit`, `deps.audit`, Sobelow `--exit high`) | CI: PRs, `main`, weekly; not a required check; the dependency advisories were cleared in #612, and it fails on Sobelow's `Config.CSP` until production sends a Content-Security-Policy | dependencies; X1–X3 in part |
