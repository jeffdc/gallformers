---
status: done
created: 2026-09-02
updated: 2026-09-02
epic: admin
---

# Safer high-impact admin deletes

## Scope and decisions

Replace the one-click browser confirmation for high-impact admin deletion of galls, hosts, and sources, in both list and edit views.

Use a shared destructive-delete modal consistent with the existing taxonomy cascade-delete pattern. The modal must:
- name the record and describe the associated data that will be removed;
- state that deletion is permanent and cannot be undone;
- require the exact record name/title before enabling the destructive action;
- validate the exact confirmation again in the LiveView before deleting;
- clear pending deletion state on cancel.

Keep lower-impact delete actions unchanged until additional entities are explicitly selected. Reuse the existing modal, button, icon, and InputEvent UI components rather than adding a second UI convention.


## Confirmed scope

Use high-friction typed confirmation for canonical records: galls, hosts, sources, every taxonomy type, articles, and identification keys. Keep ordinary confirmation for leaf mappings and isolated records. Use impact-sensitive handling separately for images and shared filter terms.

Taxonomy already uses typed confirmation, but section deletion impact must accurately report linked species rather than claiming there is no dependent data.


## Completed

Applied typed exact-name/title confirmation to Gall, Host, Source, Article, and Identification Key deletes in both index and edit views. Existing taxonomy typed confirmation remains for every rank.

Section deletion now counts linked species, explains that linked species prevent deletion until reclassification, removes the confirm form while blocked, and rechecks/refreshes impact at confirmation time.

All canonical delete handlers re-fetch the selected record before deleting so a record deleted or renamed while the modal is open cannot be deleted through stale state. Confirmation comparisons are byte-for-byte exact, including whitespace. Host index now handles all events from the Species topic it subscribes to.

Verification: 189 focused tests passed. `mix precommit` passed with 2,083 tests, zero failures, and no Credo issues. Browser smoke checks confirmed Article and Key dialogs, disabled-to-enabled typed confirmation behavior, and linked Section blocking with live impact count.
