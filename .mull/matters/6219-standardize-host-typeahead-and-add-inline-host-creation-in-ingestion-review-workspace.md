---
status: raw
tags: [design]
created: 2026-05-08
updated: 2026-05-08
epic: ingestion
---

# Standardize host typeahead and add inline host creation in ingestion review workspace

## Problem

The host-mapping panel in the ingestion review workspace (`workspace_hosts.ex`) has two issues:

1. **Non-standard typeahead.** Lines 212–242 use a hand-rolled `<form phx-change="host_search">` with an inline dropdown, instead of the standard `<.typeahead>` component used everywhere else (e.g. `workspace_identity.ex`, the public `id_live.ex` page, the source picker on `show.ex`).

2. **No path to create a host that doesn't exist.** When the source mentions a host not in the catalog, the only options are Decline or leave it unmapped — even though the rest of the app has full host-creation UI with WCVP autopopulation.

## Design

### Part 1 — Swap the bespoke typeahead for `<.typeahead>`

Replace the inline form/input/dropdown in `host_review_row/1` with the standard component, mirroring the pattern used in `workspace_identity.ex`:

```elixir
<.typeahead
  id={"host-picker-#{@review.index}"}
  query={Map.get(@review, :search_query, "")}
  results={Map.get(@review, :search_results, [])}
  selected={nil}
  search_event="host_search"
  select_event="host_select"
  clear_event="host_clear"
  create_event="host_create"
  allow_new={true}
  display_fn={& &1.name}
  target={@myself}
/>
```

`host_clear` and `host_create` are new handlers. `host_create` sends `{:request_create_host, index, name}` to the parent LiveView.

### Part 2 — Inline create-host modal (WCVP-driven)

New LiveComponent `workspace_create_host.ex`. Opens when the user clicks "Create" in the typeahead. Modal contents, in order:

1. **Name** — prefilled with the typed name, editable.
2. **WCVP picker** — `<.typeahead>` that searches WCVP. On open, auto-runs `Wcvp.Lookup.search/2` with the prefilled name (`start_async(:wcvp_search, ...)`). User picks an entry.
3. **Selected WCVP summary** — after pick, `start_async(:wcvp_select, ...)` fetches the full record. Show: "Will create with: name, family, N native places (+ M introduced)."
4. **Buttons:** Cancel / Create host.

**On Save:**

1. Resolve taxonomy from species name: `Taxonomy.lookup_taxonomy_for_new_species/1` + `Taxonomy.resolve_taxonomy_for_species/2` (same as host admin form).
2. WCVP family overrides the resolved family. Create the family taxonomy row if it doesn't exist (mirrors lines 676–699 of `host_live/form.ex`).
3. `Plants.create_host_with_associations(%{species_attrs: %{name: name, taxoncode: "plant"}, taxonomy: ..., parent_id: family_id, aliases: []})`.
4. After create: `Plants.upsert_host_traits(host.id, %{wcvp_id, powo_id, wcvp_synced_at})` and `Ranges.update_host_places(host.id, place_entries)` to persist WCVP IDs and range.
5. Send `{:host_created_and_mapped, index, host}` to parent. Parent updates the `host_review` row to `decision: "mapped"`, `species_id: host.id`, and clears search state.

**Edge cases:**

- **WCVP unavailable** (`wcvp_lookup().available?() == false`) — show a notice and disable the picker; allow create with name + resolved taxonomy only (no range).
- **No WCVP match** — same fallback. Note in the UI: "No WCVP match — host will be created without range data; edit later from the host admin."
- **New genus** (not in DB) — user must pick a family. Show a select with `Taxonomy.list_families_for_select(:plant)` only when needed.

## Files

- **Modify** `lib/gallformers_web/live/admin/ingestion_review_live/workspace_hosts.ex` — swap typeahead, add `host_clear`/`host_create` handlers.
- **Modify** `lib/gallformers_web/live/admin/ingestion_review_live/workspace.ex` — modal state assign, handle_info for `:request_create_host` and `:host_created_and_mapped`, render the modal LiveComponent.
- **Create** `lib/gallformers_web/live/admin/ingestion_review_live/workspace_create_host.ex` — new LiveComponent (~150 lines).
- **Modify** `test/gallformers_web/live/admin/ingestion_review_live/workspace_test.exs` — typeahead-shape assertions, create flow happy path, WCVP-unavailable fallback.

## Out of scope

- No range editor in the modal — WCVP is the only range source here.
- No alias entry in the modal.
- No reusable extraction over `init_new_host_from_wcvp` from the host admin form — duplicate the ~10-line WCVP-prep snippet rather than refactor across two pages.

