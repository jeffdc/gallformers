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
- Run `mix precommit` before committing
- All code must pass `mix credo --strict` with no errors
- All code must pass `mix dialyzer` with no warnings
- Treat warnings as errors during compilation (`--warnings-as-errors`)

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
The Species context.

Provides functions for querying and managing species records,
including their relationships to galls, hosts, and images.
"""
```

For internal/infrastructure modules (Application, Repo, generated code), use `@moduledoc false`.

For schema modules, briefly describe what the entity represents.

### Function Documentation

Public functions must have `@doc` and `@spec`:

```elixir
@doc """
Fetches a species by ID.

Returns `nil` if not found.
"""
@spec get_species(integer()) :: Species.t() | nil
def get_species(id), do: Repo.get(Species, id)
```

Private functions do not need `@doc` or `@spec` unless complex.

### Typespecs

Use typespecs for:
- All public function arguments and return values
- Custom types that improve readability
- Structs (define `t()` type)

```elixir
@type t :: %__MODULE__{
  id: integer(),
  name: String.t(),
  description: String.t() | nil,      # Optional field (nullable in DB)
  taxonomy: Taxonomy.t() | nil,       # Association (nil if not preloaded)
  inserted_at: DateTime.t()
}
```

Use `| nil` for fields that can be null in the database or associations that may not be loaded.

---

## Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Modules | PascalCase | `GallformersWeb.SpeciesLive` |
| Functions | snake_case | `get_species_by_name/1` |
| Variables | snake_case | `species_list` |
| Atoms | snake_case | `:species_created` |
| Files | snake_case | `species_live.ex` |
| LiveView modules | `*Live` suffix | `SpeciesLive`, `HostsLive.Index` |
| Context modules | Plural noun | `Species`, `Hosts`, `Accounts` |
| Schema modules | Singular noun | `Species.Gall`, `Hosts.Host` |

**Predicate functions** end with `?`:
```elixir
def valid?(changeset), do: changeset.valid?
```

**Never** prefix predicates with `is_`:
```elixir
# WRONG
def is_valid(changeset)

# CORRECT
def valid?(changeset)
```

---

## Code Organization

### Phoenix Contexts

Organize business logic into contexts (domain modules):

```
lib/my_app/
├── species.ex         # Species context (public API)
├── species/
│   ├── species.ex     # Species schema
│   ├── gall.ex        # Gall schema
│   └── image.ex       # Image schema
├── hosts.ex           # Hosts context
└── hosts/
    └── host.ex        # Host schema
```

**Context modules** expose the public API. **Schema modules** define data structures.

### Keep Related Code Together

- One module per file
- Files mirror module namespace (`MyApp.Species.Gall` → `lib/my_app/species/gall.ex`)
- Tests mirror source structure (`lib/my_app/species.ex` → `test/my_app/species_test.exs`)

---

## Ecto Patterns

### Queries

Use Ecto's query syntax, not raw SQL:

```elixir
def list_species_by_family(family_id) do
  from(s in Species,
    join: t in assoc(s, :taxonomy),
    where: t.family_id == ^family_id,
    order_by: [asc: s.name],
    preload: [:taxonomy, :images]
  )
  |> Repo.all()
end
```

### Changesets

Define changesets in schema modules:

```elixir
def changeset(species, attrs) do
  species
  |> cast(attrs, [:name, :description, :abundance_id])
  |> validate_required([:name])
  |> unique_constraint(:name)
end
```

**Never** put user-input fields and programmatic fields in the same `cast/3`:

```elixir
# User input
|> cast(attrs, [:name, :description])
# Then set programmatic fields explicitly
|> put_change(:updated_by, user_id)
```

### Preloading

Always preload associations that will be accessed:

```elixir
# In context
species = Repo.get(Species, id) |> Repo.preload([:taxonomy, :images])

# Or in query
from(s in Species, preload: [:taxonomy, :images])
```

### Avoiding N+1 Queries

N+1 occurs when you query a list, then query each item's association separately:

```elixir
# BAD - N+1 (1 query for species, N queries for taxonomy)
species = Repo.all(Species)
Enum.map(species, fn s -> s.taxonomy.name end)  # Each access triggers a query

# GOOD - Preload in the original query
species = Repo.all(from s in Species, preload: [:taxonomy])
Enum.map(species, fn s -> s.taxonomy.name end)  # No additional queries
```

**Detection:** Enable query logging in dev to spot repeated queries:
```elixir
# config/dev.exs
config :my_app, MyApp.Repo, log: :debug
```

### Query Performance

- Use `select` to fetch only needed fields for large result sets
- Add database indexes for frequently filtered/joined columns
- Use `Repo.stream/1` for processing large datasets without loading all into memory

---

## LiveView Patterns

### Streams for Collections

Use streams for lists to avoid memory issues:

```elixir
def mount(_params, _session, socket) do
  {:ok, stream(socket, :species, Species.list_species())}
end
```

```heex
<div id="species-list" phx-update="stream">
  <div :for={{id, species} <- @streams.species} id={id}>
    {species.name}
  </div>
</div>
```

### Forms

Always use `to_form/2` and the `<.input>` component:

```elixir
def mount(_params, _session, socket) do
  changeset = Species.change_species(%Species{})
  {:ok, assign(socket, form: to_form(changeset))}
end
```

```heex
<.form for={@form} id="species-form" phx-change="validate" phx-submit="save">
  <.input field={@form[:name]} type="text" label="Name" />
  <.button>Save</.button>
</.form>
```

### Function Components vs LiveComponents

**Function components** (default choice) are simple, stateless, and render as part of the parent:

```elixir
# In core_components.ex or any module
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
<div id="chart" phx-hook="Chart" phx-update="ignore"></div>

<%!-- Always provide a unique DOM id with phx-hook --%>
<input id="phone-input" phx-hook="PhoneFormatter" />
```

**Colocated hooks** (Phoenix 1.8+) keep JS close to the template:

```heex
<input type="text" id="phone" phx-hook=".PhoneNumber" />
<script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
  export default {
    mounted() {
      this.el.addEventListener("input", e => {
        // format phone number
      })
    }
  }
</script>
```

- Colocated hook names **must** start with a `.` prefix (e.g., `.PhoneNumber`)
- Never write raw `<script>` tags - use colocated hooks or external JS

**External hooks** go in `assets/js/` and register with LiveSocket:

```javascript
// assets/js/hooks.js
export const Chart = {
  mounted() {
    this.chart = new Chart(this.el, {...})
  },
  updated() {
    this.chart.update()
  },
  destroyed() {
    this.chart.destroy()
  }
}

// assets/js/app.js
import { Chart } from "./hooks"
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { Chart }
})
```

---

## Error Handling

### Pattern Match Results

Handle success and error cases explicitly:

```elixir
case Species.create_species(attrs) do
  {:ok, species} ->
    {:noreply,
     socket
     |> put_flash(:info, "Species created")
     |> push_navigate(to: ~p"/species/#{species}")}

  {:error, changeset} ->
    {:noreply, assign(socket, form: to_form(changeset))}
end
```

### Use `with` for Multi-Step Operations

Use `with` when chaining 2+ operations that can fail. For single checks, prefer `case`.

```elixir
with %Species{} = species <- Repo.get(Species, id),
     :ok <- authorize(user, :update, species),
     {:ok, updated} <- Species.update_species(species, attrs) do
  {:ok, updated}
else
  nil -> {:error, :not_found}
  {:error, reason} -> {:error, reason}
end
```

**Note**: Match on actual return types. `Repo.get/2` returns `struct | nil`, not `{:ok, struct}`.

---

## Testing

Examples use generic `MyApp` module names. Replace with your project's module prefix.

### Test File Structure

```elixir
defmodule MyApp.SpeciesTest do
  use MyApp.DataCase

  alias MyApp.Species

  describe "list_species/0" do
    test "returns all species" do
      species = species_fixture()
      assert Species.list_species() == [species]
    end
  end
end
```

### LiveView Tests

Use `Phoenix.LiveViewTest`:

```elixir
defmodule MyAppWeb.SpeciesLiveTest do
  use MyAppWeb.ConnCase

  import Phoenix.LiveViewTest

  test "displays species", %{conn: conn} do
    species = species_fixture()
    {:ok, view, _html} = live(conn, ~p"/species")
    assert has_element?(view, "#species-#{species.id}")
  end
end
```

### Fixtures

Test fixtures are defined in `test/support/fixtures/` and imported via `DataCase` or `ConnCase`:

```elixir
defmodule MyApp.SpeciesFixtures do
  def species_fixture(attrs \\ %{}) do
    {:ok, species} =
      attrs
      |> Enum.into(%{name: "Test Species"})
      |> MyApp.Species.create_species()

    species
  end
end
```

Import in tests: `import MyApp.SpeciesFixtures`

### Assertions

- Use `assert` and `refute`, not `assert x == true`
- Test behavior, not implementation
- Use fixtures for test data (define in `test/support/fixtures/`)
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
| One-off async work | `Task.async/1` or `Task.Supervisor` | Sending emails |
| Periodic work | `Process.send_after/3` in GenServer | Cache expiration |
| Stateful process | `GenServer` | Connection pool, rate limiter |
| Simple state | `Agent` | Counters, simple caches |

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
from(s in Species, where: s.name == ^user_input)

# DANGEROUS - SQL injection risk
from(s in Species, where: fragment("name = '#{user_input}'"))

# SAFE - Use parameterized fragments
from(s in Species, where: fragment("lower(?) LIKE ?", s.name, ^pattern))
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

LiveView templates should begin with `<Layouts.app>`:

```heex
<Layouts.app flash={@flash}>
  <h1>Page Title</h1>
  <!-- page content -->
</Layouts.app>
```

The `Layouts` module is auto-aliased in `my_app_web.ex` - no explicit alias needed.

### Flash Messages

The `<.flash_group>` component lives in `layouts.ex` and renders automatically. **Never** call `<.flash_group>` directly in LiveView templates - it's handled by the layout.

### Icons (Phosphor)

This project uses [Phosphor Icons](https://phosphoricons.com/) with the `ph-` prefix via the `<.icon>` component:

```heex
<.icon name="ph-detective" class="w-5 h-5" />
<.icon name="ph-trash" class="w-4 h-4 text-red-500" />
```

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

Use the `<.input>` component from `core_components.ex`:

```heex
<.input field={@form[:email]} type="email" label="Email" />
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
  "base-class px-4",
  @active && "bg-blue-500",
  @disabled && "opacity-50 cursor-not-allowed",
  if(@size == :large, do: "text-xl", else: "text-base")
]}>
  Content
</div>
```

`nil` and `false` values are filtered out automatically.

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

- `assets/js/app.js` → compiled to `priv/static/assets/app.js`
- `assets/css/app.css` → compiled to `priv/static/assets/app.css`

**Rules:**
- Never reference external script `src` or stylesheet `href` in layouts
- Import vendor dependencies into `app.js` or `app.css`
- Never write inline `<script>` tags (use hooks instead)

```javascript
// assets/js/app.js
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"  // Vendor deps go in assets/vendor/
```

### Tailwind CSS v4

Tailwind v4 uses CSS-based configuration (no `tailwind.config.js`):

```css
/* assets/css/app.css */
@import "tailwindcss";

@theme {
  --color-brand: #5b21b6;
  --color-danger: #dc2626;
}
```

**Rules:**
- Never use `@apply` - compose utilities in templates instead
- Define custom colors/values in `@theme` blocks
- Use standard Tailwind classes in HEEx templates

---

## Things to Avoid

| Don't | Do Instead |
|-------|------------|
| `String.to_atom(user_input)` | Use existing atoms or `String.to_existing_atom/1` |
| Nested modules in same file | One module per file |
| `<%= for %>` blocks in HEEx | `:for` attribute: `<div :for={item <- @items}>` |
| `live_redirect`/`live_patch` | `push_navigate`/`push_patch` or `<.link>` |
| Raw `<script>` tags | Colocated hooks or external JS |
| `ilike` in queries | `fragment("lower(?) LIKE ?", ...)` for SQLite |
| Map access on structs | Dot notation: `struct.field` |
| `Process.sleep` in tests | `Process.monitor` or proper synchronization |

---

## S3 Isolation in Tests

**CRITICAL**: Tests must NEVER make real AWS/S3 calls. This is enforced by:

1. **Config flag**: `config :gallformers, s3_enabled: false` in `config/test.exs`
2. **Wrapper module**: All S3 operations go through `Gallformers.S3.request/1` instead of `ExAws.request/1`

When adding new S3 operations, always use the wrapper:

```elixir
# WRONG - will fail in CI (no AWS credentials)
ExAws.S3.put_object(bucket, path, data) |> ExAws.request()

# CORRECT - respects s3_enabled config
ExAws.S3.put_object(bucket, path, data) |> Gallformers.S3.request()
```

The wrapper returns `{:ok, %{body: %{contents: []}}}` in test mode, which satisfies both list operations (need `body.contents`) and mutate operations (just check `{:ok, _}`).

---

## Pre-Commit Checklist

Before committing:

1. `mix format` - Format all code
2. `mix compile --warnings-as-errors` - No compilation warnings
3. `mix credo --strict` - No Credo issues
4. `mix test` - All tests pass
5. `mix dialyzer` - No type errors

Or run: `mix precommit` (if configured)

---

## SQLite Compatibility

This project uses **SQLite** (via ecto_sqlite3), not PostgreSQL. Always ensure queries are SQLite-compatible.

**WAL mode footgun — stale journal files:** SQLite in WAL mode uses three files: `.sqlite`, `.sqlite-wal`, and `.sqlite-shm`. If you replace the main `.sqlite` file without deleting the WAL/SHM companions, sqlite3 will replay the old WAL against the new database and report "database disk image is malformed." Always delete `-wal` and `-shm` files when replacing a database file.

**Case-insensitive search (NO `ilike`):**
```elixir
# WRONG - PostgreSQL only
where: ilike(s.name, ^search_term)

# CORRECT - SQLite compatible
search_term = "%#{String.downcase(query)}%"
where: fragment("lower(?) LIKE ?", s.name, ^search_term)
```

**Distinct on column (NO `distinct: column`):**
```elixir
# WRONG - PostgreSQL's DISTINCT ON
distinct: t.id

# CORRECT - SQLite compatible (use group_by instead)
group_by: [t.id, t.name]
```

---

## Ecto & Query Patterns (Project-Specific)

**For refactoring or new DB code**: Load `prompts/ecto-refactor.md` for full guidance with mandatory checkpoints.

### Core Principles

1. **Use preloads, not manual joins** - Schema associations exist; use `Repo.preload/2`
2. **Return structs, not maps** - Maps lose preloadability; transform at boundaries (controller/view)
3. **No parallel single/batch functions** - If you need `get_x/1` AND `get_x_batch/1`, the design is wrong
4. **Count your queries** - Know the query count before and after any change
5. **Contexts own domains, not tables** - Gall-specific logic belongs in a Galls context, not Species

### Schema Associations (USE THESE)

**Species** (`lib/gallformers/species/species.ex`):
```elixir
has_many :images                    # Species.Image
has_one :gall_traits                # Species.GallTraits
has_many :host_relations            # Hosts.Host (this species as gall)
has_many :gall_relations            # Hosts.Host (this species as host)
many_to_many :aliases               # via alias_species
many_to_many :taxonomies            # via species_taxonomy
many_to_many :host_ranges           # via host_range (places)
```

**Taxonomy** (`lib/gallformers/taxonomy/taxonomy.ex`):
```elixir
belongs_to :parent                  # Self-referential
has_many :children                  # Self-referential
many_to_many :species               # via species_taxonomy
```

### Red Flags - STOP and Discuss

| Pattern | Problem |
|---------|---------|
| `Enum.map(items, &get_X(&1.id))` | N+1 - must batch or preload |
| `from(x in "table_name", ...)` | Missing schema - should use association |
| Function returns map with `:id` | Loses preloadability |
| `get_X/1` and `get_X_batch/1` both exist | Design smell - preloads should unify |
| Manual join on junction table | Association likely exists |
| 1000+ line context module | God context - needs splitting |

### Query Pattern Examples

```elixir
# WRONG: Manual assembly (4 queries)
def get_host_for_edit(id) do
  host = get_host(id)
  taxonomy = Taxonomy.get_taxonomy_for_species(id)
  places = get_places_for_host(id)
  aliases = get_aliases_for_host(id)
  Map.merge(host, %{taxonomy: taxonomy, places: places, aliases: aliases})
end

# RIGHT: Preload (1-2 queries)
def get_host_for_edit(id) do
  Species
  |> where([s], s.id == ^id and s.taxoncode == "plant")
  |> preload([:aliases, :host_ranges, taxonomies: :parent])
  |> Repo.one()
end
```

---

## PubSub / Real-time Updates

The admin interface uses Phoenix PubSub for real-time updates. Pattern:

**Context module:**
```elixir
@topic "glossary"

def subscribe do
  Phoenix.PubSub.subscribe(Gallformers.PubSub, @topic)
end

defp broadcast({:ok, record}, event) do
  Phoenix.PubSub.broadcast(Gallformers.PubSub, @topic, {event, record})
  {:ok, record}
end
```

**LiveView:**
```elixir
def mount(_params, _session, socket) do
  if connected?(socket), do: Glossary.subscribe()
  {:ok, stream(socket, :glossaries, Glossary.list_glossaries())}
end

def handle_info({:glossary_created, glossary}, socket) do
  {:noreply, stream_insert(socket, :glossaries, glossary, at: 0)}
end
```

---

## Styling (Project-Specific)

### Custom Colors

Colors are defined in `assets/css/app.css` via `@theme`:

| Class | Hex | Use for |
|-------|-----|---------|
| `text-gf-maroon` / `bg-gf-maroon` | #661419 | Headings, links, primary accent |
| `text-gf-sky-blue` / `bg-gf-sky-blue` | #c1e0f3 | Header background |
| `text-gf-autumn` / `bg-gf-autumn` | #bc6428 | Subtitles, secondary text |
| `bg-cadet-blue` | #96adc8 | Table headers |
| `bg-canary` | #f8f991 | Selected/highlighted rows |

---

## Schema Field Definitions (In Progress)

Schemas should be the single source of truth for required/optional fields. This ensures:
- Changeset validations and UI `required` attributes stay in sync
- No drift between what the form requires and what the database validates
- Data audit tools can use the same definitions

**Target Pattern (being implemented):**

```elixir
# In schema module
defmodule Gallformers.Sources.Source do
  use Ecto.Schema
  use Gallformers.SchemaFields  # Behavior for field metadata

  @required_fields [:title, :author, :pubyear, :link, :citation, :license]
  @optional_fields [:datacomplete, :licenselink]

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  def changeset(source, attrs) do
    source
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
```

```elixir
# In form template - auto-derives required from schema
<.input field={@form[:title]} schema={Source} label="Title:" />
```

**Tracking:** `gallformers-1j8o` (field audit), `gallformers-uvz3` (tracer bullet), `gallformers-kntb` (full implementation)

**Current State:** Most forms hardcode `required` attributes separately from schema validations. This will be unified once the pattern is proven.

---

## Request Logging

The app logs all HTTP requests to JSON Lines files for incident investigation.

**Location:**
- **Production**: `/data/logs/requests-YYYY-MM-DD.log` (persistent volume)
- **Development**: `priv/logs/requests-YYYY-MM-DD.log` (gitignored)

**Log format** (one JSON object per line):
```json
{"ts":"2026-02-05T14:32:01Z","method":"GET","path":"/species/123","query":"tab=hosts","status":200,"duration_ms":45,"ip":"1.2.3.4","ua":"Mozilla/5.0..."}
```

**Retention**: Logs older than 30 days are automatically deleted.

**Retrieving logs from production:**
```bash
fly ssh sftp get /data/logs/requests-2026-02-05.log
```

**Analyzing logs locally:**
```bash
# All 500 errors
cat requests-2026-02-05.log | jq -c 'select(.status >= 500)'

# Slowest requests
cat requests-2026-02-05.log | jq -s 'sort_by(.duration_ms) | reverse | .[0:10]'

# Requests to a specific path
cat requests-2026-02-05.log | jq -c 'select(.path | startswith("/api/gall"))'

# Error rate by path
cat requests-2026-02-05.log | jq -s 'group_by(.path) | map({path: .[0].path, total: length, errors: [.[] | select(.status >= 400)] | length})'
```

**Configuration:**
- `config :gallformers, :request_log_dir` - Override log directory
- `config :gallformers, :request_logger_enabled` - Disable logging (set `false` in test.exs)

**Implementation**: `lib/gallformers/request_logger.ex` - Attaches to Phoenix telemetry events.

---

## E2E Tests (Browser-based)

E2E tests use [Wallaby](https://github.com/elixir-wallaby/wallaby) with Chrome. They're **excluded from regular test runs** to keep the dev loop fast.

**Prerequisites**: ChromeDriver is required.
```bash
brew install chromedriver
xattr -d com.apple.quarantine $(which chromedriver)
make e2e-setup
```

**Running E2E tests**:
```bash
make e2e                   # Run all E2E tests
make e2e-changed           # Run only tests affected by changed files
make e2e-public            # Public pages only
make e2e-search            # Search functionality only
make e2e-browse            # Species/hosts/galls browsing only
make e2e-admin             # Admin pages only
make e2e-auth              # Authentication flows only
```

**Debugging**: `make e2e-headed` or `E2E_HEADED=1 make e2e-admin`

### Writing E2E Tests

All E2E tests must be tagged with `@moduletag :e2e` plus an area tag. See `test/support/e2e_case.ex` for full documentation.

```elixir
defmodule GallformersWeb.E2E.MyTest do
  use GallformersWeb.E2ECase

  @moduletag :e2e
  @moduletag :e2e_public  # Area tag

  test "page loads", %{session: session} do
    session
    |> visit("/")
    |> assert_has(Query.css("body.phx-connected"))
  end
end
```
