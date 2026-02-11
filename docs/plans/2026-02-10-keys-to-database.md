# Move Identification Keys from Compile-Time JSON to Database

## Context

Keys are currently loaded from JSON files in `priv/keys/` at compile time via module attributes in `Gallformers.Keys`. This means adding or editing a key requires a code change and redeploy. We want admins to be able to upload key JSON files through the admin UI, with the keys stored in the database and served at runtime.

## Approach

Follow the Articles pattern: a `keys` table with metadata columns + a `couplets` JSON text column, a context module, an Ecto schema with a custom type for couplets, and an admin CRUD UI using `FormHelpers`.

---

## Step 1: Migration — Create `keys` table

Generate with `mix ecto.gen.migration create_keys`.

```sql
CREATE TABLE keys (
  id INTEGER PRIMARY KEY NOT NULL,
  slug TEXT NOT NULL,
  title TEXT NOT NULL,
  subtitle TEXT,
  authors TEXT,           -- JSON array, like articles.tags
  citation TEXT,
  citation_url TEXT,
  description TEXT,
  version TEXT NOT NULL,
  couplets TEXT NOT NULL,  -- JSON object, the full couplet tree
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX keys_slug_index ON keys(slug);
```

**Files:** `priv/repo/migrations/TIMESTAMP_create_keys.exs`

## Step 2: Schema — `Gallformers.Keys.Key`

New file at `lib/gallformers/keys/key.ex`. Pattern follows `Article`:

