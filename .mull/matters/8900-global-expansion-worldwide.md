---
status: active
created: 2026-02-23
updated: 2026-02-27
epic: geo-expansion
docs: ['']
relates: [1db6, b99b, 8166]
needs: [b99b]
---

# Global expansion (worldwide)

# Global expansion (worldwide)

Expand from Western Hemisphere to worldwide coverage. Infrastructure-first — ship global map/places/continent selector, data populates organically. Target: Romania conference summer 2026.

## Guiding Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Rollout model | Infrastructure-first, data-organic | Data will always be patchy outside NA. Ship the global map and let it fill in. |
| Territory classification | Pure geography, not politics | Réunion → Africa, not France. Ecology, not sovereignty. |
| Disputed territories | Follow Natural Earth defaults | Apply logic when edge cases arise. |
| Subdivision scope | Curated by ecological relevance | Most countries of meaningful size get subdivisions. |
| User region preference | localStorage, per-page scope widget | No accounts needed. Persists across sessions. |
| Host plant data | WCVP (already global) | Pipeline from WH expansion works as-is. |
| Data sourcing | Organic via admin entry + WCVP lookup | No pre-population needed. Admins add hosts as needed. |

## Work Streams

### Stream 0: Maps & Range Cleanup (b99b) — COMPLETE
Fixed bugs (list_places vs list_all_places, split_by_precision missing place_id, exclusion subtraction, ExclusionDrillDown semantics). Code quality improvements and test coverage added.

### Stream 1: Place Data Expansion — COMPLETE
8 continents, 249 countries, 4290 subdivisions in DB. Global PMTiles (4880 features, 370MB). All tests passing. Supersedes Western Hemisphere expansion (1db6).

### Stream 2: Continent Scoping UI — REWORKED

Move from global header selector to per-page scope widget. Only pages with filterable data show the widget. All other pages are always global.

#### Page classification

| Category | Pages | Behavior |
|----------|-------|----------|
| Scoped | ID tool, Search, Explore | Show region scope widget, filter results by continent |
| Global | Home, detail pages (Gall/Host/Place/Family/Genus/Section), Articles, Keys, About, Filter Terms, Glossary, Analytics, Admin | No widget, always show all data |

#### Region scope widget

A slim horizontal strip below the header, above page content. Only renders on scoped pages. Same content width as the page, subtle light gray background, compact height (breadcrumb-weight). Small text, not a banner.

**Default state** (matching localStorage value, or "All Regions" if unset):

```
 🌐 North America  ▾
```

Globe icon, region name, dropdown caret. Clean and minimal.

**After changing to a different region** (temporary override, not yet saved):

```
 🌐 Europe  ▾                          Set as default · Reset
```

- Dropdown changes results immediately on this page only
- "Set as default" — updates localStorage, strip returns to clean default state
- "Reset" — reverts to saved default, strip returns to clean state
- Navigating away without clicking either discards the change; next page uses saved default

#### First-visit modal

Triggers on first visit to any scoped page when localStorage has no saved region (no `gf_continent` key). Does NOT appear on global pages.

Content:
- Region selection grid (8 continents + "All Regions")
- Explains that the selection is sticky for pages with filterable data (ID, Search, Explore)
- Explains they can change it anytime on those pages
- Notes it does not persist across devices/browsers

Selecting a region sets localStorage and dismisses the modal. Subsequent visits to any scoped page use the saved value.

#### What gets removed

- Header continent selector (globe icon + dropdown in nav bar) — removed entirely
- Mobile menu continent section — removed
- The ContinentSelector JS hook — replaced by new widget hook
- The ContinentPrompt JS hook — replaced by contextual modal logic

#### What stays

- ContinentScope on_mount hook — still reads localStorage via connect params, still assigns continent_code/continent_name to socket
- localStorage key (`gf_continent`) — same persistence mechanism
- Query filtering in Search, ID tool — same context function calls
- Explore gets continent filtering added (currently unscoped)

### Stream 3: Data Sourcing — COMPLETE (by design)
WCVP pipeline exists. Admins add hosts as needed via WCVP lookup during entry. No pre-population required.

### Stream 4: Branding/Messaging Updates
Update site copy, about page, guides to reflect global scope. No longer position as a North American resource.

## Dependencies

- Stream 0 (b99b) → Stream 1 → Stream 2 (tiles) → Stream 3 (map JS)
- Stream 4 (branding) can parallel Stream 2

## Not In Scope

User accounts, UI localization, bulk data import.

## Territory Reference

Detailed Natural Earth investigation for 60+ overseas territories documented in docs/investigations/20260223-territory-boundary-extraction.md. Covers extraction methods, tricky mappings (BES→NLY, SJM→NSV), and multi-feature territories.

## Resolved Questions

| Question | Decision |
|----------|----------|
| Continent grouping | 8 continents as-is, no grouping |
| First-visit experience | Contextual modal on first scoped page visit |
| Map default view (no data) | Entire world |
| Scoping indicator | Per-page widget strip, not header selector |
| Non-sticky override | Temporary, discarded on navigation |
| Saving override | Explicit "Set as default" action required |
