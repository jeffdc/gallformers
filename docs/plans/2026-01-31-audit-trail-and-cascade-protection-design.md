# Audit Trail and Cascade Delete Protection - Design Document

**Date:** 2026-01-31 (Initial), 2026-02-01 (CASCADE Analysis), 2026-02-04 (Phase reorganization)
**Status:** CASCADE fixes complete - Phase 1 (Informed Delete) ready for implementation planning
**Author:** Claude + Jeff

---

## Problem Statement

### Historical Context

The Gallformers team has experienced **significant data loss trauma** from cascade delete operations:

- Deletion of a Genus cascaded to all associated Species and their related data
- Manual recovery required from old backups with carefully constructed restore processes
- Team members still anxious about data deletion operations
- Current mitigation: warnings in UI + restricted delete access to superadmins only

### Current State

**Database Protection (completed 2026-02):**

Critical CASCADE fixes have been applied during schema migration:

| FK Constraint | Status | Behavior |
|---------------|--------|----------|
| `taxonomy.parent_id → taxonomy` | ✅ RESTRICT | Cannot delete taxonomy with children |
| `species_taxonomy.taxonomy_id → taxonomy` | ✅ RESTRICT | Cannot delete taxonomy used by species |
| `image.source_id → source` | ✅ SET NULL | Deleting source preserves images (nulls reference) |
| `taxonomy.type_id → taxontype` | N/A | No FK - `type` is TEXT field |

**Remaining problem:**
- No application-level validation shows admins what will be affected before deletion
- Admins delete "blind" without seeing dependencies
- Taxonomy deletion currently blocked entirely in UI (temporary measure)

### Requirements

**Phase 1 - Informed Delete (primary goal):**
- ✅ Must prevent data loss from cascade deletes (done via RESTRICT constraints)
- ⬚ Must show admins what will be affected before deletion
- ⬚ Team must feel confident the system protects them
- ✅ Must handle race conditions safely (done via RESTRICT constraints)

**Phase 2 - Audit Trail (future):**
- ⬚ Must track who deleted what for accountability
- ⬚ Must be able to restore deleted data
- ⬚ Must require explanations for sensitive deletions

---

## Research Summary

### Evaluated Approaches

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Dolt** (Git for data) | Native versioning, time-travel queries | Complete DB migration, infrastructure overhaul | ❌ Too invasive |
| **PaperTrail** | Mature, JSON snapshots | No explicit SQLite confirmation | ⚠️ Uncertain compatibility |
| **ex_audit** | Transparent, EETF storage, extensible | Doesn't track DB-level cascades | ✅ **Chosen** (with modifications) |
| **SQLite Triggers** | Captures all deletes including cascades | Less Elixir-idiomatic, harder to test | ⚠️ Backup option |
| **Soft Delete** | Never lose data | Messy queries, deleted data in main tables | ❌ Rejected by team |
| **Manual Ecto.Multi** | Full control, guaranteed compatible | High effort, defeats transparency | ❌ Too much work |

### Key Findings

**ex_audit:**
- Uses EETF (Erlang External Term Format) stored in `:binary` columns
- Works with SQLite (binary/BLOB support is native)
- Transparent wrapping of `Repo.insert/update/delete`
- **Limitation:** Cannot track database-level CASCADE deletes
- Extensible schema allows custom fields (user_id, deletion_reason, etc.)

**SQLite:**
- Can insert with explicit IDs (preserves original IDs on restore)
- `ON DELETE RESTRICT` prevents deletes if children exist
- RESTRICT solves BOTH cascade prevention AND race conditions
- Foreign key constraint changes require table rebuilds

---

## Chosen Architecture

### Core Strategy: Two-Phase Solution

**Phase 1 - Informed Delete (current focus):**
- Application validation shows dependencies before deletion
- Admins see exactly what will be affected
- Database RESTRICT constraints provide safety net

**Phase 2 - Audit Trail (future):**
- ex_audit for transparent tracking
- Who deleted what, when
- Restore capability

### Completed: CASCADE Fixes

**Most cascades are correct** (join table cleanup, trait cleanup, etc.)

**Critical fixes applied (2026-02):**
- `taxonomy.parent_id → taxonomy` - RESTRICT ✅
- `species_taxonomy.taxonomy_id → taxonomy` - RESTRICT ✅
- `image.source_id → source` - SET NULL ✅ (preserves images, nulls reference)

### Phase 1: Informed Delete

**Coordinated cascade deletion with full transparency:**
- Shows ALL data that will be deleted (not just direct children)
- User sees impact summary + expandable details
- "Type name to confirm" safety mechanism
- Performs deletion in correct order (leaves first) within a transaction
- Database RESTRICT constraints serve as safety net for race conditions

