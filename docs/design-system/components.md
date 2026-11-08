# Components

Every piece of UI is one of these components. Each entry says what the component is for, when to use it and when not, its attributes and slots, and what it replaces. Statuses:

- **Proposed**: designed, awaiting approval. Don't build or use yet.
- **Approved**: agreed; may be built.
- **Built**: in the code, in the style guide, with a component test. Use it.
- **Retiring**: replaced; don't use in new code. Removed once nothing calls it.

The catalog was approved on 2026-11-04. Components are HEEx function components, imported into every template through `GallformersWeb.html_helpers`. Sizes come from the density context and colors from tokens (see [foundations.md](foundations.md)); no component takes a color or size class from its caller except through its documented attributes. Every component accepts `class` for layout only (margins, grid placement), and `rest` for `id`, `phx-*` and `aria-*`.

Removed on 2026-11-06 because nothing used them: `species_card`, `data_complete_badge`, `list`, `header`, `table`, `badge`, `modal` with `show_modal` and `hide_modal` (CoreComponents); `abundance_indicator`, `data_completeness_indicator`, `edit_button`, `external_links`, `host_list`, `source_citation`, `source_list`, `species_synonymy`, `taxonomy_breadcrumb`, `table_actions`, `action_button` (DataDisplayComponents); `field_wrapper`, `file_dropzone`, `multi_select`, `radio_group` (FormComponents); `back_link` (Layouts); `head`, `species_json_ld`, `website_json_ld` (SEO); `skeleton`, `tabs` and the `Tabs` hook, `card`, `error_message`, `info_tip` (UIComponents). The "Replaces" column still names them, as history.

## Summary

| Component | Module | Group | Status | Replaces |
|---|---|---|---|---|
| `command_palette` | PaletteLive | Shell | Built | the header's search box |
| `site_shell` | Layouts.app | Shell | Built | `Layouts.app`, `site_header`, `site_footer` |
| `admin_shell` | Layouts.admin | Shell | Built | `Layouts.admin`, `admin_edit_layout`, the admin nav and title band |
| `page_header` | PageComponents | Page structure | Built | `CoreComponents.header`, 6 hand-written title patterns, `taxonomy_breadcrumb`, `back_link`, Quick Links bars |
| `section` | PageComponents | Page structure | Built | `<.card>` used as a page region, sky-band section cards |
| `panel` | PageComponents | Page structure | Built | `<.card>` as an object, `.gf-card`, `.card`, `species_card`'s shell, 20 hand-rolled cards |
| `rail` | PageComponents | Page structure | Built | ad hoc side columns |
| `data_table` | DataComponents | Data | Built | `<.table>`, `species_table`, 21 raw `gf-table` tables |
| `fact_list` | DataComponents | Data | Built | the trait grid, ad hoc label/value lists, `record_metadata` |
| `name_list` | DataComponents | Data | Built | slash-separated Host lines, one-column name tables |
| `see_also` | UIComponents | Data | Built (restyled) | the See Also logos: now "See also", text links searching iNaturalist, BugGuide (Galls), Google Scholar, BHL |
| `chip` | DataComponents | Data | Built | `badge`, `chip`, `data_complete_badge`, `.gf-badge`, `.gf-pill`, `destination_badge` |
| `stat` | DataComponents | Data | Built | the home and dashboard number tiles |
| `empty_state` | DataComponents | Data | Built | ad hoc "Nothing here" text |
| `taxon_name` | DataDisplayComponents | Domain | Built | — |
| `gall_card` | DomainComponents | Domain | Built | the ID grid card, `species_card` |
| `gall_name` | DomainComponents | Domain | Built | an undescribed Gall's placeholder name shown raw |
| `gall_summary` | DomainComponents | Domain | Built | — |
| `cynipid_mark` | DomainComponents | Domain | Built | — |
| `fact_ref` | FactsComponents | Domain | Approved | the "in Facts" links and per-row Fact actions on pages in Edit mode |
| `fact_inspector` | FactsComponents | Domain | Approved | the Gall page's Edit-mode Fact rows and chips, the Facts panel as the place to edit, `ObservationIntake`'s dialog |
| `source_entry` | DomainComponents | Domain | Built | the Gall page's Further Information cards, `source_citation`, `source_list` |
| `photo_viewer` | DomainComponents | Domain | Built | `image_gallery` and the ImageGallery hook (retired) |
| `range_map` | DomainComponents | Domain | Approved (rework) | `range_map`, `range_map_legend` |
| `source_quote` | DomainComponents | Domain | Built | `blockquote` styling, review "The Source wrote" text |
| `taxonomic_position` | FactsComponents | Domain | Built | — |
| `button` | ActionComponents | Actions | Built | `button`, `edit_button`, `action_button`, `admin_edit_link`, 122 raw buttons |
| `menu` | ActionComponents | Actions | Built | the header dropdowns, row-action menus |
| `segmented_switch` | ActionComponents | Actions | Built | three hand copies of the rank pages' `view_switch` (rank pages, the image manager, the country drill-down) |
| `tabs` | UIComponents | Navigation | Removed (unused) | — (page tabs are `tab_nav`; build in-page tabs anew if a page needs them) |
| `tab_nav` | PageComponents | Navigation | Built | the Browse pages' hand-made tab links |
| `pagination` | UIComponents | Navigation | Approved (restyle) | — |
| `field` | FormComponents | Forms | Built | `field_wrapper`, `input`'s label/help/error wrapper |
| `input`, `select`, `textarea`, `checkbox`, `toggle` | FormComponents | Forms | Built (restyled) | `.gf-input` and friends |
| `search_field` | FormComponents | Forms | Built | `search_input`, three search-input classes, the header search |
| `typeahead` | FormComponents | Forms | Approved (consolidate) | `typeahead`, `multi_select`, `multi_select_dropdown`, `multi_select_typeahead` |
| `file_drop` | FormComponents | Forms | Built | `file_dropzone`, the image managers' hand-built drop boxes |
| `radio_card` | FormComponents | Forms | Built | the review's hand-built option cards (`review_option`, `review_value_list`) |
| `review_option` | ReviewComponents | Forms | Built (`use` included) | — |
| `review_rail` | ReviewComponents | Page structure | Built | the review overview's "Where this Source stands" table, the step tab bar, the repeated Source card and "holds approval" lines |
| `review_card` | ReviewComponents | Page structure | Built (the `:trait` body comes with the review page) | `ReviewLive.ItemRow`'s expanding rows and the step pages' sections |
| `fact_editor` | FactsComponents | Forms | Built | the review Facts page's and the admin Source page's two copies of the form under a Fact |
| `save_bar` | FormComponents | Forms | Approved (pending the save model) | per-section Save buttons |
| `filter_select` | FormComponents | Forms | Built | the ID page's filter dropdowns |
| `category_tile` | DomainComponents | Domain | Built | home page group and Host genus rows |
| `family_card` | DomainComponents | Domain | Built | `tree_browser` (retired) on `/galls` and `/hosts` |
| `facet_group` | FormComponents | Forms | Built | the ID page's filter row, browse filters |
| `notice` | FeedbackComponents | Feedback | Built | `alert`, `error_message`, `.gf-admin-info`, info banners |
| `toast` | CoreComponents (flash) | Feedback | Approved (restyle) | `flash` |
| `dialog` | FeedbackComponents | Overlays | Built | `modal`, `dangerous_delete_modal`, `discard_confirm_modal` |
| `tooltip` | UIComponents | Overlays | Built (`glossary_tooltip` still to move onto it) | `info_tip`, `glossary_tooltip` |
| `skeleton`, `spinner` | FeedbackComponents | Feedback | Approved (`skeleton` to build when a page needs it; the old one was unused and removed) | `loading_spinner`, `loading_overlay` |
| `loading_spinner` | UIComponents | Feedback | Built (restyled; `tone`) | — |
| `progress_bar` | FeedbackComponents | Feedback | Built | host ranges' `<progress>`, the upload hooks' bars, `review_progress`'s bar |
| `bar_chart` | DataComponents | Data | Built | the analytics chart, the `DailyChart` hook and d3 (removed) |
| `share_list` | DataComponents | Data | Built | the analytics devices and browsers tables |
| `prose` | PageComponents | Content | Built | the Tailwind typography plugin (removed) |
| `article_card` | DomainComponents | Domain | Built | the Articles list's shadowed boxes |
| `chip_nav` | PageComponents | Navigation | Built | the Articles list's tag pills |
| `link_tile` | PageComponents | Navigation | Built | — |
| `change_entry` | DomainComponents | Domain | Built | — |
| `edit_toggle`, `edit_scope`, `fact_row`, `fact_chip` | CurationComponents | Editing | Built (Gall page: Inducer, Hosts, Traits; plant page: Edit mode) | the admin's Gall and taxon edit screens, in time |
| `change_tray`, `review_apply` | CurationComponents | Editing | Built (`GallformersWeb.TrayLive`, on every page) | — |
| `key_couplet` | KeyComponents | Domain | Built | `couplet`, `lead`, `destination_badge`, `lead_images` |
| `key_path` | KeyComponents | Domain | Built | `path_tracker` |

