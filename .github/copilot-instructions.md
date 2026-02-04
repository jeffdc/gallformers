# GitHub Copilot Instructions for Gallformers

## Project Overview

**Gallformers** (gallformers.org) is a comprehensive online database and reference guide for galls - abnormal plant growths caused by insects, mites, and other organisms. The site serves researchers, naturalists, and nature enthusiasts.

**Key Features:**
- Species identification and taxonomy
- Host plant cataloging
- Educational resources and reference articles
- Data repository for research

## Tech Stack

- **Framework**: Phoenix 1.8 with LiveView
- **Database**: SQLite via ecto_sqlite3
- **Styling**: Tailwind CSS v4
- **Auth**: Auth0 (admin features only)
- **Infrastructure**: Fly.io, AWS S3, Litestream
- **Development**: Elixir, Mix, ExUnit, Credo
- **Issue Tracking**: Beads (bd)

## Coding Guidelines

### Code Quality
- Run `mix precommit` before committing (format, credo, tests)
- Use `mix compile --warnings-as-errors` (CI enforces this)
- Follow existing patterns in the codebase
- Keep solutions simple and focused

### Testing
- Write tests for new features
- Use ExUnit with Ecto SQL Sandbox
- Run `make test` before committing
- E2E tests use Wallaby with Chrome

### Git Workflow
- Always commit `.beads/issues.jsonl` with code changes
- Run `bd sync` at end of work sessions
- Follow the session close protocol (see below)

## Issue Tracking with bd

**CRITICAL**: This project uses **bd (beads)** for ALL task tracking. Do NOT create markdown TODO lists.

### Essential Commands

```bash
# Find work
bd ready                          # Unblocked issues
bd list --status open             # All open issues

# Create and manage
bd create --title "Title" --type bug|feature|task --priority 0-4
bd update <id> --status in_progress
bd close <id> --reason "Done"

# Search
bd show <id>

# Sync (CRITICAL at end of session!)
bd sync  # Force immediate export/commit/push
```

### Workflow

1. **Check ready work**: `bd ready`
2. **Claim task**: `bd update <id> --status in_progress`
3. **Work on it**: Implement, test, document
4. **Discover new work?** `bd create --title "Found bug" --priority 1`
5. **Complete**: `bd close <id> --reason "Done"`
6. **Sync**: `bd sync` (flushes changes to git immediately)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

## Project Structure

```
gallformers/
├── lib/                     # Elixir application code
│   ├── gallformers/        # Business logic (contexts)
│   └── gallformers_web/    # Web layer (LiveViews, controllers)
├── assets/                  # Frontend assets (JS, CSS, Tailwind)
├── config/                  # Phoenix configuration
├── priv/                    # Static files, database, migrations
├── test/                    # Tests
├── docs/                    # Documentation
├── runbooks/               # Operational runbooks
├── services/               # Auxiliary services (tileserver, usda_plants)
├── .beads/                 # Beads issue tracking
└── .github/                # CI workflows
```

## Key Domain Concepts

### Galls
Abnormal plant growths with properties:
- Morphology (shape, color, texture, alignment, walls, cells)
- Location (leaf, stem, bud, etc.)
- Seasonality, detachability
- Host associations

### Species
Gall-forming organisms (insects, mites, etc.) with:
- Taxonomy (family, genus, species)
- Abundance, range, aliases
- Scientific references

### Hosts
Plants that galls form on with:
- Taxonomy
- Common names
- Geographic range
- Associated galls

### Database Schema
See `lib/gallformers/` for Ecto schemas. Key modules:
- `Gallformers.Taxa` - Species, galls, hosts, taxonomy
- `Gallformers.Sources` - Scientific references
- `Gallformers.Content` - Glossary, reference articles
- `Gallformers.Places` - Geographic locations

## Common Development Tasks

### Finding Code
- Contexts: `lib/gallformers/`
- LiveViews: `lib/gallformers_web/live/`
- Components: `lib/gallformers_web/components/`
- Controllers: `lib/gallformers_web/controllers/`

### Adding a Page
1. Create LiveView in `lib/gallformers_web/live/`
2. Add route in `lib/gallformers_web/router.ex`
3. Use existing components from `core_components.ex`

### Database Migrations
1. Run `mix ecto.gen.migration migration_name`
2. Edit the generated migration file
3. Run `mix ecto.migrate`
4. Update `priv/repo/structure.sql` if needed

## Session Close Protocol

**CRITICAL**: Before saying "done" or "complete", you MUST:

```
[ ] 1. git status              (check what changed)
[ ] 2. git add <files>         (stage code changes)
[ ] 3. bd sync                 (commit beads changes)
[ ] 4. git commit -m "..."     (commit code)
[ ] 5. bd sync                 (commit any new beads changes)
[ ] 6. git push                (push to remote)
```

**NEVER skip this.** Work is not done until pushed.

## CLI Help

Run `bd <command> --help` to see all available flags for any command.

## Important Rules

- Use bd for ALL task tracking
- Run `mix precommit` before committing
- Test before committing
- Commit `.beads/issues.jsonl` with code changes
- Do NOT create markdown TODO lists
- Do NOT commit `.beads/beads.db`
- Do NOT skip the session close protocol
- Do NOT create new files unless necessary (prefer editing existing)

---

**For detailed workflows and advanced features, see [CLAUDE.md](../CLAUDE.md)**