**Scope for Phase 1:**
- Tracer bullet: Taxonomy (Family and Genus deletion)
- Sections do not cascade, so not included
- Future: extend pattern to other entities with large cascades

---

## Design Details

### Completed: Foreign Key Changes (2026-02)

These changes were applied during the V2 schema migration:

| FK | Change | Status |
|----|--------|--------|
| `taxonomy.parent_id → taxonomy` | CASCADE → RESTRICT | ✅ Done |
| `species_taxonomy.taxonomy_id → taxonomy` | CASCADE → RESTRICT | ✅ Done |
| `image.source_id → source` | CASCADE → SET NULL | ✅ Done |
| `taxonomy.type_id → taxontype` | N/A (no FK, TEXT field) | N/A |

**All other cascades are correct:**
- ✅ Join table cascades (cleanup relationships)
- ✅ Gall trait cascades (cleanup characteristics)
- ✅ `image.species_id → species CASCADE` (intentional, with S3 cleanup)
- ✅ Alias cascades
- ✅ Lookup table SET NULL

### Phase 2: Database Schema (Future)

**New `versions` table for ex_audit:**

```sql
CREATE TABLE versions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Core ex_audit fields
  entity_schema TEXT NOT NULL,      -- e.g., "species", "taxonomy"
  entity_id INTEGER NOT NULL,       -- ID of deleted/modified record
  action TEXT NOT NULL,             -- "created", "updated", "deleted"
  patch BLOB NOT NULL,              -- EETF serialized record state
  recorded_at DATETIME NOT NULL,
  rollback BOOLEAN DEFAULT 0,

  -- User tracking
  user_id TEXT,                     -- Auth0 user ID
  user_name TEXT,                   -- Display name at time of change

  -- Deletion accountability
  deletion_reason TEXT              -- Required for sensitive deletes
);

CREATE INDEX idx_versions_entity ON versions(entity_schema, entity_id);
CREATE INDEX idx_versions_user ON versions(user_id);
CREATE INDEX idx_versions_recorded_at ON versions(recorded_at);
CREATE INDEX idx_versions_action ON versions(action);
```

**See Appendix B for complete cascade constraint analysis.**

---

## Application Code Changes

### Phase 1: Informed Delete (Coordinated Cascade)

#### 1. Cascade Impact Gathering

**Recursively gather all data that will be deleted:**
```elixir
# lib/gallformers/taxonomy.ex

@doc """
Gathers all data that would be deleted if this taxonomy is deleted.
Returns counts and lists for UI display.
"""
def get_deletion_impact(%Taxonomy{id: id, type: "family"} = taxonomy) do
  genera = list_child_genera(id)
  genera_ids = Enum.map(genera, & &1.id)

  sections = list_child_sections(id)
  section_ids = Enum.map(sections, & &1.id)

  # Species linked to this family, its genera, or its sections
  all_taxonomy_ids = [id | genera_ids] ++ section_ids
  species_count = count_species_for_taxonomies(all_taxonomy_ids)

  %{
    taxonomy: taxonomy,
    genera: genera,
    genera_count: length(genera),
    sections: sections,
    sections_count: length(sections),
    species_count: species_count,
    has_impact: length(genera) > 0 or length(sections) > 0 or species_count > 0
  }
end

def get_deletion_impact(%Taxonomy{id: id, type: "genus"} = taxonomy) do
  sections = list_child_sections(id)
  section_ids = Enum.map(sections, & &1.id)

  all_taxonomy_ids = [id | section_ids]
  species_count = count_species_for_taxonomies(all_taxonomy_ids)

  %{
    taxonomy: taxonomy,
    genera: [],
    genera_count: 0,
    sections: sections,
    sections_count: length(sections),
    species_count: species_count,
    has_impact: length(sections) > 0 or species_count > 0
  }
end

def get_deletion_impact(%Taxonomy{} = taxonomy) do
  # Section or other types - no cascade concern
  %{
    taxonomy: taxonomy,
    genera: [],
    genera_count: 0,
    sections: [],
    sections_count: 0,
    species_count: 0,
    has_impact: false
  }
end
```

#### 2. Coordinated Cascade Delete (Transaction)

