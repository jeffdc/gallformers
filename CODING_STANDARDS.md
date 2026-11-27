# Elixir/Phoenix Coding Standards

These standards apply to Elixir/Phoenix projects. LLM agents and human contributors must follow these conventions.

## Tooling is Authoritative

The following tools define and enforce our coding standards:

| Tool | Command | Purpose |
|------|---------|---------|
| **mix format** | `mix format` | Code formatting (line length, spacing, indentation) |
| **Credo** | `mix credo --strict` | Code quality, consistency, readability |
| **Dialyzer** | `mix dialyzer` | Type checking via typespecs |

**Rules:**
- Run `mix precommit` before committing. It checks formatting, compiles with `--warnings-as-errors`, runs `mix credo --strict`, the JS tests and `mix test`; it does **not** run Dialyzer.
- Work is finished only when `make done-checks` passes: it rebuilds the test database, then runs `scripts/check-toolchain`, `mix precommit` and `mix dialyzer`. CI runs the same checks.
- All code must pass `mix credo --strict` with no errors and `mix dialyzer` with no warnings
- Treat warnings as errors during compilation (`--warnings-as-errors`)

The commit itself also needs a passing fresh-context review: see AGENTS.md, "Before you commit". Every check, where it runs and what it enforces is listed in [docs/architecture/rules.md](docs/architecture/rules.md#checks-that-exist), "Checks that exist".

**Line length:** The formatter targets 98 characters (default). Credo allows up to 120 characters but flags longer lines as low-priority warnings. Aim for 98; occasional lines up to 120 are acceptable.

If a tool enforces a rule, that rule is not documented here. If you're unsure about formatting or style, run the tools and follow their output.

---

## Module Structure

Organize modules in this order:

```elixir
defmodule MyApp.Context.Entity do
  @moduledoc """
  Brief description of what this module does.
  """

  # 1. use/import/alias/require (in this order)
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Context.{OtherEntity, AnotherEntity}

  # 2. Module attributes
  @primary_key {:id, :integer, autogenerate: false}
  @topic "entity"

  # 3. Schema (if applicable)
  schema "entities" do
    field :name, :string
    belongs_to :parent, Parent
  end

  # 4. Public functions with @doc and @spec
  @doc """
  Returns all entities.
  """
  @spec list_entities() :: [Entity.t()]
  def list_entities do
    Repo.all(Entity)
  end

  # 5. Private functions
  defp helper_function(arg) do
    # ...
  end
end
```

---

## Documentation

### Module Documentation

Public API modules (contexts, controllers, LiveViews) should have a `@moduledoc`:

```elixir
@moduledoc """
Taxa: taxa at every rank, their names, rank and placement in the
editorial tree, the ancestry read model, and name resolution for import.
"""
```

For internal/infrastructure modules (Application, Repo, generated code), use `@moduledoc false`.

For schema modules, briefly describe what the entity represents.

This is a convention, not a check: Credo's `ModuleDoc` check is disabled (`.credo.exs`).

### Function Documentation

Public functions must have `@doc` and `@spec`:

```elixir
@doc """
Fetches a taxon by ID, with its names.

Returns `nil` if not found.
"""
@spec get_taxon(integer()) :: Taxon.t() | nil
def get_taxon(id), do: Taxon |> Repo.get(id) |> Repo.preload(names: names_order())
```

Private functions do not need `@doc` or `@spec` unless complex. No check enforces `@spec` on public functions (Credo's `Specs` check is not enabled); Dialyzer checks the specs that exist.

### Typespecs

Use typespecs for:
- All public function arguments and return values
- Custom types that improve readability
- Structs (define `t()` type)

```elixir
@type t :: %__MODULE__{
  id: integer() | nil,
  rank: Rank.t() | nil,
  kingdom: String.t() | nil,                               # Nullable in DB
  parent: t() | Ecto.Association.NotLoaded.t() | nil,      # Association
  names: [TaxonName.t()] | Ecto.Association.NotLoaded.t(),
  inserted_at: DateTime.t() | nil
}
```

Use `| nil` for fields that can be null in the database, and `Ecto.Association.NotLoaded.t()` for associations that may not be loaded.

---

## Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Modules | PascalCase | `GallformersWeb.GallLive` |
| Functions | snake_case | `get_by_legacy_id/2` |
| Variables | snake_case | `taxon_names` |
| Atoms | snake_case | `:glossary_created` |
| Files | snake_case | `gall_live.ex` |
| LiveView modules | `*Live` suffix | `GallLive`, `Admin.GlossaryLive.Index` |
| Context modules | Named for the domain: a plural noun for a collection, or the activity | `Taxa`, `Glossaries`, `Accounts`; `Catalog`, `Import`, `Audit`, `Curation` |
| Schema modules | Singular noun | `Taxa.Taxon`, `Catalog.Gall` |
| Tables | snake_case, the name in the schema's `schema "…"` call; use it as-is in raw SQL (migrations included) | `taxon_names` (`Taxa.TaxonName`), `glossary` (`Glossaries.Glossary`) |

---

## Code Organization

### Phoenix Contexts

Organize business logic into contexts (domain modules):

```
lib/gallformers/
├── taxa.ex            # Taxa context (public API)
├── taxa/
│   ├── taxon.ex       # Taxon schema
│   └── taxon_name.ex  # TaxonName schema
├── catalog.ex         # Catalog context
└── catalog/
    └── gall.ex        # Gall schema
```

**Context modules** expose the public API. **Schema modules** define data structures. The contexts on this branch, and the tables each owns, are in [docs/architecture/README.md](docs/architecture/README.md).

### Keep Related Code Together

- One module per file
- Files mirror module namespace (`Gallformers.Taxa.Taxon` → `lib/gallformers/taxa/taxon.ex`)
- Tests mirror source structure (`lib/gallformers/glossaries.ex` → `test/gallformers/glossaries_test.exs`)

---

## Ecto Patterns

### Queries

Use Ecto's query syntax, not raw SQL:

```elixir
def list_children(parent_id) do
  from(t in Taxon,
    join: n in assoc(t, :names),
    where: t.parent_id == ^parent_id and n.status == :accepted,
    order_by: [asc: n.name],
    preload: [:names]
  )
  |> Repo.all()
end
```

### Changesets

Define changesets in schema modules:

```elixir
def editorial_changeset(taxon, attrs) do
  taxon
  |> cast(attrs, [:datacomplete, :abundance_id])
  |> validate_required([:datacomplete])
  |> foreign_key_constraint(:abundance_id)
end
```

**Never** put user-input fields and programmatic fields in the same `cast/3`:

```elixir
# User input
|> cast(attrs, [:datacomplete, :abundance_id])
# Then set programmatic fields explicitly
|> put_change(:origin, :curated)
```

### Preloading

Always preload associations that will be accessed:

```elixir
# In context
taxon = Repo.get(Taxon, id) |> Repo.preload([:names, :parent])

# Or in query
from(t in Taxon, preload: [:names, :common_names])
```

### Avoiding N+1 Queries

N+1 occurs when you query a list, then query each item's association separately:

```elixir
# BAD - N+1 (1 query for the taxa, N queries for their names)
taxa = Repo.all(Taxon)
Enum.map(taxa, fn t -> Repo.preload(t, :names) end)

# GOOD - Preload in the original query (or Repo.preload/2 on the whole list)
taxa = Repo.all(from t in Taxon, preload: [:names])
```

An association that wasn't preloaded is `%Ecto.Association.NotLoaded{}`, not a lazy query: reading it gives the wrong value rather than a slow page.

**Detection:** Ecto logs every query at `:debug`, which dev shows; repeated queries for one page are the sign.

### Query Performance

- Use `select` to fetch only needed fields for large result sets
- Add database indexes for frequently filtered/joined columns
- Use `Repo.stream/1` for processing large datasets without loading all into memory

---

## LiveView Patterns

### Streams for Collections

**Target, not built:** no page uses streams yet; lists are assigned whole. New list pages should use streams to avoid holding the collection in memory:

```elixir
def mount(_params, _session, socket) do
  {:ok, stream(socket, :glossary, Glossaries.list_glossary())}
end
```

```heex
<div id="glossary-list" phx-update="stream">
  <div :for={{id, entry} <- @streams.glossary} id={id}>
    {entry.word}
  </div>
</div>
```

### Forms

Always use `to_form/2` and the `<.input>` component:

```elixir
def mount(_params, _session, socket) do
  changeset = Glossaries.change_glossary(%Glossary{})
  {:ok, assign(socket, form: to_form(changeset))}
end
```

```heex
<.form for={@form} id="glossary-form" phx-change="validate" phx-submit="save">
  <.input field={@form[:word]} type="text" label="Word" />
  <.button>Save</.button>
</.form>
```

### LiveComponents with Interactive State Must Not Be Inside Forms

**Never** nest a LiveComponent that manages its own checkbox/input state inside a `<.form phx-change="validate">`. The form's change event fires on every input mutation inside it — including inputs owned by the component. LiveView's form recovery then resets those inputs to their server-rendered defaults, clobbering the component's local state.

If you must place such a component visually within a form's layout, today's workaround (`taxonomy_live/range_editor.ex:588`) wraps it in a div that stops event propagation:

```heex
<div onchange="event.stopPropagation()" oninput="event.stopPropagation()">
  <.live_component module={MyStatefulComponent} id="my-component" ... />
</div>
```

**Known conflict:** those inline `on*=` handlers will be blocked once the nonce Content-Security-Policy is enforced (the backlog's CSP entry, [docs/backlog.md](docs/backlog.md)). This is what's built, not the target; prefer keeping the component outside the form.

**Symptoms:** checkboxes snap back on click, "one step behind" toggle behavior, phantom `validate` events with `"_target" => ["undefined"]` in server logs.

### Function Components vs LiveComponents

**Function components** (default choice) are simple, stateless, and render as part of the parent:

```elixir
# In a components module (see docs/design-system/components.md before adding one)
attr :name, :string, required: true
def greeting(assigns) do
  ~H"""
  <span>Hello, {@name}!</span>
  """
end
```

**LiveComponents** have their own state and event handling. Only use when you need:
- Independent state that shouldn't re-render with parent
- Isolated event handling (`handle_event` in the component)
- Performance isolation for expensive renders

```elixir
defmodule MyAppWeb.CounterComponent do
  use Phoenix.LiveComponent

  def mount(socket), do: {:ok, assign(socket, count: 0)}

  def handle_event("inc", _, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def render(assigns) do
    ~H"""
    <button phx-click="inc" phx-target={@myself}>{@count}</button>
    """
  end
end
```

**Rule of thumb:** Start with function components. Convert to LiveComponent only when you hit a specific limitation.

### JavaScript Interop

When using `phx-hook`, follow these rules:

```heex
<%!-- Hook that manages its own DOM must use phx-update="ignore" --%>
<div id="range-map" phx-hook="RangeMap" phx-update="ignore"></div>

<%!-- Always provide a unique DOM id with phx-hook --%>
<input id="host-search" phx-hook="Typeahead" />
```

**Hooks** live one per file in `assets/js/hooks/<name>.js`, with a Vitest test beside it (`<name>.test.js`), and are imported and registered in `assets/js/app.js`:

```javascript
// assets/js/hooks/range_map.js
export default {
  mounted() {
    // set up the map on this.el
  },
  updated() {
    // react to new data
  },
  destroyed() {
    // tear down
  }
}

// assets/js/app.js
import RangeMap from "./hooks/range_map"
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { RangeMap, ... }
})
```

- Never write raw `<script>` tags - use a hook. The one exception is the theme-init script in `root.html.heex`, which carries the CSP nonce and must run before first paint (rules.md X3, accepted by Jeff 2026-11-26).
- Colocated hooks (`Phoenix.LiveView.ColocatedHook`, names starting with `.`) are supported by Phoenix 1.8, but none are used here; follow the `assets/js/hooks/` pattern.

---

## Error Handling

### Pattern Match Results

Handle success and error cases explicitly:

```elixir
case Glossaries.create_glossary(attrs) do
  {:ok, _entry} ->
    {:noreply,
     socket
     |> put_flash(:info, "Glossary entry created")
     |> push_navigate(to: ~p"/admin/glossary")}

  {:error, changeset} ->
    {:noreply, assign(socket, form: to_form(changeset))}
end
```

### Use `with` for Multi-Step Operations

Use `with` when chaining 2+ operations that can fail. For single checks, prefer `case`.

```elixir
with %Glossary{} = entry <- Glossaries.get_glossary(id),
     {:ok, updated} <- Glossaries.update_glossary(entry, attrs) do
  {:ok, updated}
else
  nil -> {:error, :not_found}
  {:error, reason} -> {:error, reason}
end
```

**Note**: Match on actual return types. `Repo.get/2` returns `struct | nil`, not `{:ok, struct}`.

---

## Testing

How tests are organised, the tiers, LiveView tests and what a good test verifies are in [docs/testing-philosophy.md](docs/testing-philosophy.md). Browser (E2E) tests: [docs/testing-philosophy.md](docs/testing-philosophy.md#e2e).

### Fixtures

Fixture modules live in `test/support/` as `*_fixtures.ex` (`Gallformers.TaxaFixtures`, `Gallformers.CatalogFixtures`, `Gallformers.ImportFixtures`, …), one per context, and are imported by each test file that needs them; `DataCase` and `ConnCase` don't import them. They write through the context's public functions, audited as `Gallformers.DataCase.test_actor/0`:

```elixir
defmodule Gallformers.TaxaFixtures do
  import Gallformers.DataCase, only: [test_actor: 0]

  alias Gallformers.Taxa

  def taxon_fixture(attrs \\ %{}) do
    defaults = %{
      rank: :species,
      origin: :curated,
      name: "Taxon #{System.unique_integer([:positive])}"
    }

    {:ok, taxon} = Taxa.create_taxon(test_actor(), Map.merge(defaults, Map.new(attrs)))
    taxon
  end
end
```

Import in tests: `import Gallformers.TaxaFixtures`

`test/support/fixtures/` holds data files (the WCVP CSV samples, iNaturalist JSON) and the catalog migration's curated decisions (`test/support/fixtures/catalog_migration/`), not fixture modules.

### Assertions

- Use `assert` and `refute`, not `assert x == true`
- Test behavior, not implementation
- Use fixtures for test data (the `*_fixtures.ex` modules above)
- Reference elements by ID: `has_element?(view, "#my-element")`

---

## Logging

Use the `Logger` module with appropriate levels:

```elixir
require Logger

Logger.debug("Query executed", sql: query, params: params)  # Development details
Logger.info("User signed in", user_id: user.id)             # Significant events
Logger.warning("Rate limit approaching", count: count)      # Unexpected but recoverable
Logger.error("Payment failed", error: reason, order_id: id) # Failures requiring attention
```

**Guidelines:**
- Use structured metadata (keyword lists) over string interpolation
- Never log PII (emails, passwords, tokens, full names)
- Use `debug` for high-volume or detailed tracing
- Use `info` for business events (user actions, state changes)
- Use `warning` for recoverable issues
- Use `error` for failures that need investigation

---

## OTP Patterns

For background work, prefer the simplest tool that fits:

| Need | Use | Example |
|------|-----|---------|
| Durable, retryable, or scheduled background work | `Oban` | Analytics rollups (`Analytics.RollupWorker`), imports (`Import.Worker`), the Gall index (`Catalog.ReadModels.GallIndexWorker`) |
| One-off async work | `Task.async/1` or `Task.Supervisor` | Sending emails |
| Periodic in-memory work | `Process.send_after/3` in GenServer | Cache expiration |
| Stateful process | `GenServer` | Connection pool, rate limiter |
| Simple state | `Agent` | Counters, simple caches |

Image variants are not on Oban: they run in an unsupervised `Task.start` (`Gallformers.Async.run/1`), a known violation of [rules.md](docs/architecture/rules.md) D3, not an example to follow.

**Oban basics:**

```elixir
defmodule MyApp.Workers.Example do
  use Oban.Worker, queue: :default, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    MyApp.do_work(args)
    :ok
  end
end
```

**Oban notes:**
- Prefer Oban for anything that must survive deploys or node restarts
- Keep workers thin; put domain logic in regular modules that can be tested directly
- Use cron via `Oban.Plugins.Cron` for scheduled jobs, not ad hoc GenServer timers
- Monitor queues and failed jobs via `/admin/jobs`

**GenServer basics:**

```elixir
defmodule MyApp.Counter do
  use GenServer

  # Client API
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def increment, do: GenServer.call(__MODULE__, :increment)

  # Server callbacks
  @impl true
  def init(_opts), do: {:ok, 0}

  @impl true
  def handle_call(:increment, _from, count), do: {:reply, count + 1, count + 1}
end
```

**Notes:**
- Always add GenServers to a supervision tree
- Use `@impl true` for callback functions
- Prefer named processes (`name: __MODULE__`) for singletons
- See [Elixir GenServer docs](https://hexdocs.pm/elixir/GenServer.html) for advanced patterns

---

## Security

Phoenix provides strong defaults. Don't disable them without understanding the risks.

### CSRF Protection

Phoenix forms include CSRF tokens automatically. Never:
- Disable `Plug.CSRFProtection` in router
- Use `raw` to bypass token insertion
- Accept form data without `phx-submit` or standard form POST

### Input Handling

```elixir
# SAFE - Ecto parameterizes values
from(n in TaxonName, where: n.name == ^user_input)

# DANGEROUS - SQL injection risk
from(n in TaxonName, where: fragment("name = '#{user_input}'"))

# SAFE - Use parameterized queries
from(n in TaxonName, where: ilike(n.name, ^pattern))
```

### HTML Output

```heex
<%!-- SAFE - Phoenix escapes by default --%>
<p>{@user_comment}</p>

<%!-- DANGEROUS - Only use for trusted HTML (admin-generated markdown, etc.) --%>
<p>{raw(@trusted_html)}</p>
```

### Atom Creation

```elixir
# DANGEROUS - Atoms are never garbage collected
String.to_atom(user_input)

# SAFE - Only creates existing atoms
String.to_existing_atom(user_input)
```

---

## Configuration

Phoenix uses multiple config files for different purposes:

| File | When Evaluated | Use For |
|------|----------------|---------|
| `config/config.exs` | Compile time | Shared settings, imported by all envs |
| `config/dev.exs` | Compile time | Dev-only settings (debug, local URLs) |
| `config/test.exs` | Compile time | Test settings (async, test DB) |
| `config/prod.exs` | Compile time | Production defaults (not secrets) |
| `config/runtime.exs` | Runtime | **Secrets**, env vars, dynamic config |

**Key rules:**
- Secrets (API keys, `SECRET_KEY_BASE`, DB credentials) go in `runtime.exs`
- Never commit secrets to `prod.exs`
- Use `System.get_env/1` only in `runtime.exs`

```elixir
# config/runtime.exs
if config_env() == :prod do
  config :my_app, MyApp.Repo,
    url: System.get_env("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end
```

---

## Phoenix 1.8 Patterns

Phoenix 1.8 introduced several conventions. Follow these patterns for consistency.

### Layout Wrapping

LiveView templates begin with a shell: `<Layouts.app>` for public pages, `<Layouts.admin>` for admin pages:

```heex
<Layouts.app flash={@flash}>
  <!-- page content -->
</Layouts.app>

<Layouts.admin flash={@flash} current_user={@current_user}>
  <!-- admin page content -->
</Layouts.admin>
```

`GallformersWeb.Layouts` is aliased for every LiveView and component in `lib/gallformers_web.ex`, so no explicit alias is needed. What each shell contains and its attributes: `site_shell` and `admin_shell` in [docs/design-system/components.md](docs/design-system/components.md#shell).

### Flash Messages

The `<.flash_group>` component lives in `layouts.ex` and renders automatically. **Never** call `<.flash_group>` directly in LiveView templates - it's handled by the layout.

### Icons (Phosphor)

This project uses [Phosphor Icons](https://phosphoricons.com/) with the `ph-` prefix, and its own domain icons with the `gf-` prefix, via the `<.icon>` component:

```heex
<.icon name="ph-detective" class="size-5" />
<.icon name="ph-trash" class="size-4 text-danger" />
```

When to use an icon, its size and color: [docs/design-system/foundations.md](docs/design-system/foundations.md#icons).

**When using a new icon that hasn't been used before:**

1. Download the SVG from Phosphor's GitHub:
   ```bash
   curl -o assets/vendor/phosphor/detective.svg \
     https://raw.githubusercontent.com/phosphor-icons/core/main/assets/regular/detective.svg
   ```
2. Rebuild assets: `mix assets.build`
3. Restart the Phoenix server (hot reload doesn't pick up new icons)

**Existing icons** are in `assets/vendor/phosphor/`. Check there before downloading.

**Never** use inline SVGs for standard icons.

### Form Inputs

Use the `<.input>` component from `core_components.ex`; its attributes and behavior are in the design system ([docs/design-system/components.md](docs/design-system/components.md#forms), [inventory/forms.md](docs/design-system/inventory/forms.md)):

```heex
<.input field={@form[:word]} type="text" label="Word" />
<.input field={@form[:role]} type="select" options={["Admin", "User"]} />
```

**Note:** If you override input classes with the `class` attribute, no default styles are inherited - your classes must fully style the input.

---

## HEEx Templates

HEEx (HTML + Elixir) is Phoenix's template syntax. Use `~H` sigils or `.heex` files.

### Interpolation

Use `{...}` for values in attributes and text:

```heex
<div class={@class}>Hello, {@name}!</div>
<img src={@image_url} alt={@alt_text} />
```

Use `<%= %>` only for block constructs:

```heex
<%= if @show do %>
  <p>Visible</p>
<% end %>

<%= for item <- @items do %>
  <li>{item.name}</li>
<% end %>
```

### Conditional Classes

HEEx supports list syntax for conditional classes:

```heex
<div class={[
  "base-class p-panel",
  @active && "bg-sky-soft",
  @disabled && "opacity-50 cursor-not-allowed",
  if(@size == :large, do: "text-section", else: "text-body")
]}>
  Content
</div>
```

`nil` and `false` values are filtered out automatically. Classes come from the design system's tokens; the conformance test flags Tailwind's palette colors and type scale.

### Comments

```heex
<%!-- This is an HEEx comment (not rendered in HTML) --%>

<!-- This is an HTML comment (visible in page source) -->
```

### The `:for` Attribute

Prefer `:for` over `<%= for %>` blocks:

```heex
<%!-- Preferred --%>
<li :for={item <- @items} id={"item-#{item.id}"}>
  {item.name}
</li>

<%!-- Avoid --%>
<%= for item <- @items do %>
  <li id={"item-#{item.id}"}>{item.name}</li>
<% end %>
```

### The `:if` Attribute

Prefer `:if` for simple conditionals:

```heex
<%!-- Preferred --%>
<span :if={@show_badge} class="badge">{@count}</span>

<%!-- Use <%= if %> for if/else --%>
<%= if @logged_in do %>
  <span>Welcome back!</span>
<% else %>
  <.link href={~p"/login"}>Sign in</.link>
<% end %>
```

---

## Assets & Styling

### Asset Bundles

Phoenix uses esbuild for JavaScript and Tailwind for CSS. Only two bundles are supported:

- `assets/js/app.js` → compiled to `priv/static/assets/js/app.js`
- `assets/css/app.css` → compiled to `priv/static/assets/css/app.css`

**Rules:**
- Never reference external script `src` or stylesheet `href` in layouts
- Import vendor dependencies into `app.js` or `app.css`
- Never write inline `<script>` tags (use hooks instead); the theme-init script is the one exception (see JavaScript Interop)

```javascript
// assets/js/app.js
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"  // Vendor deps go in assets/vendor/
```

### Tailwind CSS v4

Tailwind v4 uses CSS-based configuration (no `tailwind.config.js`). The design system owns every color, type size, spacing, radius and shadow: the values are in `assets/css/system/tokens.css` (its `@theme inline` block maps them to utilities), and [docs/design-system/foundations.md](docs/design-system/foundations.md#color) explains them; adding a token is in the [design-system README](docs/design-system/README.md).

**Rules:**
- Never use `@apply` - compose utilities in templates instead
- Use the token utilities (`text-ink`, `bg-surface`, `text-section`), not Tailwind's palette or type scale; the design-system conformance test flags those and the old `gf-*` brand classes

---

## Things to Avoid

| Don't | Do Instead |
|-------|------------|
| `String.to_atom(user_input)` | Use existing atoms or `String.to_existing_atom/1` |
| Nested modules in same file | One module per file |
| `<%= for %>` blocks in HEEx | `:for` attribute: `<div :for={item <- @items}>` |
| `live_redirect`/`live_patch` | `push_navigate`/`push_patch` or `<.link>` |
| Raw `<script>` tags | Hooks in `assets/js/hooks/` |
| Map access on structs | Dot notation: `struct.field` |
| `Process.sleep` in tests | `Process.monitor` or proper synchronization |
| A hand-built search box with a results list | The `<.typeahead>` component ([docs/design-system/components.md](docs/design-system/components.md#typeahead)) |

---

## S3 Isolation in Tests

**CRITICAL**: Tests must NEVER make real AWS/S3 calls. This is enforced by:

1. **Config flag**: `config :gallformers, s3_enabled: false` in `config/test.exs`
2. **Wrapper module**: All S3 operations go through `Gallformers.Storage.S3.request/1` instead of `ExAws.request/1`

When adding new S3 operations, always use the wrapper:

```elixir
# WRONG - will fail in CI (no AWS credentials)
ExAws.S3.put_object(bucket, path, data) |> ExAws.request()

# CORRECT - respects s3_enabled config
ExAws.S3.put_object(bucket, path, data) |> Gallformers.Storage.S3.request()
```

The wrapper returns `{:ok, %{body: %{contents: [], is_truncated: false}}}` in test mode, which satisfies both list operations (need `body.contents`) and mutate operations (just check `{:ok, _}`).

---

## Ecto & Query Patterns (Project-Specific)

### Core Principles

1. **Use preloads, not manual joins** - Schema associations exist; use `Repo.preload/2`
2. **Return structs, not maps** - Maps lose preloadability; transform at boundaries (controller/view)
3. **No parallel single/batch functions** - If you need `get_x/1` AND `get_x_batch/1`, the design is wrong
4. **Count your queries** - Know the query count before and after any change
5. **Contexts own domains, not tables** - Gall logic belongs in `Catalog`, taxonomy in `Taxa`; the gall system knows taxa only by ID and through `Taxa`'s API ([rules.md](docs/architecture/rules.md) S4)

### Red Flags - STOP and Discuss

| Pattern | Problem |
|---------|---------|
| `Enum.map(items, &get_X(&1.id))` | N+1 - must batch or preload |
| `from(x in "table_name", ...)` | Missing schema - should use association |
| Function returns map with `:id` | Loses preloadability |
| `get_X/1` and `get_X_batch/1` both exist | Design smell - preloads should unify |
| Manual join on junction table | Association likely exists |

---

## PubSub / Real-time Updates

Admin pages use Phoenix PubSub (`Gallformers.PubSub`) so an open page sees others' changes. The topics and who subscribes are listed in [docs/architecture/README.md](docs/architecture/README.md). The pattern, from `Gallformers.Glossaries`:

**Context module:**
```elixir
def subscribe do
  Phoenix.PubSub.subscribe(Gallformers.PubSub, "glossary")
end

def create_glossary(attrs \\ %{}) do
  %Glossary{}
  |> Glossary.changeset(attrs)
  |> Repo.insert()
  |> broadcast(:glossary_created)
end

defp broadcast({:ok, glossary}, event) do
  Phoenix.PubSub.broadcast(Gallformers.PubSub, "glossary", {event, glossary})
  {:ok, glossary}
end

defp broadcast({:error, changeset}, _event), do: {:error, changeset}
```

**LiveView** (`GallformersWeb.Admin.GlossaryLive.Index`):
```elixir
def mount(_params, session, socket) do
  if connected?(socket), do: Glossaries.subscribe()
  # ...
end

def handle_info({event, _entry}, socket)
    when event in [:glossary_created, :glossary_updated, :glossary_deleted] do
  {:noreply, load_glossary(socket)}
end
```

---

## Schema Field Definitions

A schema is the single source of truth for its required fields, so changeset validations, the form's required markers and the data audit stay in sync. Schemas opt in with the `Gallformers.SchemaFields` behaviour (`lib/gallformers/schema_fields.ex`); `Glossary`, `Source`, `Key`, `Article`, `User`, `Place`, `Image` and `HostRange` do today, the new back-end's Catalog and Taxa schemas don't yet.

```elixir
defmodule Gallformers.Glossaries.Glossary do
  use Ecto.Schema
  @behaviour Gallformers.SchemaFields

  @required_fields [:word, :definition, :urls]

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  def changeset(glossary, attrs) do
    glossary
    |> cast(attrs, [:word, :definition, :urls])
    |> validate_required(@required_fields)
  end
end
```

`required_associations/0` is an optional callback for required relationships.

In the form, give `<.input>` the `schema` attribute and it marks the field required from the schema (an explicit `required` wins):

```heex
<.input field={@form[:word]} schema={Glossary} label="Word" />
```

`mix audit.schema_fields` reports database rows that break a schema's required fields (`mix audit.schema_fields Source`, `--summary`, `--format=csv`).
