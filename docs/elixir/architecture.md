# Elixir Architecture: Contexts & Project Structure

Ecto fits into a larger architectural pattern that emphasizes **explicit boundaries** between layers and **domain-driven design**. This guide explains how Elixir projects are structured and why that structure matters.

## The Boundary Pattern

Elixir applications enforce strict layer separation:

```
gallformers_web/          ← Web layer (controllers, LiveViews, sockets)
    ↓
gallformers/              ← Business logic layer (Contexts)
    ↓
Ecto (Repo, Schemas)      ← Data access
    ↓
SQLite
```

**Critical rule**: The web layer cannot directly access the database. It must go through Contexts.

This isn't a guideline—it's enforced by structure. Your controller doesn't have `Repo.all()` in it because the context already provides the right functions.

## Contexts: The Core Abstraction

A **context** is a module that encapsulates a domain boundary. It's like a "use case handler" or "domain service" that owns all logic for a specific domain.

### Examples from Gallformers

```elixir
Gallformers.Species       ← Context for species domain
  ├── get_species/1
  ├── list_species/1
  ├── list_species_by_genus/1
  ├── create_species/2
  ├── update_species/3
  ├── delete_species/1
  └── ... other species operations

Gallformers.Taxonomy      ← Separate domain
  ├── get_taxonomy/1
  ├── list_taxonomies/1
  ├── ... taxonomy operations

Gallformers.Hosts         ← Another domain
  ├── get_host/1
  ├── list_hosts/1
  └── ... host operations
```

Each context owns a domain. **Species logic lives in the Species context, not scattered across the app.**

### Why Contexts Matter

1. **Clear boundaries** - You know where to find code for any feature
2. **Encapsulation** - Internal implementation details stay hidden; context can change how it stores data without affecting callers
3. **Testability** - You test the public API, not internals
4. **Reusability** - Same context functions work for web controllers, LiveViews, background jobs, and APIs
5. **Reasoning** - Follow one context to understand a feature end-to-end
6. **Scaling** - Large apps don't become monolithic; contexts can be extracted to separate services

## Context Structure

A typical context module looks like this:

```elixir
defmodule Gallformers.Species do
  @moduledoc """
  The Species context.

  Encapsulates all operations related to gall-forming organisms.
  """
  alias Gallformers.{Repo, Species}        # Schema is typically private
  alias Gallformers.Species.GallTraits

  # ===== PUBLIC API =====
  # What external code uses (controllers, LiveViews, tests, etc.)

  @doc """
  Get a single species by ID.

  Returns a Species struct or nil if not found.
  """
  def get_species(id) do
    Species |> Repo.get(id)
  end

  @doc """
  List all active species, ordered by name.
  """
  def list_species_active do
    from(s in Species, where: s.active == true)
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  List species in a given genus.
  """
  def list_species_by_genus(genus) do
    from(s in Species, where: s.genus == ^genus)
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  Create a new species.

  Returns {:ok, struct} or {:error, changeset} on validation failure.
  """
  def create_species(attrs) do
    %Species{}
    |> Species.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update an existing species.
  """
  def update_species(species, attrs) do
    species
    |> Species.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a species.
  """
  def delete_species(species) do
    Repo.delete(species)
  end

  # ===== PRIVATE HELPERS =====
  # Implementation details (use `defp` for private functions)

  defp apply_filters(query, filters) do
    query
    |> apply_genus_filter(filters)
    |> apply_abundance_filter(filters)
  end

  defp apply_genus_filter(query, %{"genus" => genus}) do
    where(query, [s], s.genus == ^genus)
  end
  defp apply_genus_filter(query, _), do: query

  defp apply_abundance_filter(query, %{"abundance" => abundance}) do
    where(query, [s], s.abundance == ^abundance)
  end
  defp apply_abundance_filter(query, _), do: query
end
```

### Key Observations

- The **schema** (`Species`) is imported but rarely appears in function signatures
- The context **returns structs**, not raw data or maps
- The context **hides Ecto details** - callers don't know about changesets or Repo
- **Public functions are simple** - one responsibility each, documented with `@doc`
- **Private functions** (prefixed with `defp`) handle implementation details
- **Validation lives in changesets**, not the context

## Project Layout

