# Inventory: forms (except typeaheads)

Every usage of the form components other than the typeahead family (see [typeahead-and-id.md](typeahead-and-id.md)), and the save models in use, taken from the code on 2026-11-05 (design-system branch). A replacement keeps every behavior here unless a change is approved and recorded under "Approved changes". Paths are under `lib/gallformers_web/`.

## Findings

- **No callers:** `field_wrapper`, `radio_group`, `file_dropzone`. The new `field` and `facet_group` have no app callers yet; `search_field` has one (the site header).
- **Probable bug:** `.input`'s error text uses `text-error`, and its wrappers `fieldset`/`label` classes; none is defined in `assets/css` (DaisyUI leftovers), so error text may not be red; only the icon shows. Not yet checked in a browser.
- **No `beforeunload` or navigation guard anywhere;** only Cancel is protected by the discard confirmation.

## 1. `form` (core_components 51)

`for`, `as`, `rest` (autocomplete, name, rel, action, enctype, method, novalidate, target, multipart); wraps `Phoenix.Component.form` and adds an `onkeydown` that blocks Enter unless the target is a BUTTON or TEXTAREA, so Enter in a text field never submits (816edd68: Enter confirming a typeahead pick saved the form; 00d6b0e0 let textareas through). `Phoenix.Component.form` isn't imported, so every `<.form>` is this wrapper.

`<.form>` sites: gall_live/edit 508, 604, 646, 748; taxonomy_live/edit 503, 627, 657, 672; taxonomy_live/new 629; source_live/edit 264, 442; glossary_live/form 87; key_live/form 379; profile_live 166; article_live/form 624, 897; vocabulary_live 628, 665, 708, 797, 806, 831, 852, 1036, 1050; review_live/item_row 1408, 1458, 1508; review_live/facts 597; review_live/source 507; review_live/sources 117; review_components 1589.

Raw `<form>` sites (Enter submits): search boxes (tree_components 30, search_live 339, glossary_live 108, intermediate 157, genus 309, family 129, section 138, admin glossary index 85, source index 76, gall index 63, article index 119, taxonomy index 231, review_components 1721); filter selects (id_live 1256, 1275, 1297, 1316; host_range_live 517, 533, 552, 564; article index 128, 137; article form 556; taxonomy edit 560); edit forms (images_component 637, content_image_manager 184, ops_live 86, inat_import_component 114, the dangerous delete form 1304); GET forms (layouts 113, 140).