- `slug` — auto-generated from title (same pattern as articles)
- `authors` — reuse `Gallformers.Articles.TagsType` (it's a generic JSON string-array type, rename consideration below)
- `couplets` — new custom Ecto type `Gallformers.Keys.CoupletsType` that serializes the couplet map to/from JSON. On `cast`, validate the structure (couplet "1" exists, each lead has text + destination, destinations reference valid couplet numbers, etc.)
- Implement `@behaviour Gallformers.SchemaFields`

**Files:** `lib/gallformers/keys/key.ex`, `lib/gallformers/keys/couplets_type.ex`

## Step 3: Context — Rewrite `Gallformers.Keys`

Replace the compile-time `@keys` module attribute with runtime database queries. The public API stays the same:

- `list_keys/0` → `Repo.all(Key)` with `select` to exclude couplets
- `get_key/1` → `Repo.get_by(Key, slug: slug)`, return `{:ok, key}` or `{:error, :not_found}`
- `couplet_numbers/1` → unchanged (operates on the key struct)
- Add CRUD: `create_key/1`, `update_key/2`, `delete_key/1`, `change_key/2`
- Add `get_key!/1` (by id, for admin)
- Remove `@external_resource`, `@keys`, `@key_files`, and the `Parser` module

The `Parser` module logic moves into `CoupletsType.cast/1` — parsing happens on the way into the changeset rather than at compile time.

**Files:** `lib/gallformers/keys.ex` (rewrite)

## Step 4: Seed existing keys into the database

Create a seed/migration task that reads the 4 JSON files from `priv/keys/`, inserts them into the `keys` table, then the JSON files become reference copies (or can be removed).

Approach: a data migration inside the Ecto migration itself (similar to how `mix_tasks/migrate_articles.ex` works). Read each JSON file, insert via `Repo.insert!`. This ensures keys exist after `mix ecto.migrate`.

**Files:** Inside the migration from Step 1, or a separate `mix gallformers.seed_keys` task

## Step 5: Admin UI — Key form with JSON upload

Follow the Glossary form pattern (`FormHelpers` with `crud_helpers: true`).

**Index page** (`lib/gallformers_web/live/admin/key_live/index.ex`):
- List all keys with title, slug, version, couplet count
- New key button

**Form page** (`lib/gallformers_web/live/admin/key_live/form.ex`):
- Metadata fields: title, subtitle, authors (tag-style input), citation, citation_url, description, version
- JSON input: file dropzone (`.file_dropzone` component) + JSON textarea below it
- On file upload: read file contents, populate the textarea, auto-fill metadata fields from parsed JSON
- Admin can also paste/edit JSON directly in the textarea without uploading
- On textarea change: parse JSON, auto-populate metadata fields (title, subtitle, etc.), show couplet count
- Validation: run `CoupletsType.cast/1` which validates structure, show errors inline
- Metadata fields are pre-filled from JSON but can be overridden manually

**Routes** (add to admin scope in router):
```elixir
live "/keys", Admin.KeyLive.Index, :index
live "/keys/new", Admin.KeyLive.Form, :new
live "/keys/:id", Admin.KeyLive.Form, :edit
```

**Files:**
- `lib/gallformers_web/live/admin/key_live/index.ex`
- `lib/gallformers_web/live/admin/key_live/form.ex`
- `lib/gallformers_web/router.ex` (add routes)

## Step 6: Update public KeyLive and KeysLive

Minimal changes — the public LiveViews already call `Keys.get_key/1` and `Keys.list_keys/0`. Since the API stays the same, the main change is that the returned data is now an Ecto struct instead of a plain map. The struct has the same fields so template access (`key.title`, `key.couplets`, etc.) works unchanged.

One difference: couplets are currently stored as maps with atom keys after parsing. With the DB approach, `CoupletsType.load/1` should produce the same atom-keyed structure so the components don't need changes.

**Files:** `lib/gallformers_web/live/key_live.ex`, `lib/gallformers_web/live/keys_live.ex` (verify, likely no changes needed)

## Step 7: Cleanup

- Remove JSON files from `priv/keys/` (keep `priv/keys/schemas/key-schema.json` as documentation)
- Remove `@external_resource` and compile-time loading from `keys.ex`
- Add admin nav link for keys management

## Step 8: Tests

- Context tests: CRUD operations, slug generation, couplet validation
- Seed the test database with at least one key via `test_seeds.sql` or test fixtures
- Admin LiveView tests: index lists keys, form creates/edits/deletes
- Verify existing `KeysLiveTest` and `KeyLiveTest` still pass (public pages)

---

## Key Design Decisions

**CoupletsType validation** — On `cast`, validate:
1. Couplets is a map with string-integer keys
2. Couplet "1" exists (entry point)
3. Each couplet has a `leads` array with ≥ 2 items
4. Each lead has `text` (string), `images` (list), `destination` (map)
5. Each destination has valid `type` ("couplet" or "taxon")
6. Couplet destinations reference existing couplet numbers (no dangling refs)

**Authors field** — Reuse `TagsType` (rename to a more generic name is optional, low priority).

**Form approach** — File upload dropzone that populates a JSON textarea for review/editing before save. Admin can also paste JSON directly into the textarea without uploading. On valid JSON, auto-populate the metadata fields (title, subtitle, etc.) from the JSON content so admins don't have to fill them separately.

---

## Files Changed (Summary)

| File | Action |
|------|--------|
| `priv/repo/migrations/TIMESTAMP_create_keys.exs` | New |
| `lib/gallformers/keys/key.ex` | New |
| `lib/gallformers/keys/couplets_type.ex` | New |
| `lib/gallformers/keys.ex` | Rewrite |
| `lib/gallformers_web/live/admin/key_live/index.ex` | New |
| `lib/gallformers_web/live/admin/key_live/form.ex` | New |
| `lib/gallformers_web/router.ex` | Add admin routes |
| `lib/gallformers_web/live/key_live.ex` | Verify (likely no changes) |
| `lib/gallformers_web/live/keys_live.ex` | Verify (likely no changes) |
| `test/gallformers/keys_test.exs` | New |
| `test/gallformers_web/live/admin/key_live_test.exs` | New |
| `priv/keys/*.json` | Remove after migration seeds data |

## Verification

1. `mix ecto.migrate` creates the table and seeds the 4 existing keys
2. `mix phx.server` — visit `/keys`, verify all 4 keys appear and work interactively
3. Visit `/admin/keys` — verify index shows all keys
4. Create a new key via admin form (paste JSON) — verify it appears on public `/keys`
5. Edit an existing key — verify changes reflected
6. Delete a key — verify removed from index
7. `mix precommit` passes
