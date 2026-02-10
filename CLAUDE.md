## Work Quality Standards

**CRITICAL**: These standards override any instinct to "move fast" or "show quick progress."

### Investigation Before Action

When fixing bugs, issues, or implementing changes:

1. **STOP** - Do not edit any files yet
2. **Investigate fully** - Find ALL related files, not just the obvious one
   - If fixing icons, list ALL icon files in both locations
   - If fixing a bug, trace ALL code paths involved
   - If migrating something, inventory EVERYTHING that needs to move
3. **Use TodoWrite** - Create a task list of everything that needs to happen
4. **Present findings** - Show me what you found and your proposed approach
5. **Wait for approval** - Only proceed after I confirm the approach

### No Partial Fixes

- Never commit a fix until it is COMPLETE
- If you fixed one file but there might be others, STOP and check
- When in doubt, ask: "Is there anything else related to this?"
- If you run into unexpected precommit issues from files you did not change, STOP and ask the user what to do
- One complete commit is better than three partial ones

### TodoWrite is Mandatory

Use TodoWrite for ANY task that:
- Touches more than 1 file
- Involves copying, migrating, or syncing between locations
- Fixes a bug (investigation tasks + fix tasks)
- Has any ambiguity about scope

The task list must be created BEFORE making any but the smallest changes.

### Questions Over Assumptions

If you're unsure about scope, ASK. Examples:
- "I found 3 places this bug could originate - should I investigate all of them?"
- "This fix touches the database - should I also check the related API endpoints?"

### Search Before You Write

**CRITICAL**: The most common agent failure is writing new code for something that already exists.

Before writing ANY new function, component, or query pattern:

1. **Search the codebase** for existing implementations
   - Use Grep/Glob to find similar functions, components, or patterns
   - Check the component files listed in "Reusable UI Components" below
   - Look at how similar features are implemented elsewhere in the project
2. **If similar code exists, reuse it** — call the existing function, use the existing component
3. **If almost-similar code exists, extend it** — add a parameter, not a duplicate
4. **If you must write new code, check for extraction opportunities** — if you're writing something that parallels existing code, extract the common pattern into a shared function first

**Violations that MUST NOT happen:**
- Writing a new helper that duplicates an existing one in another module
- Inlining UI markup when a component exists (see "Reusable UI Components")
- Copy-pasting a function from one module to another with minor tweaks
- Writing raw Ecto queries for patterns that context functions already handle
- Building a one-off solution when a reusable abstraction is obvious

**When in doubt, ask:** "Does something like this already exist in the codebase?"

## Architectural Principles

These principles govern where code belongs. When in doubt, apply these before writing anything.

### 1. LiveViews are routers, not orchestrators

A LiveView's job is to translate user events into context calls and context results into assigns. The moment you're writing `Repo.transaction`, computing set differences, or resolving business rules — you've left the routing layer. Push it down.

### 2. If state has its own lifecycle, it's a LiveComponent

The test: if you can open it, interact with it, and close it without the parent caring about intermediate states, extract it. A modal with its own assigns, events, and open/close/search/submit flow is a complete lifecycle independent of the parent form — that's a component, not "part of the form."

### 3. Duplication across LiveViews means a missing abstraction below them

Two LiveViews doing the same thing is never a "copy it and tweak" situation. The shared logic belongs in one of three places:
- **LiveComponent** — owns UI + state
- **Handler module** — operates on socket, no UI
- **Context function** — no socket at all, pure domain logic

Pick based on whether it needs to render, needs the socket, or is pure domain logic.

### 4. One function sets defaults, callers override

When you have 3+ functions that each set 25 assigns with slight variations, you don't have 3 functions — you have 1 function with 3 sets of overrides. Build a single `build_default_assigns` and let each path override only what's different. Forgotten assigns become impossible.

### 5. Contexts own transactions, not callers

