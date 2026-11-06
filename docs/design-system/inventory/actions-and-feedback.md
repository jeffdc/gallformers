# Inventory: buttons, dialogs and messages

Every usage of the action, dialog and message components, and what each relies on, taken from the code on 2026-11-05 (design-system branch). A replacement keeps every behavior here unless a change is approved and recorded under "Approved changes". Paths are under `lib/gallformers_web/`; line numbers point to the opening tag.

## Bugs found while inventorying

- `live/admin/gall_live/edit.ex:349` calls `put_flash(:warning, …)`; `flash_group` renders only `:info` and `:error`, so the message never shows.
- `admin/images_component.ex:98` gives a component-scoped flash `auto_dismiss` with `phx-target={@myself}`, but the AutoDismiss hook's `pushEvent` goes to the parent LiveView: the flash hides in the browser and is never cleared on the server.

## 1. Buttons

### `ActionComponents.button`

Variants primary, secondary (default), ghost, danger; retiring `soft`/`warning` render as secondary, `size="lg"` and `shape="pill"` are ignored. `icon`, `icon_only` + `label`; passes href/navigate/patch/method/download/name/value/disabled/type/form/phx-disable-with/target/rel/replace and globals; `type` defaults to `"button"`.

Retiring values in use: `variant="soft"` at 16 sites (vocabulary_live 564, 603, 654, 804, 845, 865, 902, 1009, 1048; review_live/step 298, 309; review_live/source 401; as a toggle's unselected state at renames 79, source 362, sources 99). `shape="pill"` at 5 sites, all `size="sm"` toggles switching primary/soft or primary/secondary: genus_live 411, 424 (`aria-pressed`), renames 79, review_live/source 362 (`aria-pressed` as a string), review_live/sources 99. These are really segmented or filter controls, and their `aria-pressed` use is inconsistent.

By kind:
- **Submit:** ops_live 95 (`phx-disable-with="Saving..."`, the only one); gall_live/edit 557, 626, 649, 761; taxonomy_live/edit 512, 637, 666, 688; vocabulary 654/698/804/822/845/865/1048/1066; facts 639; review_components 1605; review_live/source 515 (danger, deny modal); inat_import_component 125 (disabled when empty, `data-role`); images_component 793 and dangerous_delete (form_components 1328) submit with `form=` from outside the form; content_image_manager 237 and images_component 793 disabled until dirty.
- **Modal footers:** host_range_live 777/778, 800/801, 834/835, 888, 936; images_component 790, 827, 830, 908, 916; content_image_manager 229, 265, 273; form_components 1325/1328 (components use `phx-target={@myself}`).
- **Events:** review_components 977/998/999, 1520, 1663, 1736; item_row 1070, 1083, 1211; review_live/source 338, 401, 452, 514; step 298–338; taxonomy_live/edit 548, 781, 784 (`data-confirm="Replace this plant's Host range with WCVP's?"`), 793, 802; range_editor 572; taxonomy_live/new 621; powo_diff_review 149, 159; id_live 1118 (danger, sm); inat 142, 221, 230, 253; vocabulary 573, 762, 899–935, 1019, 1022.
- **Links:** review_components 1053, 1147, 1148, 1165.
- **Disclosures:** domain_components 229, form_components 261, genus_live 355, 389 (`aria-expanded`/`aria-controls`).
- **Off-system `class`:** genus_live 355 (`w-full text-left shadow-sm`), 389, 411/424, 450.

### Raw `class="gf-btn …"`

host_range_live 594, 626, 634, 641; `form_actions` (live/admin/form_components 34 Cancel → `request_cancel`, 41 submit disabled unless dirty and valid; used by profile_live 269, source_live/edit 387, glossary_live/form 136, key_live/form 467); taxonomy_live/edit 740 Cancel, 743 "Save & Confirm Range" (`bg-green-600`, `phx-value-confirm`), 753 Save (disabled unless dirty), 831 Delete (opens the dangerous modal); taxonomy_live/index 246, 249, 269, 273, 369, 372 (move disabled until a target); taxonomy_live/new 703, 706 (`form="taxon-form"`); "New" links glossary_live/index 95, key_live/index 96, article_live/index 147; deletes glossary_live/form 126 (**browser `data-confirm`**), key_live/form 450 and article_live/form 734 (dangerous modal), key_live/form 458; source_live/edit 406 (`data-confirm`), 444; article_live/form 680 (`data-upload-trigger`, ArticleImageUpload), 695, 777.

### `edit_button` (data_display_components 815)

No call sites: dead.

### `table_actions` / `action_button` (data_display_components 958, 989)

`action_button`: required `icon` and `label` (aria-label and a hover-only tooltip, not shown on focus); variants default/primary/danger; href/navigate/button; `confirm` → `data-confirm` (button branch only); `rest` only phx-click, phx-value-id, disabled. Used in index tables: key_live/index 134–146 (delete opens the dangerous modal), glossary_live/index 124–136 (delete uses **`confirm=`**, a browser confirm), article_live/index 206–219 (View passes `target="_blank"`, which isn't in `rest`: check it renders; delete opens the dangerous modal). Deletes are inconsistent across the three.

### `admin_edit_link` (rank_page_components 23)

Admin-only pencil link (`href`, full page load) to `/admin/taxonomy/:id`, `title="Edit in admin"`, no aria-label. intermediate_live 128, genus_live 289, section_live 114, family_live 107.

### Raw `<button>` (161)

- Icon close/dismiss: core_components 107 (flash, no handler; the click bubbles), 630, 640; ui_components 388; form_components 171, 731 (mousedown guard), 974 (`tabindex=-1`), 1145, 1170, 1245; data_components 59; gall_live 642; id_live 1377; article_live/form 547, 885.
- Icon actions: images_component 119/135, 218/229/240 (`data-action`), 466/476/487; content_image_manager 102/113; gall_live 424, 685, 828 (CopyToClipboard, `data-copy-*`, no `type`).
- Tabs and toggles: ui_components 566 (`tabs`, Tabs hook); article_live/form 592/606; analytics_live 283; galls_browse_live 104; id_live 1230 (ANY/ALL); users_live 88 (`role=switch`); country_drill_down 177/193/228/244; facts_components 172/182; form_components 315; powo_diff_review 323.
- Disclosures: tree_components 41/45/77; facts_components 548, 644; review_components 1275, 235; form_components 1407/1431; powo_diff_review 258/293; id_live 1111; gall_live 726; about page 234; layouts 127 (static `aria-expanded`), 327; action_components 118; ui_components 912.
- Menu items: facts_components 660; ui_components 932/944.
- Forms: form_helpers 477/484; article_live/form 744, 751, 951/958, 858/865; range_editor 690/697 (spinner while loading); images_component 439/454, 543 (`data-upload-button`, enabled by a hook); content_image_manager 159; key_components 31/47/54/61; place_drill_down 209–304; country_drill_down 213–295; host_range_live 648/655/662; host_live 362/372; ui_components 201, 270/281, 871/883/962/970; home_live 182; search_live 369; gall_live 634, 696, 759/768.
- Carousel: data_display_components 140/150, 387/396, 218, 244, 332, 774 (`data-prev/next/open-info/close-info/close-lightbox`).
- Missing `type` (would submit inside a form): tree_components, key_components, galls_browse_live 104, host_live 362/372, gall_live CopyToClipboard, the about page.

## 2. Dialogs

### `CoreComponents.modal` (core_components 596)

`id`, `show`, `on_cancel`, `class` (`gf-modal-sm/md/lg/xl` or `max-w-*`); slots header, body (required), footer. `data-cancel = JS.exec(on_cancel, "phx-remove")`; Escape, click-away and × run it; `focus_wrap`; body scroll lock; 300 ms in / 200 ms out; the × renders only with a header. `show_modal` focuses the first element without `push_focus` while `hide_modal` calls `pop_focus`. `show_modal`/`hide_modal` have no call sites: **every modal is server-driven** (`:if` + `show` + `on_cancel={JS.push(...)}`).

Call sites: gall_live 748 (Source detail, `max-w-3xl`, A-/A+ in the header, CopyToClipboard in the footer, opens from `?source=`); host_range_live 764, 784, 807 (→ `cancel_confirm`), 850, 894; images_component 565 (edit; footer submits with `form=`), 805 (delete), 843 (view, `max-w-7xl`), 863 (copy confirm) — all `target: @myself`, and the component's own Escape → `cancel_copy` can collide; content_image_manager 170, 247 (buttons in the body); taxonomy_live/index 336 (move; typeahead in the body); range_editor 631 (`phx-keyup` debounce 300 + spinner); review_live/source 504 (deny; required textarea, buttons in the body).

### `dangerous_delete_modal` (form_components 1277)

`show`, `item_type`, `item_name`, `consequences`, `confirmation_value`, `id`. Modal `gf-modal-sm ring-2 ring-red-600`, cancel → `cancel_delete`; red consequences list; form `#{id}-form` `phx-submit="confirm_delete"`; input `id="dangerous-delete-confirmation"` (not scoped to `@id`), autofocus, autocomplete/capitalize/spellcheck off, InputEvent hook → `update_delete_confirmation`; submit `dangerous-delete-submit` with `form=`, disabled until the typed value equals `item_name`; the server re-validates. Sites: taxonomy_live/edit 849, key_live/form 485, key_live/index 163, article_live/index 242, article_live/form 803. Tests depend on the ids.

### `discard_confirm_modal` (live/admin/form_helpers 461)

Fixed id `discard-confirm-modal`, `gf-modal-md`, cancel → `cancel_discard`; "Keep Editing" → `cancel_discard`, red "Discard Changes" → `confirm_discard`. `request_cancel` shows it only when `form_dirty` (`handle_form_event`, form_helpers 176); article_live/form 224 intercepts first. Sites: profile_live 273, taxonomy_live/edit 847, taxonomy_live/new 713, key_live/form 483, glossary_live/form 140, source_live/edit 452, article_live/form 801.

### Image gallery `<dialog>`s (data_display_components 237, 327)

ImageGallery hook, `phx-update="ignore"`, `data-images` JSON; native `showModal()`; ArrowLeft/Right wrap and push `gallery_index_changed` (no-op handlers in gall_live, host_live, source_live); Escape closes; no backdrop close; the hook rewrites caption, attribution and license through `data-caption`, `data-creator`, `data-license-link`, `data-info-*`, `data-lightbox-*`, `data-counter`; the admin ✎ shows only with `edit_href` and an admin. Sites: gall_live 609, host_live 447, source_live 230.

### Other modal-like UI

Region prompt (ui_components 856, RegionPrompt; `z-[60]`, no focus trap, no Escape, no dialog role) via `region_scope` in search_live 332 and id_live 994; article_live/form's inline panels (image browser, delete confirm 820, insert form 880); `drill_down_panel` (form_components 1236).

## 3. Messages

### `flash` / `flash_group`

`flash`: `kind` :info/:error, `title`, `auto_dismiss` (AutoDismiss hook, `data-dismiss-after`). Fixed `.gf-toast`, `role=alert`; clicking anywhere pushes `lv:clear-flash` and hides it. AutoDismiss uses `pushEvent`, not `.click()`, so it never trips an open modal's click-away. `flash_group` (`aria-live=polite`): info auto-dismisses after 5000 ms, error sticky, plus `#client-error` ("We can't find the internet" / "Attempting to reconnect", spinner) and `#server-error` ("Something went wrong!"), toggled by `phx-disconnected`/`phx-connected`. Used by both shells; direct flashes in images_component 98, 105; ~62 `put_flash` calls.

### `UIComponents.alert`

Variants info/success/warning/error, `dismissible` (unused), title slot; always `role=alert`. gall_live 529 (range caveat), admin/form_components 69 ("Possible duplicate", links), source_live/edit 395, facts 520 (`facts-errors`, list), gall_live/edit 768, 772, 779, 786, 793.

### `error_message`

Variants error/warning/info; `title`, `message`, `on_retry`. images_component 586 (`data-attribution-error`), inat_import_component 102, facts 502 (`facts-failed`, Retry → `JS.push("retry")`).

### Others

`.gf-admin-info`: users_live 61. `info_tip` (hover-only; `aria-describedby="tooltip"` points nowhere): gall_live 521, images_component 597, 652, 679, 702, 743, 752, 767. `loading_spinner` (sm everywhere, `role=status`, label): source_live 285, inat 140/241, taxonomy_live/new 592, range_editor 568/658/711, facts 490/499. `loading_overlay`: taxonomy_live/new 557. `skeleton`: dead. Banners: unsupported-browser (root.html.heex 49, inline styles on purpose, `role=alert`), preview bar (57), maintenance (63, SiteSettings, test), region scope bar, gall notes alert (gall_live 620, server-side dismissal), images unattributed warning (160), article draft banner, host_range progress (607), taxonomy move note (358), review `#banner` (470), vocabulary `#seed-bulk-confirm` (926).

## Must preserve

**Buttons:** `type` defaults to button; `type="submit"` + `form=` from outside the form; disabled bindings (dirty, valid, empty selection, typed name); `phx-disable-with`; `data-confirm` (and `action_button confirm=`); `phx-target={@myself}` and `phx-value-*`; navigate vs href; toggle state through variant + `aria-pressed`; `aria-expanded`/`aria-controls` on disclosures; an accessible label on icon-only buttons; hook markers on raw buttons (`data-upload-trigger`, `data-upload-button`, `data-prev/next/open-*/close-*`, `data-region-*`, `data-prompt-code`, `data-typeahead-option`, `data-copy-*`, `data-action`, `data-role`); `admin_edit_link` admin-only to `/admin/taxonomy/:id`; `target="_blank"` on article View; `form_actions` and the article form's disabled-until-dirty.

**Dialogs:** the server-driven pattern (`:if` + `show` + `on_cancel` push, `target: @myself`) on Escape, backdrop and ×; focus trap, scroll lock, focus restore; header extras and actions in body or footer; per-site sizes (sm, md, 3xl, 7xl); no Escape collision with the images copy mode; dangerous delete exactly as above (ids, events, typed name, autofocus, disabled submit, consequences, red emphasis); discard flow and its labels; the lightbox and info dialogs' hook, keys, `gallery_index_changed` and every `data-*` target.

**Flash:** info auto-dismiss 5000 ms by pushEvent; error sticky; click to dismiss; reconnect toasts; `aria-live`; ids `flash-info`/`flash-error`; component-scoped flashes; decide the `:warning` kind on purpose.

**Alert, error_message → notice:** success→ok, warning→warn, error→danger; title; links and lists; `id`, `data-*`, `class` pass through; Retry → the `action` slot. The notice uses `role=status` for non-danger kinds where alert always used `role=alert` (a change to approve).

**info_tip, spinners:** text or rich content, position, inline in labels; spinner labels per site, in a disabled button, overlay needs a relative parent; ids `facts-loading`, `facts-updating`, `wcvp-nomatch-loading`.

**Dead:** `skeleton`, `edit_button` (safe to remove).

**Banners:** the unsupported-browser banner keeps inline styles and `role=alert`; maintenance banner and its id; preview bar; region bar hooks and localStorage keys `gf_continent`, `gf_continent_dismissed`; the gall notes alert's server-side dismissal.

## Approved changes

- `button` (2026-11-04, with the catalog): retiring `soft`/`warning` render as secondary; `lg`/`pill` ignored. Look only; every attribute and event passes through as before.
