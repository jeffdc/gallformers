# Gallformers Admin Guide

A task-oriented guide for Gallformers admins. Whether you're brand new or returning after a break, find what you need by looking for the task you're trying to do. For terminology and domain concepts, see the [Domain Reference](admin-domain-reference.md).

## Getting Started

### First Login

1. Log in at [gallformers.org/admin](https://gallformers.org/admin) using your Auth0 credentials.
2. You'll be asked to set up your **profile** — a display name is required before you can access the admin.
3. Fill in your display name and any optional info (bio, iNaturalist username, website). Toggle **Show on About Page** if you'd like to appear on the public About page.
4. You'll land on the **Dashboard** — this is home base.

### The Admin Navigation

The bar at the top of every admin page leads to: **Dashboard**, **Queue** (the review queue), **Galls**, **Taxonomy** (taxa of every rank, plants and their Host ranges included), **Sources**, then the content screens **Glossary**, **Articles** and **Keys**. **My Profile** is on the right; operators also see **Ops**.

### The Dashboard

The dashboard is organized into sections:

- **Quick Actions** — review the queue, find a Gall, find a Source, review Host ranges
- **Review Queue** — how many queue items are open, in all and by kind; each count opens the queue filtered to it
- **Taxonomy** — create a new Host (a plant) or a new taxon, browse the taxonomy
- **Content & Reference** — articles, identification keys, glossary entries
- **Super Admin** — user management, the jobs dashboard and the live dashboard (only visible to superadmins)
- **Stats** — current counts for Galls, Hosts, Sources and images; the first three open their lists

There's also a **Discord** link and a link to this help doc in the top right for help.

### Key Concepts

Before diving in, a few things that apply everywhere in the admin:

**Most data arrives as imports.** Galls, their Hosts, Traits and common names, and what Sources say about them, come into Gallformers as **import packages**: batches of statements extracted from Sources. A package is checked and matched against what Gallformers already knows; whatever can't be settled on its own (an ambiguous name, an unknown Host, a dispute) becomes an item in the **review queue**, and a package needing review waits there for an admin to approve or deny it. The admin screens are for that review and for what is Gallformers' own: Gall editorial fields, the Gallformers note, range exclusions, the taxonomy, Sources' details and images.

**Every edit is yours.** Saves are recorded under your name in the audit history, and edits that must survive a re-import (taxonomy edits, Source edits, queue decisions) are also kept in the replay log.

**Saving.** Pages are split into sections (cards), each with its own **Save** button that saves just that section. On forms with a **Cancel** button, leaving with unsaved changes asks you to confirm.

**Data completeness.** Galls and plants have a "data complete" flag (green checkmark vs red X on public pages). It tells visitors and other admins whether everything relevant has been added. For Galls the system enforces two rules: a Gall **without Sources** cannot be marked complete, and an **undescribed Gall** cannot be marked complete. When either applies, the checkbox is locked with the reason.

**Edit shortcuts on public pages.** When you're logged in as an admin, small pencil icons appear on the public site: next to a Gall's name (its Gall page in admin), a Host's or a rank page's name (its taxon page in admin), a Source's title (the Source editor), each Gall in a Host's table, and on image galleries (the images section of the Gall or taxon page; **Add images** when there are none). This is often the fastest way to edit something: find it on the public site, click the pencil.

**Old links.** Links to the old admin screens still work where a new screen replaces them: `/admin/hosts…` and `/admin/section…` go to the taxonomy admin, `/admin/species-sources…` to the Source editor, `/admin/gallhost?id=…` to that Gall's page, and `/admin/images?species_id=…` to the images of that Gall's or taxon's page. Other old admin URLs are gone.

---

## How Do I Work the Review Queue?

Go to **Queue** (`/admin/queue`). The page has two parts.

### Open items

Everything imports could not settle on their own, oldest first, filtered by kind with a count for each:

| Kind | What you decide |
|---|---|
| **Ambiguous match** | A name matched more than one taxon, Gall or Source: pick the right candidate (or another taxon by ID), or skip it. A Gall can also be new. |
| **Unresolved name** / **Unresolved Host** | A name or Host matched nothing: pick a taxon, or skip. Add the missing taxon in the [taxonomy admin](#how-do-i-create-or-edit-taxonomy) first if needed, then re-resolve the package. |
| **Undescribed-Gall candidate** | A statement may be about an undescribed Gall: pick one, make it new, or skip. |
| **Dispute** | A statement contradicts what Gallformers holds: keep or drop the statement. |
| **Same-date conflict**, **Taxonomy disagreement**, **Generation outside its group** | Acknowledge, with a note. |
| **Gall rename proposal** | A taxonomy change would rename a Gall (from → to, with any name collision shown): accept or reject. These come from taxonomy edits, not from a package. |

Any decision can carry a note. Items that hold up a package's approval can be decided here or on the package's page.

### Packages

The delivered import packages, newest first, filtered by status. Open one (`/admin/queue/packages/:id`) to see:

- the package — its status, who submitted it, its Source, any validation problems;
- its open queue items, with their decision controls;
- its batches — type, mode and status — with each statement and how it resolved (to what, among which candidates, and once applied what it changed), and the entries that mapped to nothing.

Then:

- **Approve** applies the package. If something still holds it (open items, a blocked batch), the page says what.
- **Deny** the package, or a single batch, with a reason.
- **Resolve again** after you've fixed what held it, e.g. added a missing name to the taxonomy.

---

## How Do I Edit a Gall?

Galls are not created or deleted by hand: new Galls arrive with imports, and mistakes or duplicates wait for the merge workflow. To edit one:

1. Go to **Galls** (`/admin/galls`) and search by name, alias or the Inducer's names — or click the pencil next to the Gall's name on its public page.
2. The Gall page (`/admin/galls/:id`) has these sections, each saved on its own:
   - **Editorial fields** — the **Gallformers Code** (checked for uniqueness as you type), **Abundance**, the **Lead Source** (one of the Gall's Sources; the public page leads with it) and **data complete** (locked off for an undescribed Gall or one with no Sources). Click **Save editorial fields**.
   - **Name** — the name parts: the **Host qualifier** (the plant written "on …"), the **Form label**, the **Descriptor** (for undescribed Galls) and a **Name override**. The name they make, and any collision with another Gall's name, show as you type. Click **Save name**.
   - **Images** — see [How Do I Manage Images?](#how-do-i-manage-images)
   - **Gallformers note** — Gallformers' own description of the Gall, in Markdown. Each save is a new version dated today; earlier versions are listed below it. Click **Save note**.
   - **Range exclusions** — see below.

Hosts, Traits and common names come from imports and are not edited here.

### Excluding Places from a Gall's Range

A Gall's range is computed from its Hosts' ranges: its **potential range**. When there's evidence the Gall doesn't occur somewhere its Hosts grow, exclude that place:

1. In the **Range exclusions** section, the map shows the potential range with the current exclusions. (A Gall whose Hosts have no range data can be excluded anywhere.)
2. Click a place to exclude it, or click an excluded one to restore it. Click a country to open the drill-down panel for its subdivisions, with **Select All** / **Deselect All**.
3. Write a short **statement** saying why, in plain words (required).
4. Click **Save exclusions**.

The change is saved as a Gallformers statement and goes through the import path like any other, so it is audited and attributed to Gallformers. The page shows the outcome: applied, or waiting in the review queue (with a link to its package).

---

## How Do I Add a New Host Plant?

Plants are taxa, managed in the taxonomy admin.

1. From the dashboard, click **Create a New Host** (or go to `/admin/taxonomy/new`).
2. **From POWO-WCVP (recommended):** search the World Checklist of Vascular Plants by name and pick the record. Its name, family and genus are filled in (WCVP is authoritative for a plant's family; a missing family or genus is created) and its range is drawn. **By default only the native range is included**; check the option to include the introduced range too. Be thoughtful about this — introduced Host ranges widen the potential range of every Gall on the Host.
3. **Or by name:** enter the name, the rank and the parent. A plant (Plantae, species rank or below) needs a Host range: draw it on the map.
4. Possible duplicates are flagged — the same name, a synonym or common name of another taxon, the same WCVP record — each linking to the existing taxon.
5. Save. You land on the new taxon's page.

### Editing a Host's Range

On a plant's taxon page, the **Host range** section has the range map:

- Click a state or province to cycle it **native → introduced → removed**. Click a country to open the drill-down panel for its subdivisions.
- Colors: dark green = exact, light green = country-level, white = not in range; introduced places have a diagonal hatching.
- Changes are saved when you click **Save**.

### Refreshing a Host's Range from WCVP

On a plant linked to WCVP, **Refresh from POWO-WCVP** compares the current range with WCVP's and shows the differences:

- **Green (to add)** — places in WCVP but not in the current range
- **Red (to remove)** — places in the current range but not in WCVP
- **Amber (introduced)** — introduced distributions you can select or deselect one by one

Toggle each item, then **Apply Selected Changes** to stage them on the map. Nothing is saved until you click **Save**.

The **POWO-WCVP link** section shows the plant's WCVP record and lets you match it to a record, sync from it, or mark it ignored.

### Reviewing Host Ranges in Bulk

**Review Host Ranges** on the dashboard (`/admin/host-range`) lists plants whose range needs review, with bulk range confirmation and bulk WCVP match / sync / ignore. Matching all filtered plants at once is for superadmins only.

---

## How Do I Create or Edit Taxonomy?

Every taxon — family, intermediate ranks (subfamily, tribe, …), genus, section, species and below, for animals, fungi and plants alike — lives in the taxonomy admin.

### Finding a Taxon

Go to **Taxonomy** (`/admin/taxonomy`). **Search** by accepted name, synonym or common name, or **browse** the tree from its roots down: click a taxon's children to go a level deeper; the breadcrumb leads back up.

### Moving Taxa

While browsing a taxon's children, select several with the checkboxes and click **Move** to put them under another parent at once (the old "move genera").

### Creating a New Taxon

1. Go to `/admin/taxonomy/new` (or click **Create a New Taxon** on the dashboard).
2. Enter the **name**, pick the **rank** and the **parent** (a root needs a kingdom).
3. A rank above species can take some of the parent's children under it — an **intermediate rank needs at least one**.
4. Save.

### A Taxon's Page

Each taxon's page (`/admin/taxonomy/:id`) has sections for:

- **Name** — rename it. The old accepted name stays a synonym. Galls whose names derive from it and would change get **rename proposals** in the review queue, which you accept or reject there.
- **Placement** — move it under a new parent.
- **Plants in this section** (sections) — the section's member plants, all in the section's genus.
- **Synonyms** and **Common names** — add and remove.
- **Plant details** (plants) — data complete and abundance.
- **Host range** and **POWO-WCVP link** (plants) — see [Adding a Host](#how-do-i-add-a-new-host-plant).
- **Images** — see [How Do I Manage Images?](#how-do-i-manage-images)
- **Delete** — only for a taxon nothing refers to (no children, Facts, Galls, Host ranges, images). You type its name to confirm. Otherwise the page lists what refers to it.

Every taxonomy edit is audited and kept in the replay log.

---

## How Do I Edit a Source?

Sources arrive with imports; there is no "new" and no delete (Facts and citations refer to them).

1. Go to **Sources** (`/admin/sources`) and search by title or author — or click the pencil next to a Source's title on its public page.
2. On the Source editor (`/admin/sources/:id`), edit its **details**: title, authors, date, DOI, URL, ISBN, license (a license with a canonical link fills the link in), citation and the data complete flag. Save.
3. **Retract** a Source when a retraction notice withdraws it: pick the notice (another Source, by search) and the date. **Undo the retraction** if it was a mistake. Either recomputes the standing of every statement the Source supports.

Every Source edit is audited and kept in the replay log.

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

Images belong to a Gall or to a taxon (usually a plant) and are managed in the **Images** section of the Gall page or the taxon page. From a public page, the ✎ button under the image gallery (or **Add images** when there are none) takes you there.

### Uploading Images

1. **Drag and drop** images into the upload area, or click to browse, then **Upload Images**. They are added after the existing images.
2. Fill in each image's metadata (see [Image Licensing and Attribution](#image-licensing-and-attribution)). A save must leave the image attributed: a license, and a creator unless the license is Public Domain / CC0 or the image comes from a licensed Source. Picking a Source fills in the license, its link and the creator.
3. An image that isn't properly attributed carries a warning until it is fixed.

### Reordering Images

Drag images in the grid to change their order. The first image is the default one, shown first on the public page and in the ID tool.

### Copying Metadata and Deleting

In **Table** view you can copy one image's metadata to the selected images — handy after uploading several photos from the same photographer. Deleting an image removes it and its sizes from storage.

### View Modes

Toggle between **Grid** and **Table** view. Table view is useful when you need to quickly review metadata across many images.

---

## How Do I Import Images from iNaturalist?

1. In the Images section of a Gall or taxon page, find **Import from iNaturalist**.
2. Enter the **iNaturalist observation URL** (or its ID) and fetch it.
3. The observation's photos are shown with their licenses. Select the ones to import.
4. License, credit ("login - name") and the observation link are filled in from iNaturalist.
5. Import — the photos are uploaded and added to the Gall's or taxon's images.

**Tips:**
- Only import photos with [appropriate licenses](#accepted-licenses). The license of each photo is shown before you import.
- If an iNat photo is "All Rights Reserved," do not import it unless you've gotten permission from the photographer.

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

## SuperAdmin-Only Features

These are only available to users with the superadmin role.

### User Management (`/admin/users`)
- View all registered users.
- Clean up access and display when admin privileges are revoked.

### Jobs and Live Dashboards
- **Jobs Dashboard** (`/admin/jobs`) — background jobs (imports, rollups, image processing).
- **Live Dashboard** (`/admin/dashboard`) — the running application's metrics.

### Host Range Review
- On **Review Host Ranges**, matching all filtered plants to WCVP at once.

---

## Tips and Gotchas

- **Search everywhere.** Before adding a taxon, search first — it might already exist under a synonym or common name; the new-taxon form warns you too.
- **Fix the tree, then resolve again.** When a package is held by an unresolved name, add the missing taxon in the taxonomy admin, then **Resolve again** on the package.
- **Renames ripple.** Renaming or moving a genus can propose new names for the Galls under it; look in the review queue for the rename proposals.
- **Discord is your friend.** If something seems wrong or confusing, ask in the Discord channel. The link is on the dashboard.