Relied on: submit buttons outside their form via `form=` (taxonomy new 707, the article image-insert modal, images_component's modal footer, the dangerous delete modal); `phx-value-*` on the `<form>` element is sent with change events (id_live; c3878f2d).

## 2. `input` (core_components 157–329)

Attrs `id`, `name`, `label`, `value`, `type`, `field`, `schema`, `errors`, `checked`, `prompt`, `options`, `multiple`, `class` (replaces the default), `error_class`, `required` (nil/true/false); `rest` accept … step plus globals (`phx-debounce`). Clauses: FormField (errors only when `used_input?`; `required` = explicit, else `SchemaFields.required?(schema, field)`, else false; `[]` appended when multiple; id from the field); hidden; checkbox (hidden `value="false"` first, carrying `disabled` and `form`, so a disabled checkbox posts nothing; `gf-checkbox`); select (`options_for_select`; `prompt` renders `<option value="">`, even `prompt=""`; `gf-select`/`-error`); textarea; everything else `gf-input`/`-error`. The label wraps the control (implicit label); a span only when `label` is set, red `*` when required; required sets native `required` **and** `aria-required` (so the browser blocks submit).

Error timing: changeset forms show errors only for touched fields, then all after submit; map forms (`to_form(map, errors:)`) show them at once (gall edit 427 statement, source edit 193 retract, review source 233 deny); bare calls with `errors=` always show (vocabulary).

Sites:
- **gall_live/edit** (four forms, each saved separately, no dirty tracking): editorial (`validate_editorial`/`save_editorial`): 515 `gallformers_code` with the only `phx-debounce="300"` (a test checks a taken code is shown as typed), 521/531 selects with prompts "Unknown"/"None", 541 checkbox `datacomplete` `disabled={@lock != :unlocked}` (server forces "false" when locked); name (`validate_name`/`save_name`): 606, 611, 618, redraws the derived-name preview; errors also in a block (620); note 647 textarea (submit only); exclusions 754 textarea in a map form.
- **taxonomy_live/edit:** 510 rename, 633/635 synonym and sensu, 664 common name (map forms, submit only; blank refused with a flash); 561 section select **saves on change**; 674 select `prompt=""`, 682 checkbox (editorial, submit only).
- **taxonomy_live/new:** 631, 632, 659 (map form, `validate` + `mark_dirty`; a second `validate` clause catches change events from the typeahead inside the form).
- **source_live/edit:** 269–383 with `schema={Source}`; 308 readonly url from the license (still posts; tested); 362 authors textarea joined/split by newlines; 443 retract date.
- **glossary_live/form** 89, 100, 111 (`schema={Glossary}`); **key_live/form** 420–444 (`schema={Key}` on title, version); **article_live/form** 632–645 (`schema={Article}`), 730 checkbox, 557 filter select, 905 (required), 916, 936 (number min/max, `w-32`) in the image-insert form; **profile_live** 169 (required), 207, 264; **review_live/source 512** (required textarea, deny modal); **vocabulary_live** 671, 681, 688 (bare, explicit ids, `errors=` after submit); **ops_live 87**; **content_image_manager** 191–222; **images_component** 654–769 (`label=""` renders an empty span; the visible label sits outside, so no accessible name; 704 readonly with a class override).
- **Filter selects:** host_range_live 518, 534, 553, 565; article index 129, 138; id_live 1257, 1276, 1298 + checkbox 1317: bare `name="value"`, one per raw `phx-change` form, no id; host range labels aren't linked.

## 3. Raw controls

article_live/form 660 (content textarea built by hand, required, **no error display**), 687 (hidden file input for ArticleImageUpload), 975 (`size_radio`); profile_live 181 (disabled nickname), 223 (`user[inat_username]` → `inaturalist_url` on validate and save), 239/253 (`type="url"`, browser validation, **no errors shown**); key_live/form 401 (JSON textarea: InputEvent `json_changed` + `phx-debounce=500`; a good parse overwrites the metadata form and marks dirty; `merge_json_only_fields` adds `couplets` and `authors` on save, tested; `couplets` is required with no input, so its error never shows); vocabulary hidden inputs, `gf-select`s with `sr-only` labels, `candidates[]` checkboxes, tick checkbox; review item_row selects that pick on change (1410, 1510, 1518), search 1460 (debounce 150), 1250; review facts 635, sources 119, source 550; review_components 801/1382 radios with `phx-click` + `phx-target`, 1475 value lists, 1598 notes (`note_draft` on change, `save_note` on submit); `phx-click` checkboxes (taxonomy new 612/672, index 293, host_range 677/701 disabled while running, images_component 268/326, inat 195, place_drill_down 279, data_components 241, powo_diff_review 282/313); `phx-keyup` inputs outside forms (range_editor 644 autofocus debounce 300; id_live 1365 debounce 200); images_component 681 license select with its own `phx-change` inside a form with another; inat_import 115 `phx-change` on the input; layouts 141 mobile search.

## 4. `search_input` (form_components 356)

`id`, `name`, `value`, `placeholder` ("Search..."), `label` (falls back to placeholder for `aria-label`), `class`, `size` `:default`/`:sm`; `rest` phx-change, phx-submit, phx-debounce, form, data-typeahead-input; `type="search"`. Sites: in raw `phx-change`/`phx-submit` forms, debounce 300: tree_components 31, intermediate 158, glossary 109, section 139, genus 310, family 130, search_live 340 (change event `search_input` differs from submit; window keydown parent), taxonomy index 237, admin glossary index 86, source index 77, gall index 64, article index 120; review_components 1727 (`:sm`); vocabulary 737 (in a `.form`, debounce 200); host_range 579 (`:sm`, **`phx-keyup="search"`**, no form, `name="value"`).

## 5. Others

- **`toggle`** (form_components 446): hidden "false", `sr-only` peer checkbox, track; ops_live 78, 112 (`phx-click`, saves at once); country_drill_down 166 (`form="detached"` keeps it out of the parent form's change events; `phx-target`; nested in another `<label>`).
- **`drill_down_panel`** (1236): `open` (w-80 / 0), `country_name`, `on_close`, `target`, `header_extra`; country_drill_down 155, place_drill_down 202 (LiveComponents reporting with `send(self(), …)`).
- **`dangerous_delete_modal`** (1277): see [actions-and-feedback.md](actions-and-feedback.md).
- **`selectable_tree`** (1385): `id`, `label`, `groups`, `selected`/`expanded` MapSets, five events, class hooks, `target`, `group_footer`; three-state group checkbox via IndeterminateCheckbox; phx-click only; select/deselect all; `max-h-96`. powo_diff_review 191, 209. **Lesson:** range_editor 584 stops `onchange`/`oninput` propagation around it; otherwise form recovery resets the checkboxes.
- **`form_actions`** (live/admin/form_components): Cancel → `request_cancel`; Save submit disabled unless dirty (and `form_valid`, which no caller passes); new/edit labels. profile 269, key form 467, source edit 387, glossary form 136; article form 746–763 and taxonomy edit's range card 739–761 hand-build the same pair.
- **`duplicate_host_warning`:** reasons `:name_match`, `:alias_match` (+ `alias_type`), `:wcvp_id_match`, each linking `/admin/taxonomy/:id`; taxonomy new 597, 662.
- **`FormHelpers`:** `init_form_state`; `mark_dirty` on any change (even back to the original); `reset_dirty`; `handle_form_event` (`request_cancel` opens the discard modal when dirty, else `close_form`; `cancel_discard`; `confirm_discard`); `discard_confirm_modal` (fixed id); `crud_helpers: true` adds `init_admin_form`, `apply_new_action`, `apply_edit_action` (not found → flash + redirect), `handle_validate`, `handle_save`, `handle_delete`, `after_*` (stays on the page after an update with a clean form). Latent trap: error branches call `to_form(changeset)` without `as: form_key()`. Users: glossary form, key form (crud), profile, source edit, article form, taxonomy new, taxonomy edit (dirty tracks only the range editor; `wcvp_sync` refuses while dirty).

## Save models in use

1. **Explicit Save with dirty tracking and a discard confirmation:** glossary, key, source details, profile, article, taxonomy new, taxonomy edit's range card. Validation on every keystroke (no debounce except the gall code); Save disabled until something changes; profile redirects via `refresh-session`, article redirects, the rest stay.
2. **Explicit Save per section, no dirty tracking, no confirmation:** gall edit (editorial, name, note, exclusions), taxonomy edit (rename, synonym, common name, editorial), source retraction, vocabulary, ops banner text, review deny and notes, the fact editor.
3. **Save on change or click:** taxonomy edit's section select, ops toggles, review pickers (held on the server until the decision), ticks, every list filter.
4. **Modal compared against the original:** images_component (`image_changed?`: reverting makes it clean; "Discard Changes" discards without asking); content_image_manager (also swallows save errors silently).

## Must preserve

- **`form`:** Enter submits only from buttons and textareas; `form=` on outside submit buttons; `phx-value-*` on the form sent with change events; every `rest` attribute.
- **`input`:** error timing (`used_input?` for FormFields, immediate for map forms and explicit `errors`); required order and native `required` + `aria-required`; the checkbox's hidden "false" and disabled-posts-nothing; select `prompt` (including `""`) and `multiple`; `value` override; readonly posts; `class` replaces, `error_class`; implicit labelling and the `label=""` callers; bare name/value with no id; `name="value"` in raw forms; debounce via `rest`.
- **Raw controls to fold in:** article content and profile URL/iNat fields (no errors today); the key JSON textarea's InputEvent and merge-on-save; phx-click checkboxes with `phx-target`; element-level `phx-change` inside a form.
- **`search_input` → `search_field`:** `type="search"`; aria-label falling back to the placeholder; `:sm`; works in change/submit forms and with `phx-keyup` outside a form; debounce passes through; cover every caller above.
- **`toggle`:** hidden "false"; `form` on both inputs ("detached"); `phx-click` + `phx-target`; disabled look.
- **`drill_down_panel`, `dangerous_delete_modal`, `selectable_tree`, `form_actions`, `duplicate_host_warning`, `FormHelpers`:** as described above, including the isolation of `selectable_tree` from the parent form and the range-editor dirty state blocking WCVP sync.

## Approved changes

- **Controls restyled on tokens** (2026-11-05, the catalog's approved restyle): `.gf-label`, `.gf-input`, `.gf-select`, `.gf-textarea`, `.gf-checkbox`, `.gf-search-input(-sm)`, `.gf-hint`, `.gf-error` moved from `legacy.css` to `system/components.css`: one control height (`h-ctl`), border, radius and focus; labels at the meta size. CSS only: no markup, attribute or behavior change.
