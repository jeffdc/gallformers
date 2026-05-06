**CRITICAL**: 
- Investigation Before Action
- Search Before You Write
- The most common agent failure is writing new code for something that already exists. Do not do this.
- Do not commit until precommit passes.
- Always compile with `--warnings-as-errors`**. When verifying code changes, NEVER use plain `mix compile` - always use `mix compile --warnings-as-errors` or run `mix precommit`. CI enforces warnings-as-errors, so skipping this locally will cause CI failures.

### Test Database

Tests use a **separate PostgreSQL test database** (`gallformers_test`) that is:
- **Schema-only**: Created via Ecto migrations (no production data)
- **Minimal seed data**: Loaded from `priv/repo/test_seeds.sql` with just enough data for tests
- **Rebuilt fresh**: `make test` rebuilds the test DB before each run

```bash
make test-db               # Rebuild test database manually (rarely needed)
```

## Reusable UI Components

**CRITICAL**: This project has reusable UI components that MUST be used. Do NOT implement custom/inline versions of these components. Creating new UI patterns requires explicit user approval.

All component files are in `lib/gallformers_web/components/`.

### Before Adding UI Code

1. **Check existing components** - Search `core_components.ex` and `form_components.ex`
2. **Check existing pages** - See how similar UI is implemented elsewhere
3. **If no component exists** - ASK before implementing inline. We may want to create a reusable component.

See **[CODING_STANDARDS.md](./CODING_STANDARDS.md)** for details as needed.

## Work Tracking & Planning

### Mull is the single source of truth

All work tracking — ideas, plans, research, status — lives in **mull matters**. There are no separate plan documents committed to git.

- `mull add "title" --epic <name>` to capture new work
- `mull append <id> - <<'EOF'` to add body text (always pipe via stdin, never use inline text args)
- `mull append <id> - --replace` to rewrite a matter's body (pipe via stdin)
- `mull done <id>` when work is complete
- `mull rm <id>` to permanently delete (done matters are purged periodically; git history preserves them)

### No plan files in git

The `docs/plans/` directory is gitignored. Some skills may write files there as working drafts during a session — that's fine, but those files are ephemeral scratch paper. **The plan content must be captured in the mull matter before the session ends.**

After a planning or brainstorming session:
1. Distill key decisions, architecture choices, and remaining work into the matter body
2. The matter should be self-contained — a future session should be able to pick up the work from the matter alone
3. Don't copy plans verbatim. Summarize decisions and rationale. Drop implementation checklists that will be recreated when work begins.

### What goes where

| Content | Location | Persisted? |
|---------|----------|------------|
| Work tracking, plans, status | Mull matter body | Yes (until purged) |
| Ephemeral planning drafts | `docs/plans/` (gitignored) | No |
| Incident docs | `docs/investigations/` | Yes |
| Operational procedures | `runbooks/` | Yes |

### Planning workflow

When planning work for a matter:
1. Load the matter with `mull show <id>` to get context
2. Do research, brainstorm, design — use whatever tools help
3. Write findings and decisions into the matter via `mull append`
4. When the plan is solid, mark the matter as `planned` with `mull plan <id>`

Check the `infra/` dir for OpenTofu defintions if you need to work with the AWS infrastructure.

## Getting Help

- Check README.md for setup issues
- See [runbooks/](runbooks/) for operational procedures
