# Inventory: typeaheads and the ID page

The behavior contract for the typeahead components and the ID page's filters, taken from the code on 2026-11-05 (design-system branch). A redesign may change how these look. It must keep every behavior listed here unless a change is explicitly approved and recorded below. Line references: `FC` is `lib/gallformers_web/components/form_components.ex`, `hook` is `assets/js/hooks/typeahead.js`, bare numbers in Part 2 are `lib/gallformers_web/live/id_live.ex`.

Two findings about the current code:

- `phx:focus_input` (listener at `assets/js/app.js:47-58`) is dead: nothing pushes it. Focus after clearing is restored by the hook's `pendingFocus`.
- The `phx-debounce` attributes on typeahead inputs (FC:993, FC:1161) do nothing: the inputs have no `phx-change`/`phx-keyup`; searches go through the hook's `input` listener, one round trip per keystroke.

## 1. The shared Typeahead hook

**State lives in JavaScript.** `highlightedIndex` (starts at -1) and `pendingFocus` are on the hook (hook:4-5). No `phx-update="ignore"`; `updated()` re-finds the elements, re-binds listeners and re-applies the highlight after every patch (hook:12-38). Elements are re-found each update and marked with `_typeaheadListener`, so a replaced input gets listeners and none is bound twice (hook:40-68).

**Searching** (hook:51-60): the `input` event (not `phx-keyup`, which misses paste and autofill) pushes `data-search-event` with `{value}` plus `type` when `data-search-type` is set, to `[data-phx-component=data-target]` when `data-target` is set, else to the LiveView (hook:71-78). No client-side stale-response check: events arrive in order, and LiveView never patches a focused input's value.

**Keys in the input** (hook:86-129):

| Key | Behavior |
|---|---|
| ArrowDown | preventDefault; highlight +1, clamped at the last item (no wrap); nothing if no results; scrolls into view (`block: nearest`). |
| ArrowUp | preventDefault; `max(i-1, 0)`, so from none it highlights the first item; no wrap. |
| Enter | preventDefault always (never submits a form). With a highlight: `.click()` the option, highlight reset to -1. No highlight and non-blank text: pushes `data-close-event` (only multi_select_dropdown sets it) and empties the input. Empty: nothing. |
| Escape | preventDefault; clears the highlight only. Doesn't close the list or clear the text. |

Tab, Home, End and Backspace are not handled.

**Keys on a selected value** (`[data-typeahead-selected]`, single typeahead only; hook:131-152): Escape, Backspace or Delete set `pendingFocus` and push the clear event; any single-character key pushes clear, then a search for that character. After the patch, `updated()` focuses the new input.

**Highlight across patches** (hook:31-37, 154-165): -1 when results are empty; clamped when the list shrinks; otherwise kept. Shown with `data-highlighted` and `aria-selected`. Group headers aren't navigable (only `[data-typeahead-option]`).

**Clearing the input after a pick** (hook:22-28): only when the root has `data-query` and it is `""` and the input isn't empty. (An earlier version erased the first typed character.)

## 1a. `typeahead` (single), FC:892-1061

- Root `div#id` with the hook and `data-clear-event`, `data-search-event`, `data-query`, `data-target`. `<label class="gf-label">` without `for`; `label_suffix` slot; required `*`.
- **Selected:** `div#{id}-selected` `tabindex=0`, `aria-label="Selected: X. Type to search, or press Escape to clear."`, the `display_fn` text in italics, an × (`tabindex=-1`, `aria-label="Clear selection"`) that sends the clear event (no focus restore on that path). No input while selected.
- **Unselected:** `input#{id}-input` `role=combobox`, `aria-controls`, `aria-autocomplete=list`, `aria-expanded` when the list shows; no `aria-activedescendant`. List `div#{id}-results` `role=listbox` (max-h-60, scrolls). Options are `<button role=option data-typeahead-option phx-click=select phx-value-id>`, rendered by the `:result` slot or an italic `display_fn`.
- **Grouping:** with `group_key`, a `role=presentation` header before each change of group.
- **No matches:** "No matches found" (`role=status`) at 2+ characters with no results and no create option. No loading state.
- **Create option:** `allow_new` + `create_event`, 2+ characters, no exact match → `Create "query"`. Unused today.
- **Closing:** no blur handler, no click-away: the list closes only when the server empties results or query.