**Delete in correct order to satisfy RESTRICT constraints:**
```elixir
# lib/gallformers/taxonomy.ex

@doc """
Deletes taxonomy and all dependent data in a single transaction.
Deletes leaves first (species), then sections, then genera, then family.
Returns {:ok, impact} or {:error, reason}.
"""
def delete_taxonomy_cascade(%Taxonomy{id: id, type: "family"}) do
  impact = get_deletion_impact(taxonomy)

  Repo.transaction(fn ->
    # 1. Delete all species linked to this family tree
    #    (cascades: images, aliases, sources, places, host associations)
    delete_species_for_taxonomies(impact.all_taxonomy_ids)

    # 2. Delete sections (now safe - no species references)
    Enum.each(impact.sections, &Repo.delete/1)

    # 3. Delete genera (now safe - no species or section references)
    Enum.each(impact.genera, &Repo.delete/1)

    # 4. Delete the family itself
    Repo.delete!(taxonomy)

    impact
  end)
end

def delete_taxonomy_cascade(%Taxonomy{id: id, type: "genus"} = taxonomy) do
  impact = get_deletion_impact(taxonomy)

  Repo.transaction(fn ->
    # 1. Delete all species linked to this genus or its sections
    delete_species_for_taxonomies(impact.all_taxonomy_ids)

    # 2. Delete sections
    Enum.each(impact.sections, &Repo.delete/1)

    # 3. Delete the genus itself
    Repo.delete!(taxonomy)

    impact
  end)
end

defp delete_species_for_taxonomies(taxonomy_ids) do
  # Get species IDs first for S3 cleanup
  species_ids = from(st in SpeciesTaxonomy,
    where: st.taxonomy_id in ^taxonomy_ids,
    select: st.species_id)
    |> Repo.all()

  # Delete images from S3 (before DB delete)
  cleanup_species_images(species_ids)

  # Delete species (cascades: speciestaxonomy, speciessource,
  #                speciesplace, images, aliases, host associations)
  from(s in Species, where: s.id in ^species_ids)
  |> Repo.delete_all()
end
```

#### 3. LiveView Handler

```elixir
def handle_event("initiate_delete", _params, socket) do
  taxonomy = socket.assigns.taxonomy
  impact = Taxonomy.get_deletion_impact(taxonomy)

  {:noreply, assign(socket, deletion_impact: impact, show_delete_modal: true)}
end

def handle_event("confirm_delete", %{"confirmation" => name}, socket) do
  taxonomy = socket.assigns.taxonomy

  if String.trim(name) == taxonomy.name do
    case Taxonomy.delete_taxonomy_cascade(taxonomy) do
      {:ok, impact} ->
        {:noreply,
         socket
         |> put_flash(:info, "Deleted #{taxonomy.name} and all dependent data")
         |> push_navigate(to: ~p"/admin/taxonomy")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Delete failed: #{inspect(reason)}")}
    end
  else
    {:noreply, put_flash(socket, :error, "Name does not match")}
  end
end

def handle_event("cancel_delete", _params, socket) do
  {:noreply, assign(socket, deletion_impact: nil, show_delete_modal: false)}
end
```

#### 4. UI: Cascade Delete Confirmation Modal

```heex
<.modal :if={@show_delete_modal} id="cascade-delete-modal" show>
  <:title>Delete <%= @deletion_impact.taxonomy.name %>?</:title>

  <div class="space-y-4">
    <p class="text-red-700 font-medium">
      To delete <%= @deletion_impact.taxonomy.name %>, all dependent data will be permanently deleted.
    </p>

    <%!-- Impact Summary --%>
    <div class="bg-red-50 border border-red-200 rounded p-4">
      <p class="font-medium mb-2">This will delete:</p>
      <ul class="list-disc list-inside space-y-1">
        <li :if={@deletion_impact.genera_count > 0}>
          <strong><%= @deletion_impact.genera_count %></strong> genera
        </li>
        <li :if={@deletion_impact.sections_count > 0}>
          <strong><%= @deletion_impact.sections_count %></strong> sections
        </li>
        <li :if={@deletion_impact.species_count > 0}>
          <strong><%= @deletion_impact.species_count %></strong> species
        </li>
        <li :if={@deletion_impact.species_count > 0} class="text-sm text-gray-600">
          All related data: images, aliases, sources, host associations
        </li>
      </ul>
    </div>

    <%!-- Expandable Details --%>
    <details :if={@deletion_impact.genera_count > 0 or @deletion_impact.sections_count > 0}>
      <summary class="cursor-pointer text-blue-600 hover:text-blue-800">
        Show details
      </summary>
      <div class="mt-2 pl-4 text-sm space-y-2">
        <div :if={@deletion_impact.genera_count > 0}>
          <p class="font-medium">Genera:</p>
          <ul class="list-disc list-inside">
            <li :for={genus <- @deletion_impact.genera}><%= genus.name %></li>
          </ul>
        </div>
        <div :if={@deletion_impact.sections_count > 0}>
          <p class="font-medium">Sections:</p>
          <ul class="list-disc list-inside">
            <li :for={section <- @deletion_impact.sections}><%= section.name %></li>
          </ul>
        </div>
      </div>
    </details>

    <%!-- Type to Confirm --%>
    <.simple_form for={%{}} phx-submit="confirm_delete" class="mt-4">
      <p class="text-sm text-gray-700 mb-2">
        Type <strong><%= @deletion_impact.taxonomy.name %></strong> to confirm:
      </p>
      <.input name="confirmation" type="text" autocomplete="off" required />

      <:actions>
        <.button type="submit" class="bg-red-600 hover:bg-red-700">
          Delete Forever
        </.button>
        <.button type="button" phx-click="cancel_delete">
          Cancel
        </.button>
      </:actions>
    </.simple_form>
  </div>
</.modal>
```

