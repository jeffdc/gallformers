# Gallformers Domain Reference

A reference for the terminology, concepts, and data model behind Gallformers. Read this alongside the [Admin Guide](admin-onboarding.md) to understand *what things mean* in addition to *how to do things*.

---

## What Is a Gall?

A gall is an abnormal growth on a plant caused by another organism — an insect, mite, fungus, bacterium, nematode, or virus. The organism that causes the gall is the **inducer** (or gall-former). The plant it grows on is the **host**.

Gallformers.org is a database of galls, their inducers, and their host plants. Every record on the site is ultimately about one of these three things: a gall-forming organism, a host plant, or the relationship between them.

---

## Species: The Core Record

Everything in Gallformers is a **species**. Both gall-formers and host plants are species records in the same table, distinguished by a type code:

- **Gall** (`taxoncode = "gall"`) — an organism that induces galls
- **Plant** (`taxoncode = "plant"`) — a host plant

A species record holds the scientific name, taxonomy links, abundance, description, and flags like data completeness and (for galls) undescribed status. Images, sources, and aliases all attach to the species record.

---

## Scientific Names

Species names follow standard binomial nomenclature: **Genus epithet** (e.g., *Callirhytis furva*). On the site, genus and species names are italicized; family names are not.

Some gall species include a **generation qualifier** in parentheses:

- **(agamic)** — the asexual generation of an alternating-generation wasp
- **(sexgen)** — the sexual generation

These are part of the display name because the same wasp species can produce different galls depending on its generation. For example, *Callirhytis furva (agamic)* and *Callirhytis furva (sexgen)* are separate entries because they produce different galls.

### Specific Epithet

