---
status: raw
created: 2026-11-05
updated: 2026-11-05
epic: identification
relates: [bc0d, b5bd]
---

# ID tool: rethink region handling (and the known-places discrepancy)

Pinned by Jeff on 2026-11-05: the ID tool needs a more substantial change in how it handles regions. Come back to it after the design work (matter bc0d).

## The discrepancy we have now

On the design-system branch, Browse by place (`/places`) and the place page (`/place/:code`) count and list the Galls **known** in a place:
- Stored in `gall_index.known_place_ids`, computed by `PotentialRange.known_for_galls/1`.
- A Gall counts where its Hosts are native, or where a Host is introduced and the Gall itself is recorded in that country (a current recorded-occurrence Fact in the country or one of its subdivisions).
- A Gall with no range data is known nowhere.

The ID tool's region filter (`Identify` `:place_codes`) still uses the **potential range** (`gall_index.place_ids`):
- Hosts' native and introduced ranges, as decided on 2026-10-25 (b5bd).
- Plus every Gall with no range data, in every region (`everywhere`).

So the two can disagree. For example, a North American oak gall whose only host, red oak, is planted in Europe appears for Europe in the ID tool but not on the Europe place page.

Jeff, 2026-11-05: counting introduced ranges was "wildly inaccurate"; "if a plant is introduced AND the gall is shown to be in the country then it should count"; "if the data is not present … the count is 0".

## Numbers (taxogall, 2026-11-05)

| Continent | Potential range | Known places |
|---|---|---|
| North America | 3,663 | 3,486 |
| Europe | 1,577 | 467 |
| Asia | 1,161 | 516 |
| South America | 756 | 336 |
| Africa | 715 | 405 |
| Oceania | 707 | 88 |
| Caribbean | 613 | 279 |
| Central America | 551 | 421 |

Only 4 recorded-occurrence Facts exist (for one Gall), so introduced ranges almost never count yet.

## To decide

- How the ID tool should treat regions: known places, the potential range, or something else.
- What to do with Galls that have no range data.
- How to show uncertainty.
- Whether the potential range keeps introduced ranges at all (this would revisit the b5bd 2026-10-25 decision and 8567 rule 10).

## Related

- bc0d: the design system, where known places were built.
- b5bd: the range migration decisions.
- 8567: the domain design, rule 10.
- 3272: Host-range proposals from recorded occurrences.