---

### Phase 2: Audit Trail (Future)

#### 1. ex_audit Setup

**Dependencies:**
```elixir
# mix.exs
{:ex_audit, "~> 0.10"}
```

**Repo enhancement:**
```elixir
# lib/gallformers/repo.ex
defmodule Gallformers.Repo do
  use Ecto.Repo,
    otp_app: :gallformers,
    adapter: Ecto.Adapters.SQLite3

  use ExAudit.Repo  # Add this
end
```

**Configuration:**
```elixir
# config/config.exs
config :ex_audit,
  ecto_repos: [Gallformers.Repo],
  version_schema: Gallformers.Audit.Version,
  tracked_schemas: [
    Gallformers.Species.Species,
    Gallformers.Hosts.Host,
    Gallformers.Species.Gall,
    Gallformers.Taxonomy.Taxonomy,
    # ... all other schemas
  ]
```

#### 2. User Context Tracking

**Plug to capture current user:**
```elixir
# lib/gallformers_web/plugs/audit_context.ex
defmodule GallformersWeb.Plugs.AuditContext do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case Gallformers.Accounts.get_user_from_session(conn) do
      %{id: user_id, name: name} ->
        ExAudit.track(conn, %{
          user_id: user_id,
          user_name: name
        })
      nil ->
        conn
    end
  end
end
```

#### 3. Deletion Reason Collection (Phase 2 UI Enhancement)

```heex
<.modal :if={@pending_delete_deps == %{}} id="delete-confirm-modal" show>
  <:title>Delete <%= @taxonomy.name %>?</:title>

  <.simple_form for={@form} phx-submit="confirm_delete">
    <.input
      field={@form[:reason]}
      type="textarea"
      label="Reason for deletion (for audit trail):"
    />

    <:actions>
      <.button type="submit" class="danger">Delete</.button>
      <.button type="button" phx-click="cancel_delete">Cancel</.button>
    </:actions>
  </.simple_form>
</.modal>
```

---

## Implementation Strategy

### Completed: CASCADE Fixes (2026-02)

Database constraints updated during V2 schema migration. No further migration work needed.

---

### Phase 1: Informed Delete (Current Focus)

**Goal:** Admins see what will be affected before confirming deletion.

**Phase 1 Scope (Tracer Bullet):**

| Entity | What to Show | Cascade Concern |
|--------|--------------|-----------------|
| **Taxonomy (Family)** | Genera, Sections, Species count | ✅ Yes - large cascade |
| **Taxonomy (Genus)** | Sections, Species count | ✅ Yes - large cascade |
| **Taxonomy (Section)** | N/A | ❌ No cascade concern |

**Future scope** (after tracer bullet validated):
- Source → Images (SET NULL, but user should know)
- Gall → Species, Images, Host associations
- Host → Gall associations

**Implementation pattern:**
1. `get_deletion_impact/1` - recursively gather ALL dependent data
2. Modal shows summary + expandable details
3. "Type name to confirm" safety mechanism
4. `delete_taxonomy_cascade/1` - atomic transaction, deletes leaves first
5. Database RESTRICT serves as safety net for race conditions

**UI workflow:**
- Click delete → Modal shows full impact
- Summary: "X genera, Y sections, Z species"
- "Show details" expands to list genera/sections by name
- Type taxonomy name to confirm
- Transaction deletes everything or nothing

---

### Phase 2: Audit Trail (Future)

**Goal:** Track who deleted what, when, with ability to restore.

**Components:**
1. Add ex_audit dependency
2. Create `versions` table
3. Configure Repo and tracked schemas
4. Add user context plug
5. (Optional) Build restore capability

**Restore capability:**
```elixir
def restore_from_version(version_id) do
  version = Repo.get!(Version, version_id)
  original_record = ExAudit.Tracking.deserialize_patch(version.patch)
  Repo.insert(original_record)
end
```

**No cascade restore needed** because RESTRICT prevents cascade deletes.

See "Application Code Changes" section below for full ex_audit implementation details.

---

## Testing Strategy

### Phase 1: Coordinated Cascade Delete Tests

