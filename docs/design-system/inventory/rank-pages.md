# Inventory: the higher-taxon (rank) pages

The behavior contract for the public family, intermediate-rank, genus and section pages, taken from the code on 2026-11-05 (design-system branch). A redesign may change how they look. It must keep every behavior listed here unless a change is explicitly approved and recorded below. Line references: `G` is `lib/gallformers_web/live/genus_live.ex`, `F` `family_live.ex`, `S` `section_live.ex`, `I` `intermediate_live.ex` (same directory), `RP` `lib/gallformers_web/rank_page.ex`, `RPC` `lib/gallformers_web/components/rank_page_components.ex`, `DDC` `lib/gallformers_web/components/data_display_components.ex`, `TB` `lib/gallformers/taxa/read_models/browse.ex`, `CB` `lib/gallformers/catalog/read_models/browse.ex`. The target layouts are in `docs/design-system/patterns.md` ("Rank pages", "Plant pages") with dev mockups at `/dev/mockups/genus/:name`, `/dev/mockups/taxon/:rank/:name`, `/dev/mockups/plant-genus/:name`, `/dev/mockups/plant-taxon/:rank/:name` (router.ex:335-338).

## Findings

- **Nothing is in the URL but the name and the genus page's `?family=`.** No page defines `handle_params`; search, sort, related-genus filter and the filter panel's open state are socket assigns, lost on reload and not shareable. No pagination anywhere: every row renders.
- **Not found is a 200, not a 404.** An unknown name renders a red box ("Genus not found", "Family not found", "Section not found", "Taxonomy not found") with `page_noindex: true` and title "Not Found"/"Genus Not Found"/"Section Not Found" (G:46-58, F:49-67, S:277-288, I:69-88). Matter 803b's Task 6 planned "unknown name → 404"; the code doesn't. The red box uses Tailwind palette classes (`bg-red-50 … text-red-700`).
- **Old numeric URLs redirect with a 302, not a 301.** `/genus/33` is `push_navigate(replace: true)` from mount (RP:40-49, G:31-33), so the dead render answers 302 (the comment at `plugs/legacy_entity_redirect.ex:12` says so). `taxonomy_redirect_test.exs`'s moduledoc claims 301; only `/taxonomy/:id` (RedirectController:43-52) is a real 301. The redirect follows the crosswalk to **any** rank: `/section/30` would land on `/family/Cynipidae`. Every all-digit name is treated as an ID (`TaxonomyURL.numeric?`), so a taxon named with digits only is unreachable. Unlike the plug, there is no bigint bound: a 20-digit number likely raises in Postgrex (not verified).
- **Lookup is exact and accepted-name only** (`Taxa.get_by_name/2`, TB:33-42): case-sensitive (`/genus/andricus` is not found), and a synonym in the URL is not found rather than redirected.
- **Duplicate names:** only the genus page disambiguates. Family, section and intermediate pages silently take the lowest ID (`[taxon | _]`, F:22, S:273, I:34).
- **Disambiguation dead end:** a genus with no family in its lineage is offered as "in Family Unknown" linking to `?family=Unknown`, which matches nothing and shows the same disambiguation again (G:62-66, 81, 258).
- **The "Hosts" column on family and intermediate tables is plants in the subtree, not Hosts used** (`Taxa.count_plants_under/1`, TB:100-116: Plantae taxa at species rank or below). On a gall-former family it is always 0; on a plant family "Galls" is 0 unless a plant induces galls (mistletoes). Tests pin both zeros (`Cynipinae subfamily 8 0`).
- **Children that have no page are plain text.** `TreeBuilder.rank_path/2` has pages only for family, subfamily, tribe, subtribe, genus, section (`taxa/tree_builder.ex:90-94`); a species or subgenus child (e.g. a species placed directly under a tribe) is shown unlinked, never linked to `/host/:id` or a Gall.
- **Breadcrumb links aren't URL-encoded** (`DDC:661, 676, 700, 729` interpolate the raw name), while `TaxonomyURL.public_path` encodes (`URI.encode`). Names with spaces or parentheses produce raw links in the breadcrumb. Breadcrumbs use `navigate` (live), table links use `href` (full page load).
- **`datacomplete` is never shown.** `gall_cards` carries it (catalog.ex:987-998) but `RP.gall_rows/1` drops it. No images, synonyms, notes, Sources or ranges on any rank page.
- **Section h1 is plain text** ("Section Lobatae (red oaks)", S:361-363) though `taxon_name` italicizes sections in the breadcrumb; the genus h1 goes through `taxon_name` (G:282-288). Family and intermediate names are upright plain text, correctly.
- **Wording:** genus `page_description` and the disambiguation count say "species" for the sum of Galls and plants (G:83, 108, 271). The genus Hosts section's related heading says "found on this host" for a whole genus (G:154). The genus footer says "Showing N" with no noun (G:488).
- **Crashes on crafted events:** `sort` with an unknown column has no matching clause; `filter_related_genus` calls `String.to_integer` on `id` (G:190). Harmless to real users.
- **Sortable headers are `<th phx-click>`** (F:149-184, I:177-212, RPC:286-295): not focusable, no `aria-sort`, mouse only. Arrows "↑"/"↓" are bare text.
- The genus page's breadcrumb renders an empty `div` for a genus with no family or intermediate above it (`from_lineage` finds the genus itself, so it isn't nil; G:114, 296-301).

