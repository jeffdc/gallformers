# What's New: Undescribed Galls, Reclassification, and Admin Improvements

## Consistent naming for undescribed galls

All undescribed galls now follow a single naming convention: **Unknown (Family) host-description**. Previously, names used several inconsistent formats — `Unknown-cynipidae`, `Unknown-cecid`, bare `Unknown`, etc. — making it hard to tell if a gall already existed or was entered twice under different spellings.

We renamed all 780 affected species to the new format automatically. For example:

| Old name | New name |
|----------|----------|
| Unknown-cynipidae q-alba-leaf-gall | Unknown (Cynipidae) q-alba-leaf-gall |
| Unknown-cecid t-americana-tuft-gall | Unknown (Cecidomyiidae) t-americana-tuft-gall |
| Unknown m-fistulosa-apical-rosette-gall | Unknown (Cecidomyiidae) m-fistulosa-apical-rosette-gall |

You don't need to do anything — this conversion already happened.

Going forward, when a new gall family is added to the database, an Unknown genus for that family is created automatically. You no longer need to manually set up the "Unknown-something" genus yourself.

## Adding new undescribed galls

There's a dedicated **Add an Undescribed Gall** button on the admin dashboard. It walks you through a step-by-step flow:

1. **Do you know the genus?**
   - If yes, pick the genus, and the family fills in automatically.
   - If no, pick just the family. An "Unknown" genus under that family will be used (or created if needed).

2. **Pick the type host** — the host plant this gall was found on.

3. **Enter a short description** — a few adjectives separated by dashes (e.g., `red-bead-gall`).

4. **The name generates automatically** — based on your choices. For example: `Unknown (Cynipidae) q-alba-red-bead-gall`. This becomes the Gallformers Code.

This prevents typos and naming inconsistencies. No need to remember the convention.

## Undescribed status is now enforced

Two rules are now enforced automatically:

- **Galls in an Unknown genus are always marked undescribed.** The checkbox is locked with an explanation. If you move a gall into an Unknown genus, it's marked undescribed automatically.
- **A gall without any sources can't be marked as described**, since there's no literature to back that up.

## Rename and Reclassify

The biggest change, and probably one of the most welcome is the ability to not simply and easily reanme and reclassify species. To do this a **Rename/Reclassify** button on the gall and host edit pages was added, it opens a modal where you can:

- Change just the specific epithet (rename)
- Move the species to a different family and genus (reclassify)
- Do both at once

The modal opens pre-filled with the current family, genus, and epithet. Changing the family filters the genus picker to only show genera in that family. An **"Add scientific synonym alias"** checkbox (on by default) saves the old name as a searchable alias.

If the family or genus you need doesn't exist yet, a link takes you to the taxonomy admin to create it first.

A warning reminds you that changes save immediately when you click Save. All associated hosts, sources, images, and traits are preserved — no need to delete and recreate anything.

## Gallformers Code and iNaturalist links are preserved after reclassification

This is the big one for data continuity.

When an undescribed gall gets formally described and reclassified to a known genus, the old undescribed name is saved as a **"former undescribed" alias** — a new alias type separate from regular scientific synonyms. The gall's public page uses this alias to keep linking to iNaturalist observations that were tagged with the original Gallformers Code.

Previously, reclassifying a gall broke these iNat links because the code was derived from the species name, and the name changed.

**What you'll see:**
- On the **admin edit page**, the former undescribed alias appears in the alias list (you can manage it there).
- On the **public gall page**, beneath the species name, you'll see text like: *"Formerly tracked as Unknown (Cynipidae) q-alba-clown-shoe"* with a link to the iNat observations. The Gallformers Code is shown and clickable to copy.

Once all iNat observations have been moved to the new name, you can delete the former undescribed alias and the old Gallformers Code link will go away.

**If you reclassify again** (a gall that was already reclassified once), the modal detects the existing former undescribed alias and gives you two choices:

- **Keep original (recommended)** — preserves the original Gallformers Code as the former undescribed alias and adds the intermediate name as a scientific synonym.
- **Replace** — swaps them, making the intermediate name the new former undescribed alias.

Each gall can only have one former undescribed alias at a time, so this choice matters.

## Cleaner search results

Empty Unknown genera — families that have an Unknown genus but no undescribed galls in it yet — are now filtered out of search results and the ID tool. They'll appear once an undescribed gall is actually added to them. This keeps the search and browse views from being cluttered with dozens of unused entries. There is also a filter in the Admin taxonomy view for showing/hiding these.

## Admin dashboard redesign

The dashboard is reorganized into clear sections:

- **Quick Actions** toolbar at the top — the things you do most often (create galls, hosts, sources, manage associations, bulk add from sources)
- **Taxonomy** section — create taxa, manage sections
- **Content & Reference** section — articles, keys, glossary, image audit
- **Super Admin** section (for superadmins only) — users, places, filter terms

## Bug fixes

- **Multi-image upload** — uploading multiple images at once no longer gives them identical file paths (which caused all but one to be lost).
- **Image attribution** — the "last modified by" field on images now shows the person's display name instead of their email address.
- **Paste and drag-drop in search fields** — search inputs throughout the admin now respond to paste, drag-drop, and autofill, not just keyboard typing.
- **Taxonomy section hierarchy** — sections are now correctly treated as children of genera (Family > Genus > Section), fixing a bug where editing sections showed the wrong parent options.

## One thing to watch out for

The specific epithet for an undescribed species is entirely in your control and it becomes the Gallformers Code. There are currently no checks on uniqueness for this value, so it's possible to create duplicate codes. We scanned the database and there are no duplicates so far — just be mindful when naming.