**Unit tests - impact gathering:**
```elixir
describe "get_deletion_impact/1" do
  test "family shows genera, sections, and species counts" do
    family = insert_family()
    genus1 = insert_genus(parent: family)
    genus2 = insert_genus(parent: family)
    section = insert_section(parent: genus1)
    insert_species(taxonomy: genus1)
    insert_species(taxonomy: genus1)
    insert_species(taxonomy: section)

    impact = Taxonomy.get_deletion_impact(family)

    assert impact.genera_count == 2
    assert impact.sections_count == 1
    assert impact.species_count == 3
    assert impact.has_impact == true
  end

  test "genus shows sections and species counts" do
    genus = insert_genus()
    section = insert_section(parent: genus)
    insert_species(taxonomy: genus)
    insert_species(taxonomy: section)

    impact = Taxonomy.get_deletion_impact(genus)

    assert impact.genera_count == 0
    assert impact.sections_count == 1
    assert impact.species_count == 2
  end

  test "section has no cascade impact" do
    section = insert_section()

    impact = Taxonomy.get_deletion_impact(section)

    assert impact.has_impact == false
  end
end
```

**Unit tests - cascade delete:**
```elixir
describe "delete_taxonomy_cascade/1" do
  test "deletes family and all descendants in transaction" do
    family = insert_family()
    genus = insert_genus(parent: family)
    species = insert_species(taxonomy: genus)
    image = insert_image(species: species)

    assert {:ok, impact} = Taxonomy.delete_taxonomy_cascade(family)

    assert impact.species_count == 1
    refute Repo.get(Taxonomy, family.id)
    refute Repo.get(Taxonomy, genus.id)
    refute Repo.get(Species, species.id)
    refute Repo.get(Image, image.id)
  end

  test "rolls back on failure - all or nothing" do
    family = insert_family()
    genus = insert_genus(parent: family)

    # Simulate failure mid-transaction (mock or constraint violation)

    assert {:error, _} = Taxonomy.delete_taxonomy_cascade(family)

    # Everything still exists
    assert Repo.get(Taxonomy, family.id)
    assert Repo.get(Taxonomy, genus.id)
  end

  test "cleans up S3 images during cascade" do
    genus = insert_genus()
    species = insert_species(taxonomy: genus)
    image = insert_image(species: species, path: "images/test.jpg")

    expect(S3Mock, :delete_object, fn "images/test.jpg" -> :ok end)

    assert {:ok, _} = Taxonomy.delete_taxonomy_cascade(genus)
  end
end
```

### E2E Tests (Phase 1)

```elixir
test "delete family shows full cascade impact", %{session: session} do
  family = insert_family(name: "Fagaceae")
  genus = insert_genus(parent: family, name: "Quercus")
  insert_species(taxonomy: genus)
  insert_species(taxonomy: genus)

  session
  |> visit("/admin/taxonomy/#{family.id}")
  |> click(Query.button("Delete"))
  |> assert_has(Query.text("1 genera"))
  |> assert_has(Query.text("2 species"))
  |> assert_has(Query.text("All related data"))
end

test "show details expands to list genera", %{session: session} do
  family = insert_family(name: "Fagaceae")
  insert_genus(parent: family, name: "Quercus")
  insert_genus(parent: family, name: "Castanea")

  session
  |> visit("/admin/taxonomy/#{family.id}")
  |> click(Query.button("Delete"))
  |> click(Query.text("Show details"))
  |> assert_has(Query.text("Quercus"))
  |> assert_has(Query.text("Castanea"))
end

test "requires typing name to confirm deletion", %{session: session} do
  family = insert_family(name: "Fagaceae")

  session
  |> visit("/admin/taxonomy/#{family.id}")
  |> click(Query.button("Delete"))
  |> fill_in(Query.text_field("confirmation"), with: "Wrong Name")
  |> click(Query.button("Delete Forever"))
  |> assert_has(Query.text("Name does not match"))

  # Still exists
  assert Repo.get(Taxonomy, family.id)
end

test "successful cascade delete with correct confirmation", %{session: session} do
  family = insert_family(name: "Fagaceae")
  genus = insert_genus(parent: family)

  session
  |> visit("/admin/taxonomy/#{family.id}")
  |> click(Query.button("Delete"))
  |> fill_in(Query.text_field("confirmation"), with: "Fagaceae")
  |> click(Query.button("Delete Forever"))
  |> assert_has(Query.text("Deleted Fagaceae"))

  refute Repo.get(Taxonomy, family.id)
  refute Repo.get(Taxonomy, genus.id)
end
```

### Phase 2: Audit Trail Tests (Future)

```elixir
test "creates audit version on successful delete" do
  genus = insert_genus()
  {:ok, deleted} = delete_taxonomy(genus, reason: "Test cleanup")

  version = Repo.one!(from v in Version,
    where: v.entity_schema == "taxonomy" and v.entity_id == ^genus.id)

  assert version.action == "deleted"
  assert version.deletion_reason == "Test cleanup"
end
```

---

## Success Metrics

### Phase 1: Coordinated Cascade Delete