## 1. Shared machinery

**Routes** (router.ex:222-232, `:public` live_session): `/family/:name` FamilyLive, `/genus/:name` GenusLive, `/section/:name` SectionLive, and IntermediateLive with `live_action` `:subfamily`, `:tribe`, `:subtribe`, `:infratribe`, `:supertribe`, `:infrafamily`. The last three are not in `Gallformers.Taxa.Rank.all/0`, so they always render "Taxonomy not found" (I:26-29; test intermediate_live_test:245). Related: `/taxonomy/:id` 301s through the crosswalk or 404s (RedirectController:43-52); `/host/:id` of an old "Genus spp" placeholder 301s to the genus page (`plugs/legacy_entity_redirect.ex:39-42`).

**Lookup** (`RP.lookup/2`, RP:40-49): digits only → `TaxonomyURL.legacy_path/1` (crosswalk kind `:taxonomy`, then the target's own rank and accepted name, taxonomy_url.ex:52-56) → `{:redirect, path}` or not found; otherwise `{:ok, Taxa.get_by_name(name, rank)}` (all matches, by ID).

**Inbound URL format** (`TaxonomyURL.public_path/1` → `TreeBuilder.rank_path/2`): `/#{rank}/#{URI.encode(name)}`. Built by the browse trees, search (`search_live.ex:263`), the sitemap (`sitemap_controller.ex:73`, `Taxa.list_rank_pages/0`: every accepted name at the six page ranks), admin taxonomy edit (`taxonomy_live/edit.ex:454`), and the breadcrumbs on Gall and Host pages.

**Description** (`RP.description/1`, RP:53-58): a taxon's common names in insertion order joined ", ", or nil. The migration turned old genus, section and intermediate descriptions ("Elms") into common names and dropped family descriptions (803b decision 7), so a family "description" is now only a common name if one was added.

**Head assigns** (root.html.heex:10-30): `page_title`, `page_description`, `page_url` (canonical, `TaxonomyURL.public_path`), `page_noindex`; `page_image` and `page_json_ld` always nil. The pages pass no `page_title` to `Layouts.app`, so they render their own h1.

**Admin edit link** (`RPC.admin_edit_link`, RPC:204-215): only when `Accounts.admin?(current_user)`; a pencil icon (`ph-pencil-simple`, h-5 w-5) linking with `href` to `/admin/taxonomy/:taxon_id`, `title="Edit in admin"`, no other accessible name. Beside the h1 on every page that found its taxon (not on disambiguation or not-found).

**Search box** (all four pages): `<form phx-change="search" phx-submit="search" id="{page}-search-form">` around `search_input` (FC:415-442; `type="search"`, magnifier icon, `aria-label` = placeholder) with `name="query"`, `phx-debounce="300"`, ids `genus-search`, `family-search`, `section-search`, `intermediate-search`. Enter submits the same event (no reload). Case-insensitive substring: rows match on name or their one common name (`RP.filter_rows/2`, RP:153-162); children on name, description (all common names) or rank word (`RP.filter_children/2`, RP:92-102). Whitespace is not trimmed; no word splitting.

**Sorting** (`RP.toggle_sort/3`, RP:122-124): clicking the current column flips direction; another column starts ascending. Default `:name` `:asc`. Rows (`RP.sort_rows/3`, RP:166-177): `name` (downcased), `common_name` (downcased; nil sorts as "zzz", so blanks last ascending and first descending), `count`. Children (`RP.sort_children/3`, RP:106-118): `name` (downcased), `type` (the rank word alphabetically, not taxonomic order), `gall_count`, `host_count`. Descending is `Enum.reverse` of the ascending sort, so ties reverse too. The active header shows " ↑"/" ↓".

**`RPC.species_table`** (RPC:225-272): `id` on the wrapper div; columns name (header `name_header`, default "Species Name"), "Common Name" (centered), `count_header` (centered, muted); each name links (`href`) to `url_prefix <> id` and renders with `taxon_name` at the default species rank; common name cell empty when nil. With `sort_by: nil` the headers are plain `<th>` and rows keep their given order. Class `gf-table` in a white bordered box; `th.sortable` hover styles in `assets/css/legacy.css:286-298`.

**Row data:** a Gall row is `%{id, name (name_override or name), common_name, count}` where `common_name` is the alphabetically first current `common_name` alias Fact and `count` the distinct current Hosts (`CB.add_gall_details/1`, CB:147-175); Galls come by name then ID (catalog.ex:987-998). A plant row is every Plantae taxon at species rank or below in the subtree (subspecies and varieties are their own rows), by accepted name, with its first common name by insertion order and the distinct Galls with a current `host_of` Fact on exactly that taxon (`TB.list_plants_under/1` TB:120-138, `CB.count_galls_for_hosts/1` CB:181-192). Note the two common-name orders differ (alphabetical for Galls, insertion order for plants).

**Breadcrumb** (`taxonomy_breadcrumb`, DDC:654-747, from `LineageBreadcrumb.from_lineage/1`): bold "Family:", each intermediate "Subfamily:", "Tribe:" … (rank capitalized), "Genus:" (italic via `taxon_name`, " - description" only when given; the lineage never gives one), "Section:" (italic); `|` separators; `navigate` links to `/family/`, `/{rank}/`, `/genus/`, `/section/` + raw name; text instead of a link when the entry has no id. Ranks between genus and section (subgenus) are never shown. Nil when the lineage holds none of these ranks, and then hidden.

## 2. Genus page (`/genus/:name`)

**Serves both** gall-former and plant genera, and both at once (803b Task 6: "a genus with both galls and Hosts shows both lists", e.g. mistletoes). It does not branch on kingdom: it builds three sections and drops the empty ones (G:128-170).

**Mount** (G:30-44): redirect, not found, one genus, or several.

- **Several genera** with the name: `?family=` (read in mount only) picks the one whose lineage's family has that accepted name (G:60-68). Otherwise the **disambiguation** view (G:70-99, 247-276): h1 "Genus *Name*", "This genus name exists under multiple families. Select the one you're looking for:", one card-link per genus to `/genus/#{URI.encode(name)}?family=#{URI.encode(family_name)}` (`navigate`) reading "*Name* in Family F (family common names)" and "N species" (Galls under it + plants under it). Title "Genus Name — Disambiguation", noindex, no canonical.
- **Found** (G:101-125): title "Genus Name", description "Name - A taxonomic genus documented on Gallformers with N species." (N = all rows of all sections), canonical `/genus/Name`, **noindex when N is 0** (inherited from 51b08a70's "empty Unknown genus" rule).

**Header** (G:278-302): h1 "Genus *Name (common names)*" (one `taxon_name` call, rank genus; the parenthetical is upright), the admin edit link, then the breadcrumb with family and intermediates only (`show_genus={false}`, no section).

**Body** (G:304-334): with N = 0, "No species found for this genus." (italic, muted) and no search box. Otherwise the search box (placeholder "Filter by name or common name...") above the sections, which it filters **all at once**; one shared `sort_by`/`sort_dir` drives every section's table.

**Sections**, in this order, each only when it has rows:

| key | h2 | rows | links | name / count headers | related filter |
|---|---|---|---|---|---|
| `galls` | "Galls (N)" | Galls whose current Inducer is the genus or anything in its subtree (species, sections, the genus itself for undescribed Galls; `Taxa.subtree_ids` + `RP.galls_of_inducers`) | `/gall/:id` | "Gall" / "Number of Hosts" | "Host genera used by this genus", label "host genus" (`CB.host_genera_of_galls/1`) |
| `hosts` | "Hosts (N)" | plants in the subtree (`RP.host_rows`) | `/host/:id` | "Species Name" / "Number of Galls" | "Gall-former genera found on this host", label "gall-former genus" (`CB.inducer_genera_on_hosts/1`) |
| `genus_host` | "Galls on the genus as a whole (N)" | Galls whose current Host is the genus taxon itself (today's "Genus spp."; not its sections or subgenera) | `/gall/:id` | "Gall" / "Number of Hosts" | none |

The h2 count is always the unfiltered total. Table ids `genus-galls`, `genus-hosts`, `genus-genus_host`. Under each table: "Filtering X of Y" when the search is non-empty or a related genus is selected, else "Showing X". When the filters leave a section empty: a grey box "No entries found matching "query"" (shown even when it's the related-genus filter, not the search, that emptied it), and the h2 and the related-genera control stay.

**Related-genera filter** (G:351-463; from 657ec340, rewritten on the new back-end):

- Data (CB:194-258): for Galls, the genus of each current Host (the Host itself when it is a genus); for plants, the genus of each Inducer of the Galls on them (only the section's plant rows, not the genus-as-Host Galls). A related taxon with no genus in its lineage is dropped. Each entry: `taxon_id`, `name`, `focal_ids` (the section's rows it covers, sorted), `association_count` (distinct Gall–Host pairs); sorted by name then ID.
- **Collapsed by default.** A full-width secondary button (`phx-click="toggle_related_genera"`, `phx-value-section={key}`, `aria-expanded="false"`, `aria-controls="related-genera-filters-{key}"`): arrows icon, the heading, a count pill (number of genera), "— filtered by *Genus*" when one is selected, "Show filters ⌄".
- **Expanded:** `card` `id="related-genera-filters-{key}"`, title "Heading (N)", a ghost "Hide ⌃" action (same event, `aria-expanded="true"`). Text "Select a genus to filter the list below. Counts show how many entries in *Genus* have that association." A `role="group"` with `aria-label="Filter by {label}"` of pill buttons: "All {rows}" then one per genus (italic name, pill count = `length(focal_ids)`, `title="{association_count} associations"`); the selected one is `primary` with `aria-pressed="true"`, others `secondary`. `phx-click="filter_related_genus"`, `phx-value-section`, `phx-value-id` (`"all"` or the taxon ID). With a selection: "Showing entries associated with *Genus*. Clear filter" (ghost button, `id="all"`).
- `filter_related_genus` also opens the panel (G:189-196). Collapsing keeps the selection applied. Each section has its own selection and open state (maps keyed by section key). The selection keeps rows whose ID is in the genus's `focal_ids`, then the search applies (G:217-234).

## 3. Family page (`/family/:name`)

**Serves both** plant and gall-former families, identically; nothing branches on kingdom. Duplicate names take the lowest ID.

**Assigns** (F:26-47): title is the bare name (no "Family"), description "Name - A taxonomic family documented on Gallformers.", canonical `/family/Name`, never noindex when found (even with no children).

**Header** (F:100-118): h1 with a smaller muted "Family:" then the name (plain, upright), admin edit link; a paragraph of the common names when any. **No breadcrumb** (nothing above family is shown).

**Children** (F:120-229; `RP.children/1`, RP:66-83, from `Taxa.children_with_ranks/1`): the taxa directly under the family (genera and intermediate ranks; any rank), by name. h2 "Children (N)", the search box (placeholder "Filter by name, type, or description..."), then a `gf-table` with sortable columns **Name** (link `href` to the child's page when it has one, `taxon_name` with the child's rank so genera are italic, then " (common names)" small and muted), **Type** (the lowercase rank word, centered), **Galls** (Galls whose current Inducer is in the child's subtree, distinct; `CB.count_galls_under/1`, CB:116-137), **Hosts** (plants in the subtree, see Findings). Footer "Filtering X of N children" / "Showing X children". No match: "No children found matching "query"". No children: "No children found." (italic) and no search box, even when Galls are placed at the family.

**Galls placed in this family** (F:231-243): only when Galls have the family itself as current Inducer (undescribed Galls placed at family; not the subtree). h2 "Galls placed in this family (N)", `species_table` `id="family-galls"`, "Gall" / "Number of Hosts", **unsortable** (`sort_by` nil), by name, **not filtered by the search box**.

Events: `search` (filters children only), `sort` with `column` in `name type gall_count host_count` (F:69-89).

## 4. Intermediate-rank pages (`/subfamily/:name`, `/tribe/:name`, `/subtribe/:name`; dead: `/infratribe/`, `/supertribe/`, `/infrafamily/`)

The family page's layout plus a breadcrumb; **serves both** kingdoms identically (in practice gall-former subfamilies and tribes). The rank comes from `live_action`; the name must have that rank exactly (`/tribe/Cynipinae`, a subfamily, is "Taxonomy not found").

- Assigns (I:38-67): title "Tribe: Cynipini" (rank capitalized), description "Name - A taxonomic tribe documented on Gallformers.", canonical `/tribe/Name`, never noindex when found.
- Header (I:121-146): h1 muted "Tribe:" + plain name, admin edit link, common-names paragraph, then the breadcrumb of the ancestors (itself excluded, I:42-46): family and higher intermediates, linked.
- Children table, search (`id="intermediate-search-form"`), footer, empty states: as the family page (I:148-257).
- "Galls placed in this tribe (N)" (rank lowercased), `id="intermediate-galls"`, unsortable, not searched (I:259-271).

## 5. Section page (`/section/:name`)

**Plants only in effect:** it lists `RP.host_rows/1` (Plantae taxa at species rank or below under the section). A gall-former section (if one existed) would show "No species found for this section."; Galls whose Inducer is a section appear only on the genus page; Galls whose Host is the section itself appear nowhere. Duplicate names take the lowest ID.

- Assigns (S:290-317): title "Section Name", description "Name - A taxonomic section documented on Gallformers with N species.", canonical `/section/Name`, never noindex when found (even when empty).
- Header (S:357-377): h1 "Section Name (common names)" as plain text (not italic), admin edit link; breadcrumb of the ancestors (itself excluded): Family, intermediates, Genus (italic, linked). Subgenus omitted.
- Body (S:379-425): h2 "Species (N)", search (placeholder "Filter by species or common name...", `id="section-search-form"`), `species_table` `id="section-species"`, "Species Name" / "Common Name" / "Number of Galls", links `/host/:id`, sortable (`name common_name count`). Footer "Filtering X of N species" / "Showing X species". No match: "No species found matching "query"". Empty: "No species found for this section." (no search box).

## 6. Client-side behavior

No JS hooks, no `phx-update="ignore"`, no localStorage, no region scope. Everything is a server round trip: `search` (300 ms debounce), `sort`, `toggle_related_genera`, `filter_related_genus`. Table links are full page loads (`href`); breadcrumb and disambiguation links are live navigation.

## 7. Tests (selectors and texts asserted)

- `genus_live_test.exs`: `page_title` "Genus Andricus"; breadcrumb `a[href="/family/Cynipidae"]`, `a[href="/subfamily/Cynipinae"]`, `a[href="/tribe/Cynipini"]`; "Galls (4)" and no "Hosts ("; `a[href="/gall/{200,300,301,304}"]`; `tbody tr` matching `Andricus seedii \(agamic\)\s+seed oak apple\s+1` and `Andricus n-densiflorus-seed-gall\s+2`; `#genus-search-form` `render_change(%{"query" => "oak apple"})`; "Genus not found" + title "Not Found"; `/genus/33` live_redirect to `/genus/Andricus`; host genus: "Hosts (1)", `a[href="/host/10"]`, `tbody tr` `Notholithocarpus densiflorus\s+tanoak\s+5`, "Galls on the genus as a whole (1)", `a[href="/gall/304"]`, no "Galls (1)"; "Notholithocarpus (Tanoaks)"; related: "Host genera used by this genus" / "Gall-former genera found on this host", "Show filters", `#related-genera-filters-galls|hosts` absent then present, `button[phx-click='toggle_related_genera'][phx-value-section='galls|hosts']`, `button[phx-value-id='all']`, `button[phx-click='filter_related_genus'][phx-value-id='<id>']`; both lists for a mistletoe genus; disambiguation: "This genus name exists under multiple families", `a[href="/genus/Twinfixta?family=Twinfixtidae"]`, title "Disambiguation", `?family=Twinfixtaceae` resolves.
- `family_live_test.exs`: "Family:", title contains the name, "Children (1)", "Galls", "Hosts"; row words `["Cynipinae", "subfamily", "8", "0"]` and `["Notholithocarpus", "(Tanoaks)", "genus", "0", "1"]` (the row's text, tags stripped: column order Name, description, Type, Galls, Hosts); `a[href="/subfamily/Cynipinae"]`; "Galls placed in this family (1)"; `/family/30` → `/family/Cynipidae`; "Family not found" + "Not Found".
- `intermediate_live_test.exs`: "Subfamily", title "Subfamily: Cynipinae"; breadcrumb links family and subfamily but not itself; `tbody tr` `Cynipini\s+tribe\s+8\s+0`, `Andricus\s+genus\s+4\s+0`; `a[href="/tribe/Cynipini"]`; `/tribe/32` → `/tribe/Cynipini`; "Taxonomy not found" for wrong rank, unknown name, and `/infratribe/`.
- `section_live_test.exs`: "Section Sectionfixtlobatae (red fixture oaks)", title "Section …", breadcrumb `a[href="/family/…"]`, `a[href="/genus/…"]`; "Species (2)", `a[href="/host/:id"]`, `tbody tr` `rubra\s+northern fixture oak\s+1` and `velutina\s+0`; `#section-search-form` filter; "Section not found".
- `taxonomy_redirect_test.exs`: numeric redirects, "not found"/"Not Found" for unknown numeric IDs, `/taxonomy/:id` 301s and 404s.

## Hard-won lessons

1. Names, not IDs, in rank URLs, with old numeric URLs redirected through the crosswalk (9a14daf4; the crosswalk replaced the old table in 67378c93). Placeholder "Unknown" genera redirect to their family (`/taxonomy/35`).
2. Names are URI-encoded in built URLs because real names have spaces and parentheses ("Santalaceae (gall)") — e9592ed3. (The breadcrumb never got this.)
3. Genus names repeat across families (Phoradendron under Santalaceae and "Santalaceae (gall)"); the disambiguation page and `?family=` exist for that — e9592ed3. Now the two are in different kingdoms.
4. A genus can have both Galls and plants; the page must not decide "gall genus or host genus" from the first species (the old taxoncode heuristic, 803b) — it shows every non-empty list.
5. Undescribed Galls hang on the genus (or family, or tribe) as Inducer: the genus list takes the whole subtree including the genus; the family and intermediate pages list "Galls placed in this …" separately.
6. "Genus spp." placeholder Hosts became the genus taxon as Host; their Galls are the "Galls on the genus as a whole" list, and old placeholder `/host/:id` URLs 301 to the genus page (41ad2d39, 67378c93).
7. Empty genus pages are noindexed (51b08a70).
8. The family page replaced its tree with the sortable table that intermediates use (eca47e83).
9. The related-genera panel is collapsed by default and says what it is filtered by while collapsed (657ec340 and its review rounds).
10. Common names come from the old descriptions; empty descriptions must not render "()" (bf4ef982).
11. `taxon_name` renders a name's italic and upright parts as separate elements, so tests of a name followed by a qualifier ("Andricus seedii (agamic)") assert on the page's text (`LazyHTML.text`), not raw HTML (genus_live_test, uncommitted on this branch).

## Must preserve

- Routes `/family/:name`, `/genus/:name`, `/section/:name`, `/subfamily/:name`, `/tribe/:name`, `/subtribe/:name` (and the three dead intermediate routes keep answering, not crashing); lookup by exact accepted name and the route's rank.
- Numeric names redirect through the crosswalk (`kind :taxonomy`) to the target's own rank page with `replace: true`; unknown IDs are not found. `/taxonomy/:id` 301/404 and the placeholder `/host/:id` 301 stay.
- Not found shows the page's message ("Genus not found", "Family not found", "Section not found", "Taxonomy not found"), title containing "Not Found", noindex (decide whether to make it a real 404).
- Genus disambiguation: one option per genus with its family name, family common names and count; `?family=` (by family accepted name) picks one; title "— Disambiguation"; noindex.
- Titles, descriptions and canonicals as listed; genus noindex when empty.
- Admin-only edit link to `/admin/taxonomy/:id` on every found page.
- Common names shown with the name ("Genus X (Tanoaks)", "Section X (red oaks)") or as the family/intermediate paragraph; nothing shown when there are none.
- Breadcrumbs: family and intermediates on genus and intermediate pages, plus genus on section pages; linked by name; the page's own taxon excluded; hidden when empty.
- Genus: the three lists in order, each only when non-empty, with their headings, link targets and count columns (Hosts per Gall, Galls per plant); undescribed Galls on the genus included; subspecies and varieties as their own plant rows.
- Genus related-genera filters per list: collapsed by default; heading, genus count, "filtered by" while collapsed; All + one pill per genus with its row count and association count; single selection, Clear filter; filter combines with the search; selection survives collapsing.
- Family and intermediate: children by name with rank, common names, Galls in subtree and plants in subtree; links only for ranks with pages; "Galls placed in this {rank}" list of Galls at the taxon itself.
- Section: its plants with common name and Galls count, linked to `/host/:id`.
- Search: 300 ms, case-insensitive substring over name and common name (children also over rank word and all common names); Enter does nothing extra; genus search spans every list; family/intermediate search leaves the placed-Galls list alone.
- Sorting: click toggles, new column ascending, default name ascending; blank common names last ascending; counts numeric; one sort state for all genus lists.
- Counts: h2 totals unfiltered; "Filtering X of Y" / "Showing X" footers; the per-page empty and no-match messages.
- The test selectors above (`#genus-search-form`, `#section-search-form`, `#related-genera-filters-{galls,hosts}`, the `toggle_related_genera` / `filter_related_genus` buttons with `phx-value-section` / `phx-value-id`, `tbody tr` rows with name, common name, count in that order) or their replacements in updated tests.

## Approved changes
- **Rank pages on the design system** (Jeff approved the higher-taxa design, tabs and pagination, and the plant genus and Fagaceae pages, 2026-11-05). Kept: the routes and actions; lookup, numeric redirects (`replace: true`), not-found messages and titles (still a 200), genus disambiguation and `?family=`; titles, descriptions, canonicals and noindex rules; the admin edit link (now an "Edit" button); common names; breadcrumbs of the ancestors with pages, now URL-encoded (`RankPage.crumbs/1`); the genus page's lists (Galls, plants, Galls on the genus as a whole), each only when it has rows; Host counts per Gall and Gall counts per plant; links on every name (`<a>`, live navigation); the search form ids, `query`, 300 ms, and one search over every list; click-to-sort with new columns ascending (counts start descending on the children list) and one sort state for the page; "N of M" counts while narrowed; the empty messages. Changes:
  - Galls show as `gall_card` photos or a table (`GallformersWeb.RankGalls`), 48 or 50 a page; over 150 open as a table.
  - The Galls' related-genera filter became the Host genus facet, alongside plant part, form and season. It allows several choices, and it is offered only from 8 Galls up and only with two or more options (round-2 approval).
  - The plants' related-genera filter moved to the rail: each Gallformer genus filters the Species table, with "Show all plants" to clear; the collapsed panel and its "Show filters" are gone.
  - "Galls on the genus as a whole" is a rail panel (link and Host count, narrowed by the name filter) instead of a table.
  - Family and intermediate pages: one LiveView (`/family` now routes to `IntermediateLive`, `:family`). The Galls tab lists every Gall in the subtree, not only those placed at the taxon (those show as Undescribed). The taxa within are a tab, `?tab=within`: for Gallformers a column list with Galls (sort "Most galls" / "Name"; the always-zero Hosts column is gone), for plants a table of name, common name, species and the Galls on each (Host counts from `Catalog.host_gall_counts/0`; before, Galls induced, almost always 0). The name filter applies to both tabs.
  - The section h1 is italic; plant genus and section pages have "Identify a gall on …" (`/id?g=`).
  - Sortable headers are `data_table` buttons: focusable, with `aria-sort`.
