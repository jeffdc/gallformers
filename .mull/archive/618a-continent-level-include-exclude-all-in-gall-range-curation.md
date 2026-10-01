---
status: done
tags: [design]
created: 2026-04-09
updated: 2026-09-13
epic: gall-traits
---

# Continent-level include/exclude all in gall range curation

## Problem

After syncing host ranges from WCVP, curating gall ranges on the GallHost page is tedious — admins must click every country individually. The existing "Include All / Exclude All" pattern works within a country (for subdivisions) but nothing similar exists at the continent level.

## Design

Extend the existing RangeDrillDown component with an "up" navigation level that shows all countries in a continent.

### Interaction flow

1. Admin clicks a country on the GallHost map → existing subdivision drill-down opens (unchanged)
2. Panel header shows a breadcrumb/up-arrow with the continent name (e.g., "↑ North America")
3. Clicking it switches the panel to continent view: lists all countries in that continent that are in the host range
4. **Include All**: for countries with subdivisions (US, CA), includes every leaf subdivision; for leaf countries (MX, BM), includes the country directly. Everything in that continent turns green.
5. **Exclude All**: inverse — removes all places in that continent from the gall range
6. Clicking a specific country in the continent view drills back down to the subdivision level (existing behavior)

### What changes

- `RangeDrillDown` gains a `:continent` mode alongside the existing `:country` mode
- New "up" navigation uses `Places.get_ancestors/1` to find the continent parent, then `Places.get_children/1` to list sibling countries
- Include All at continent level collects leaf descendant IDs for countries with subdivisions, direct IDs for leaf countries
- Parent (GallHost) gets new `handle_info` clauses for continent-level include/exclude messages

### What doesn't change

- Direct country/subdivision clicking works exactly as before
- Map rendering unchanged — no continent boundaries needed
- Save flow unchanged — still saves `gall_range_place_ids`