## Shell

### `site_shell`

The public page frame.

- **Header** (56px, sticky, `bg-sky`): wordmark; Identify, Browse ▾, Resources ▾ (League Spartan); a search field with a `/` shortcut; Log in, or the signed-in user's menu (with Admin for admins). On phones: wordmark, search icon, menu button.
- **Main**: `max-w-page`, `px-page-x`, Reading density.
- **Footer** at the end of the page, never fixed: Phenology Tool, Donate, Privacy, About, license line.
- **Search:** the `palette_trigger`, a button that looks like a search field ("Search Gallformers" and its key `/`), opens the command palette; on phones a search icon. The header has no search box of its own.
- **Theme switch** (`theme_switch`) at the right of the header, on phones too: an icon button showing the current choice (a half circle for Match my device, a sun, a moon; `gf-contrast`, `gf-sun`, `gf-moon`) that opens Match my device, Light and Dark as `menuitemradio`s. See foundations.md, "Dark mode".
- Slots: `inner_block`. Attributes: `current_user`, `flash`, `region` (the region scope bar, shown on pages that filter by region).

### `admin_shell`

The admin frame.

- **Sidebar** (212px, `bg-surface-2`): Admin mark; Dashboard; Review with its count of open questions (`text-autumn-ink`); Galls; Taxonomy; Sources; Host ranges; then Glossary, Articles, Keys, Vocabulary; then the roles' extras (Users, Jobs, Ops); then View public site ↗. The current item has a maroon inset bar. Collapses to a menu button below 960px.
- **Top bar** (44px): a search across Galls, taxa and Sources; the user; Log out.
- **Main**: fills the remaining width, Working density (`gf-density-working`).
- Light theme only (`data-theme="light"`) until the admin pages are on tokens.
- Slots: `inner_block`. Attributes: `current_user`, `active` (sidebar item), `counts` (badge numbers).

### `command_palette`

Search and go anywhere, on every page, public and admin (`GallformersWeb.PaletteLive`, rendered once from the root layout; the Palette hook). Opened by a `palette_trigger` (the header's, the admin top bar's) or the keys `/` and `s` while not typing in a field (not ⌘K: browsers bind it). With nothing typed: for a curator whose tray holds changes, Your changes first (Review and apply with the count, then up to five of the changes, from `Curation.summary/1`; each opens the tray's own Review and apply, `tray_review` pushed to `TrayLive`); then the fixed Go to list (Identify a gall, Browse galls / host plants / places, Articles, Identification keys, Glossary) and, for a curator, their commands (Edit this page, Add from observation… (`/admin/observation`), Sources to review, Changes). Typing matches the commands too (each word typed starts a word of the command's name, description or synonyms; Review and apply while the tray holds changes), in their own Commands group: first when the words match a command's name, else after the results, just before "See every result". Typing searches (`GallformersWeb.Palette`: `Search.global_search/2` and `Articles.search_published/2`): Go to shortcuts into the ID tool ("Galls on *Quercus alba*", "… in Virginia", "Galls in Virginia"), for a curator "Review: <Source>" for each Source found with an import under review, then Galls, Gallformers (organisms at species rank and below, to their species pages), Host plants, Groups, Places, Sources, Glossary, Articles, and last "See every result" (the search page). ↑ ↓ move the selection, Enter follows it, Esc or a click outside closes; following a row closes the palette. A panel near the top of the screen (`gf-palette`); full screen on phones. Keys are shown with `gf-kbd`.

## Page structure

### `page_header`

The top of every page. One per page; it holds the page's only `h1`.

```heex
<.page_header>
  <:crumb navigate={~p"/family/Cynipidae"}>Cynipidae</:crumb>
  <:crumb navigate={~p"/genus/Callirhytis"} italic>Callirhytis</:crumb>
  <:title name>Callirhytis quercuscornigera (agamic)</:title>
  <:chip variant={:warn}>In progress</:chip>
  <:meta label="Other generation"><.link navigate={…}><em>C. quercuscornigera (sexgen)</em></.link></:meta>
  <:meta label="Season">Spring, Summer</:meta>
  <:action><.button navigate={…}>Edit</.button></:action>
</.page_header>
```

- `crumb` slots make the breadcrumb (lineage, or the admin path). `title` with `name` sets a scientific name in Source Sans italic; without it, League Spartan.
- `chip` slots sit beside the title; `meta` slots make one line of label/value pairs under it; `action` slots sit at the right.
- Use it on every page. Don't put a title anywhere else, and don't add an "Editing …" prefix: the admin context already says so.

### `section`

A part of a page: a heading on a rule, then content. Not a box.

```heex
<.section title="Hosts" count={14}>
  <:aside>Oldest first · <.link …>newest first</.link></:aside>
  …
</.section>
```

- Attributes: `title`, `count` (muted, beside the title), `id` (anchor), `level` (2 by default; 3 inside another section).
- Slots: `aside` (right side of the heading row: sort, a filter, an action), `inner_block`.
- Use for every page region. Don't wrap a section in a panel.

### `panel`

A separate object on the page: a bordered surface. Use it when the thing inside is one object (a Source excerpt opened for reading, a review item, an ID Notes box, a rail box), never for a page region.

