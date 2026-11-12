---
kind: decision
text: 'Admin migration look changes: image manager copy-mode controls moved, row tints gone, rows lost data-image-id, hover actions on keyboard focus too, info tips as help lines, ''Delete image'' wording, country drill-down Native/Introduced as a switch with swatch and hatch, the discard dialog''s wording'
plan: taxogall
source: matter bc0d, 'Handoff update (2026-11-06)', 'Behaviour/look changes ... for Jeff to review'; replaces entry 3b61
by: /Users/jeff/dev/gallformers
created: "2026-11-12T02:23:22Z"
---

What was decided. Six parallel agents moved the admin onto the design system on 2026-11-06 (the conformance baseline fell from 1,850 to 15). Along the way they made the behaviour and look changes below, which bc0d listed for Jeff to review. The matter records no separate reason for each, beyond moving the screens onto the system's components and tokens. Where a change is in line with the design system's direction (bc0d round 1 and the catalog), that is noted.

The full list from bc0d, with where each lives (as of a0434bcf):

1. Image manager: the copy-mode controls moved above the table (copy metadata from one photo to others).
- Code: lib/gallformers_web/live/admin/images_component.ex (copy_mode; a notice titled "Copy metadata" with Apply (N)). It manages Gall and taxon photos, on the Gall page's Edit mode and the taxonomy admin.
- Later changed: the 50ff build of 2026-11-06/07 moved copy-mode "select all" into the table header (its own entry, c485).

2. Image manager rows lost their state tints. Row state is now data_table's row_state (image_row_state/2). It is in line with the system's direction that chips mean state.

3. Image manager table rows lost data-image-id. Anything that selected rows by it (tests, scripts, hooks) has to find them another way.

4. Hover-only actions on the photos also show on keyboard focus (group-focus-within), so keyboard users can reach them. Code: images_component.ex (about line 188), content_image_manager.ex (about line 102), and the upload preview's remove button in assets/js/hooks/content_image_upload.js.

5. Info tips are shown as help lines. The info_tip component was removed (UIComponents), and its text now shows as a visible line of help text.

6. The wording is "Delete image": images_component.ex and content_image_manager.ex (article and key images).

7. Host range: select-all moved above the table, not in the header.
- Code: lib/gallformers_web/live/admin/host_range_live.ex, /admin/host-range.
- Later changed: the 50ff build put it back in the table header, with the bulk row shown only while something is selected (its own entry, cd5c).

8. Country drill-down: Native/Introduced is a switch, and rows are marked by a swatch and hatch rather than green and amber.
- Code: lib/gallformers_web/live/admin/country_drill_down.ex (the toggle, and each row's swatch matching the map legend's fill).
- This matches the range-map legend, which moved onto map tokens with .gf-hatch for introduced in the dark-mode work.

9. The discard dialog's wording is "Discard your changes?", "Keep editing", "Discard changes".
- Code: lib/gallformers_web/live/admin/form_helpers.ex, also in tray_live.ex.

10. The Source edit page shows Retracted and Complete chips. It is the Source admin page (lib/gallformers_web/live/admin/source_live/).

11. Notices carry role status or alert (FeedbackComponents.notice), so screen readers announce them.

12. Card titles are no longer on a sky band.
- This follows the round-1 direction, "sections are headings on a rule; cards only for separate objects", which replaced the 69px sky-blue card bands measured in round 1.
- card was removed in favour of panel and section.

Items 10–12 are in bc0d's list but not named in this entry's text.

The alternative is to restore any of these: the old placement, the tints, the attribute, hover-only actions, info-tip popovers, the old wording, green/amber rows.
