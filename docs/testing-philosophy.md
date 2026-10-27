# Test Philosophy & Architecture

## Purpose

This document defines how we test, why we test that way, and what "green means deployable" requires. All future test work — new tests, refactored tests, deleted tests — is evaluated against this document.

## Testing

Tests use Ecto's SQL Sandbox with PostgreSQL. Tests can run with `async: true` where appropriate.

### Test Types

| Type | Location | Run with | What it covers |
|------|----------|----------|----------------|
| Context/Unit | `test/gallformers/` | `make test` | Domain logic, context functions, changesets |
| LiveView | `test/gallformers_web/live/` | `make test` | Page rendering, user interactions, form workflows (public + admin) |
| Controller/API | `test/gallformers_web/controllers/` | `make test` | REST endpoints, JSON responses, auth, error pages |
| Component | `test/gallformers_web/components/` | `make test` | Reusable component rendering and events |
| Plug | `test/gallformers_web/plugs/` | `make test` | Analytics, caching, CORS middleware |
| Integration | `test/gallformers_web/integration_test.exs` | `make test` | Full page load flows, navigation, PubSub |
| E2E (browser) | `test/e2e/` | `make e2e` | Real browser tests via Playwright (Firefox). Requires prod data. Excluded by default. |
| Prod data | `test/prod_data/` | `make test-prod-data` | Validates against a converted production DB copy (`PROD_DATA_DB=gallformers_taxogall` clones an already converted one). Excluded by default. |
| Prod data E2E | `test/prod_data/e2e/` | `make test-prod-data-e2e` | Browser tests against real production data. Excluded by default. |

**Support files** (`test/support/`): `DataCase` (Ecto sandbox), `ConnCase` (HTTP), `E2ECase` (Playwright, prod data), `ProdDataCase` (real DB validation).

### S3 Isolation in Tests

Tests must NEVER make real AWS/S3 calls. Use `Gallformers.S3.request/1` instead of `ExAws.request/1`. See CODING_STANDARDS.md for details.

### E2E Tests (Browser-based)

E2E tests use Playwright with Firefox. All tests run against a production data copy and are excluded from regular test runs and CI. Install browsers with `make e2e-setup`.

```bash
make e2e                   # Run all E2E tests (loads prod data automatically)
make e2e-changed           # Run only tests affected by changed files
make e2e-public            # Public pages only
make e2e-admin             # Admin pages only (taxonomy, reclassify, etc.)
make e2e-headed            # Run with visible browser
```

See CODING_STANDARDS.md for E2E writing guide, test organization, and setup instructions.

## Core Beliefs

### 1. Green means deployable

If the test suite passes, the site works. Manual testing is for discovery and UX judgment, not for catching bugs. If a bug reaches production, the response is always "why didn't a test catch this?" followed by a test that does.

### 2. Tests verify behaviour, not implementation

A test should describe what the system does, not how it does it. "Creating a gall with hosts updates the host count" — not "save_gall_host_changes calls Repo.insert_all with the right params." Tests that break when you refactor internals are tests that are coupled to the wrong thing.

### 3. Needing a mock is a design smell

If code is hard to test without mocking, the code is too coupled. The fix is to improve the design — extract a behaviour, pass a dependency, separate the side effect — not to patch around it with a mock library. The one exception is external systems (AWS, WCVP) where a behaviour-based stub is the correct boundary.

If you're tempted to mock: extract a behaviour, pass the dependency explicitly, separate the pure logic from the side effect. Then test the pure logic directly and test the integration with the real dependency.

### 4. Every layer earns its own tests

A LiveView test should not be the first test that exercises a context function. A context test should not be the first test that validates a changeset. An E2E test should not be the first test that checks if a JS hook works. When a bug is found, you should be able to point to which layer's tests failed their job.

### 5. TDD going forward

All new code and all code changes are test-first. Existing tests are evaluated against this document and rewritten when they don't fit — but the rewriting happens as we touch that code, not as a bulk migration.

### 6. Tests create their own world