## 1b. `multi_select_typeahead`, FC:1093-1203 (ID page: plant parts, textures)

- Events from `name`: `{name}_search`, `_focus`, `_blur`, `_select`, `_remove`, `_clear`. Hook on `div#{id}-wrapper` with `data-query`, no close event.
- Chips (`gf-chip gf-chip-sm`, × sends `_remove`) in **options order**, then the input (`phx-focus`/`phx-blur`, `role=combobox`). Placeholder only when nothing is selected. A "Clear all" × sends `_clear`.
- The dropdown shows while focused (server-tracked) with options left: every unselected option matching all typed words as substrings (case-insensitive, `TextMatch.matches_all_terms?`), no limit, scrolls (max-h-48), no "no results" message.
- `onmousedown="event.preventDefault()"` on the dropdown keeps focus, so the list stays open for the next pick. Chip × has no guard (clicking one while typing closes the list).

## 1c. `multi_select_dropdown`, FC:625-778 (article tags only)

- Static mode (`options`, server-side `TextMatch`, selected left out) or async mode (`search_results`).
- `data-search-type`, `data-query`, `data-close-event` on the root. Opens on container click and input focus; closes on blur, click-away, or Enter with text and no highlight. Dropdown and chip × both guard mousedown.
- No ARIA roles. For article tags, closing with text **adds it as a new tag**.

## 1d. `multi_select` (pills), FC:300-332

Toggle buttons sending `on_toggle`. Used nowhere but its own docs.

## 1e. Where typeaheads are used

| Where | id | Notes |
|---|---|---|
| `home_live.ex:162` | `home-host-picker` | `search_host` ≥2 chars, ≤50 results; a pick goes to `/id?h=Name`. |
| `id_live.ex:1005, 1029, 1081` | host, genus, place | See Part 2. |
| `id_live.ex:1062, 1138` | `plant_parts`, `textures` | `multi_select_typeahead`. |
| `admin/images_component.ex:610` | source picker | The only `target={@myself}`. |
| `admin/review_live/item_row.ex:1580` | dynamic | `target`, `group_key` for plants. |
| `admin/review_live/facts.ex:604` | `fact-editor-plant` | `group_key={:group}`. |
| `admin/taxonomy_live/{index:348, new:569/636, edit:530/592}`, `source_live/edit.ex:421`, `gall_live/edit.ex:590` | various | Plain single typeahead. |

**Host results** read "Accepted (synonyms…, common names…)" (`format_host_display`, id_live.ex:965-972; synonyms then common names), rendered with `taxon_name` (binomial italic, bracket upright), plus "(incomplete)" when not datacomplete. Ranking: exact, then prefix, then the rest; every word must appear in one name or the accepted name. A selected Host shows only its accepted name.

## 2. The ID page

**The URL is the state.** Every filter change calls `push_filter_patch` (829-832); `handle_params` re-parses the URL, re-resolves host, genus, place and family, and reloads results (147-153, 327-343). No debounce except the name filter.

Top to bottom:

0. **Region scope bar** (994-998; `ui_components.ex:845-981`): "Filtered to {continent}" or "All Regions" with a continent menu → `change_region` (762-775). The continent isn't in the URL. "Set as default" writes or removes `localStorage.gf_continent`, sets `gf_continent_dismissed` and reloads; "Reset" returns to the default. The default arrives via connect params (`app.js:32`, `continent_scope.ex:35-51`). The first-visit **region prompt** shows only when neither localStorage key is set; picking saves both, "Show all regions" saves only the dismissed key.
1. **Host Plant Species** (single typeahead, 1005-1023): `search_host` (≥2 chars, ≤50) **clears the genus on every keystroke** without a patch (478-495); `select_host` clears the genus and patches `h`; `clear_host` clears only the host and keeps every other filter.
2. "OR", **Host Plant Genus / Section** (1029-1050): `search_genus` (≥2, ≤10; genera, subgenera, sections; prefix on names or common names contain) clears the host the same way. Results show "[Section]"/"[Subgenus]" and common names; selected shows "Name [Section] - common names". URL `g` + `gt` (rank tried first).