**Safety:**
- ✅ Zero accidental cascade deletes (RESTRICT constraints as safety net)
- ✅ Zero race condition data loss (RESTRICT + transactions)
- ⬚ Admins see FULL impact before confirming delete
- ⬚ "Type name to confirm" prevents accidental clicks

**Team Confidence:**
- ⬚ Team reports feeling safe to delete data
- ⬚ Admins can delete families/genera without fear
- ⬚ Taxonomy deletion re-enabled (currently blocked)

**Technical:**
- ✅ CASCADE constraints fixed (safety net)
- ⬚ Recursive impact gathering for taxonomy
- ⬚ Atomic transaction for cascade delete
- ⬚ S3 image cleanup during cascade
- ⬚ Delete confirmation UI with full impact display

### Phase 2: Audit Trail (Future)

**Accountability:**
- ⬚ Every deletion has user_id and timestamp
- ⬚ Sensitive deletions have required reasons
- ⬚ Audit log queryable by entity, user, time
- ⬚ 100% of deletes tracked in audit log

---

## Open Questions

### Phase 1 (Resolved)
1. ✅ **Which entities first?** Taxonomy (Family, Genus) as tracer bullet
2. ✅ **UI pattern:** Modal with impact summary + expandable details + type-to-confirm
3. ✅ **Cascade approach:** Show full impact, then perform coordinated delete in transaction

### Phase 1 (Open)
1. **S3 cleanup timing:** Delete images before or after DB transaction? (Before = orphans on rollback, After = orphan DB refs on S3 failure)
2. **Large cascades:** Should we add a threshold (e.g., >100 species) that requires extra confirmation?
3. **Progress feedback:** For very large cascades, show progress indicator?

### Phase 2 (Future)
1. **Restore UI:** Admin UI for browsing/restoring versions, or iex-only?
2. **Retention:** How long to keep audit records?
3. **Performance:** Will audit logging impact high-volume operations?

---

## Next Steps

### Completed
1. ✅ Design document (this document)
2. ✅ CASCADE constraint fixes (done in V2 schema migration)

### Phase 1: Coordinated Cascade Delete (Taxonomy Tracer Bullet)
3. ⏭️ Create Phase 1 implementation plan
4. ⏭️ `get_deletion_impact/1` - recursive impact gathering for Family/Genus
5. ⏭️ `delete_taxonomy_cascade/1` - atomic transaction delete
6. ⏭️ S3 image cleanup integration
7. ⏭️ Cascade delete confirmation modal UI
8. ⏭️ Write tests (unit + E2E)
9. ⏭️ Re-enable taxonomy deletion in admin UI

### Phase 2: Audit Trail (Future)
8. ⏭️ Add ex_audit dependency and configuration
9. ⏭️ Create versions table migration
10. ⏭️ Add user context tracking
11. ⏭️ (Optional) Build restore capability

---

## Appendix A: Domain Model Context

### Critical Understanding: Species, Galls, and Hosts

**Domain model:**
- `species` table = Base entity for ALL organisms (both gall-forming species AND host plants)
- `gall` table = Additional properties for gall-forming species (linked via `gallspecies` 1:1)
- `host` table = **Misnamed** - actually represents the `gallhost` relationship (which gall affects which host plant)
- Both galls and hosts are entries in the `species` table

**UI reality:**
- Users delete **galls** (species with gall properties) from the UI
- Users delete **hosts** (species that are plants) from the UI
- Users NEVER delete "species" directly - it only happens as a cascade from gall/host deletion

**Deletion flow:**
```
User deletes GALL →
  1. Delete gall record (extra properties)
  2. CASCADE delete gallspecies association (1:1 link)
  3. CASCADE delete species record (gall and species are tightly bound)
  4. CASCADE delete speciestaxonomy, speciessource, speciesplace, image (from species cascade)
  5. CASCADE delete host relationships (gall↔host)
```

**Verified schema facts:**
- `gallspecies` is currently many-to-many but behaves as 1:1 (verified via query: all relationships are 1:1)
- **Schema refactor consideration:** Should be a simple FK `gall.species_id → species`

---

## Appendix B: Complete CASCADE Constraint Analysis

**Date analyzed:** 2026-02-01
**Updated:** 2026-02-04 (changes applied)
**Status:** Critical changes applied during V2 schema migration

### Summary of Changes (Applied)

| Foreign Key | Was | Now | Rationale |
|-------------|-----|-----|-----------|
| `taxonomy.parent_id → taxonomy` | CASCADE | **RESTRICT** ✅ | Prevent catastrophic deletion |
| `species_taxonomy.taxonomy_id → taxonomy` | CASCADE | **RESTRICT** ✅ | Force explicit handling of species |
| `image.source_id → source` | CASCADE | **SET NULL** ✅ | Preserve images, null the reference |
| `taxonomy.type_id → taxontype` | N/A | N/A | No FK exists - `type` is TEXT field |