A test that depends on seed data IDs is a test that breaks when seeds change. Tests set up exactly what they need in `setup` and assert against what they created. Seed data provides a realistic baseline (taxonomy tree, place hierarchy, abundances) but tests never reference it by ID.

### 7. Boundary validation is not optional

Every input boundary — changesets, form params, API params, JS hook payloads — must be tested for the boring cases: whitespace, empty strings, nil, missing keys, maximum lengths. These are the bugs that corrupt data silently. They are tedious to write and they catch real production issues.

## Test Tiers

### Tier 1: Unit Tests

**Runs:** Every change. Part of `mix precommit`. TDD builds these.

**Speed:** Seconds.

**Scope:**

- **Context functions** — inputs, outputs, error cases, edge cases. Each context function has at minimum: happy path, expected error, boundary input.
- **Changesets and validations** — every schema's changeset tested for required fields, type coercion, format constraints, whitespace handling, empty-string-vs-nil.
- **Components** — rendered in minimal test harnesses (dedicated test LiveViews, not full page mounts). Props in, HTML out. Event handlers fire and produce correct assigns.
- **JS hooks** — tested in a JS test framework against the hook module directly. Given these data attributes / push events, the hook produces the right DOM mutations / pushes the right events back. No browser, no server.
- **Pure functions** — TDWG mapping, markdown rendering, display range computation, changeset helpers.

**Rules:**