**The filter panel appears only once a Host or genus is chosen** (1058):

3. **Plant Part(s)**: `multi_select_typeahead` over every plant_part value, sorted. A pick is validated and added to the front. URL `lo` (comma-joined; legacy `leaf_anywhere` → `leaf`). **ANY/ALL toggle** (1073-1077, 1228-1249) only with 2+ values; default ANY; `lol=and` written only for ALL, and kept in the URL even when the toggle is hidden.
4. **Detachable**: Any / Integral / Detachable / Both; `de` (legacy 0-3 translated).
5. **Region**: single typeahead (`search_place`, ≥2, ≤10, countries then states/provinces, **limited to the current continent**, grouped "Countries" / "States & Provinces", states as "Name — Parent"). URL `pl` (code; legacy names rewritten). A chosen place **replaces** the continent scope.
6. **Family**: single select of the inducer families of the Host's or genus's galls; `fa` (name; legacy numbers via crosswalk). Like every trait filter, it **survives a Host change**; if the new Host lacks it, the filter still applies while the select reads "Any Family".

Then a "Show/Hide Advanced Filters" toggle (local state) and **Clear Filters** (red, small; 1110-1121).

**Advanced filters** (1124-1202): a warning that many galls lack these properties; Season (`se`), Texture(s) (multi, ANY/ALL, `te`/`tel`), Alignment `al`, Form `fo`, Walls `wa`, Cells `ce`, Shape `sh`, Color `co`; "Show only undescribed galls" (`un=1`). Each single filter is its own `<form phx-change="change_filter" phx-value-filter=…>` with an "Any X" prompt; values are validated, "" means nil. Old parameter names and trait IDs are translated (79-197, 231-289).

**Clear Filters** (`clear_all`, 778-785) resets parts, textures and both logics, every trait, detachable, place, family and undescribed. It **keeps** the Host or genus, the continent scope, the name filter, the advanced-panel state, and any half-typed text in the multi-select or place inputs. It reads as destructive (red) and leaves the name filter, which is confusing.

**Results** (882-924, 1339-1426): name order, no sort control. No Host or genus: an instruction box, and the name filter is reset. Incomplete Host: a yellow warning. Count line "Showing N [of M] [(T unfiltered)] galls" (`total_count` is only set when filters are at defaults, so a URL with filters shows "(0 unfiltered)", and a Host change with filters keeps the old T). **Name/trait filter** (1364-1385): shown when results aren't empty; `phx-keyup` debounced 200 ms; searches loaded results (every word in the name or a whole trait term; stopwords ignored); × clear; not in the URL; survives filter changes. **Empty states:** with a place or continent and matches elsewhere, "No galls found in {continent} … N galls in other regions … try All Regions" (names the continent even when a place caused it); otherwise "no galls that match your filter… undescribed" with a link to the ID guide's troubleshooting. A troubleshooting footer follows every non-empty grid.

## Hard-won lessons

1. Searches use `input`, not `phx-keyup` (paste, autofill) — 816edd68.
2. The hook clears a focused input itself, only when `data-query` exists and is `""`; an earlier version erased the first typed character — d37e16ed, a7893696, 6ff8db16.
3. `data-search-type` is forwarded so `type`-keyed handlers don't crash — f8a3d14a.
4. `onmousedown preventDefault` on dropdowns and chip × stops blur from beating the click.
5. `_typeaheadListener` re-binds after the input is replaced, never twice.
6. `pendingFocus` focuses the new input after a keyboard clear; type-to-replace on a selected value.
7. Enter always preventDefaults: never submits an enclosing form.
8. Group headers are `role=presentation` and skipped by the keyboard.
9. "No matches found" from 2 characters — 000c0804.
10. The selected text has an explicit dark color because a browser theme (Zen) made it invisible — 699e8f5b.
11. Host and genus exclude each other while typing; Host search returns 50; the card's overflow-hidden was removed so the dropdown isn't clipped — f08be9f7.
12. The name filter survives filter changes — 699e8f5b.
13. The "other regions" count uses all active filters — 000c0804.