Your project structure reflects this pattern:

```
lib/gallformers/
  ├── repo.ex                     ← Database connection
  │
  ├── species/                    ← Domain: species
  │   ├── species.ex              ← Schema definition
  │   ├── gall_traits.ex          ← Related schema (gall morphology)
  │   └── plants.ex               ← Related schema (host plants)
  │
  ├── species.ex                  ← Context (public API for species domain)
  │
  ├── taxonomy/
  │   └── taxonomy.ex             ← Schema
  │
  ├── taxonomy.ex                 ← Context
  │
  ├── hosts/
  │   ├── host.ex                 ← Schema
  │   └── host_plant.ex
  │
  ├── hosts.ex                    ← Context
  │
  └── application.ex              ← Supervision tree

lib/gallformers_web/             ← Web layer (Phoenix-specific)
  ├── controllers/
  │   ├── species_controller.ex    ← HTTP endpoints for species
  │   ├── host_controller.ex
  │   └── ...
  │
  ├── live/                        ← LiveView pages (real-time web UI)
  │   ├── species_live/
  │   │   ├── index.ex
  │   │   └── show.ex
  │   ├── host_live/
  │   └── ...
  │
  └── components/                  ← Reusable UI components
      ├── core_components.ex       ← Buttons, inputs, modals
      ├── form_components.ex       ← Typeaheads, dropdowns
      └── data_display_components.ex ← Cards, galleries, tables
```

### Naming Pattern

```
Context Module              Schema Module(s)
lib/gallformers/species.ex  lib/gallformers/species/species.ex
                           lib/gallformers/species/gall_traits.ex
```

The context and its schemas live in parallel structure:
- Context: `Gallformers.Species`
- Schema: `Gallformers.Species.Species` (or `Gallformers.Species.GallTraits`)

## Data Flow: From User to Database and Back

Here's how a complete feature flows through all layers:

### 1. User Action
User fills out a form to create a new species in the web UI (LiveView).

### 2. LiveView Receives Event
```elixir
def handle_event("save", %{"species" => params}, socket) do
  # LiveView calls context function
  case Species.create_species(params) do
    {:ok, species} ->
      # Success - redirect or update UI
      {:noreply, socket |> put_flash(:info, "Created!")}

    {:error, changeset} ->
      # Validation failed - show errors
      {:noreply, assign(socket, :changeset, changeset)}
  end
end
```

### 3. Context Handles Business Logic
```elixir
def create_species(attrs) do
  %Species{}
  |> Species.changeset(attrs)      # Validate & cast
  |> Repo.insert()                 # Insert or get error
end
```

### 4. Changeset Validates
The changeset handles:
- Type casting (string → integer, etc.)
- Required field validation
- Custom validation logic
- Database constraint checks

```elixir
def changeset(species, attrs) do
  species
  |> cast(attrs, [:name, :genus, :family])
  |> validate_required([:name])
  |> unique_constraint(:name)
end
```

### 5. Repo Executes
```elixir
Repo.insert(changeset)
# ↓ Validates again, then executes INSERT
# ↓ Returns {:ok, struct} or {:error, changeset}
```

### 6. Response
- **Success**: `{:ok, species_struct}` returns to LiveView
- **Failure**: `{:error, changeset}` returns with error details

### 7. LiveView Updates UI
```elixir
case create_result do
  {:ok, species} ->
    # Add to stream, show success message
    {:noreply, stream_insert(socket, :species, species)}

  {:error, changeset} ->
    # Re-render form with error messages
    {:noreply, assign(socket, :changeset, changeset)}
end
```

**Key point**: Data flows in one direction: User → LiveView → Context → Ecto → Database → Context → LiveView → User.

## Why This Matters: Comparison to Other Frameworks

### Rails Model
```ruby
# Rails - Models know everything
class User < ApplicationRecord
  validates :email, presence: true
  has_many :posts

  def self.find_active
    where(active: true)
  end
end

# Rails controller calls model directly
user = User.find(id)
user.posts.each { |p| p.update(...) }  # Direct DB access
```

**Problems:**
- Models get huge (1000+ lines)
- Hard to trace where logic lives
- Easy to accidentally break things
- Hard to test without a database
- Business logic mixes with ORM concerns

