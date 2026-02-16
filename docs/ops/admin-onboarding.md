# Gallformers Admin Guide

A task-oriented guide for Gallformers admins. Whether you're brand new or returning after a break, find what you need by looking for the task you're trying to do. For terminology and domain concepts, see the [Domain Reference](admin-domain-reference.md).

## Getting Started

### First Login

1. Log in at [gallformers.org/admin](https://gallformers.org/admin) using your Auth0 credentials.
2. You'll be asked to set up your **profile** — a display name is required before you can access the admin.
3. Fill in your display name and any optional info (bio, iNaturalist username, website). Toggle **Show on About Page** if you'd like to appear on the public About page.
4. You'll land on the **Dashboard** — this is home base.

### The Dashboard

The dashboard is organized into sections:

- **Quick Actions** — the things you'll do most often (create galls, hosts, sources, manage associations)
- **Taxonomy** — create families, genera, and sections
- **Content & Reference** — articles, identification keys, glossary entries, image audit
- **Super Admin** — user management, places, filter terms (only visible to superadmins)
- **Stats** — current counts for galls, hosts, sources, and images (clickable to browse each list)

There's also a **Discord** link and a link to this help doc in the top right for help.

### Key Concepts

Before diving in, a few things that apply everywhere in the admin:

**Deferred saves.** Most forms don't save changes as you make them. You build up your edits (adding aliases, hosts, filter values, etc.) and everything saves in one batch when you click **Save**. If you navigate away without saving, changes are lost — you'll get a confirmation prompt.

**Data completeness.** Species and sources have a "data complete" flag (green checkmark vs red X in lists). This tracks whether a record has all expected information filled in. It's a signal to other admins about what still needs work. For galls, the system enforces two rules: a gall **without sources** cannot be marked complete, and an **undescribed gall** cannot be marked complete. When either condition applies, the checkbox is locked with an explanation.

**Aliases.** Galls can have multiple names: scientific synonyms and common names. Aliases make species findable by any of their names in search.

**Real-time updates.** Pages update in real-time — if another admin creates or edits a record, you'll see the change without refreshing.

**Edit shortcuts on public pages.** When you're logged in as an admin, small pencil icons appear throughout the public site — next to the species name, the host list, individual source mappings, and more. Clicking one takes you straight to the relevant admin page. This is often the fastest way to edit something: find it on the public site, click the pencil.

**View links on admin pages.** Going the other direction, admin list pages have a **View** button (arrow icon) on each record that opens its public page. Use this to check how your edits look to visitors.

---

## How Do I Add a New Gall?

Use this when a gall species is formally described in the literature.

1. From the dashboard, click **Create a New Gall** (or go to `/admin/galls/new`).
2. Start typing the species name in the search field. If it already exists, you'll see it — click to edit instead.
3. Fill in taxonomy: **Family**, **Genus**, and **specific epithet**.
4. Set **Abundance** (how common the gall is).
5. Set **Detachable** type: Integral (can't detach), Detachable (falls off), Both, or Unknown.
6. Add a **Description** — a brief text describing the gall.
7. **Morphological filters** — select all that apply for colors, shapes, textures, alignments, walls, cells, forms, seasons, and plant parts. These power the ID tool's filtering.
8. **Aliases** — add common names, scientific synonyms, or colloquial names as needed.
9. Click **Save** to create the gall with all its associations in one transaction.

**After creating:** You'll probably want to also:
- [Add images](#how-do-i-manage-images)
- [Map host plants](#how-do-i-manage-gall-host-associations)
- [Map sources](#how-do-i-map-species-to-sources)

---

## How Do I Add an Undescribed Gall?

Use this when you've found a gall that hasn't been formally described yet — you might not know the exact species.

1. From the dashboard, click **Add an Undescribed Gall** (or go to `/admin/galls/undescribed`).
2. **Do you know the genus?**
   - **Yes** — pick the genus, and the family fills in automatically.
   - **No** — pick just the family. An "Unknown" genus under that family will be used (or created automatically).
3. **Pick the type host** — the plant this gall was found on.
4. **Enter a short description** — a few adjectives separated by dashes (e.g., `red-bead-gall`).
5. The **name generates automatically** based on your choices, e.g., `Unknown (Cynipidae) q-alba-red-bead-gall`. You can edit it if needed.
6. Click **Continue** to go to the full gall form with your choices pre-filled.
7. Add morphological filters, description, etc. and **Save**.

**Important:**
- Galls in an Unknown genus are **automatically marked undescribed** — you can't override this.
- A **Gallformers Code** is automatically derived from the descriptive part of the name and stored on the gall record. This code is used for iNaturalist cross-referencing.
- Gallformers Codes must be unique — the system enforces this with a uniqueness constraint.

---

## How Do I Rename or Reclassify a Species?

Use this when a species has been formally re-described, moved to a different genus, or when an undescribed gall gets a real name.

1. Open the species edit page (either gall or host).
2. Click the **Rename/Reclassify** button.
3. The modal opens pre-filled with the current family, genus, and epithet.
4. **To rename:** Change the specific epithet.
5. **To reclassify:** Change the family and/or genus. Changing the family filters the genus picker to only show genera in that family.
6. **"Add scientific synonym alias"** (on by default) — saves the old name as a searchable alias so people can still find this species by its former name.
7. Click **Save** — changes apply immediately. All hosts, sources, images, and traits are preserved.

**If the family or genus you need doesn't exist yet**, use the link in the modal to go create it in taxonomy admin first.

**For undescribed galls being formally described:** The Gallformers Code is preserved on the gall record. After reclassifying, the public page continues to show "Formerly tracked as..." with a link to iNat observations tagged with the original code. The old name is saved as a scientific synonym alias.

---

## How Do I Add a New Host Plant?

1. From the dashboard, click **Create a New Host** (or go to `/admin/hosts/new`).
2. Select **Family** and **Genus** from the dropdowns.
3. Enter the **specific epithet**.
4. Add **common names** — click the add button and type each name.
5. Set **Abundance** and add a **Description** if available.
6. Click **Save**.

**After creating:** You'll probably want to [map galls to this host](#how-do-i-manage-gall-host-associations).

---

## Image Licensing and Attribution

Every image on Gallformers must have proper attribution and an appropriate license. This isn't optional — it's a legal and ethical requirement, and it respects the photographers and artists whose work makes the site useful.

### Required Metadata

Every image must have:
- **License** — the terms under which we're allowed to use it
- **Credit** — the name of the photographer or artist
- **Source** — where the image came from (a publication, iNaturalist, personal submission, etc.)

Do not upload an image unless you know its license and can properly attribute it.

### Accepted Licenses

Images should have one of these Creative Commons licenses (or equivalent):

| License | What It Means |
|---|---|
| **Public Domain / CC0** | No restrictions. Free to use without attribution (though we still credit). |
| **CC-BY** | Must give credit to the creator. |
| **CC-BY-SA** | Must give credit; derivatives must use the same license. |
| **CC-BY-NC** | Must give credit; non-commercial use only. |
| **CC-BY-NC-SA** | Must give credit; non-commercial; share-alike. |
| **CC-BY-ND** | Must give credit; no derivatives (we can display but not modify). |
| **CC-BY-NC-ND** | Most restrictive CC license — credit required, non-commercial, no derivatives. |

### All Rights Reserved Images

If an image is licensed "All Rights Reserved," you **cannot use it without explicit permission** from the creator. If you want to use such an image:

1. Contact the photographer and explain how Gallformers will use the image (educational reference, non-commercial).
2. Get their written permission (email is fine).
3. Upload the image with the license set to "All Rights Reserved."
4. Note the permission in the credit or source fields so other admins know it was authorized.

**When in doubt, don't upload it.** There are plenty of appropriately licensed images on iNaturalist.

---

## How Do I Manage Images?

### Uploading Images

1. Go to `/admin/images` (or click **Edit Images** from a species' list entry).
2. Search for and select the species.
3. **Drag and drop** images into the upload area, or click to browse.
4. Once uploaded, fill in the required metadata for each image (see [Image Licensing and Attribution](#image-licensing-and-attribution) above).
5. Click **Save** for each image's metadata.

### Reordering Images

Drag and drop images in the grid to change their display order. The first image is the one shown on the species' public page.

### Copying Images Between Species

1. Click the **Copy** button to enter copy mode.
2. Select the images you want to copy.
3. Search for and select the destination species.
4. Confirm the copy in the modal.

### View Modes

Toggle between **Grid** and **Table** view. Table view is useful when you need to quickly review metadata across many images.

---

## How Do I Import Images from iNaturalist?

1. Go to the images page (`/admin/images`) and select a species.
2. Click the **iNaturalist Import** button.
3. Enter an **iNaturalist observation ID** (the number from the observation URL).
4. The system fetches the observation and shows available photos.
5. Select which photos to import — pay attention to the license shown for each photo.
6. License and credit information are pulled automatically from iNaturalist.
7. Click **Import** — images are uploaded to S3 and linked to the species.

**Tips:**
- Only import photos with [appropriate licenses](#accepted-licenses). The system shows the license for each photo before you import.
- Credit is set automatically from the iNat observation.
- If an iNat photo is "All Rights Reserved," do not import it unless you've gotten permission from the photographer.

---

## How Do I Add a Source (Paper/Reference)?

1. From the dashboard, click **Create a New Source** (or go to `/admin/sources/new`).
2. Fill in: **Title**, **Author**, **Publication Year**, **Type**.
3. Add **DOI**, **ISBN**, or **URL** if available.
4. Add any **body text** or notes.
5. Set the **Data Complete** flag if you've entered all relevant information.
6. Click **Save**.

---

## How Do I Map Species to Sources?

There are two workflows depending on your starting point.

### "I have a new paper and want to add all the species it covers"

1. From the dashboard, click **Bulk Add Species Descriptions from Sources** (or go to `/admin/species-sources/add`).
2. **Select the source** first — it stays pinned at the top.
3. For each species in the paper:
   - Search for and select the species.
   - Enter the **description** (the relevant text from the paper).
   - Add an **external link** if the paper provides one.
   - Toggle **Use as default** if this should be the primary description shown on the public page.
   - Click **Save & Add Another** to continue with the next species.
4. Already-mapped species for the current source are shown so you can see your progress.

### "I want to find or edit an existing mapping"

1. From the dashboard, click **Find and Edit Species-Source Mappings** (or go to `/admin/species-sources/find`).
2. Search by **species name**, **source title**, or **description text**.
3. Click a result to open the inline edit modal.
4. Edit the description, external link, or default flag.
5. Click **Save** or **Delete** as needed.

---

## How Do I Manage Gall-Host Associations?

This dedicated page manages which galls form on which host plants, plus geographic range exclusions.

1. From the dashboard, click **Manage Gall-Host Associations** (or go to `/admin/gallhost`).
2. **Select a gall** using the typeahead search.
3. The current hosts are shown.
4. **Add hosts:** Search for and select additional host plants.
5. **Remove hosts:** Click the remove button on any host.
6. **Range exclusions** (advanced): Below the host list, you can see all the places covered by the selected hosts. Exclude specific places from the gall's range if needed — for example, if a gall occurs on a host everywhere *except* a certain region.
7. Click **Save** to apply all changes.

**Tip:** You can also get here by clicking **Map Hosts** from the gall list page, which pre-selects the gall.

---

## How Do I Create or Edit Taxonomy?

Taxonomy follows the hierarchy: **Family > Genus > Section** (sections are optional).

### Creating a New Taxon

1. Go to `/admin/taxonomy/new` (or click **Create a New Taxon** on the dashboard).
2. Select the **type**: Family, Genus, or Section.
3. Enter the **name** and optional **description**.
4. **If creating a genus**, select its parent **family**.
5. **If creating a section**, select its parent **genus**.
6. Click **Save**.

### Browsing and Editing Taxonomy

1. Go to `/admin/taxonomy` to see the full list.
2. **Search** by name, **filter** by type (family/genus/section), or **sort** by any column.
3. Click a taxon to edit it.

### Moving Genera Between Families

1. On the taxonomy list page, use the checkboxes to select one or more genera.
2. Click the **Move** button that appears.
3. Select the destination family in the modal.
4. Confirm the move.

### Hiding Empty Unknown Genera

Toggle the filter to hide "Unknown" genera that have no undescribed galls in them — this keeps the list cleaner.

---

## How Do I Write Articles, Keys, or Glossary Entries?

### Articles

1. Go to `/admin/articles/new`.
2. Enter **Title**, **Slug** (URL-friendly name), and **Body** (rich text).
3. Set **Status**: Draft, Published, or Archived.
4. Add **Tags** for categorization (multi-select, or create new tags).
5. Toggle **Featured** if it should appear prominently on the site.
6. Click **Save**.

### Identification Keys

1. Go to `/admin/keys/new`.
2. Enter **Title**, **Slug**, and **Version**.
3. Build the **couplet tree** — the hierarchical structure of identification choices.
4. Each couplet has a pair of contrasting statements (leads).
5. Each lead either links to the **next couplet** or terminates at a **species**.
6. Click **Save**.

### Glossary Entries

1. Go to `/admin/glossary/new`.
2. Enter the **Term** and its **Definition**.
3. Add cross-references to related terms if applicable.
4. Click **Save**.

---

## How Do I Audit Images?

The image audit tool (`/admin/image-audit`) helps find problems:

- **Orphans** — files in S3 storage with no matching database record. You can delete them or assign them to a species.
- **Unattributed** — images missing required metadata (source, license, credit). You can edit them inline to add the missing info.

Check this periodically to keep the image library clean.

---

## SuperAdmin-Only Features

These are only available to users with the superadmin role.

### User Management (`/admin/users`)
- View all registered users.
- Clean up access and display when admin privileges are revoked.

### Place Management (`/admin/places`)
- Create and edit geographic places used for gall/host range tracking.
- Full CRUD — search, list, create, edit, delete.

### Filter Terms (`/admin/filter-terms`)
- Manage the filterable gall characteristics used throughout the system.
- Organized by type: alignments, cells, colors, forms, plant parts, seasons, shapes, textures, walls.
- Create, edit, or delete terms (deletion is blocked if the term is in use by any gall).

---

## Tips and Gotchas

- **Search everywhere.** Before creating anything new, search first — the species, source, or taxon might already exist under a different name or spelling.
- **Aliases are searchable.** When you add aliases to a species, all of those names become findable in search across the site.
- **Deferred saves mean you can experiment.** Add and remove things freely — nothing is committed until you click Save.
- **Discord is your friend.** If something seems wrong or confusing, ask in the Discord channel. The link is on the dashboard.