- `async: true` always.
- No seed data ID references.
- No database queries spanning multiple contexts.
- No LiveView page mounts (that's integration).

### Tier 2: Integration Tests

**Runs:** Before calling a change done. After unit tests pass.

**Speed:** Low minutes.

**Scope:**

- **LiveView workflows** — mount page, interact, save, **verify database state**. Not just "flash says success" — query the DB and confirm the data is correct.
- **Cross-context operations** — rename species and verify: aliases updated, search works, taxonomy links intact, gall associations preserved. These test the seams between contexts.
- **LiveView↔JS hook contract** — server pushes event, verify the payload shape matches what the hook expects. Hook pushes event, verify the server handler exists and processes it correctly. This doesn't need a browser — it tests the protocol, not the rendering.
- **Transaction integrity** — operations that span multiple tables produce consistent state. No orphans, no partial writes, no deadlocks.
- **Data invariants on test DB** — after all tests run, verify structural integrity: no orphaned aliases, no broken taxonomy links, no species without genus. Lightweight version of the prod data checks.

**Rules:**

- LiveView tests always verify DB state after mutations, not just UI feedback.
- Cross-context tests document which contexts they span (makes ownership clear).
- Transaction tests explicitly test concurrent access where the production code allows it.

### Tier 3: E2E Browser Tests

**Runs:** Preflight before release. `make preflight`.

**Speed:** Minutes. Acceptable.

**Scope:**

Critical user journeys only — not every page, not every flow:

1. **ID Tool** — select filters, results narrow, click result, arrive at correct gall page with correct data.
2. **Gall detail page** — renders with hosts, range map, sources, images, traits all present and correct.
3. **Admin: create/edit gall workflow** — create gall → add hosts → set range → save → verify on public page.
4. **Admin: edit host workflow** — edit range → WCVP refresh → apply diff → save → verify.
5. **Search → detail** — search, click result, correct page with correct data.

These test the full stack: Elixir, JS hooks, browser rendering, database. They catch the bugs that only manifest when everything is running together.

**Rules:**

- Each test is a complete journey, not a page-load smoke test.
- Tests verify end state (public page shows correct data after admin save).
- Playwright + Firefox, headless default, `E2E_HEADED=1` for debugging.
- Tests create their own data where possible.

### Tier 4: Auxiliary Tests

**Runs:** On relevant changes only, or in CI as a separate job.

**Scope:**

- Mix tasks (WCVP build, restore).
- WCVP Lookup integration tests (real SQL against wcvp_test).
- Request logger.
- Prod data invariants (`make test-prod-data`) — deep check against production copy.

### Tier 5: Post-Deploy Smoke Tests

**Runs:** After every production deploy. Automated.

**Speed:** Seconds. Must be fast — they gate whether a deploy is considered successful.

**Scope:**

Verify the deploy actually worked — the app is up, serving correct responses, and critical paths aren't broken. These are NOT functional tests. They answer: "is the site alive and healthy?"

- Key pages return 200 (home, ID tool, a known gall page, a known host page).
- API endpoints respond with valid JSON.
- Static assets load (CSS, JS bundles).
- Database is reachable (a page that queries data renders correctly).
- Auth redirect works (admin page redirects to Auth0, not 500).

**What does NOT belong here:**

- Business logic verification (that's tiers 1-3).
- Data correctness checks (that's tier 4 prod data invariants).
- Anything that writes to production.

**Rules:**

- Read-only. Never mutate production data.
- Fast-fail. If any smoke test fails, the deploy is suspect.
- Run against the production URL, not a test environment.
- Keep the set small and stable — a flaky smoke test erodes trust in deploys.

## JS Testing

JS is not a second-class citizen. The hooks are complex (RangeMap alone is 800+ lines) and the LiveView↔JS border is where subtle bugs live.

**Unit (Tier 1):** Each hook is tested in isolation using a JS test framework. Mock the MapLibre/PMTiles dependencies where needed (these are external libraries, not our code — stubbing them is correct). Test: event handlers receive correct data, DOM mutations happen, pushEvent calls fire with correct payloads.

**Contract (Tier 2):** The server and client agree on event names and payload shapes. These tests live on the Elixir side — verify that `push_event(socket, "range-update", data)` produces a payload that matches what the JS handler expects. When either side changes, the contract test breaks.

**E2E (Tier 3):** The browser tests exercise JS naturally. The ID tool flow tests the filter hooks. The admin range workflow tests the RangeMap hook. These aren't JS-specific tests — they're journey tests that happen to exercise JS.

## On Mocking and Stubs

**The rule:** If you need a mock, fix the design first.

**Acceptable stubs:**

- `Wcvp.LookupStub` — external database behind a behaviour. The behaviour IS the contract. The stub returns canned data. Tests using the stub run fast and don't need a WCVP database.
- S3 disabled in test config — external service. Tests verify that the right calls are made, not that AWS responds correctly.

**Not acceptable:**

- Mocking Repo or Ecto queries.
- Mocking context functions to test LiveViews.
- Runtime patching (Mox, :meck, etc.) — if you need this, the dependency is wrong.
- Any mock that makes a test pass when the real system would fail.

## Evaluating Existing Tests

Every existing test is evaluated against these criteria:

1. **Does it test behaviour or implementation?** If implementation, rewrite or delete.
2. **Does it depend on seed data IDs?** If yes, refactor to create its own data.
3. **Is it in the right tier?** A context test masquerading as a LiveView test should be moved down. A unit test that hits the database across multiple contexts should be moved up.
4. **Does it verify the right thing?** A LiveView test that checks "flash says success" but not DB state is incomplete.
5. **Does it cover boundaries?** If the function accepts user input and the test only passes clean data, it's missing cases.

Tests that don't meet the standard get fixed when we touch that area of code. We don't do a bulk rewrite — we improve incrementally, guided by TDD on new work.

## What "Done" Looks Like

When this architecture is fully realized:

- Every context function has unit tests covering happy path, error path, and boundary cases.
- Every interactive component has its own test harness with prop/event coverage.
- Every admin form's save operation is verified at the database level.
- Every JS hook has unit tests for its event handlers and DOM mutations.
- The LiveView↔JS contract is tested explicitly — neither side can change the protocol without breaking a test.
- The 5 critical user journeys pass end-to-end in a real browser.
- Data invariants are checked against both the test DB (every run) and prod DB (periodic).
- Post-deploy smoke tests verify every production deploy is healthy.
- A new developer can run `mix precommit` and know, with confidence, that green means the site works.