The second part of the binomial name (after the genus). For described species, this is a Latin word assigned by the describing author (e.g., *furva*). For undescribed species, this is a constructed code with dashes (e.g., `q-alba-red-bead-gall`). See [Gallformers Codes](#gallformers-codes) below.

---

## Taxonomy

Gallformers tracks a simplified taxonomic hierarchy:

```
Family
└── Genus
    └── Section (optional, plants only)
        └── Species
```

### Families

A family is the highest level tracked. Each family has a **type** that identifies what kind of organisms it contains:

- **Plant families** (type = "Plant"): Fagaceae, Rosaceae, Asteraceae, etc.
- **Gall-former families** by inducer type: Wasp, Midge, Mite, Fly, Aphid, Moth, Beetle, Sawfly, Psyllid, Scale, Thrips, True Bug, Plant (gall forming), Fungus, Bacteria, Virus, Nematode, Oomycete, Unknown

The family type determines whether a family appears in gall-related or host-related contexts throughout the admin and public site.

### Genera

A genus belongs to exactly one family. When a genus is renamed, all species names under it update automatically.

### Sections

Sections are an optional level *below* genus, used only in plant taxonomy for large genera (e.g., the genus *Quercus* has sections like *Quercus* (white oaks) and *Lobatae* (red oaks)). A species can optionally belong to one section within its genus.

Sections are **children** of genera, not parents. The hierarchy is always Family > Genus > Section.

---

## Unknown Families and Genera

The taxonomy system has built-in placeholders for galls whose classification is incomplete.

### The Unknown Family

A single family called **Unknown** exists for gall-formers whose family is entirely unknown. It contains one genus: "Unknown."

### Unknown Genera

Every gall-former family has an **Unknown genus** automatically created when the family is created. The naming convention is **Unknown (*Family*)** — for example, "Unknown (Cynipidae)."

These are used when:
- You know the family but not the genus (use that family's Unknown genus)
- You don't know the family at all (use the Unknown family's Unknown genus)

**Any gall assigned to an Unknown genus is automatically locked as undescribed.** You cannot mark it as described until it's reclassified to a real genus.

Unknown genera with no species assigned are hidden from search results, the ID tool, and browse pages to avoid clutter. They're visible in the admin taxonomy view with a toggle.

---

## Undescribed Galls

A gall is **undescribed** when its inducer hasn't been formally described in the scientific literature. This is a statement about the state of scientific knowledge, not about how much data we have in our database.

On the public site, undescribed galls show an amber alert: *"The inducer of this gall is unknown or undescribed."*

### What Makes a Gall Undescribed?

Two cases:

1. **Assigned to an Unknown genus** — automatically locked as undescribed. The gall-former's genus (and possibly family) isn't known.
2. **Manually marked** — an admin can mark a gall as undescribed even if it's assigned to a real genus. This covers cases where the genus is suspected but the species hasn't been formally described.

### Undescribed vs. Incomplete

These are different concepts that are easy to confuse:

| | Undescribed | Incomplete |
|---|---|---|
| **Means** | Science hasn't formally described this species | Our database entry is missing information |
| **Controlled by** | Genus assignment + admin toggle | Data completeness flag |
| **Example** | A new gall found on oaks, no paper describes it yet | A well-known gall wasp, but we haven't added its source papers yet |

A gall can be described but incomplete (we know what it is, just haven't finished entering data). A gall that is undescribed is always incomplete — the system enforces this by locking the data completeness flag.

---

## Gallformers Codes

A Gallformers Code is a short identifier assigned to undescribed galls so they can be tracked on [iNaturalist](https://www.inaturalist.org) before they have formal scientific names.

### Format

Codes follow the pattern: **host-abbreviation-descriptive-words**

Examples:
- `q-alba-red-bead-gall` (a gall on *Quercus alba*)
- `r-carolina-folded-terminal-leaflet` (a gall on *Rosa carolina*)
- `c-dentata-stem-swelling` (a gall on *Castanea dentata*)

The host abbreviation is typically the first letter of the genus + the specific epithet (e.g., `q-alba` for *Quercus alba*).

### How They're Stored

The Gallformers Code is a dedicated field on the gall record (`gallformers_code` on `gall_traits`), separate from the species name. When an undescribed gall is created, the code is automatically derived from the descriptive part of the name and stored in this field.

### How They're Used

1. An admin creates an undescribed gall using the undescribed workflow
2. The code is derived from the name's specific epithet and stored on the gall record
3. The code appears on the gall's public page with a **copy button**
4. Citizen scientists on iNaturalist use the code in the Gallformers Code observation field to tag their sightings
5. The public page links directly to iNaturalist observations tagged with that code

### When a Gall Gets Described

When an undescribed gall is later formally described and reclassified:

1. The gall gets a real scientific name via the Rename/Reclassify tool
2. The Gallformers Code remains on the gall record — it doesn't change when the name changes
3. The old name is saved as a scientific synonym alias
4. The public page shows: *"Formerly tracked as [code]"* with a link to iNaturalist observations under the original code
5. The iNaturalist link continues working permanently because the code is stored independently of the name

### Uniqueness

Each Gallformers Code must be unique — it's an identifier. The system enforces this with a database uniqueness constraint. If two galls had the same code, iNaturalist observations couldn't be linked to the correct one.

---

## Data Completeness

The **data complete** flag on a species record indicates whether the Gallformers entry has all the information we want it to have.

### What "Complete" Means

**Complete** (green checkmark): All known sources containing unique information relevant to this gall have been added, and that information is reflected in the gall's data (traits, hosts, description, etc.).

**In Progress** (amber badge): We're still working on this entry. Data may be missing, sources may not be added yet, or traits may be incomplete.

### Enforced Rules

The admin form locks the data complete checkbox and shows a reason when either condition applies:

- A gall **without any sources** cannot be marked complete — there's no literature backing the data.
- An **undescribed gall** cannot be marked complete — by definition, an undescribed species has incomplete data.

If you save a gall while the lock is active, the system forces `datacomplete = false` regardless of the checkbox state.

### Data Completeness on Sources

Sources also have a data complete flag with a slightly different meaning: whether all the information from that source has been extracted and entered into Gallformers. A "complete" source means we've gone through it and captured everything relevant.

---

## Aliases

A species can have multiple names. The primary name is the one shown at the top of the page; aliases are alternative names that make the species findable in search.

### Alias Types

| Type | Purpose | Example |
|---|---|---|
| **Common** | Vernacular / common name | "cedar-apple rust" for *Gymnosporangium juniperi-virginianae* |
| **Scientific** | Former scientific names, synonyms from taxonomic revisions | Old genus name before a species was reclassified |

All alias types are searchable — visitors can find a species by any of its names.

Scientific synonyms appear in a **Synonymy** section on the public page. Common names appear in a separate **Common Names** section.

---

## Hosts and Ranges

### Host Plants

Each gall can form on one or more host plants. The gall-host relationship is the core association in the database — it's what makes a gall a gall (something has to grow on something).

### How Ranges Work

Geographic ranges on Gallformers are computed, not directly assigned to galls:

1. Each **host plant** has a set of **places** where it grows (its range).
2. A gall's **possible range** is the union of all its hosts' ranges — everywhere at least one of its hosts grows.
3. **Range exclusions** let admins remove specific places from that computed range. This handles cases where a gall's host grows somewhere but the gall itself doesn't occur there.

**Example:** A gall forms on *Quercus alba* and *Quercus rubra*. Both oaks grow across the eastern US, so the gall's range covers the eastern US. But if the gall has only been observed south of New York, an admin can exclude northern states.

The public page shows this as "Possible Range" with a map.

### Places

Places are geographic regions (states, provinces, countries, etc.) with a hierarchical parent-child structure. They're managed by superadmins.

---

## Sources

Sources are references to scientific literature, field guides, web resources, or Gallformers editorial notes. They document where the data comes from.

### Species-Source Mappings

When you link a source to a species, the mapping includes:
- **Description** — what information from this source is relevant (a quote or summary)
- **External link** — a URL to a specific page or section of the source
- **Use as default** — whether this should be the primary description shown on the public page

Multiple sources can be linked to one species. On the public page, they appear in a "Further Information" section.

### Gallformers Notes

Source #58 ("Gallformers Notes") is special — it's our own editorial content. When linked to a species, it always appears first and is highlighted: *"Our ID Notes may contain important tips necessary for distinguishing this gall from similar galls."*

Use Gallformers Notes for identification tips, disambiguation notes, or editorial comments that aren't tied to a specific publication.

---

## Morphological Traits

Galls have morphological characteristics that describe their physical appearance and structure. These power the identification tool — visitors filter by what they observe to narrow down which gall they're looking at.

### Trait Categories

| Category | What It Describes | Examples |
|---|---|---|
| **Color** | Visual color of the gall | green, brown, red, white, yellow |
| **Shape** | Overall shape | spherical, conical, irregular, elongated |
| **Texture** | Surface feel/appearance | smooth, hairy, bumpy, waxy, woolly |
| **Alignment** | How structures align on the plant | erect, pendant, rosette |
| **Walls** | Internal wall structure | thin, thick |
| **Cells** | Internal chamber structure | monothalamous (one chamber), polythalamous (many) |
| **Form** | Overall form category | closed, open, covering, roll/fold |
| **Season** | When visible | spring, summer, fall, winter, year-round |
| **Plant Part** | Where on the host | leaf, stem, bud, root, petiole, flower, fruit, bark |

Each trait category allows multiple selections — a gall can be both green and brown, or appear on both leaves and stems.

### Why Traits Matter

The more accurately traits are filled in, the better the ID tool works. When a visitor selects "spherical, brown, on oak leaves in fall," only galls matching all of those criteria appear. Missing or incorrect traits means galls won't show up when they should (or will show up when they shouldn't).

---

## Detachability

A gall's relationship to the plant surface:

| Value | Meaning |
|---|---|
| **Integral** | The gall is part of the plant tissue — it can't be removed without cutting or tearing |
| **Detachable** | The gall can be cleanly separated from the plant |
| **Both** | Some specimens are integral, others detachable (or it varies by maturity) |
| **Unknown** | Not yet determined |

This is a useful field identification characteristic — a visitor in the field can try to pull a gall off to narrow their search.

---

## Abundance

How common a gall-forming species or host plant is:

| Level | Meaning |
|---|---|
| **Common** | Frequently encountered; widespread |
| **Uncommon** | Present but not frequently seen |
| **Rare** | Seldom encountered; limited range or population |
| **Very rare** | Extremely uncommon; very few records |

Abundance helps visitors calibrate expectations — a very rare gall is worth extra effort to document, while a common one is good for learning.

---

## Identification Keys

Keys are structured decision tools that guide a visitor through a series of yes/no or either/or choices to arrive at a gall identification. They follow the traditional dichotomous key format used in field biology:

- Each **couplet** presents two contrasting statements (leads)
- Choosing a lead takes you either to the **next couplet** or to a **species** identification
- The key narrows down possibilities with each step

Keys are authored by experts and are a valuable resource, especially for parasioids, inquilines, and adult gall-formers.

---

## Glossary

The glossary defines technical terms used throughout the site. Terms appear as tooltips — when a visitor hovers over or taps a highlighted word, they see the definition without leaving the page.

Common glossary terms include morphological vocabulary (monothalamous, polythalamous, sessile, pubescent) and biological concepts (agamic, sexgen, inquiline, parasitoid).

---

## Summary: How It All Fits Together

```
Family (Cynipidae, type: Wasp)
└── Genus (Callirhytis)
    └── Species: Callirhytis furva (taxoncode: gall)
        ├── Traits: spherical, brown, on leaf...
        ├── Hosts: Quercus alba, Quercus rubra
        │   └── Range: computed from host places minus exclusions
        ├── Sources: Smith 2020, Jones 2018...
        ├── Aliases: "oak apple gall" (common)
        ├── Images: 3 photos with credits and licenses
        └── Flags: described, data complete
```

For an undescribed gall, it might look like:

```
Family (Cynipidae, type: Wasp)
└── Unknown (Cynipidae)  ← placeholder genus
    └── Species: Unknown (Cynipidae) q-alba-red-bead-gall (taxoncode: gall)
        ├── Gallformers Code: q-alba-red-bead-gall
        ├── Traits: spherical, red...
        ├── Hosts: Quercus alba
        ├── Images: 1 photo from iNaturalist
        └── Flags: undescribed, in progress
```
