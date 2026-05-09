---
status: planned
tags: [design]
created: 2026-05-08
updated: 2026-05-08
epic: ingestion
---

# Traits table redesign for ingestion review workspace

## Traits Table Redesign

Replace the current list-of-cards traits UI with a dense table. Driven by poor information density and unusable conflict resolution in the current implementation.

### Layout

Table with columns: **Trait | Current | Extracted | Result**

- When identity is "new" (no existing gall), Current column hidden.
- Locked state (identity unresolved): section header with "Locked" badge, table hidden.

### Columns

**Trait:** Human-readable label only (e.g., "Color", "Shape"). No internal field name.

**Current:** Values currently on the gall in the DB. Rendered as toggleable pills (`gf-pill` styling). User can deselect to remove values. Same widget/behavior as Extracted.

**Extracted:** Values from LLM extraction (`suggested_values`). Toggleable pills, same as Current. No page references for now. Small `+` button at end opens dropdown of remaining controlled vocabulary (full vocab minus values already shown in Current or Extracted). Selecting from dropdown adds to `extracted_selected`.

**Result:** Computed read-only view. `result = current_selected ∪ extracted_selected`. Rendered as inline comma-separated text (not pills) to save space. Styling relative to `original_current` (frozen snapshot of Current at load time):
- In result AND in original_current → plain bold black (unchanged)
- In result but NOT in original_current → bold brown/orange (addition)
- NOT in result but WAS in original_current → strikethrough gray (removal)

### Data Model Per Row

```
%{
  name: "color",
  label: "Color",
  current_values: ["green", "brown"],
  extracted_values: ["pale brown"],
  current_selected: MapSet<>,
  extracted_selected: MapSet<>,
  original_current: MapSet<>
}
```

### Density Rules

- Table cells: `px-2 py-1.5`
- Pills: `text-xs px-1.5 py-0.5`
- Trait labels: `text-sm`
- No card wrappers — table rows separated by hairline borders
- Section header inline with table

### Detachable Trait

Same table row, values are `["integral", "detachable"]`. Works identically.

### Raw Evidence

Not shown in table. Available in source text drawer.

### Communication

Same `send(self(), {:trait_updated, trait_name, selected_values})` to parent, where `selected_values` is the result set (union of selected from both columns).