`Repo.transaction` in a LiveView means the UI layer decides what's atomic. That's a domain decision. Wrap the "create X with all its associations" into a single context function that accepts a params map. The LiveView's only job is assembling that map from assigns and handling the `{:ok, _}` / `{:error, _}` result.

### 6. Domain concepts deserve types, not strings

A species name isn't a string — it has internal structure (genus, epithet, qualifier, unknown flag). When a domain concept has structure, model it as a struct/type. Every time someone writes `String.split(name, " ", parts: 2)` they're re-discovering that structure ad-hoc.

Test: if you're parsing the same string format in more than one place, it's an unmodeled type.

### 7. Formatting rules belong to the domain, not the template

"Genus and species italic, family not" is a biological convention — it's domain knowledge. It shouldn't be rediscovered by each template author deciding whether to use `<em>` or `italic`. Domain rules get a single authoritative function; templates call it.

Test: if a new developer would need to know something to format correctly, that knowledge needs to be in code, not convention.

### 8. One concept, one component

If the same visual pattern appears in 20+ files, it should be a component — even if each instance is "just one line." The component isn't about saving keystrokes, it's about making the rule changeable in one place and making violations grep-able. A stray `<em>` is invisible; a missing `<.taxon_name>` is findable.

Test: could a styling rule change (e.g., "sections should no longer be italic") be made in one file? If not, you have a missing component.

### 9. Semantic markup over visual classes

`<em class="taxon-name">` tells you what it is. `<span class="italic">` tells you how it looks today. When someone reads the template, the semantic version communicates intent. When someone greps the codebase, the semantic version finds all taxonomic names. The visual version is invisible among hundreds of other italicized things.

## Fly.io Safety Rules

**Before ANY Fly.io infrastructure operation**, read `runbooks/fly-operations.md` for detailed procedures.

These rules are **non-negotiable** and exist because of a production incident:

- **STOP MEANS STOP** — if the user says "STOP", immediately cease all tool execution. No exceptions.
- **NEVER destroy machines** — causes volume attachment issues and crash loops. Use stop/update/restart.
- **NEVER use `fly machine run`** — bypasses fly.toml config. Always use `fly deploy`.
- **Always check machine state first** — `fly machine list` before SSH/SFTP operations.
- **Always get user approval** before machine stop/start/update operations.
- **Execute ONE step at a time** — verify success before proceeding to the next step.

# Gallformers Project Overview

