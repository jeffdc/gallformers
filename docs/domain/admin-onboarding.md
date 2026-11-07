# Gallformers Admin Guide

A task-oriented guide for Gallformers admins. Whether you're brand new or returning after a break, find what you need by looking for the task you're trying to do. For terminology and domain concepts, see the [Domain Reference](admin-domain-reference.md).

## Getting Started

### First Login

1. Log in at [gallformers.org/admin](https://gallformers.org/admin) using your Auth0 credentials.
2. You'll be asked to set up your **profile** — a display name is required before you can access the admin.
3. Fill in your display name and any optional info (bio, iNaturalist username, website). Toggle **Show on About Page** if you'd like to appear on the public About page.
4. You'll land on the **Dashboard** — this is home base.

### The Admin Navigation

The bar at the top of every admin page leads to: **Dashboard**, **Review** (the import review), **Galls**, **Taxonomy** (taxa of every rank, plants and their Host ranges included), **Sources**, then the content screens **Glossary**, **Articles** and **Keys**. **My Profile** is on the right; superadmins also see **Vocabulary** (the vocabulary requests), and operators **Ops**.

### The Dashboard

The dashboard is organized into sections:

- **Quick Actions** — review Sources, find a Gall, find a Source, review Host ranges
- **Review** — how many questions the imports have left to decide (opens the Sources to review), and how many Gall rename proposals are open, when there are any (opens them)
- **Taxonomy** — create a new Host (a plant) or a new taxon, browse the taxonomy
- **Content & Reference** — articles, identification keys, glossary entries
- **Super Admin** — user management, the vocabulary requests, the jobs dashboard and the live dashboard (only visible to superadmins)
- **Stats** — current counts for Galls, Hosts, Sources and images; the first three open their lists

There's also a **Discord** link and a link to this help doc in the top right for help.

### Key Concepts

Before diving in, a few things that apply everywhere in the admin:

**Most data arrives as imports.** Galls, their Hosts, Traits and common names, and what Sources say about them, come into Gallformers as **import packages**: batches of statements extracted from Sources. A package is checked and matched against what Gallformers already knows; whatever can't be settled on its own (an ambiguous name, an unknown Host, a dispute) becomes a **question** for an admin, and a package needing review waits on its Source's review page for an admin to approve or deny it. The admin screens are for that review and for what is Gallformers' own: Gall editorial fields, the Gallformers note, range exclusions, the taxonomy, Sources' details and images.

**Every edit is yours.** Saves are recorded under your name in the audit history, and edits that must survive a re-import (taxonomy edits, Source edits, review decisions) are also kept in the replay log.

**Saving.** Pages are split into sections (cards), each with its own **Save** button that saves just that section. On forms with a **Cancel** button, leaving with unsaved changes asks you to confirm.

**Data completeness.** Galls and plants have a "data complete" flag (green checkmark vs red X on public pages). It tells visitors and other admins whether everything relevant has been added. For Galls the system enforces two rules: a Gall **without Sources** cannot be marked complete, and an **undescribed Gall** cannot be marked complete. When either applies, the checkbox is locked with the reason.

**Edit shortcuts on public pages.** When you're logged in as an admin, small pencil icons appear on the public site: next to a Gall's name (its Gall page in admin), a Host's or a rank page's name (its taxon page in admin), a Source's title (the Source editor), each Gall in a Host's table, and on image galleries (the images section of the Gall or taxon page; **Add images** when there are none). This is often the fastest way to edit something: find it on the public site, click the pencil.

**Old links.** Links to the old admin screens still work where a new screen replaces them: `/admin/hosts…` and `/admin/section…` go to the taxonomy admin, `/admin/species-sources…` to the Source editor, `/admin/gallhost?id=…` to that Gall's page, `/admin/images?species_id=…` to the images of that Gall's or taxon's page, `/admin/queue` to the Sources to review (`?kind=gall_rename` to the rename proposals), `/admin/queue/packages/:id` to that package's review page, and `/admin/vocab-requests` to the vocabulary page. Other old admin URLs are gone.

---

## How Do I Review Imports?

The review goes Source by Source: each Source's statements are checked on its own page, and nothing on one Source's page depends on another's.

### The Sources to review

Go to **Review** (`/admin/review`). Each Source with a package under review is one row: its title and citation, its kind, how many questions are left and how many have a proposed answer, what holds its approval, and its status. Filter to **Needs decisions** (the default), **Ready to approve** or **All**, and sort by **Closest to done**, **Most to decide** or **Oldest Source first**. Click a row to open the Source's page. A package not matched to a Source yet has a row of its own; the Gallformers notes are one row (see below). While any Gall rename proposal is open, a row **Gall rename proposals** leads to them.

### A Source's page

`/admin/review/sources/:id` (or `/admin/review/packages/:id` for one package) shows:

- what the Source states: its Galls, statements about them, taxonomic acts, and the terms and statements the reader set aside;
- progress: how many questions are decided, how many are left, and how many of those have a proposed answer;
- **Approve**, with what holds it if anything does, and **Deny…** with a reason;
- the questions, in sections by kind (Host names Gallformers doesn't hold, names held by several species, Galls whose generation isn't named, disputed statements, Trait terms to settle, statements set aside, and so on). Each section says what it is about and whether it holds approval.

Each question is one compact row: the Source's words, the proposed answer and **Accept**. Click anywhere on the row to open it: the question in plain words, the Source's quotes, the evidence (candidates side by side, both readers' cases, the definitions of the Trait values in play), every choice with what it does, a name search where a choice needs one (taxa with their synonyms, plants in Gallformers and WCVP, Galls), what leaving it open means, an optional note, and the technical details. **Reject** a proposal you disagree with: the row stays open for another answer (**Undo** gives the proposal back). **Accept all N proposed…** in a section's header accepts the rest at once, after a confirmation; rejected rows, suggestions to check and rows with no proposal stay open. After each decision the page updates: questions it settles go and any it calls for appear. **Show decided** lists the decided ones too.

### Trait terms to settle

A Source describes its Galls in its own words: the term ("ovoid", "pale tan", "swelling"). Gallformers keeps the term and files it under a Trait's category (globular, tan, …), the values the ID tool filters on. A term already placed, or placed alike by the producer and the checker each on their own, goes in with no question. The rest are in **Trait terms to settle**, one row per term: the term, its Trait, how many Galls use it, and the category proposed if the readers agree. The row says whether the term is a **New term** or **Used in more than one sense** (a term like "swelling" that means different categories in different Galls, so each Gall is decided on its own).

Open a row to see each Gall it covers: the Gall's name, the quote, what the producer suggested and what the checker placed (with its reason), and a category for that Gall, chosen already where the readers agree. The candidate categories' definitions are side by side. The choices:

- **Place "term" under a category for every Source**: every Source's use of the term gets that category, now and from now on, and the Galls waiting on it get their Facts. Only for a new term.
- **Use these categories for these Galls only (the term depends on the gall)**: each Gall gets the category chosen for it, or keeps the term as text. The term is then decided Gall by Gall in every Source.
- **Fits no category (to superadmins)**: the term stays as text; superadmins see the terms that fit no category and may add one.
- **Keep as text**: these Galls show the term without a category.

Trait terms and statements set aside never hold approval. Left alone, a Gall shows the term without a category (not used by the ID tool), and set-aside statements stay out.

### The Gallformers notes

The Gallformers Source's page lists its notes, grouped by what each holds, in three tabs: **Ready, nothing to decide** (one line each, with what the note adds, ticked by default; **Approve N ticked notes** approves them, each on its own), **Needs you** (notes held by an open question, decided in place) and **Approved**.

### Gall rename proposals

A taxonomy change that would rename a Gall makes a rename proposal (`/admin/review/renames`). They come from taxonomy edits, not from a Source, and hold nothing. **Accept** renames the Gall, keeping the old name as a former name; **Keep the name** fixes it, so later changes to the tree propose nothing for it. A new name another Gall already has is flagged, and accepting it is refused until that Gall's name changes.

### The vocabulary (superadmins)

**Vocabulary** (`/admin/vocabulary`) holds the Trait categories and the Sources' terms under them. Terms are added by the import; categories change rarely, and only here.

- **Placements to spot-check**: terms placed for every Source because the producer and the checker agreed, most Galls first, and placed terms the producer suggested another category for. **Looks right** records the check; **Move…** moves the term.
- **Terms that fit no category**, most used first. Place one under a category (an existing one, or one you add) and every Gall that kept it as text gets its Fact.
- **Add a category**: a new Trait value, with its definition (required).
- **Terms**, filtered by Trait, status or a search: each term's status, category, how it was placed and how many Galls use it. **Change…** moves a placed term to another category (the Facts of every Gall using it move too; this should be rare), marks it as used in more than one sense, or places an ambiguous term under one category.

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

The change is saved as a Gallformers statement and goes through the import path like any other, so it is audited and attributed to Gallformers. The page shows the outcome: applied, or waiting for review (with a link to its review page).

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

- **Name** — rename it. The old accepted name stays a synonym. Galls whose names derive from it and would change get **rename proposals** (`/admin/review/renames`), which you accept or reject there.
- **Placement** — move it under a new parent.
- **Plants in this section** (sections) — the section's member plants, all in the section's genus.
- **Synonyms** and **Common names** — add and remove.
- **Plant details** (plants) — data complete and abundance.
- **Host range** and **POWO-WCVP link** (plants) — see [Adding a Host](#how-do-i-add-a-new-host-plant).
- **Images** — see [How Do I Manage Images?](#how-do-i-manage-images)
- **Delete** — only for a taxon nothing refers to (no children, Facts, Galls, Host ranges, images). You type its name to confirm. Otherwise the page lists what refers to it.

Every taxonomy edit is audited and kept in the replay log.

**Taxa that aren't plants follow their Sources.** The tree of Gallformers, Inducers and every other taxon outside Plantae follows the Sources' accepted taxonomic statements, so a move, a name (with its rank and authorship), a synonym or a common name, added or removed, and a new taxon first ask **Based on which Source?**:

- **A Source in Gallformers** (recommended) — search by title or author. The change is recorded as that paper's statement, accepted by you, and competes by the paper's date. When the backscan later imports the paper, its statement matches and raises no question. The dialog starts with the Source you last used on the page.
- **A new citation** — the paper's title, authors (separated by semicolons) and date (DOI optional) make it a Source on the spot; complete it later in the Source editor.
- **No Source: Gallformers' own position** — only when no paper supports it (an undescribed Gall's Inducer, say). It needs a reason, and is recorded as Gallformers' statement dated today.

If an accepted newer paper already decides it ("Weld 2019 already places Basa under Otherbasisidae: this 2008 Source won't change the tree"), the dialog says so and nothing changes. A synonym that was the taxon's accepted name in an earlier statement stays a synonym. Plants are edited directly, as above.

---

## How Do I Edit a Source?

Sources arrive with imports, or as a citation entered when a taxonomy change follows a paper Gallformers doesn't hold yet (see [A Taxon's Page](#a-taxons-page)); there is no delete (Facts and citations refer to them).

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
- **Renames ripple.** Renaming or moving a genus can propose new names for the Galls under it; look in **Review** for the rename proposals.
- **Discord is your friend.** If something seems wrong or confusing, ask in the Discord channel. The link is on the dashboard.
