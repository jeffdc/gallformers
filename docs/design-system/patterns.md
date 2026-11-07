# Patterns

How components combine into pages, and how common interactions behave. Every page is one of these templates; a page that fits none is a sign to talk before building.

## Page templates

### Detail page (public)

One thing in depth: a Gall, a Host, a Source, a taxon, a place.

```
site_shell
  page_header      crumbs (lineage) · title · chips · meta line · actions
  main column                         rail (420px)
    section …                           photo_viewer
    section …                           range_map (card)
                                        also known as · see also (see_also) · created/updated
  footer
```

- The first screen shows the name, what identifies the thing (photo, traits, Hosts) and the start of the evidence (Sources).
- **Host page** (built, `HostLive`): crumbs (sections as "sect. X"), the italic name, rank, Host plant, Complete; "Identify a gall on …"; the Galls on it as `rank_galls` (admins get each Gall's range-exclusions edit link via `edit_path`); a pointer to Galls on the genus as a whole. Rail: photos (if any), the range card with Enlarge, "Also known as", See also, created/updated. Edit mode (`?edit`, curators; the `edit_toggle` replaces the old "Edit in admin" link): the Editing notice with its `edit_scope`s (lineage, common names, WCVP link and photos ↗ the taxonomy admin); an Editorial `panel` (`HostLive.Editor`) of rows, each label beside its value and actions (as the Gall page's Traits): the name (Rename…), the synonyms (each with Take out; Add a synonym opens its fields, Sensu and Based on behind an "optional" disclosure), the range (a summary, "12 places, 2 introduced", and Range…, which opens the Host range editor in a dialog), each with "Based on" and into the tray; delete and merge at the foot of the rail.
- **Species page** (built, `SpeciesLive`, `/species/:id`; matter `803b`): an organism that induces Galls (a non-plant taxon at species rank or below; a plant's ID goes to its Host page, a higher taxon's to its rank page, a merged taxon's follows its redirect). Crumbs (its lineage, to the rank pages), the italic name with its authorship upright, its rank, Gallformer; its common names. Its Galls, every generation, as `rank_galls`; Taxonomy: `taxonomic_position` (placement and name with the Source deciding each, the papers that disagree), its synonyms, and its split and lump history (Split into / Split from with the Source, Merged into it with the date); Sources citing it or its Galls in a `data_table` (year, Source, what it covers). Rail: its Galls' ranges together on one range card with Enlarge ("Where it occurs"), See also, created/updated. Edit mode (`?edit`, curators): the Editing notice with its `edit_scope`s (its Galls follow from each Gall's Inducer, ✎ on each card to the Gall in Edit mode; photos and deletion ↗ the taxonomy admin); a Names and placement `panel` (`SpeciesLive.Editor`) of rows (Name with Rename…, Placed under with Move…, Synonyms and Common names each with Take out… and Add), every change asking "Based on which Source?" (`BasisPicker`) and made as that Source's statement, not through the tray. The Gall page's breadcrumb ends with its Inducer, linked here; search and the palette list Gallformers.
- **Delete and merge** (built, `GallformersWeb.RecordRemoval`; matter ec2c, "Deletes"): a `:danger` panel at the foot of the rail in Edit mode (Gall and plant pages) and on the taxonomy admin's page. Delete… works out the impact when asked: what blocks it (each blocker with what to do instead) in a `dialog`, or the impact itemised in `dangerous_delete_modal`. Merge into another… picks the record to keep (`typeahead`), previews the merge (alias, redirects, photos, note, each Fact and what happens to it in a `data_table`, what blocks it) and asks for the absorbed name typed. Merged Galls' old IDs and codes, and merged plants' IDs, redirect (301).
- **Source page** (built, `SourceLive`): title, kind, Retracted, Complete; authors, year, DOI, ISBN, license; Original; a retraction notice; the citation in serif; the Galls it covers in three columns (60 a page); what it says; the dates. Photos in a rail only when it has some.
- **Gall page** (built, `GallLive`): a summary line under the title (other generation, common name, season, location, form); Hosts; Traits ("N of 11 recorded", one "Not recorded" line); the Gallformers ID Notes pinned in full; Sources by year (Oldest/Newest first), each opening in the reader dialog, which a `?source=` link opens directly; then Facts (everyone; `facts_view` as on the Source page, `Import.facts_for_gall/1`): by category, each Fact with its standing and its Sources linked ("denied by" for a denial), the withdrawn and superseded ones collapsed under "History: 1 withdrawn, 1 superseded"; left out when the Gall has none. Rail: photos, the map card framed on the native range with Enlarge, "Also known as", "See also", created/updated. Gallformers notes are where non-Fact prose lives, so they are always pinned and visible when present. In Edit mode, Add from observation… is a button in the page header beside the Edit toggle (`GallformersWeb.ObservationIntake` in the Editor's dialog, the Gall given; from the palette, `/admin/observation`, the Gall is chosen, with "Open this Gall in Edit mode" once chosen): an iNaturalist observation read into proposals (the recorded occurrence, dated as seen; the Hosts it names), ticked as proposed, an "Add a host" `typeahead` for a Host the curator gives, added to the tray with the observation as evidence; its photos through the iNaturalist image import. The Editorial panel's foot holds Photos…, ID note… and Range exclusions….
- **Article** (built, `ArticleController`): crumbs, title, By · Published · Updated · Topics, Edit for admins; a Draft notice; the text in `prose` at 18px in a `max-w-text` column; Related articles in the rail. The Articles list is topic chips, the newest article featured, the rest as `article_card`s in a grid, and More to read (`link_tile`s). The Keys list is a reading list: title, one muted line, a two-line preview.
- **Key** (built, `KeyLive`): title, Covers · By · Couplets · Source, PDF buttons; every couplet as a `key_couplet`; the path as a `key_path` panel in the rail on wide screens and a bar under the header on narrow ones.
- **Analytics** (built, `AnalyticsLive`): title and the privacy link; the period as `chip_nav` (`?range=`); totals as `stat`s; Each day (`bar_chart`, longer periods); Top pages; referrers beside devices and browsers (`share_list`).
- On phones: header, photo, then the main column, then the rest of the rail.
- Empty fields don't take space: missing traits collapse into one "Not recorded" line; a section with nothing to show is left out unless its absence matters to the reader.

### Collection page (public)

Many things to browse or narrow down. Two shapes:

**Identification** (the ID tool):

```
site_shell
  page_header       title
  pickers panel     Host species · or Host genus/section · region — always visible
  filter row        filter_select × 5, More filters (one Filters button on phones)
  toolbar           count · active filter chips · Clear all · name filter
  gf-photo-grid     gall_card ≥ 280px
```

- Changing the Host is the most frequent action: the picker is never behind a click.
- Photos are the most important thing on the page. They stay at least 280px; a wider screen adds columns.

**Home page:** the ID tool's first step (the real Host typeahead), the numbers, and **a gall to meet** as the page's centerpiece: a large photo shown whole (letterboxed, never cropped: many images are plates and drawings), its name and credit, "See this gall" and "Show me another". Below it, "Start from the plant" and "Browse by what causes them" as compact two-column lists of `category_tile` rows (not photo walls), then "Recently changed" (`Sources.list_recently_changed/1` in a `data_table`). Built: `GallformersWeb.HomeLive`.

**Rank pages** (a genus or family of Gallformers):

```
site_shell
  page_header       crumbs (lineage) · title · rank chip · actions
  stats             Galls · Host genera · Undescribed · With photos
  facets (left)     facet_group (only when there are 8+ Galls)
  section Galls     Photos | Table switch
                    gf-photo-grid (sm) of gall_card, each leading with "N hosts"
                    — or — data_table: Gall · Common name · Hosts (sortable) · Plant part · Season
```

- The count of Hosts per Gall (or Galls per Host) is one of the page's most useful facts, especially at higher ranks. Every view shows it; the table sorts by it.
- Above genus, the Galls and the taxa within the rank are **tabs** (Galls · Genera, or "Within it" when ranks are mixed), one at a time. The children tab is a dense multi-column list with gall counts, not a wide table.
- Long lists **paginate**: 48 photos or 50 rows a page (`pagination`); sorting, filtering or switching view returns to page 1. A taxon with more than 150 Galls opens on the Table view.
- The tab is in the URL (`?tab=galls`, `?tab=within`, through `tab_nav` patch links). One name filter (beside the stats) narrows every list on the page, and one sort orders every table. Headings count what is shown, "N of M" while narrowed.
- Built: `GenusLive` (Gallformer and plant genera, and genera that are both), `IntermediateLive` (family, subfamily, tribe, subtribe; a plant family shows its genera with species and Galls on them), `SectionLive`. Parts in `GallformersWeb.RankPageComponents` (`rank_galls`, `plant_table`, `inducer_genera_panel`, `galls_on_panel`, `children_list`), logic in `GallformersWeb.RankGalls` and `GallformersWeb.RankPage`.

**Plant pages** (a genus or family of Hosts): Hosts rarely have photos and trait filters don't apply.

```
site_shell
  page_header       crumbs · title · Genus · Host plants · common name · Identify a gall on …
  stats             Galls · Species · Species with galls · Gallformer genera
  main              section Species: data_table (Species · Common name · Galls, sorted by Galls) with a name filter
  rail (narrow)     panel: Gallformer genera on it, with counts (each filters the Species table) · panel: Galls on the genus as a whole
```

**Browse**: `page_header` "Browse galls", then `tab_nav`: By what causes them (`/galls`: inducer families in their plain-language groups, one `section` per group with jump links, and an "Undescribed galls only" checkbox) · By host plant (`/hosts`: plant families, most galled first) · By place. A toolbar holds the name filter ("Filter by name…"), "Show all galls" and "Collapse all". Each family is a `family_card`, which opens in place to its genera and their Galls or plants. By place (`/places`): continent tiles with Gall counts, then the chosen continent's countries in a sortable `data_table` with each country's busiest states or provinces; the filter searches every continent. Built: `GallsBrowseLive`, `HostsBrowseLive`, `PlacesBrowseLive`.

**Place page** (`/place/:code`): `page_header` (crumbs Places › ancestors · name · type chip · Code), stats (Galls may occur here · sub-places), the range map (large, a click opens a sub-place) with a narrow rail of the sub-places and their Gall counts (scrolling within the map's height), then `rank_galls` "Galls that may occur here" (Galls with no range data left out, as in Browse by place). Built: `PlaceLive`.

**Search** (built, `SearchLive`): `page_header`, the query field (`?q=`, debounced), the region bar, a `tab_nav` of the result types with counts (`?type=`; All first), then one `data_table` of the results (an icon and type; the name with its aliases and a second line: a Gall's photo, Hosts, plant part and season; a plant's Gall count; a taxon's common names and Galls; a glossary term's definition; a place's kind), by relevance, sortable by type and name, 50 a page; ↑/↓ move the `active` row and Enter opens it. The second lines are read for the page shown only. Empty and no-results states are `empty_state`s; with a region filter, "All Regions" is the way back.

**Glossary** (built, `GlossaryLive`): `page_header`, a filter, and a `data_table` (word with an edit link for signed-in users, the definition `full` with other terms linked, numbered references), each row anchored by its lowercase word for `/glossary#word` links.

**Error pages** (built, `ErrorHTML.error_page/1`): standalone documents (no site shell), the stylesheet, the wordmark home, the status, a heading, what happened, and Go Back / Go Home / the ID tool.

### Admin dashboard and Changes

The admin's front page (built, `Admin.DashboardLive`) leads with work: **Sources to review** (the review index's rows: Source, year, to decide, status; with rows for the Gall rename proposals and the questions merges left, `/admin/review/merges`), then **Your changes** (the curator's tray: each change, the Gall or plant it is on, linked to its page in Edit mode, and whether it is in the tray or waiting to apply), then **Recent changes**, the latest eight curator changes (`Catalog.changes/1`) as `change_entry`s, with "All changes". The rail: Create, and Site for a superadmin (Find is gone: the command palette finds, and Galls and plants are edited on their pages). The **Changes page** (built, `Admin.ChangesLive`, `/admin/changes`) lists every curator change with a search (a Gall, taxon, Source or value), Curator and Kind selects and a Period (7 days, 30 days, Everything), all in the URL. Both render the same `change_entry`, so View and Edit are on every Gall, taxon and Fact. Mistakes are corrected through Edit (the normal edit process, matter ec2c); there is no flag or discussion feature (the team talks on Discord, matter 15db).

### Admin list

```
admin_shell
  page_header      title · count · primary action (if any)
  toolbar          search_field · filters · count
  data_table       one row per record; row click opens it
  pagination
```

### Admin edit page

```
admin_shell
  page_header      crumbs · title · chips · meta (created, updated, save state) · actions (View public page ↗)
  main column (max-w-form)              rail (300px)
    section · field rows …               panels: facts about the record, what refers to it, danger zone
```

- Sections are headings on rules, with `field`s in the `:row` layout.
- Facts about the record (rank, kingdom, children, where it's used, why it can't be deleted) go in the rail, not in the form.
- Destructive actions live in a `:danger` panel at the bottom of the rail and confirm through a `dialog`.

### Review step

The import review (matters `6611`, `f14c`): a Source's questions, grouped by kind, one compact row each.

```
admin_shell
  page_header      Source title · citation · kind chip · progress
  step bar (sticky, 40px)
  section per kind of question         count · what leaving it open means · bulk accept
    row: what the Source wrote → the proposed answer · Accept · expand for evidence and choices
```

- The proposed answer is the default and takes one action to accept.
- Evidence (the Source's own words in serif, candidates, links) appears on expand, not before.

## Interaction patterns

### Saving

Decided (matter ec2c, 2026-11-06): curators edit inline on the public pages with Edit on; every edit, Fact or editorial, collects in the curator's **change tray** (saved with their account, shown on every page while it holds changes) and is applied through Review and apply (a Facts preview for Fact edits; evidence asked once per change set). Non-Fact admin content (glossary, articles, keys, vocabulary, users) keeps its forms until it moves too. The tray and Edit mode are to be designed as components (matter bc0d).

### Empty states

Say what would be here and how to get it there: "No synonyms. Add one below." Never a bare "None" in a box, and never an empty table with headers.

### Loading

LiveView navigation shows the top loading bar. A region that loads after the page (a map, a chart) shows a `skeleton` the size of what's coming, so nothing jumps.

### Confirmation

Ask only before something destructive or hard to undo. The dialog names the thing and the consequence ("Delete the taxon Acanthaceae? Its 3 synonyms are deleted with it.") and the button repeats the verb ("Delete taxon"). Reversible actions don't confirm; they show a toast with Undo where possible.

### Errors

Say what went wrong and how to fix it, next to where it happened: field errors under the field, page errors as a `:danger` notice at the top of the main column. No apologies, no codes in the main text.

### Bulk actions

Select rows (checkboxes in a `data_table`), and the toolbar shows what will happen to them ("Accept 7 proposed answers"). Rows a bulk action skips say why.

### Keyboard

`/` focuses search. In lists and review rows, ↑ ↓ move, Enter opens, Escape closes. Every action reachable by mouse is reachable by keyboard.