## Behaviors a redesign must preserve

- Search on every `input` event; payload `{value[, type]}`; to the LiveComponent when `target` is set. Minimums and limits as above (host ≥2/50, genus ≥2/10, place ≥2/10 within the continent).
- Arrow keys clamp (no wrap); ArrowUp from none highlights the first; arrows and Enter preventDefault; Escape only clears the highlight; Tab/Home/End unhandled.
- Enter on a highlight clicks it; Enter with text and no highlight sends the close event (tags: adds a tag) and empties the input.
- On a selected value: Esc/Backspace/Delete clears and focuses the input; a printable key clears and searches with it.
- Highlight in JavaScript, kept across patches (reset when empty, clamped when shorter), shown with `data-highlighted` + `aria-selected`.
- Input emptied only when `data-query` is `""`; the first typed character is never erased.
- Mousedown guards on dropdowns (and chip × in multi_select_dropdown); multi-select keeps focus and stays open after a pick.
- `multi_select_typeahead`: server-driven open state; all-words substring match; selected left out; no limit; chips in options order; Clear all. `multi_select_dropdown`: opens on click or focus, closes on blur, click-away or Enter.
- Single typeahead: no blur/click-away close; selected box `tabindex=0` with its label; × `tabindex=-1`.
- ARIA roles and attributes as listed (no `aria-activedescendant` today).
- Group headers on change, not selectable; "No matches found" at 2+; create option at 2+ with no exact match.
- Host results "Accepted (synonyms, common names)" + "(incomplete)"; selected Host shows the accepted name; genus "[Section]/[Subgenus]" + common names; places "Name — Parent".
- ID page: Host and genus exclude each other on every keystroke and pick; the filter panel is hidden until one is chosen.
- The URL is the state; parameters `h g gt lo lol te tel de pl fa co sh al fo wa ce se un`; legacy names and IDs keep working; unknown values are dropped.
- ANY/ALL only with 2+ values, default ANY, only ALL in the URL.
- A place replaces the continent scope; the continent isn't in the URL; it is saved only through "Set as default" (reload); the first-visit prompt is driven by the two localStorage keys.
- Clear Filters resets every filter, keeps Host/genus, region, name filter and the advanced-panel state.
- Name filter on loaded results, 200 ms, not in the URL, survives filter changes, reset when no Host/genus.
- Results live on every change, in name order; the two empty states; the troubleshooting footer under results.

## Approved changes

- **Unfiltered count fixed** (Jeff, 2026-11-05: "the quirk sounds like a bug"). `total_count` is now counted with the filters reset whenever any filter is set, so a page opened with filters, or a new Host under filters, shows the true "(N unfiltered)". Test: `id_live_test.exs` "a page opened with filters counts the Host's unfiltered galls".
- **Typeahead look restyled, behavior untouched** (2026-11-05): only class strings changed in `typeahead`, `multi_select_typeahead` (selected box, results list, options, group headers, chips box, input, clear buttons) and the `.gf-label` / `.gf-input` / highlight CSS. Every id, data attribute, ARIA attribute, event, `tabindex` and mousedown guard is unchanged; the selected text keeps an explicit color (`text-ink`).
- **Clear filters** (Jeff, 2026-11-05): keeps its behavior (clears the trait filters only; never the Host). It sits with the trait filters, as a secondary button that says how many it will clear ("Clear 3 filters").
- **Home page on the design system** (Jeff approved the round-4 home, 2026-11-05). The `home-host-picker` typeahead is unchanged (same events, ≥2 chars, ≤50 results, a pick goes to `/id?h=Name`); only its label and placeholder text changed ("What plant is it on?"). The unused `go_to_id` event and its "Find Galls" button are gone: a pick navigates straight away, so the button only ever opened `/id`, which the header's Identify does. New: "Show me another" (`shuffle`) draws another random Gall.