**Note**: This project uses [bd (beads)](https://github.com/steveyegge/beads) for issue tracking. Use `bd` commands instead of markdown TODOs. See AGENTS.md for workflow details.

## What is Gallformers?

Gallformers (gallformers.org) is a comprehensive online database and reference guide for **galls** - abnormal plant growths caused by insects, mites, and other organisms. The site serves as a resource for:

- **Identification**: Helping users identify galls by their characteristics (shape, color, texture, location on host plant)
- **Taxonomy**: Documenting gall-forming species and their relationships
- **Host Plants**: Cataloging which plants are affected by which gall-formers
- **Education**: Providing guides, keys, and reference materials about galls
- **Research**: Serving as a data repository for researchers and naturalists

## Tech Stack

- **Phoenix 1.8** with LiveView - Full-stack web framework
- **Ecto** with ecto_sqlite3 - Database ORM (see "Ecto & Query Patterns" for usage guidelines)
- **SQLite** - Database
- **Tailwind CSS v4** - Styling
- **Fly.io** - Production hosting

## Project Structure

```
gallformers/
├── assets/              # Frontend assets (JS, CSS, Tailwind)
├── config/              # Phoenix configuration
├── lib/                 # Elixir application code
│   ├── gallformers/     # Business logic (contexts)
│   └── gallformers_web/ # Web layer (LiveViews, controllers)
├── priv/                # Static files, database, migrations
├── test/                # Tests
├── docs/                # Documentation
├── runbooks/            # Operational runbooks
├── services/            # Auxiliary services
│   ├── tileserver-gl/   # Map tile server
│   └── usda_plants/     # USDA plants data (Rust)
├── .beads/              # Beads issue tracking
└── .github/             # CI workflows
```

## Development Commands

```bash
mix setup                  # Install deps, setup DB, build assets
mix phx.server             # Start dev server at http://localhost:4000
mix format                 # Format code
mix credo --strict         # Run code quality checks
mix precommit              # Run all checks before committing

# Database
mix ecto.migrate           # Run migrations
mix ecto.rollback          # Rollback last migration
mix ecto.reset             # Drop, create, migrate, seed

# Assets
mix assets.build           # Build CSS/JS
mix assets.deploy          # Build for production
```

## Before Committing

Always run before committing:

```bash
mix precommit    # Runs format, credo, and tests
make ci          # Full CI check (format, compile, credo, test, assets, dialyzer)
```

Do not commit until precommit passes.

**CRITICAL: Always compile with `--warnings-as-errors`**. When verifying code changes, NEVER use plain `mix compile` - always use `mix compile --warnings-as-errors` or run `mix precommit`. CI enforces warnings-as-errors, so skipping this locally will cause CI failures.

## Testing

### Test Database

Tests use a **separate test database** (`priv/gallformers_test.sqlite`) that is:
- **Schema-only**: Created from `priv/repo/structure.sql` (no production data)
- **Minimal seed data**: Loaded from `priv/repo/test_seeds.sql` with just enough data for tests
- **Rebuilt fresh**: `make test` rebuilds the test DB before each run

```bash
make test-db               # Rebuild test database manually (rarely needed)
```

**Important**: The test database uses `journal_mode: :wal` (write-ahead logging) for better
concurrency. WAL mode allows reads during write transactions, preventing "Database busy" errors
that occurred with DELETE mode.

### Unit & Integration Tests

```bash
make test                  # Rebuild test DB + run tests (excludes E2E)
mix test                   # Run tests without rebuilding DB
mix test test/gallformers  # Run only context tests
mix test path/to/test.exs  # Run specific test file
mix test path/to/test.exs:42  # Run specific test at line 42
```

Tests use Ecto's SQL Sandbox for isolation - each test runs in a transaction that's rolled back.

### S3 Isolation in Tests

Tests must NEVER make real AWS/S3 calls. Use `Gallformers.S3.request/1` instead of `ExAws.request/1`. See CODING_STANDARDS.md for details.

### E2E Tests (Browser-based)

E2E tests use Wallaby with Chrome. Excluded from regular test runs.

```bash
make e2e                   # Run all E2E tests
make e2e-changed           # Run only tests affected by changed files
make e2e-public            # Public pages only
make e2e-admin             # Admin pages only
make e2e-headed            # Run with visible browser
```

See CODING_STANDARDS.md for E2E writing guide, test organization, and setup instructions.

## Database

- **Local dev**: `priv/gallformers.sqlite` (not committed)
- **Production**: Fly.io volume at `/data/gallformers.sqlite`
- **Query patterns**: See "Ecto & Query Patterns" section below

### Getting the Database

```bash
# Download from S3 (recommended - daily snapshot from production)
make download-db
```

### Schema Changes: Use Ecto Migrations

All schema and data changes go through **Ecto migrations** (`mix ecto.gen.migration`).
The `priv/repo/structure.sql` file was a one-time bootstrap from V1 — it is not the
source of truth for ongoing changes. Never edit it directly.

### Table Naming: Use snake_case

Table names use **snake_case** (e.g., `species_source`, `gall_traits`, `host_range`).
**When writing raw SQL in migrations, always check `priv/repo/structure.sql`
or the Ecto schema's `schema "table_name"` declaration for the correct table name.**

## Key Domain Concepts

### Species
The standard scientific concept of a species. 

Each species has:
- **Taxonomy**: family, genus, species name
- **Abundance**: how common it is
- **Range**: geographic distribution
- **Aliases**: alternative names
- **Sources**: references to scientific literature

Both a Gall and a Host are Species.

### Galls
A gall is an abnormal plant growth induced by another organism. Each gall entry includes:
- **Morphology**: shape, color, texture, alignment, walls, cells
- **Location**: where on the host plant (leaf, stem, bud, etc.)
- **Seasonality**: when the gall appears
- **Detachability**: whether it falls off the plant
- **Hosts**: which plants it affects

They are:
- Insects (wasps, midges, aphids, flies, etc.)
- Mites
- Other organisms (fungi, bacteria, nematodes)

### Hosts
Plants that galls form on, with:
- **Taxonomy**: family, genus, species
- **Common names**
- **Geographic range**
- **Associated galls**

### Taxonomy
Standard biological classification:
- Kingdom -> Phylum -> Class -> Order -> Family -> Genus -> Species
- The database tracks only partial taxonomic levels and relationships: 
  - Family
  - Genus
  - Section (optional)
  - Species

## Reusable UI Components

**CRITICAL**: This project has reusable UI components that MUST be used. Do NOT implement custom/inline versions of these components. Creating new UI patterns requires explicit user approval.

### Component Locations

| File | Components |
|------|------------|
| `core_components.ex` | `.button`, `.input`, `.modal`, `.table`, `.icon`, `.flash`, `.header`, `.list`, `.badge`, `.chip`, `.data_complete_badge`, `.record_metadata` |
| `form_components.ex` | `.typeahead`, `.multi_select_typeahead`, `.multi_select_dropdown`, `.multi_select`, `.search_input`, `.field_wrapper`, `.toggle`, `.radio_group`, `.file_dropzone`, `.cascade_delete_modal`, `.reclassify_modal`, `.taxonomy_genus_family_row`, `.genus_disambiguation_modal` |
| `ui_components.ex` | `.card`, `.loading_spinner`, `.error_message`, `.pagination`, `.alert`, `.info_tip`, `.loading_overlay`, `.skeleton`, `.tabs`, `.see_also`, `.glossary_tooltip` |
| `data_display_components.ex` | `.taxon_name`, `.image_gallery`, `.species_card`, `.host_list`, `.source_citation`, `.taxonomy_breadcrumb`, `.data_completeness_indicator`, `.edit_button`, `.external_links`, `.source_list`, `.species_synonymy`, `.abundance_indicator`, `.table_actions`, `.action_button`, `.range_map` |
| `key_components.ex` | Identification key rendering components |
| `tree_components.ex` | Tree navigation components |
| `seo.ex` | SEO/meta tag components |

All component files are in `lib/gallformers_web/components/`.

### Key Components

- **`.typeahead`** - Single-select search with keyboard navigation, ARIA accessibility, and the `Typeahead` JS hook. Use for host/genus pickers.
- **`.multi_select_typeahead`** - Multi-select with chips and dropdown. Use for locations, textures, etc.
- **`.reclassify_modal`** - Combined rename/reclassify modal for changing species name and/or taxonomy.
- **`.taxonomy_genus_family_row`** - Genus/Family row used on both gall and host admin forms.
- **`.taxon_name`** - Renders taxonomic names with correct italicization. Use everywhere a species/genus name is displayed.
- **`.input`** - Standard form inputs with labels and error handling.
- **`.card`** - Consistent card styling with title and icon.

### Before Adding UI Code

1. **Check existing components** - Search `core_components.ex` and `form_components.ex`
2. **Check existing pages** - See how similar UI is implemented elsewhere
3. **If no component exists** - ASK before implementing inline. We may want to create a reusable component.

### Never Do This

```elixir
# WRONG - inline typeahead implementation
<input type="text" phx-keyup="search" ... />
<div :if={@results != []}>
  <button :for={item <- @results} phx-click="select" ...>
```

```elixir
# CORRECT - use the component
<.typeahead
  id="host-picker"
  query={@query}
  results={@results}
  selected={@selected}
  search_event="search"
  select_event="select"
  clear_event="clear"
  ...
/>
```

## Coding Standards & Patterns

See **[CODING_STANDARDS.md](./CODING_STANDARDS.md)** for detailed reference on:
- Ecto query patterns, schema associations, and red flags
- SQLite compatibility (no `ilike`, no `distinct`, WAL footguns)
- PubSub real-time update patterns
- Custom colors and Phosphor icon setup
- Schema field definitions pattern (in progress)
- Request logging and analysis
- E2E test writing guide

**Quick reminders** (details in CODING_STANDARDS.md):
- **SQLite, not PostgreSQL** — no `ilike`, no `DISTINCT ON`, use `fragment("lower(?) LIKE ?", ...)`
- **Phosphor icons** — check `assets/vendor/phosphor/` before downloading new ones
- **Preloads over manual joins** — use schema associations, return structs not maps
- **Count your queries** — know the count before and after any change

## Deployment

Hosted on **Fly.io**. See `runbooks/fly-operations.md` for deploy commands, configuration, and secrets management.

```bash
fly deploy              # Deploy to production
fly status              # Check deployment status
```

**`fly logs` streams forever** — use `fly logs 2>&1 | timeout 5 cat` for a snapshot, or check request log files via SFTP.

## Request Logging

HTTP requests are logged to JSON Lines files. See CODING_STANDARDS.md for log format, jq analysis examples, and configuration.

- **Production**: `/data/logs/requests-YYYY-MM-DD.log`
- **Development**: `priv/logs/requests-YYYY-MM-DD.log`
- **Retrieve**: `fly ssh sftp get /data/logs/requests-YYYY-MM-DD.log`

## Beads Workflow

This project uses **Beads** for issue tracking.

Key points:
- Use `bd ready` to find available work
- Use `bd create` to create new issues (NOT TodoWrite)
- Run `bd sync` before ending sessions
- Follow the session close protocol for git commits

## Git Workflow

**Push approval rules:**
| Change Type | Approval Required | Notes |
|-------------|-------------------|-------|
| Beads | No | Daemon auto-syncs to `beads-sync` branch |
| Everything else | **Yes** | Always ask user before pushing |

**Commit messages:** Present tense, imperative mood.

**CRITICAL: Never amend commits unless the user asks you to.** 

CRITICAL: Never push to main. Only the user can do this.

Do not use `git -C <some-path> <cmd>` If you are unsure, check your directory (almost always it git -C is not needed). If you are not in the correct dir for the git operation, STOP and ask the user what to do. Using 'git -C' commands requires the user to approve every invocation and it is a wasteful time sink.

## Releases

Use the `/release` skill. Before running it, confirm with the user that the full deploy pipeline has completed (push → CI → deploy → production verified). Creating a release before deploy means the release won't match what's running.

## Project Philosophy

The primary value is the **data** — gall records, images, and references. Code serves to make it accessible. Be scientifically conservative (mark uncertain species as "undescribed"), keep the site fast and accessible, and attribute sources properly.

## External Services

- **Domain**: gallformers.org, gallformers.com (Namecheap)
- **Hosting**: Fly.io
- **Images**: AWS S3
- **Auth**: Auth0
- **Monitoring**: Fly.io alerts
- **SSL**: Automatic via Fly.io
- **DNS**: Route53

## AWS Infrastructure

**Region**: `us-east-1` (N. Virginia) - matches Fly.io's `iad` datacenter.

Check the `infra/` dir for OpenTofu defintions if you need to work with the AWS infrastructure.

## Getting Help

- Check README.md for setup issues
- Use `bd doctor` to diagnose Beads issues
- See [runbooks/](runbooks/) for operational procedures