- Attributes: `variant` (`:plain` — surface with a line border; `:info` — sky-soft, no border, for Gallformers' own notes; `:danger` — for destructive zones), `title`, `padding` (`:default`, `:none` for tables and images).
- Slots: `header_action`, `inner_block`, `footer`.

### `rail`

The right-hand column of a detail or edit page. Stacks under the page header on phones (the photo first on Gall pages).

- Attributes: `width` (`:wide` 420px for public detail pages, `:narrow` 300px for admin), `stack` (`:first` or `:last` on narrow screens; a wide rail stacks first, a narrow one last).
- Put the main column and the rail inside `<div class="gf-with-rail">`, which makes the two-column grid on wide screens.
- Holds panels, a `fact_list`, a photo viewer or a map. Facts *about* the record go here; the record's content goes in the main column.

## Data

### `data_table`

The one table. Rows are `--gf-row-h` tall and single-line: long text truncates, with the full text in a `title`. A column's `wrap` allows two lines; `full` shows its whole text (glossary definitions). `active` (a function row -> boolean) marks the row a keyboard highlights (`aria-current`, highlighted; search results).

```heex
<.data_table id="sources" rows={@sources} row_navigate={&~p"/admin/sources/#{&1.id}"} sort={@sort}>
  <:col :let={s} label="Title" field={:title} sortable grow><%= s.title %></:col>
  <:col :let={s} label="Authors" field={:authors}><%= s.authors %></:col>
  <:col :let={s} label="Year" field={:year} sortable numeric><%= s.year %></:col>
  <:col :let={s} label="Status"><.chip :if={s.complete} variant={:ok}>Complete</.chip></:col>
  <:empty>No Sources match "<%= @query %>".</:empty>
</.data_table>
```

- Column attributes: `label`, `field`, `sortable`, `numeric` (right-aligned, tabular), `grow` (takes the spare width), `wrap` (allow two lines), `hide_below` (`:md`, `:lg`: hide on narrow screens).
- Table attributes: `id`, `rows` (a list or a stream), `row_id`, `row_item`, `row_navigate` or `row_click`, `sort` (`%{field:, dir:}`; a sortable head emits `sort` with `field`), `selectable` with `selected`, `select_id` and `select_label` (a checkbox column, emits `select` with `id`), `compact` (28px rows).
- Per row: `row_attrs` (function row -> a map of attributes put on the `tr`, for the page's hooks and tests: `%{"data-image-id" => id}`) and `row_state` (function row -> `nil`, `:selected`, `:ok`, `:warn`, `:danger` or `:info`: the row's tint, each with its chip meaning, and `data-state`; a selected row is `:selected` by itself).
- Selection, for a page or a LiveComponent: `select_event` (default `select`), `target` (a LiveComponent's `@myself`, for the checkboxes and the header's), `selectable_row` (function item -> boolean; a row it rejects has no checkbox and is left out of select-all), `select_disabled` (while a bulk action runs). `select_all` adds a checkbox in the header (labelled "Select all"), ticked when every selectable row is selected; it sends `select_all`'s event, or `select_none`'s when every row is already selected (default: the same event, a toggle).
- Slots: `col`, `empty`, `footer` (pagination, totals).
- Grey heads (`bg-surface-2`), sentence-case group-heading labels, hairline rows, `bg-sky-soft` on hover.
- A column that is empty for every row is not shown (columns with a `field`, list rows).
- The table has a minimum width (36rem): in a narrow container it scrolls sideways rather than crushing its `grow` column. Don't use a table for a list of names alone (use `name_list`) or for label/value pairs (use `fact_list`).

### `fact_list`

Label/value pairs in one to three columns: a Gall's traits, a record's facts in a rail.

```heex
<.fact_list columns={3} missing_label="Not recorded">
  <:item label="Detachable">Integral</:item>
  <:item label="Shape" value={nil} />
</.fact_list>
```

- Items with no value collect into one line at the end ("Not recorded: shape, alignment, walls"), so known values stand out and gaps stay visible.
- Attributes: `columns`, `missing_label` (nil hides missing items), `layout` (`:grid` ruled cells, `:inline` for a rail).

### `name_list`

A list of short names that flows into columns: Hosts, a Source's Galls, families on a browse page.

- Attributes: `items`, `columns` (max columns, 1–6; fewer on narrow screens), `italic` (scientific names). Names flow down each column, so an alphabetical list reads down.
- Slots: `item` (to render a link and a count).

### `chip`

A small labelled state or category. Every variant has one meaning.

| Variant | Meaning | Example |
|---|---|---|
| `:ok` | done, complete | Complete |
| `:warn` | in progress, needs a look | In progress · Holds approval |
| `:danger` | conflict, error | Conflicts with Gallformers |
| `:info` | neutral fact | Publication |
| `:rank` | a taxonomic rank | Family |
| `:neutral` | a category | Plantae |
| `:count` | a number that needs you | 358 |
| `:recommended` | the recommended answer to a question (brand tint) | Recommended · rec. |

Attributes: `variant`, `icon`. Never a chip for decoration, never color without a word.

### `stat`

A number with a label: 3,976 Galls. For dashboards and the home page only, where the figures are the point.

### `empty_state`

What a list or region says when it has nothing: one line saying what would be here and, when possible, how to add the first one. Attributes: `title`, `action` slot.

### `bar_chart`

A bar chart drawn on the server as SVG: one group of bars per item (a day), one bar per series, to scale against a y axis from 0 to a round number (steps of 1, 2, 2.5 or 5 × 10^k, at most five). Bars use percentage positions, so the chart fills its column at any width without stretching its text. Each bar is titled with its value ("Oct 21 · Page views: 3,861", the browser's tooltip); a legend names the series; a visually hidden table carries the numbers for screen readers. Day labels thin out on long ranges (every day up to 7, every 3rd up to 30, else every 7th). With no data: "No data for this period." Attributes: `id`, `label` (accessible name), `data` (maps with `label` and a number per series key), `series` (maps with `key`, `label`, `tone`: `:brand`, `:autumn`, `:sky`), `height` (px, default 180), `class`. Replaced the analytics page's d3 chart; d3 and the `DailyChart` hook are gone.

### `share_list`

Shares of a whole, one row each: the name, a bar as wide as the share, the percentage and the count (the analytics page's devices and browsers). With no items: "Nothing recorded in this period." Attributes: `id`, `items` (maps with `count` and `percentage`), `name` (function item -> its name), `class`.

## Domain

### `taxon_name`

Renders a name with correct italics, from `Gallformers.TaxonName.segments/1`: the binomial and an infraspecific name italic; rank words (var., subsp.), authorities (Michx.) and a parenthetical qualifier such as the generation, "(agamic)", upright. An undescribed Gall's placeholder ("Unknown (Cynipidae) q-rubra-spur-gall") is not a scientific name and stays upright. Ranks above genus are upright. Every component that shows a name uses it.

### `gall_card`

A Gall at a glance: the photo (square, `rounded-panel`), the name (italic), and one muted line of what tells it apart (plant part · form · season). Optional chips (Undescribed). For the ID results grid, rank pages, browse pages and the home page.

- Attributes (plain values, so any page maps its own read model onto them): `navigate` (required; the whole card is one link), `name` (required; set through `taxon_name`), `image_url`, `image_alt` (defaults to "Photo of …"; `""` when the name beside it says enough), `subtitle` (the distinguishing traits, e.g. "stem · abrupt swelling · Spring"), `size` (`:md`, `:sm`). Slot `chip` (e.g. Undescribed).
- Lay cards out in `<div class="gf-photo-grid">`: photos fill the row at a minimum of 280px, so a wider screen shows more photos, never smaller ones (four across at 1312px, six at 1920px). Photos are the most important thing on an identification page; don't shrink them to fit more. `data-size="sm"` (at least 176px, two across on phones) is for overview rows (home page tiles, rank pages).
- A Gall with no photo shows the gall icon on `bg-surface-2`, not an empty grey box.

### `gall_name`

A Gall's name as a reader should see it. A described Gall's name goes through `taxon_name`. An undescribed Gall is named by what it is, read from its placeholder name by `Gallformers.Catalog.GallName.undescribed/1` (the inverse of `derive/1`): "Undescribed red bud gall", "Undescribed *Neuroterus* new growth swelling (sexgen)". The descriptor's Host code is dropped and one likening it to another gall says so ("gall like rosaria"). The placeholder stays in the `title`, for those who know the codes. For anywhere a Gall's name is shown to readers: the home page, search results, cards.

- Attributes: `name` (required), `undescribed` (the Gall has no species-rank Inducer; read models carry the flag), `article` ("An undescribed …", for a name standing alone as a heading), `class`. It sets only italics; size, weight and color come from outside.

### `gall_summary`

One plain sentence of where a Gall is found, on which Hosts and when: "Found on the stem of *Quercus alba* and *Quercus rubra* and 2 more, in spring and fall." An undescribed Gall whose name names a family says which Gallformers make it: "Made by one of the gall midges, on …". From the data `Catalog.gall_search_details/1` loads (search results, the random Gall).

- A plant part that is already a phrase ("between leaf veins") is used as one; several follow the Hosts in brackets. Seasons run through the year. Hosts are set as scientific names. With nothing known it renders nothing.
- Attributes: `hosts`, `plant_part`, `season` (lists of names and values), `name` and `undescribed` (for the group), `max_hosts` (default 2, then "and N more"), `class`.

### `cynipid_mark`

Gallformers' stipple drawing of a cynipid wasp (`priv/static/images/cynipid_R.svg`), drawn as a mask (`.gf-cynipid-mark`) so it takes the text color in light and dark. Decoration, hidden from screen readers. Set a color (`text-brand`) and a size; it keeps its 3:2 proportions. Use it sparingly, once on a page at most: the home page beside the counts, and places that want a little of the site's character (an empty state, an error page).

### `fact_ref`

A Fact-backed value on a page (an Inducer, a Host, a Trait value, a range place, a common name) as it reads to everyone: the value with a dotted underline (`decoration-line-strong`, darker on hover), hover text "Who says so?". Selecting it opens the `fact_inspector` on that Fact; the selected value sits on `bg-sky-soft`. A page with `fact_ref`s shows readers a dismissible hint once ("Underlined values show the Sources that state them"). In Edit mode the page doesn't change shape: each group gains one Add, nothing else. Design and build: matter `87a1`; mockup `/dev/mockups/fact-inspector/:id`.

### `fact_inspector`

Who says so, and in Edit mode what to do about it, for one Fact, beside the page: in the rail's place on wide screens, a bottom sheet on phones. The kind ("Host"), the value, what it is of ("A Host of *Diplolepis rosae*"), its standing ("Holds · Stated by 2 Sources", or "Unconfirmed" when only Gallformers' undated original data states it), then **Who says so**: one block per Source, the same template for each ("**{Source}** says so · date", its words as written, up to two quotes), Gallformers pinned first, the others newest first.

- **Edit mode** puts each action in its Source's block: Gallformers' has Change…, Deny…, Add a note… (and Confirm… when it hasn't stated the Fact); "Found an error in a Source reading?" reveals "Fix our reading…" on the others' blocks. Each opens a short form in the panel and adds to the tray.
- **States:** a Fact; a new Fact (from a group's Add); an observation ("Add from observation…": the observation's card and grade, a warning when its taxon isn't the Gall's Inducer, its proposals ticked and previewed on the page, its photos, one "Add N to your tray").
- Replaces the Edit-mode Fact rows and chips, the Facts panel as the place to edit (it stays as the full record), and the observation dialog. Design and build: matter `87a1`.

### `source_entry`

One Source as it relates to a page: year, title (link), authors, and the opening of what it says, in serif (`source_quote`). Expands in place to the whole excerpt, the license and links to the Source page and the original. Used on Gall pages (one row per Source, by year) and on Source pages.

- Attributes (plain values): `id`, `title` (both required), `href` (the Source page), `year` (missing shows "n.d."), `authors`, `excerpt` (plain text; paragraphs split on blank lines — strip Markdown first), `license`, `license_url`, `original_url`, `open`, `pinned` (Gallformers ID Notes: an `:info` panel, always open, placed above the list).
- Expanding is client-side, with `aria-expanded` on the toggle.

### `photo_viewer`

The photos of a Gall, a Host or a Source: one large photo shown whole (never cropped), its caption and its own credit (creator, license linked or plain, source link), arrows and a "n / N" count and a thumbnail strip with two or more, a full-size view (a dialog; photos load when shown) and a Details dialog (source, license, attribution, creator, uploader, last changed by, caption). The `PhotoViewer` hook shows the current photo: arrows, thumbnails, arrow keys (wrapping) and a horizontal swipe move; Escape or Close closes a dialog and focus returns to what opened it; every move pushes `gallery_index_changed`. With no photos: "No photos yet." and, for an admin, "Add images". Attributes: `id`, `photos` (maps with atom or string keys: `src`, `thumb`, `alt`, `caption`, `creator`, `license`, `licenselink`, `sourcelink`, `attribution`, `uploader`, `lastchangedby`), `name` (for alt text: "Photo n of <name>"), `edit_href`, `admin`, `class`. The admin image manager is a separate component.

### `range_map`

The possible-range map, as a card that opens a large map in a dialog, with full screen from there.

- The card frames the native range. Introduced ranges are drawn but don't widen the frame (built on the Gall page: bounds from the range without its introduced places).
- The legend is a single line under the card; the caveat ("Where the Hosts grow, not where the Gall was found") goes under the legend.
- Attributes: `ranges`, `size` (`:card` 420×293, `:wide` the main column's width).
- On the Gall page: a 288px-high card in the wide rail, with Enlarge opening a full-size dialog that has the map's own full-screen control.

### `source_quote`

What a Source wrote, in Source Serif: a quote or excerpt, with a page reference. Used inside `source_entry` and in review. (Named `source_quote` because `quote` is reserved in Elixir.)

### `taxonomic_position`

Where a taxon stands in the Sources, compactly (matter `f923` Task 10), for a taxon's page: a `fact_list` (`:inline`) of **Placed** (under its parent, or at the root), **Name** (the accepted name with its authorship and any sensu), each followed by "· from" the Source whose statement decides it, and **Papers that disagree**: each Source linked, its mark (accepted, declined with the curator's reason, awaiting a curator), "not" for a denial, and what it says. Links go to public pages only. Renders nothing when no current Fact places or names the taxon and no paper disagrees.

```heex
<.taxonomic_position id="species-position" position={Import.taxonomic_position(taxon.id)} />
```

- Attributes: `id` (required), `position` (required: `Gallformers.Import.taxonomic_position/1`'s `%{placement, name, disagreeing}`).
- Parts carry `data-part` (`placement`, `name`, `disagreeing`) and each disagreeing paper `data-decision`.
- Used by the species page (`SpeciesLive`, in its Taxonomy section).

## Actions and navigation

### `button`

One button, as a `<button>` or a link (`navigate`, `patch`, `href`).

- Variants: `:primary` (maroon fill: one per region), `:secondary` (surface, line-strong border: the default), `:ghost` (no border, link color: low-emphasis actions), `:danger` (destructive, confirms through a dialog).
- Attributes: `variant`, `icon`, `icon_only` (requires `label` for `aria-label`), `size` (`:default` follows density, `:sm`), `disabled`, `loading`.
- Labels say exactly what happens ("Approve 9 notes", "Rename", "Add synonym").

### `menu`

A button that opens a list of links or actions (the header's Browse and Resources; a row's actions). Keyboard-navigable; closes on Escape and outside click. Uses `shadow-float`.

### `segmented_switch`

A few mutually exclusive choices as one joined row of buttons, the current one filled with the brand (`aria-pressed`): Photos | Table on rank pages, Grid | Table in the image manager, Native | Introduced in the country drill-down. For switching how a region shows its content or a mode of clicking, not for page tabs (`tab_nav`) or a form value (a `select` or radios).

```heex
<.segmented_switch label="View" value={@view} event="galls_view" param="view">
  <:option value={:photos}>Photos</:option>
  <:option value={:table}>Table</:option>
</.segmented_switch>
```

- Attributes: `label` (the group's accessible name), `value` (the current choice; compared as strings), `event` (sent on a click, with `phx-value-<param>` set to the option's value), `param` (default `value`), `target` (a LiveComponent's `@myself`), `disabled`, `size` (`md`, `sm`), `id`, `class`.
- `option` slot: `value` (required), `id` (the button's id, for tests and labels), `icon` (with no inner block an icon-only button), `label` (the accessible name and title of an icon-only option).
- Clicking the current option sends the event again; the page decides.

### `pagination`

Exists. Restyle to tokens. (`tabs`, the in-page tabs with the `Tabs` hook, was unused and is removed.)

### `tab_nav`

Tabs that are links, each tab its own page: Browse's "By what causes them" (`/galls`), "By host plant" (`/hosts`), "By place" (`/places`); the tab list is `BrowseHelpers.browse_tabs/0`. Attributes: `label` (the nav's accessible name), `class`; a `tab` slot with `navigate`, `href` or `patch`, and `current` (sets `aria-current="page"`). It sits right under the `page_header`. For tabs that switch content within one page, use `tabs`.

## Forms

### `field`

A control with its label, help and error. Two layouts:

- `:stacked` (label above): public forms and narrow spaces.
- `:row` (label left, 150px; help under the control): admin edit pages.

Attributes: `label`, `for` (the control's id), `help`, `errors`, `layout`, `required`, `saved`. Slot: the control. The help and errors get ids `<for>-help` and `<for>-errors`; wire them to the control with `aria-describedby`, and set `aria-invalid` when there are errors. `saved` shows "Saved" in an `aria-live` region beside the control.

### Controls

`input`, `select`, `textarea`, `checkbox`, `toggle` keep their current APIs and take their look from tokens: `h-ctl` tall, `border-line-strong`, `rounded-ctl`, focus ring from `--gf-focus`.

- `input`'s label is `gf-label`, its required mark and errors `text-danger`; a checkbox sits beside its label with a gap.
- `toggle` is a checkbox with `role="switch"` drawn as a track (`.gf-toggle-track`). With no visible `label`, give it an `aria-label`; `phx-click` and `phx-value-*` go on the checkbox.
- A file input takes `.gf-file`: its button drawn like a secondary button, the chosen file's name beside it.
- `dangerous_delete_modal` (typed-name delete) keeps its API and events and renders as a `dialog` with a `:danger` notice. `target` (a LiveComponent's `@myself`) sends its events to that component.

### `search_field`

A search input with an icon, a clear button (`on_clear`) and an optional keyboard shortcut hint (`shortcut="/"`, shown while the field is empty). One component for the header search, list filters and the admin top bar. Attributes: `name`, `label` (both required), `value`, `placeholder`, `debounce`, and anything for the input (`phx-change` …).

### `typeahead`

Find and pick by name: one component for single and multiple selection (`multiple`), with chips for chosen items, grouped results (accepted name, synonym, WCVP), and keyboard support. Consolidates four components into one.

### `file_drop`

Where to drop or choose files: a dashed box (`layout={:box}`, the default) with an icon, what to do and the limits, or one row (`layout={:row}`: "Choose files… or drop JPG or PNG images here") when space is short. It renders the `data-dropzone` element and its hidden `data-file-input` that the upload hooks (`ImageUpload`, `ContentImageUpload`) find inside their own element; the hook handles the click, the drop and its highlight (`border-brand`, `bg-sky-soft`). The preview, progress and Upload button stay the page's, inside the hook's element.

```heex
<div id="images-uploader" phx-hook="ImageUpload" phx-update="ignore" …>
  <.file_drop accept="image/jpeg,image/png" multiple hint="Max 20 files. JPG or PNG only." />
  <div data-preview-container …></div>
  …
</div>
```

- Attributes: `accept` (the input's `accept`), `multiple`, `label` (default "Drop images here, or click to choose"), `hint` (the limits), `icon` (default `ph-cloud-arrow-up`), `layout` (`:box`, `:row`), `class`.
- For a single file in a form, use the file input with `.gf-file`; for an upload button beside a textarea (the article editor), a `button`.

### `radio_card`

One option of a question as a card: a radio (or a checkbox, `type="checkbox"`) with its name, what it does under it, and what it needs once chosen. The review's options (`review_option`) and Trait values (`review_value_list`) are built on it.

```heex
<div role="radiogroup" aria-label="Which plant is meant?" class="grid gap-1.5">
  <.radio_card id="q-0" name="q" value={0} checked={@choice == 0} recommended
    summary="The accepted name." phx-click="pick" phx-value-choice={0}>
    <:label>Quercus lobata</:label>
    <:aside>2 of 3 readers</:aside>
    <:follow>…the input the option needs…</:follow>
  </.radio_card>
</div>
```

- States: plain (`border-line`), recommended (brand border, a `:recommended` chip "Recommended" after the label; `recommended_label` changes its words, `nil` hides it), chosen (brand border on a brand tint). The card carries `data-recommended` and `data-chosen`.
- Attributes: `id` (the input's), `name`, `value`, `checked`, `type` (`radio`, `checkbox`), `recommended`, `recommended_label`, `summary` (under the label, muted: what it does), `size` (`:md`; `:sm` for long value lists), `class`; `rest` (`phx-click`, `phx-value-*`, `phx-target`) goes on the input.
- Slots: `label` (required; chips may follow the name), `aside` (right of the label on wide screens: who recommends it, who chose it), `extra` (under the card's text, chosen or not), `follow` (shown only once chosen).
- Put the cards in an element with `role="radiogroup"` and an `aria-label` (the question). For a short row of choices without descriptions use `segmented_switch` or plain radios.

### `review_option`

One answer to a curator's question, as a `radio_card`: what it is, what choosing it does, whether it is the recommended answer and on whose word, who chose it, and the input it needs once chosen. The review's questions (`ReviewLive.ItemRow`) and "Based on which Source?" (`Admin.TaxonomyLive.BasisPicker`) set their options with it.

```heex
<div role="radiogroup" aria-label="Based on" class="grid gap-1.5">
  <.review_option id="basis-source" name="basis[choice]" value="source"
    checked={@choice == "source"} recommended label="A Source in Gallformers"
    summary="The paper the change follows." on_pick="pick" target={@myself}>
    <:follow>…the Source typeahead…</:follow>
  </.review_option>
</div>
```

- Attributes: `id` (the radio's), `name` (the group's), `value`, `checked`, `recommended`, `by` (who recommends it, or why, shown at the right while recommended and nobody has chosen), `tally` (who chose it, recommended or not; in place of `by`), `label`, `summary`, `tags` (`%{text, kind: :best | :conflict}` chips after the label: `:conflict` danger, `:best` info), `on_pick` (the event the radio sends, with `phx-value-choice` set to `value`), `target`.
- Slots: `extra` (under it, chosen or not: a comparison), `follow` (shown once chosen, in a `data-role="follow"` grid).
- Put the options in a `role="radiogroup"` element labelled with the question, as `radio_card`'s. For a Trait's values use `review_value_list`.

#### `use`

For the one-at-a-time review (`6611`, mockup `/dev/mockups/source-reading/:package_id`). With `use`, the option is decided in one click: a button at its right ("Use this") sends `on_pick`, and no separate Decide button is needed. An option that needs input first (a plant or Gall search) shows "Search…" in its place, which opens its `follow`. The recommended option's button is primary. Without `use` the option behaves as today (a radio, then Decide).

### `fact_editor`

The form of an edit open on one Fact, in the `editor` slot of `facts_view` and `facts_taxonomy`, under the Fact it changes: the review Facts page's edits before approval (Drop, Change Host, Change value, Note) and the admin Source page's corrections after it (Withdraw, Change Host, value, parent or accepted taxon). Top to bottom: what the edit does, in words; a taxon search when the edit picks a taxon (a `typeahead`, results grouped and each with its rank and aliases muted); the Trait's values to tick when it picks values (`review_value_list`, checkboxes); the page's own fields (the inner block: "Accept it now"); the note; the refusal; Save and Cancel.

```heex
<.fact_editor id="correction-editor" title="Change the Host: the plant the Source names."
  on_submit="correct" target={@myself} pick={@pick}
  search_label="The plant: species and below, genera, sections"
  note_label="Note: why (required)" error={@edit_error} save_text="Save the correction" />
```

- Attributes: `id` (required; the parts are `<id>-note`, `<id>-values`, `<id>-error`, `<id>-save`, `<id>-cancel`), `title` (required), `on_submit` (required), `target`, `pick` (required: `%{query, results, selected, values, note}`, the open edit's choices), `search_label` (shows the search; nil for none), `search_id` (default `<id>-taxon`), `search_event`, `select_event`, `clear_event` (default `search_taxon`, `select_taxon`, `clear_taxon`), `values` (the Trait's `{value, definition}` pairs; nil for none), `on_toggle` (default `toggle_value`), `note_label` (required: say whether the note is required), `error`, `save_text` (required), `save_variant` (`danger` for an edit that takes a statement away).
- Slots: `inner_block` (the edit's own fields, before the note).
- Cancel sends `edit_cancel`. The page holds the edit's state and its events; the Host search's results come from `GallformersWeb.Admin.ReviewLive.Loader.host_choices/2`.
- Used by the review Facts page (`Admin.ReviewLive.Facts`) and the admin Source page's Facts (`Admin.SourceLive.Facts`).

### `save_bar`

Shows unsaved changes and offers Save and Discard. Its role depends on the admin save model, which is still open (matter `bc0d`).

### `filter_select`

A filter in the ID page's filter row. It matches the current screens' behavior exactly ([inventory/typeahead-and-id.md](inventory/typeahead-and-id.md)):

- **Single-value filters** (detachable, family, season, alignment, form, walls, cells, shape, color): a select inside its own `<form phx-change="change_filter" phx-value-filter=…>` with `name="value"` and an "Any …" prompt, as today. While a filter is unset, each option shows how many of the loaded results have that value ("leaf midrib (22)"); a set filter is drawn with a brand border.
- **Multi-value filters** (plant parts, textures): the `multi_select_typeahead` mechanics unchanged (type to filter, chips in options order, Clear all, the mousedown guard, server-tracked focus), restyled to sit in the same row, with the ANY/ALL toggle under it when two or more values are chosen (only ALL is written to the URL).
- On phones the filter row folds behind one Filters button showing how many filters are set.

Built (2026-11-05); used by the ID page (`IDLive`).

### `category_tile`

A group of Galls to browse into, as one link: a photo, the name and how many Galls it holds. The home page's "Start from the plant" (Host genera, `italic`) and "Browse by what causes them" (the Gallformer groups of `Gallformers.Catalog.InducerGroups`).

- `layout={:row}` (default): a compact list row (40px thumbnail, name, count, ruled below). Lay rows out in a `<ul>` grid of one or two columns. The home page uses this.
- `layout={:tile}`: a square photo above the name and count, for `gf-photo-grid data-size="sm"`.

Attributes: `navigate`, `name`, `count`, `image_url`, `italic` (genus and below), `icon` (shown on the well when there is no photo; `gf-gall` by default, `gf-host` for plants), `layout`, `class`. The photo is decorative (`alt=""`): the name says what the tile is.

### `family_card`

A family on a Browse page: a photo, the family (a link) with its common names, "N galls · M genera", and its largest genera with their counts. Built from the browse tree by `GallformersWeb.BrowseHelpers.family_cards/2`. On `/galls` the count is the Galls under it; on `/hosts` it is the distinct Galls on the plant family or genus.

It is also the browse tree. Its toggle opens the card across the grid to every genus, flowing in columns; each genus has its own caret that lists its leaves (Galls, or plants with `leaves="plants"`). The page keeps the open keys (`expanded`) and handles `toggle_node`, `expand_all` and `collapse_all`, as the tree did. Lay cards out in `grid gap-3 md:grid-cols-2 xl:grid-cols-3`. Attributes: `card`, `expanded`, `on_toggle`, `limit` (genera shown while closed, 6), `icon` (`gf-host` for plants), `leaves`.

### `facet_group`

A filter with counts: a legend and options, each with how many results it would leave ("leaf 41 · stem 22 · bud 12"). For the ID page and browse pages. Options with zero results are dimmed, not hidden; options past `limit` hide behind "Show N more". Attributes: `id`, `title`, `name`, `options` (`%{value:, label:, count:, selected:}`), `multiple` (checkboxes named `name[]`, with an empty value so clearing all still sends the param), `limit`, `italic`. It sits inside the page's `<form phx-change>`.

### `review_rail`

The side of a Source's review page: where the curator is, and how to move. Pinned beside the review card on wide screens, below it on phones. Top to bottom:

- the Source's title; "12 of 35 answered" with a `progress_bar`; "23 to go. 22 of them must be answered before you can approve.";
- the stages (Names, Galls, Disputes, Traits) as a list of buttons, each with what's left ("4 left", "done" with a tick), the current one marked: choosing one makes its work come next;
- "81 hedged statements were left out. Review them", which opens them in the main column;
- Up next: the next three units of work, one line each;
- Approve (disabled with "You can approve once the 22 marked questions are answered.") and Deny.

Every count on the page comes from one tally: questions answered and to go, the ones that must be answered before approving among them, the hedged statements apart. Attributes: `tally`, `stages`, `next`, `hedged`, `title`; events `stage`, `hedges`, `approve`, `deny`. Mockup: `/dev/mockups/source-reading/:package_id`.

### `review_card`

One unit of a Source's review, the one thing on the page (`6611`). A panel holding, top to bottom: the kind of question in small type ("Host plants · needed before you can approve"); **Affects**, the Galls and which of their Facts the answer settles; the question as the heading (headings wrap normally, `text-wrap`, not balanced); the Source's words (`source_quote`, two at most); the answers; a footer with Add a note…, Read the Source and Skip for now. Variants (`kind`):

- `:question`: the answers are `review_option`s with `use` (one click each). A Host nothing matches offers Search…, Add a new plant… ↗ and Leave this Host out, in that order. An undescribed Gall first asks "Is it one of these Galls we already have?", listing the genus's undescribed Galls with the one whose Host the Source names first. A Host question says in one plain line what WCVP has for the name (`review_wcvp_panel` with `line`; POWO and IPNI links only when WCVP has nothing). Each candidate Gall's summary is its comparison in a sentence ("Agrees on 2 of 3: Host and where on the plant. Conflicts on generation and season."), the side-by-side (`review_gall_comparison`) behind "Compare".
- `:batch`: a group's firm suggested answers as a checklist, ticked by default ("9 of the 13 Traits questions have suggested answers. They look right to us. Untick any you want to check yourself."); each row "texture: lumpy → Keep as text"; "Accept all 9" / "Accept the 8 ticked". Unticked ones come next on their own. "Create a new Gall" and "It depends on the Gall" are never batched.
- `:trait`: a Trait term or a Trait dispute, one block per Gall it covers: the Gall, the Source's sentence, one line on what the pipeline made of it ("The import pipeline couldn't agree how to map “lumpy” to a texture value." / "The producer mapped “fleshy” to succulent. A checker disagreed: …"), "What each AI said" folded away, then two `radio_card`s: "Keep “lumpy” as text" or "Map it to texture values", which opens every value of the Trait as checkboxes in columns (`review_value_list` `compact`: each definition in a `tooltip` on its value, "Hover a value to see its definition." above them; no underline, as a dotted underline is `fact_ref`'s), each side's values pre-ticked and marked. "Use this for the other N Galls" copies one Gall's answer to the rest. Save waits until each Gall has an answer.
- `:hedges`: the hedged statements, grouped, each with Add it…, and Back to the questions. The same card, with its own heading, line and action ("Look at it…"), lists the names we didn't read (names the Source prints that we have but nothing was read from); the rail links to it ("4 names we didn't read. Look them over"), as does the last step.
- `:facts`: the last step before Approve: what approving will add, by Gall (`facts_view`).

Laid out at the Reading sizes inside the admin shell (`gf-density-reading`, foundations). Keyboard: Enter takes the suggested answer, S skips, up and down move between answers.

## Feedback

### `notice`

An inline message in the page: `kind` `:info`, `:ok`, `:warn`, `:danger` (role `alert` for danger, `status` otherwise), optional `title`, an `action` slot and `on_dismiss`. One line where possible. Replaces four message components.

### `toast`, `skeleton`, `spinner`

`toast` exists: restyle to tokens; toasts use `shadow-float`. `skeleton` is to be built (to tokens) when a page first needs one; the old, unused one was removed.

### `loading_spinner`

A spinning ring while something loads (`role="status"`, `label` its accessible name), with its words beside it ("Searching WCVP…"). Attributes: `size` (`sm`, `md`, `lg`), `label`, `tone` (`:brand`, the default, on a page or panel; `:current`, the text color around it, inside a button: on a primary button's fill it is `text-on-fill`), `class` (layout only). `loading_overlay` covers a region (a `relative` parent) with a large one.

### `progress_bar`

How far something has got: a sync of 120 Hosts, an upload, a Source's review. A thin rounded track (`bg-line`) filled from the left, drawn as SVG so the width needs no inline style. The words beside it say the numbers ("Syncing: 40 / 120"); the bar adds the picture.

```heex
<.progress_bar value={@done} max={@total} label="Hosts synced" />
<.progress_bar max={@total} segments={[{@done, :ok}, {@proposed, :info}]} />
```

- Attributes: `value`, `max` (a zero `max` draws an empty bar), `label` (the accessible name: with it the bar is a `progressbar` with `aria-valuenow`; without it the bar is decorative, `aria-hidden`, because the text beside it says the numbers), `tone` (`:brand` default, `:ok`, `:info`, `:warn`), `segments` (in place of `value`: `{value, tone}` pairs drawn one after another, e.g. decided then proposed), `size` (`md` 8px, `sm` 6px), `id`, `class`.
- The upload hooks draw the same markup from JavaScript (`.gf-progress`, a `rect[data-bar]` whose width they set).

## Overlays

### `dialog`

One modal: `title`, body, `actions` slot. Sizes `:sm`, `:md`, `:lg`, `:full` (the range map). Open and close with `show_dialog/2` and `hide_dialog/2`. Escape, the backdrop and the Close button cancel it; focus is trapped inside and returns to what opened it.

Confirmation and discarding are patterns, not variants (see the component's docs and [patterns.md](patterns.md)): the title names the thing, the body the consequence, and a `danger` button repeats the verb ("Delete taxon"). A typed-name confirmation is a form in the body. Replaces three modal components.

### `tooltip`

A short explanation of what it wraps, shown below it on hover or keyboard focus: `bg-ink text-paper`, `shadow-float`, caption size; the wrapped content is described by it (`aria-describedby`). It doesn't show on touch screens, so nothing may depend on it. Attributes: `id`, `text`, `class`; the inner block is what it explains. The review's Trait card shows each value's definition with it (`review_value_list` `compact`).

## Content

### `chip_nav`

Links as a wrapping row of rounded chips, for filters that are their own pages (the Articles list's topics, `?tag=`). The current chip is filled with the brand and carries `aria-current="page"`; each may show a `count`. For page tabs, use `tab_nav`; for state labels, `chip`. Attributes: `label` (the nav's accessible name), `class`; slot `chip` with `href`, `navigate`, `patch`, `current`, `count`.

### `link_tile`

A link to another part of the site as a small tile: an icon on a sky square, a name, one line saying what is there. For a "More to read" row at the end of a page (the Articles list links the keys, glossary and filter guide). Attributes: `href`, `icon`, `name`, `class`; the inner block is the line.

### `prose`

Running text: rendered Markdown (`markdown` attribute, through `Gallformers.Markdown`, glossary terms linked) or the page's own markup (inner block). Styles headings (Markdown's `#` and `##` both at section size, since the page header holds the `h1`), paragraphs, links, lists, quotes (serif), images and captions, tables (scrolling sideways when wide), code, rules and `details` from tokens. Glossary links keep the text's color with a dotted underline. It sets no width: put it in a `max-w-text` column. Attributes: `markdown`, `size` (`:sm` 14px, `:base` 16, `:lg` 18, `:xl` 20; the source reader's A−/A+ steps through them), `font` (`:sans`, `:serif` for ID Notes and Source text), `class`. Used by articles (`:lg`), Privacy (`:lg`), the Gall page's ID Notes (`:sm`, serif) and source reader, and the admin article preview (`:sm`). Replaces the Tailwind typography plugin.

### `article_card`

An article in the Articles list. A band tinted by its topic (`tone`: `:sky` identification and guides, `:autumn` FAQ, taxonomy, undescribed, `:brand` the site and its people, `:plain` anything else) carries a large icon, tilted and cropped by the band's edge, and no text; then the title in the brand face, a three-line preview and a meta line (topic · author · date). The card is one link; `edit_href` adds an admin pencil in its corner. `featured` lays it out wide (band beside the text on wide screens, a larger title and preview, every topic named). Which tone and icon a topic gets is the page's choice (`ArticlesHTML`), not the component's. Attributes: `href`, `title`, `topic`, `icon`, `tone`, `meta`, `featured`, `edit_href`, `class`; the inner block is the preview.

### `change_entry`

One curator change in the change log (a `Gallformers.Audit.ChangeLog` group, via `Catalog.changes/1`): when (`time_ago`), who did what and from which Source (linked to its review); the Galls and taxa it touched and the taxon names it added (each taxon with its rank); what happened to its Facts as chips (added, made current, superseded, withdrawn, unsupported); and "Show the N Facts", each Fact in words with its Gall or taxon. Every Gall, taxon and Fact links **View** (the public page, at `#fact-<id>`, in a new tab) and **Edit** (the same page with `?edit`, the inline editor, matter ec2c). An inducer species has its species page (`/species/:id`, Edit at `?edit`); a taxon with no page of its own (an order) is found by search and edited in the taxonomy admin. The dashboard and the Changes page render the same entry. Attribute: `group`.

### Inline editing (`CurationComponents`)

Curators edit on the pages themselves (matter ec2c). These take data in the change-set contract's shapes (`Gallformers.Curation`, built on the ingestion side): items with their display text and flags, each flag `%{kind, text}` with its words from the back end. Fact keys travel as strings (`GallformersWeb.FactKey`: `host:7`, `trait:season:spring`).

- **`edit_toggle`**: in a page header, for admins: "Edit", or "Editing · Done" filled with the brand; a link to the page with `?edit` or without it. Attributes `editing`, `path`.
- **`edit_scope`**: with Edit on, what isn't edited here. `:elsewhere` (↗, edited on another page: says where, with Open ↗) or `:follows` (ⓘ, follows from other data: says from what, muted). The Editing notice keys the three kinds: ✎ actions (edit here), ↗, ⓘ. Attributes `kind`, `href`, `class`.
- **`fact_row`**: one Fact in a list with Edit on: what it says, the Sources stating it, and its actions (Withdraw, Correct…, Note…, as three text buttons) sending `fact_action` with the action and key. In the tray it shows "in your tray" (struck through when withdrawn) or, once submitted, "waiting to apply", and has no actions. Attributes `fact_key`, `sources`, `actions`, `pending`, `target` (a LiveComponent's, for the actions).
- **`fact_chip`**: one value of a Trait with Edit on, as a chip: the value, its Sources as its title, ✕ to withdraw it (`fact_action`). In the tray it has no ✕: struck through when withdrawn, marked green (`data-pending`) when added. Attributes `fact_key`, `sources`, `pending`, `target`.
- **`change_tray`**: pinned at the foot of every page while the curator's tray holds changes: the count, the changes on one line, Discard (`tray_discard`; the page confirms) and Review and apply (`tray_review`). Attribute `summary` (`%{count, lines, oldest_at}`).
- **`review_apply`**: the body of the Review and apply dialog. Each change with its flags as chips (new ok; already held neutral; supersedes, changed since, needs confirmation warn; editorial and adds-statement info; needs a reason, blocked danger; each flag carries `data-flag` and `data-variant`), "I'm sure" for one needing confirmation (`toggle_confirm`), Apply for it alone (`apply_item`; not while it needs a reason, is blocked, awaits confirmation or is already submitted) and Take out (`remove_item`); under a Fact change with evidence of its own (Add from observation's), that evidence (`data-part="evidence"`: its text, its observations as links, its Source linked); the evidence for the Fact changes without their own, asked once and saying so (why, observations, a Source; `set_evidence`), not shown when every Fact change has its own; Apply all (`apply_all`). Attributes `id`, `items` (each may carry its own `evidence`: `%{text, observations, source}`), `evidence`, `confirmed`, and for the Source picker (a `typeahead` outside the evidence form: `search_evidence_source`, `select_evidence_source`, `clear_evidence_source`) `source`, `source_query`, `source_results`. Observations show as their links (iNaturalist, BugGuide), so a pasted link round-trips.

### `key_couplet`

One couplet of a dichotomous key, set as a printed key sets it: the couplet number, then its leads a, b, c… each with its text, notes and images, and where it goes at the right ("go to 4" with the group label when the key gives one, or the result: the taxon linked to its Gall, its context under it; a result covering several Galls names each, linked). `state`: `:active` (the couplet to choose at: a brand edge, raised), `:visited` (a well; the chosen lead checked on an ok fill, the others muted) or `:unvisited` (dimmed, still choosable). A choosable lead is a button inside a row that sends `select_lead`. Attributes: `number`, `couplet`, `key_slug`, `state`, `chosen`, `image_url_map`, `gall_names`. `key_result` renders a result on its own.

### `key_path`

The path through a key. `layout: :panel`: "Your path" in the rail on wide screens, each step ("3b") with its lead's text, the result on an ok fill, then Copy link and (at a result) Copy as text, Back and Start over. `layout: :bar`: the same as one line pinned under the site header on narrow screens (`data-sticky-chrome`, so `ScrollToCouplet` clears it). Before the first choice it says where to start. A step sends `jump_to`; Copy link copies the `?path=` link (CopyToClipboard hook); Copy as text sends `copy_path`. Attributes: `layout`, `key`, `path`, `terminal`, `link`, `gall_names`, `class`.

## Third-party code

The system adds no dependencies. Current front-end dependencies and what happens to them:

| Dependency | Used for | Proposal |
|---|---|---|
| MapLibre GL, pmtiles | The range maps | Keep: real value, no lighter equivalent. |
| d3-array, d3-axis, d3-scale, d3-selection | One chart on the analytics page | Removed: replaced by `bar_chart` (server-rendered SVG). |
| @tailwindcss/typography | `.prose` on Markdown pages | Removed: replaced by `prose`. |
| topbar | LiveView's page-loading bar | Keep: tiny and standard; color it from a token. |
| Phosphor icons (vendored) | Interface icons | Keep. |