### Elixir Context Pattern
```elixir
# Elixir - Clear separation
defmodule Users do
  def get_user(id), do: Repo.get(User, id)

  def get_user_posts(id) do
    from(p in Post, where: p.user_id == ^id)
    |> Repo.all()
  end
end

# Controller calls context, never touches Repo directly
user = Users.get_user(id)
posts = Users.get_user_posts(id)
```

**Benefits:**
- Functions are small and focused
- Business logic is explicit and traceable
- Easy to test (context functions are simple)
- Schema changes don't affect callers
- Scales to large apps without becoming unmaintainable

## Phoenix-Specific: LiveViews

LiveViews blur the line slightly—they handle events and state directly—but the pattern holds:

```elixir
defmodule GallformersWeb.SpeciesLive.Index do
  use GallformersWeb, :live_view
  alias Gallformers.Species

  def mount(_params, _session, socket) do
    # Call context, not Repo
    species = Species.list_species()
    {:ok, stream(socket, :species, species)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    # Still call context
    {:ok, _species} = Species.delete_species(id)
    {:noreply, stream_delete(socket, :species, ...)}
  end

  # LiveView can show loading states, handle real-time updates, etc.
  # But it delegates business logic to contexts
end
```

The LiveView is the "web layer"—it handles user interaction and UI state. The context handles business logic. They stay separate.

## Testing Pattern

This structure makes testing clean and fast:

### Context Tests (Unit)
```elixir
defmodule SpeciesTest do
  use ExUnit.Case
  alias Gallformers.Species

  setup do
    # Insert test data
    species = insert(:species, active: true)
    {:ok, species: species}
  end

  test "get_species returns active species", %{species: species} do
    assert Species.get_species(species.id) == species
  end

  test "create_species validates required fields" do
    {:error, changeset} = Species.create_species(%{})
    assert "can't be blank" in errors_on(changeset).name
  end
end
```

**Key point**: You test contexts with data, not HTTP.

### LiveView Tests (Integration)
```elixir
defmodule SpeciesLiveTest do
  use GallformersWeb.ConnCase

  test "lists all species", %{conn: conn} do
    insert(:species)
    {:ok, _lv, html} = live(conn, "/species")
    assert html =~ "Species"
  end
end
```

**Key point**: You test LiveViews with DOM, not database.

### E2E Tests (Browser)
```elixir
defmodule GallformersWeb.E2E.SpeciesTest do
  use GallformersWeb.E2ECase

  @moduletag :e2e
  @moduletag :e2e_browse

  test "user can view species", %{session: session} do
    session
    |> visit("/species/123")
    |> assert_has(Query.css("h1", text: "Oak Gall"))
  end
end
```

**Key point**: E2E tests verify the complete flow through the browser.

## Supervision & Application Startup

Elixir has a supervision tree that starts all your services:

```elixir
defmodule Gallformers.Application do
  use Application

  def start(_type, _args) do
    children = [
      Gallformers.Repo,              # Database connection pool
      {Phoenix.PubSub, name: ...},   # Pub/Sub for real-time updates
      GallformersWeb.Endpoint,       # Phoenix web server
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

**Key points:**
- Repo is started as a supervised process
- Contexts assume the Repo is already running—they just call it
- If a service crashes, the supervisor restarts it
- `:one_for_one` strategy means if one child crashes, others keep running

## Common Patterns & Best Practices

### 1. Preload Upfront, Not Later

**WRONG**—causes N+1 queries:
```elixir
species = Species.list_species()
Enum.each(species, fn s ->
  images = Repo.all(from(i in Image, where: i.species_id == ^s.id))
end)
```

**RIGHT**—preload once:
```elixir
def list_species_with_details do
  Species
  |> preload([:images, :gall_traits, taxonomies: :parent])
  |> Repo.all()
end

# Now the struct contains everything needed
species = list_species_with_details()
# species.images is available without another query
```

### 2. Batch Operations Instead of Loops

**WRONG**:
```elixir
species_ids = [1, 2, 3]
Enum.map(species_ids, &Species.get_species/1)  # 3 queries!
```

**RIGHT**:
```elixir
def get_species_by_ids(ids) do
  from(s in Species, where: s.id in ^ids)
  |> Repo.all()
