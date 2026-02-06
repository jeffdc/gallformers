# Ecto Architecture & Refactoring Guide

> **Purpose**: Guide deliberate, architecture-aware changes to Ecto code. Prevents rushed tactical fixes that ignore existing patterns, performance implications, and context boundaries.

## CRITICAL: You Are NOT Authorized to Write Code Yet

Before writing ANY code, you must complete the Discovery and Design phases with explicit user approval at each checkpoint. Rushing to code is the failure mode this prompt exists to prevent.

---

## Phase 1: Discovery (MANDATORY)

### 1.1 Understand the Request

First, clarify with the user:
- What is the actual problem or goal?
- Is this a bug fix, new feature, refactor, or performance issue?
- What is the scope boundary? (Don't let scope creep)

### 1.2 Audit Existing Code

Before proposing ANY changes, you MUST:

1. **Find ALL related code** - not just the obvious file
   - Search for existing functions that do similar things
   - Check if batch versions already exist
   - Look for patterns already established in the codebase

2. **Read the schemas** - Check what associations are ALREADY DEFINED
   ```
   lib/gallformers/species/species.ex    # Core schema with associations
   lib/gallformers/taxonomy/taxonomy.ex  # Taxonomy schema
   lib/gallformers/hosts/host.ex         # Join table schema
   ```

3. **Identify the context boundaries**
   - Which context module owns this functionality?
   - Are there functions scattered across contexts that should be consolidated?
   - Is this creating a new responsibility that belongs elsewhere?

4. **Check for N+1 patterns** in the call chain
   - Trace from controller/LiveView down to Repo calls
   - Count queries: Is this called in a loop? Inside an Enum.map?
   - Look for `get_X_for_Y(id)` functions called per-item

### 1.3 Present Findings to User

**CHECKPOINT: Do not proceed without user acknowledgment**

Present:
- Summary of existing related code found
- Schema associations that are/aren't being used
- Potential N+1 or performance concerns
- Context boundary observations

Ask: "Does this match your understanding? Should I investigate anything else before proposing a design?"

---

## Phase 2: Design (MANDATORY)

### 2.1 Ecto Best Practices Checklist

For any proposed change, verify:

#### Associations & Preloads
- [ ] Are we using schema associations that already exist?
- [ ] Can `Repo.preload/2` replace manual joins?
- [ ] If returning data for multiple records, are we batching?
- [ ] Are we returning structs (preloadable) or maps (dead end)?

#### Query Patterns
- [ ] Is the query composable or monolithic?
- [ ] Are we duplicating logic that exists elsewhere?
- [ ] Do we need both single-item AND batch versions? (Usually a design smell)

#### Context Boundaries
- [ ] Does this function belong in this context?
- [ ] Are we reaching into another context's internals?
- [ ] Should this be a shared query module instead?

#### Performance
- [ ] How many queries does this operation execute?
- [ ] Is this called in a loop anywhere?
- [ ] Would this cause N+1 if used in a list context?

### 2.2 Design Principles

**Principle 1: Preload-First, Transform-Last**
```elixir
# WRONG: Fetch then manually assemble
def get_gall(id) do
  gall = Repo.get(Species, id)
  aliases = get_aliases_for_species(id)      # Query 2
  hosts = get_hosts_for_gall(id)              # Query 3
  %{gall: gall, aliases: aliases, hosts: hosts}
end

# RIGHT: Preload associations, return struct
def get_gall(id) do
  Species
  |> Repo.get(id)
  |> Repo.preload([:aliases, :gall_traits, host_relations: :host_species])
end
# Transform to map at the boundary (controller/view) if needed
```

**Principle 2: No Parallel Single/Batch Functions**
```elixir
# SMELL: Having both of these
def get_aliases_for_species(id)        # Single
def get_aliases_for_species_batch(ids) # Batch

# BETTER: One function that handles both, or use preloads
def get_species_with_aliases(ids) when is_list(ids) do
  Species |> where([s], s.id in ^ids) |> preload(:aliases) |> Repo.all()
end
```

**Principle 3: Queries Compose, Results Don't**
```elixir
# WRONG: Transform early, lose composability
def list_galls do
  from(s in Species, where: s.taxoncode == "gall")
  |> Repo.all()
  |> Enum.map(&%{id: &1.id, name: &1.name})  # Now can't preload
end

# RIGHT: Return query or struct, transform at boundary
def galls_query do
  from(s in Species, where: s.taxoncode == "gall")
end

# Caller decides what to load
galls_query() |> preload(:gall_traits) |> Repo.all()
```

**Principle 4: Context Owns Domain, Not Tables**
```elixir
# WRONG: Species context does everything related to species table
Gallformers.Species.get_gall_filter_values(id)
Gallformers.Species.add_filter_field_to_gall(id, type, filter_id)

# RIGHT: Galls context owns gall-specific domain logic
Gallformers.Galls.get_filter_values(gall_id)
Gallformers.Galls.add_filter(gall_id, type, filter_id)
```

### 2.3 Propose the Design

**CHECKPOINT: Do not proceed without user approval**

Present:
1. **What changes** - specific functions/modules affected
2. **Why this design** - which principles it follows
3. **Query count** - before vs after
4. **Breaking changes** - what callers need to update
5. **What you're NOT changing** - explicit scope boundary

Ask: "Does this design make sense? Any concerns before I show implementation details?"

---

## Phase 3: Implementation Planning

### 3.1 Create Incremental Steps

Large refactors fail. Break into steps where each step:
- Is independently testable
- Doesn't break existing functionality
- Can be reviewed in isolation

Example breakdown:
```
Step 1: Add association to schema (if missing)
Step 2: Create new preload-based function alongside old one
Step 3: Update one caller to use new function
Step 4: Verify with tests
Step 5: Migrate remaining callers
Step 6: Deprecate/remove old function
```

### 3.2 Identify Test Requirements

- What existing tests verify current behavior?
- What new tests are needed?
- How do we verify query count/performance?

### 3.3 Present Implementation Plan

**CHECKPOINT: Get explicit approval for the plan**

Present the step-by-step plan. Ask: "Should I proceed with Step 1?"

---

## Phase 4: Implementation

### 4.1 One Step at a Time

- Implement ONE step from the plan
- Show the diff
- Run tests
- Get user sign-off before next step

### 4.2 After Each Step

Ask:
- "Tests pass. Ready for the next step?"
- "I noticed X while implementing - should we address it now or track for later?"

### 4.3 Do NOT

- Refactor adjacent code "while you're in there"
- Add improvements not in the approved plan
- Change function signatures without discussion
- "Fix" things that aren't broken

---

## Red Flags to Call Out

If you observe any of these, STOP and discuss with the user:

| Pattern | Problem | Discussion Point |
|---------|---------|------------------|
| `Enum.map(items, &get_X(&1.id))` | N+1 query | Should this be batched? |
| `from(x in "table_name", ...)` | Missing schema/assoc | Should we add association? |
| Function returns map with `id` | Loses preloadability | Should return struct? |
| Same logic in 2+ contexts | Unclear ownership | Which context owns this? |
| `get_X/1` and `get_X_batch/1` | Dual maintenance | Can preloads unify these? |
| 1000+ line context module | God context | Should we split? |
| `Repo.get` then `Repo.preload` | Two queries | Use `preload:` in query |

---

## Quick Reference: This Codebase

### Schema Associations Already Defined

**Species schema** (`lib/gallformers/species/species.ex`):
- `has_many :images`
- `has_one :gall_traits`
- `has_many :host_relations` / `gall_relations`
- `many_to_many :aliases` (via alias_species)
- `many_to_many :taxonomies` (via species_taxonomy)
- `many_to_many :host_ranges` (via host_range)

**Taxonomy schema** (`lib/gallformers/taxonomy/taxonomy.ex`):
- `belongs_to :parent`
- `has_many :children`
- `many_to_many :species`

### Known Issues in Current Codebase

1. **Associations defined but not used** - Manual joins instead of preloads
2. **Parallel single/batch functions everywhere** - Maintenance burden
3. **Species context is 1300+ lines** - Should split gall-specific logic
4. **Filter values = 9 queries** - `get_gall_filter_values/1` should consolidate
5. **GallController has N+1** - `gall_to_response/1` per-item alias fetch

### Context Responsibilities (Current)

| Context | Current Scope | Issues |
|---------|--------------|--------|
| Species | Species CRUD, galls, aliases, images, filters, FTS, admin | Too broad |
| Taxonomy | Hierarchy, species links, cascade delete | Reasonable |
| Hosts | Host plants, ranges, gall relationships | Reasonable |
| Images | S3 operations, image CRUD | Good |
| Search | FTS, global search | Good |

---

## Example Session Flow

```
User: "I need to add a function to get gall details for the API"

Agent: "Before I propose anything, let me audit the existing code..."
       [Reads schemas, searches for similar functions]

       "I found:
        - Species.get_gall_by_id/1 exists but doesn't include hosts
        - GallController.gall_to_full_response/1 assembles this manually (5 queries)
        - Species schema has host_relations association defined but unused

        Should I propose a preload-based approach that unifies these?"

User: "Yes, show me the design"

Agent: [Presents design with query count comparison]
       "This would reduce queries from 5 to 1-2. Breaking change:
        returns struct instead of map. Approve this direction?"

User: "Yes but don't change the controller yet, just add the new function"

Agent: "Understood. Step 1: Add get_gall_with_associations/1 function.
        Here's the implementation..."
        [Shows code]
        "Tests pass. Ready to discuss controller migration as a separate change?"
```

---

## Remember

1. **Discovery before design, design before code**
2. **Existing code exists for a reason** - understand before changing
3. **User approval at every checkpoint** - no autonomous refactors
4. **Scope discipline** - do what was asked, note other issues for later
5. **Performance is a feature** - count your queries