All other constraints remain CASCADE or SET NULL as designed.

---

### Detailed Constraint Decisions

#### SPECIES Relationships

**Domain context:** Species are deleted indirectly (via gall or host deletion), never directly from UI.

| Foreign Key | Direction | Decision | Rationale |
|-------------|-----------|----------|-----------|
| `image.species_id → species` | Species deleted | **CASCADE** | Images belong to species; includes S3 cleanup. Intentional data loss. |
| `speciestaxonomy.species_id → species` | Species deleted | **CASCADE** | Cleanup join table. Species no longer exists, associations meaningless. |
| `speciestaxonomy.taxonomy_id → taxonomy` | Taxonomy deleted | **RESTRICT** ⚠️ | **CHANGED:** Prevent taxonomy deletion if species are using it. Forces explicit handling. |
| `speciessource.species_id → species` | Species deleted | **CASCADE** | Cleanup join table. |
| `speciessource.source_id → source` | Source deleted | **CASCADE** | Cleanup join table only. Species remain (just lose source association). |
| `speciesplace.species_id → species` | Species deleted | **CASCADE** | Cleanup join table. |
| `speciesplace.place_id → place` | Place deleted | **CASCADE** | Cleanup join table only. Species remain. |
| `gallspecies.species_id → species` | Species deleted | **CASCADE** | Cleanup join table (gall ↔ species link). |
| `host.species_id → species` | Gall species deleted | **CASCADE** | Cleanup gall↔host relationships when gall is deleted. |
| `host.host_species_id → species` | Host plant deleted | **CASCADE** | Cleanup gall↔host relationships when host plant is deleted. |
| `aliasspecies.species_id → species` | Species deleted | **CASCADE** (two-level) | Cascade delete join table + alias records. Alias is meaningless without species. |
| `aliasspecies.alias_id → alias` | Alias deleted (SQL) | **CASCADE** (one-level) | Cleanup join table only. Species remain. |
| `species.abundance_id → abundance` | Abundance deleted (migration) | **SET NULL** | Species lose abundance classification but remain. Lookup table change. |

#### GALL Relationships

**Domain context:** Galls are deleted from UI. Deleting gall cascades to delete its species (tightly bound).

| Foreign Key | Direction | Decision | Rationale |
|-------------|-----------|----------|-----------|
| `gall.detachable_id → detachable` | Detachable deleted (migration) | **SET NULL** | Gall loses detachability classification. Lookup table change. |
| `gall.walls_id → walls` | Walls deleted (migration) | **SET NULL** | Gall loses walls classification. Lookup table change. |
| `gall.cells_id → cells` | Cells deleted (migration) | **SET NULL** | Gall loses cells classification. Lookup table change. |
| `gall.form_id → form` | Form deleted (migration) | **SET NULL** | Gall loses form classification. Lookup table change. |
| `gallcolor.gall_id → gall` | Gall deleted | **CASCADE** | Cleanup trait association. |
| `gallcolor.color_id → color` | Color deleted (migration) | **CASCADE** | Cleanup associations. Fixed lookup data (migration-only changes). |
| `gallshape.gall_id → gall` | Gall deleted | **CASCADE** | Cleanup trait association. |
| `gallshape.shape_id → shape` | Shape deleted (migration) | **CASCADE** | Cleanup associations. Fixed lookup data. |
| `galltexture.gall_id → gall` | Gall deleted | **CASCADE** | Cleanup trait association. |
| `galltexture.texture_id → texture` | Texture deleted (migration) | **CASCADE** | Cleanup associations. Fixed lookup data. |
| `gallalign.gall_id → gall` | Gall deleted | **CASCADE** | Cleanup trait association. |
| `gallalign.alignment_id → alignment` | Alignment deleted (migration) | **CASCADE** | Cleanup associations. Fixed lookup data. |
| `gallloc.gall_id → gall` | Gall deleted | **CASCADE** | Cleanup trait association. |
| `gallloc.location_id → location` | Location deleted (migration) | **CASCADE** | Cleanup associations. Fixed lookup data. |
| `gallseason.gall_id → gall` | Gall deleted | **CASCADE** | Cleanup trait association. |
| `gallseason.season_id → season` | Season deleted (migration) | **CASCADE** | Cleanup associations. Fixed lookup data. |
| `gallwalls.gall_id → gall` | Gall deleted | **CASCADE** | Cleanup trait association. |
| `gallcells.gall_id → gall` | Gall deleted | **CASCADE** | Cleanup trait association. |
| `gallform.gall_id → gall` | Gall deleted | **CASCADE** | Cleanup trait association. |

**Pattern:** All gall trait join tables CASCADE on both sides. Traits are fixed lookup data (migration-only).

#### TAXONOMY Relationships

