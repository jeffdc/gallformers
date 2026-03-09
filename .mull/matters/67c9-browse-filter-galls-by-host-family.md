---
status: raw
created: 2026-03-04
updated: 2026-03-08
epic: identification
relates: [85c0, 53cb]
---

# Browse/filter galls by host family

## Survey Feedback (2026-03-04)

"Currently can only identify galls by host species or genus, but sometimes it would be nice to view galls by host family, especially for plant taxa that are difficult to ID or when necessary characters for a precise host ID are lacking when a gall is observed (eg: this plant is in the mint family but isn't blooming so the precise ID is ambiguous)"

## Use Case

Field observers often can't ID a host plant to species or genus (e.g., not blooming, lacking key characters). They CAN usually ID to family. Currently there's no way to browse galls at that level.

## Data Analysis (2026-03-08)

### Result set sizes by host family (top 10)

| Family | Gall count |
|--------|-----------|
| Fagaceae | 1,403 |
| Asteraceae | 590 |
| Salicaceae | 219 |
| Rosaceae | 206 |
| Juglandaceae | 132 |
| Fabaceae | 98 |
| Ericaceae | 82 |
| Pinaceae | 65 |
| Cupressaceae | 54 |
| Betulaceae | 53 |

For comparison, Quercus alone is 1,372 — so Fagaceae is barely worse than the existing worst case. Most families are under 100.

### Large result sets are already broken

Quercus today loads ~1,400 results with all images. It's slow and useless for ID. Adding family filtering doesn't create a new problem — it exposes an existing one.

**Approach:** Paginate at ~100/page. When results are large, show a message nudging users to add more filters. Fixes the existing Quercus problem too.

## Fix: `description` field overload

The `taxonomy.description` field is overloaded on families. For genera/sections it stores common names ("Maple", "Birch"). For gall-inducer families it also stores common names ("Wasp", "Mite", "Moth"). But for plant families it stores the literal "Plant" — used as a type discriminator in queries, not a common name.

Every query only checks `== "Plant"` or `!= "Plant"`. The specific inducer types are never queried — they're just displayed as common names, same as genera.

### The fix

1. **Add `is_plant` boolean to taxonomy** — migration, default false
2. **Backfill** from `description = 'Plant'` (and `'Plant (gall forming)'`)
3. **Update 6 query sites** to use `is_plant` instead of description checks:
   - `plants.ex:66` — `WHERE f.description = 'Plant'`
   - `galls.ex:102` — `WHERE f.description != 'Plant'`
   - `tree.ex:100` — `if description != "Plant"` (Unknown genus creation)
   - `tree.ex:848-849` — `list_families_for_select` plant/gall filter
   - `tree.ex:882` — genera-for-select plant filter
4. **Replace "Plant" descriptions** with actual common names (Fagaceae → "Oaks & Beeches", Rosaceae → "Roses", etc.)
5. Inducer family descriptions stay as-is — already correct common names

## Implementation pieces

1. Fix `description` overload (above)
2. Add family to the host filter dropdown on the ID page — extend the existing genus/section typeahead. Common names are critical for discoverability ("oak" → Fagaceae)
3. Paginate large result sets — ~100/page with guidance to add more filters. Fixes the existing Quercus problem too