end

# One query
get_species_by_ids([1, 2, 3])
```

### 3. Return Structs, Not Maps

**WRONG**—loses Ecto knowledge:
```elixir
Repo.all(from(s in Species, select: map(s, [:id, :name])))
# Returns plain maps, can't preload, can't validate
```

**RIGHT**—return full structs:
```elixir
Species |> Repo.all()
# Returns Species structs with all fields
```

If you need to serialize (JSON response), do it at the boundary:

```elixir
def species_to_json(species) do
  %{
    id: species.id,
    name: species.name,
    genus: species.genus
  }
end
```

### 4. Compose Queries Without Executing

Use private helpers to build complex queries:

```elixir
def list_species_filtered(filters) do
  Species
  |> apply_genus_filter(filters)
  |> apply_abundance_filter(filters)
  |> apply_range_filter(filters)
  |> order_by(:name)
  |> Repo.all()
end

defp apply_genus_filter(query, %{"genus" => genus}) do
  where(query, [s], s.genus == ^genus)
end
defp apply_genus_filter(query, _), do: query

defp apply_abundance_filter(query, %{"abundance" => abundance}) do
  where(query, [s], s.abundance == ^abundance)
end
defp apply_abundance_filter(query, _), do: query

# ...
```

This is much cleaner than big if/else chains building different queries.

### 5. Keep Changesets for Writes Only

Changesets are for **validation and transformation**, not reading:

```elixir
# CORRECT - changesets for writes
def create_species(attrs) do
  %Species{}
  |> Species.changeset(attrs)
  |> Repo.insert()
end

# CORRECT - direct queries for reads (no changeset)
def list_species do
  Species |> Repo.all()
end

# WRONG - using changesets for reads
def list_species do
  Species
  |> Repo.all()
  |> Enum.map(&Species.changeset/1)  # Pointless
end
```

### 6. Don't Do Single/Batch Function Pairs

**WRONG**:
```elixir
def get_species(id), do: Repo.get(Species, id)
def get_species_batch(ids) do
  from(s in Species, where: s.id in ^ids) |> Repo.all()
end
```

Why? Because preloading solves this:

**RIGHT**:
```elixir
# Single function, preload handles batching
def get_species(id) do
  Species |> preload(:images) |> Repo.get(id)
end

# For multiple, batch with a query
def list_species do
  Species |> preload(:images) |> Repo.all()
end
```

## Comparison to Other Frameworks

| Framework | Pattern | Tradeoff |
|-----------|---------|----------|
| **Rails** | Model + migrations | Simpler initially, scales poorly; models become god objects |
| **Django** | Models + views | Clear structure but mixed concerns; N+1 queries easy to miss |
| **Node.js (Sequelize/TypeORM)** | Models + repos | More boilerplate; often still allows direct DB calls in controllers |
| **Elixir (Phoenix)** | Contexts + schemas + LiveViews | More upfront boilerplate, but excellent for large apps; structure enforced by language |

Elixir pushes you toward scalable, maintainable architecture **upfront**. Rails lets you ignore structure until it becomes a problem at scale.

## Your Project's Standards

Your `CLAUDE.md` enforces these patterns:

> **"Contexts own domains, not tables"** - A context should handle all operations for a domain, not just crud on one table.

> **"Use preloads, not manual joins"** - Schemas already have associations; use them.

> **"No parallel single/batch functions"** - Preload instead of creating separate batch functions.

> **"Return structs, not maps"** - Maps lose preloadability; always return Ecto structs.

> **"Count your queries"** - Know the query count before and after changes. Aim for the minimum.

These aren't suggestions—they're the Elixir way of avoiding N+1 queries, god modules, and the problems that plague large Rails applications.

## Summary

Elixir's architecture pattern:

1. **Contexts** encapsulate domains and expose simple public functions
2. **Schemas** define data structure and validation rules
3. **Ecto** handles database access through explicit Repo calls
4. **Controllers/LiveViews** delegate all logic to contexts—never call Repo directly
5. **Tests** test each layer independently—unit tests for contexts, integration tests for LiveViews

This enforces **clear boundaries**, **explicit data flow**, and **testability** from the start. It requires more upfront boilerplate than Rails, but pays dividends as your app grows.