**Domain context:** Taxonomy forms a parent-child hierarchy (Kingdom → Phylum → ... → Genus → Species).

| Foreign Key | Direction | Decision | Rationale |
|-------------|-----------|----------|-----------|
| `taxonomy.parent_id → taxonomy` | Parent deleted | **RESTRICT** ⚠️ | **CRITICAL FIX:** Prevent catastrophic cascade (e.g., delete Family → all Genera → all Species). |
| `speciestaxonomy.taxonomy_id → taxonomy` | Taxonomy deleted | **RESTRICT** ⚠️ | **CHANGED:** Force handling of species before taxonomy deletion. Prevents orphaning species. |
| `taxonomyalias.taxonomy_id → taxonomy` | Taxonomy deleted | **CASCADE** (two-level) | Cascade delete join table + alias records. Alias meaningless without taxonomy. |
| `taxonomyalias.alias_id → alias` | Alias deleted (SQL) | **CASCADE** (one-level) | Cleanup join table only. Taxonomy remains. |
| `taxonomy.type_id → taxontype` | Taxontype deleted (migration) | **RESTRICT** ⚠️ | **NEW:** Prevent deletion of taxonomy types (family, genus, etc.) if in use. |

#### SOURCE Relationships

| Foreign Key | Direction | Decision | Rationale |
|-------------|-----------|----------|-----------|
| `image.source_id → source` | Source deleted | **RESTRICT** ⚠️ | **CHANGED FROM PLAN:** Prevent source deletion if images reference it. Forces explicit handling. Original plan was SET NULL. |
| `speciessource.source_id → source` | Source deleted | **CASCADE** | Cleanup join table only. Species remain (just lose source association). |

#### IMAGE Relationships

| Foreign Key | Direction | Decision | Rationale |
|-------------|-----------|----------|-----------|
| `image.species_id → species` | Species deleted | **CASCADE** | Images belong to species. Includes S3 cleanup. Intentional data loss. |
| `image.source_id → source` | Source deleted | **RESTRICT** ⚠️ | Prevent image loss. Must handle images before deleting source. |

#### PLACE Relationships

| Foreign Key | Direction | Decision | Rationale |
|-------------|-----------|----------|-----------|
| `speciesplace.place_id → place` | Place deleted | **CASCADE** | Cleanup join table only. Species remain. |
| `placeplace.parent_id → place` | Parent place deleted | **CASCADE** | Geographic hierarchy (State → County → City). OK to cascade delete children. |

#### ALIAS Relationships

**Pattern:** Aliases have asymmetric cascades (two-level from owner, one-level from alias).

| Foreign Key | Direction | Decision | Rationale |
|-------------|-----------|----------|-----------|
| `aliasspecies.species_id → species` | Species deleted | **CASCADE** (two-level) | Delete join table → delete alias. Alias meaningless without species. |
| `aliasspecies.alias_id → alias` | Alias deleted (SQL) | **CASCADE** (one-level) | Delete join table only. Species remains. |
| `taxonomyalias.taxonomy_id → taxonomy` | Taxonomy deleted | **CASCADE** (two-level) | Delete join table → delete alias. Alias meaningless without taxonomy. |
| `taxonomyalias.alias_id → alias` | Alias deleted (SQL) | **CASCADE** (one-level) | Delete join table only. Taxonomy remains. |

---

### Open Investigation Items

**Discovered during analysis:**

1. **`taxonomytaxonomy` table** - May be legacy artifact unused since `taxonomy.parent_id` exists. Needs investigation.
   - If unused: Consider dropping in schema refactor
   - If used: Document purpose and cascade behavior

2. **`gallspecies` 1:1 behavior** - Currently many-to-many table but verified to only have 1:1 relationships.
   - **Schema refactor opportunity:** Replace with `gall.species_id → species` FK
   - Would simplify schema and deletion logic

---

### Key Decisions Different from Original Plan

| Original Plan | Actual Decision | Rationale |
|---------------|-----------------|-----------|
| `image.source_id → source`: SET NULL | **RESTRICT** | Stronger protection. Force explicit image handling before source deletion. |
| Only 2 cascades need fixing | **3+ cascades need fixing** | Added `speciestaxonomy.taxonomy_id`, `taxonomy.type_id`, and reconsidered join table behavior. |

---

### Schema Refactor Considerations

**Issues identified for future schema work:**

1. **`host` table misnamed** → Should be `gallhost` (represents relationship, not host entity)
2. **`gallspecies` unnecessary join table** → Could be simple FK `gall.species_id → species`
3. **`taxonomytaxonomy` potentially unused** → Investigate and possibly remove
4. **Asymmetric alias cascades are confusing** → Consider alternative design where aliases are owned by species/taxonomy with FK

**This cascade analysis is foundational for schema refactor planning.**
