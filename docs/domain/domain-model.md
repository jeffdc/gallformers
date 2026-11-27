# Gallformers Domain Model

> This document is Gallformers' shared language: the words the domain uses (galls, the organisms connected to them, and the work of studying and cataloging them), what they mean, and the rules that follow from them. It is for the people who work on Gallformers, curators and developers alike, as much as for agents. **It says nothing about software:** how the system is built is in [the architecture docs](../architecture/README.md). The two are living documents, kept aligned with each other and with what's built; plans point to them rather than repeating them. Production (`main`) still runs the old model, described in [general.md](general.md) and [admin-domain-reference.md](admin-domain-reference.md), until the cutover.

## How this document is built

A term lands here only once a domain expert has confirmed it, and a rule once it's decided; [where each decision came from](#where-the-decisions-came-from) is at the end. Where a word's meaning is still being worked out, it is listed under *Being discovered*, not defined.

## What Gallformers is

A website and database to aid the **Identification** and **Cataloging** of gall-inducing organisms. Gallformers aims to **Source** every **Fact** it states about Galls. It documents galls, not lookalikes.

## Confirmed concepts

### Galls

- **Gall** — a novel structure on a plant, induced by another organism in a repeatable way. The word means both the individual one you find and the abstract thing all such finds are instances of; context tells you which. (In this document, "Gall" alone means the abstract one; an individual gall is an *observed gall*, part of an Observation.)
- **Host** — the plant a Gall forms on.
- **Inducer** — the organism that **induces** a Gall. Inducers come from any of the kingdoms of life.
- **Generation** — some Inducers are multivoltine, and each generation produces a distinct Gall (in Cynipini, an agamic and a sexual generation). Terms vary by group (see *Traits*).
- **Gall Community** — all the organisms involved in a Gall's existence: the Inducer, the Host, Parasitoids, Inquilines, herbivores, organisms that move into a vacant Gall, and so on.
- **Inquiline** — lives in a Gall it didn't induce; some change the Gall's form.
- **Parasitoid** — kills its host organism within the Gall; hyperparasitoids parasitize Parasitoids.
- **Non-Gall** — something that looks like a Gall but isn't: a plant's damage response, or a structure an arthropod builds for eggs or pupation. Outside what Gallformers catalogs.
- **Gall name** — a Gall is named from its Inducer plus parts of its own: its form, its generation, its Host. A curator can override the name, and every Gall's name is unique. A Gall whose Inducer is undescribed is named by a descriptor instead.

### Observations

- **Observation** — the record of one discrete thing someone observed: an observed gall found on its Host at a **Place** and **Time**, with its **Traits** and any **DNA Barcode**, or an organism that emerged from a reared gall. An Observation shows rather than claims; general knowledge is built from many of them.
  - A **museum specimen** is an Observation.
  - A **Rearing** can generate many Observations: each gall, and each emerged organism that isn't the Inducer, is a discrete entity.
  - A **collection event** (one trip, one site, one day) is a set of *potential* Observations.
  - Gallformers thinks about Observations the way iNaturalist does, and prefers researchers' data to reach iNaturalist first so it can integrate from there. Linking Observations to each other (this *Torymus* emerged from that gall) is iNaturalist's business, not Gallformers'.
- **Trait** — a characteristic used to identify a Gall. Most are visible (color, shape, size, plant part); **Place** and **Time** are Traits too, just not visible ones. A **DNA Barcode**, from sequencing a Gall or its contents, is another Trait — it belongs to an observed gall, never to a species.
- **Rearing** — keeping a collected Gall until its occupants emerge. A Rearing can yield adult Inducers, Inquilines, and/or Parasitoids.
- **Research Grade** — iNaturalist's mark that an Observation's identification is trustworthy.

### Identification

- **Identification** — recognizing what an Observation is, using its Traits. It yields both **the Gall** (this is *that* known gall) and the **best-known Taxon for its Inducer**. The goal is the lowest possible Taxon, but that's often not possible; identifying to Genus, Section, or Family is still worthwhile, and an Identification can be as broad as "Life."

### Taxonomy

- **Taxonomy** and **Taxon** — the standard scientific meanings.
- **Gallformers' Taxonomy** follows the literature. Names, placements and synonymy come from Sources; a curator accepts or declines each newer Source's taxonomic statement. Gallformers takes a taxonomic position of its own only as a rare exception (an undescribed Gall's Inducer, or a position no Source supports), and then the Source is Gallformers.
- **Curated and imported taxa** — the taxa of the whole Gall Community, and the rare plant that forms a gall itself, are **curated**: Gallformers keeps their taxonomy from the literature. Plants are **imported**.
- **Plants** — Gallformers is not an authority on plants. A plant's names, synonymy, placement, common names and range are Facts from POWO/WCVP or iNaturalist, which also backs the higher taxa of non-plants. A curator who corrects one makes a Gallformers statement.
- **Taxonomic act** — a rename, move, merge (lump) or split. Each is sourced, and the earlier taxonomy stays in the history. A Gall is not renamed by a taxonomic act on its own: the new Gall name is proposed for a curator to review. When a split is accepted, a curator says, for each Gall, which daughter induces it; when a lump is accepted, its Galls move to the taxon they were lumped into.

### Knowledge, Sources, and Facts

- **Source** — documented scientific discovery: a paper, book, website, or database (iNaturalist, as a database, is a Source), research data from pending (unpublished) research — such as a lab's records of galls it is still describing — or other documented work. Sources never cite each other formally in Gallformers' data.
- **Gallformers as a Source** — Gallformers is two Sources, both authored by "Gallformers Contributors":
  - **Gallformers legacy data** holds what the old site recorded. It is undated, so any dated statement overrides it, and a Fact only it supports shows as unconfirmed.
  - **Gallformers** holds the curators' own statements, each dated when it was made: curator knowledge (Hosts seen in Observations, corrections, descriptions) and, rarely, a taxonomic position no other Source supports.
- **Citation** — a Source is cited on a Gall's page (today, e.g., `/gall/587?source=58`); individual Facts may later get their own links.
- **Fact** — a statement about a Gall or a taxon: a Gall's Traits, the Species that induces it, its Hosts, its Relationships, where it occurs, its abundance; a taxon's name, placement and synonymy; a plant's range. A Fact stands on its own; Sources **confirm** or **deny** it. Every Fact is attributed to at least one Source.
- **Editorial content** — what Gallformers writes or keeps that isn't a Fact and needs no Source: a Gall's name parts, its ID notes (guidance for telling it apart, attached to no Source), its photos, and, on an undescribed Gall only, its Gallformers code; also keys, articles, the glossary and the people who use the site.
- **Attribution** — what ties a Source to a Fact: whether the Source confirms or denies it, the quote that says so and where in the Source it is, the name as the Source wrote it for each taxon it names, any Observations it cites, and the statement in words.
- **Newer work wins** — what Gallformers currently holds is decided by the most recently authored Source to confirm or deny a Fact, not by when Gallformers learned of it. A Fact a newer Source denies is **withdrawn**; where a Fact has one value (a placement, a current name), a newer value **supersedes** the older one. Both stay visible as history. When two Sources of the same date disagree, a curator decides. Gallformers states its own position on a Gall by making a newer statement as a Source. Taxonomy differs: a newer Source's taxonomic statement counts only once a curator accepts it, and a curator who doesn't follow it declines it with a reason instead of stating a Gallformers position.
- **Standing** — where a Fact stands: **current**, **withdrawn**, **superseded**, **retracted** (every Source that supported it is retracted), or **unsupported** (nothing that counts supports it, such as a taxonomic statement no curator has accepted; hidden).
- **Facts are never edited or deleted.** A newer statement overrides an older one, which stays in the record. The only deletion is of data added by mistake or in testing.
- **Reading** — how Gallformers read a Source: the Facts it took the Source to state, in the Source's own words. A **misreading** (a Host the Source doesn't name, the wrong value) is fixed under that Source's authority, at its date: the Source didn't say it, or said something else. Fixing a reading takes no Gallformers position, and is not a **Correction**, which only a Source publishes.
- **Correction** and **retraction** — a published correction (erratum, corrigendum) or a later revision is simply a newer Source. A **retracted** Source can no longer be relied on: everything it confirmed or denied stops counting, and it stays visible, marked as retracted.
- **Relationship** — the formal, general connection between a Gall and another member of its Community, e.g. "the *Andricus weldi* gall has Parasitoid *Torymus* sp." A Relationship is a Fact. The word is not used for connections between individual Observations.
- **Observations and Facts** — Observations are not Facts and are never Sources, but they can support Facts: a Source's statement can cite them. Typically the Source is Gallformers — e.g. "the *Andricus weldi* gall has Parasitoid *Torymus* sp., according to iNaturalist Observations 12345 and 67890."
- **Curator** — a person who reviews what Gallformers read a Source to say, settles its conflicts and applies it. Nothing changes on the site until a curator applies it: people stay responsible for what goes in.
- **Attribution vs. audit** — **attribution** is whose authority stands behind a Fact (for curator knowledge, Gallformers); **audit** is which person made a change. They are different questions.

### Ranges

- **Place** — a country or a region within one (ISO), a botanical region (TDWG), or a named area. Any place covers the smallest places within it, so a Fact about a large place counts for each of them.
- **Host range** — where a plant grows: Facts on the plant, each place **native** or **introduced**, mostly from POWO/WCVP in its own regions.
- **Potential range** — where a Gall *could* occur: its Hosts' native range, narrowed by the Gall's **only within** and **absent from** Facts. A region where a Host is introduced counts only when there's evidence the Gall occurs there. Every Gall has a Host, and every Host a range, so every Gall has a potential range; for most Galls it's the best information there is, and the site says so.
- **Only within** and **absent from** — Facts that narrow a Gall's potential range: a Source says the Gall occurs only in certain places, or not in a place its Hosts grow. A curator removing a place is an *absent from* Fact attributed to Gallformers.
- **Occurrence** — a Fact that a Gall was found somewhere: at a point (with its uncertainty, its date and the Observation it cites) or in a place.
- **Observed range** — where a Gall has actually been found: its occurrences. An occurrence counts even when it conflicts with an *only within* or *absent from* Fact; the conflict goes to a curator.
- **A Gall's range never extends beyond its Hosts' ranges** (native or introduced). A Gall recorded where none of its Hosts grows is a statement about a Host's range — the Host grows there, perhaps introduced or planted — not about the Gall's.
- **Using ranges** — identifying by place, and a place's list of Galls, use both the potential and the observed range, and say why each Gall matched.

### Traits

Traits describe a Gall, and they belong to the Gall: a Trait never varies by Host. Where a Gall really differs on one Host, that's a separate Gall entry (see *Cataloging*). Traits of the abstract Gall are Facts; the Traits of an observed gall are part of its Observation. Except for generation and detachable, a Gall can have several values of each Trait.

| Trait | What it describes |
|---|---|
| **Generation** | which generation of the Inducer's life cycle the Gall belongs to |
| **Detachable** | whether the Gall separates from the plant |
| **Plant part** | where on the Host the Gall forms |
| **Form** | the Gall's overall type |
| **Shape** | its geometry |
| **Color** | its colors |
| **Texture** | its surface |
| **Alignment** | how it sits on the plant |
| **Walls** | its wall structure |
| **Cells** | its larval chambers |
| **Season** | when it forms and grows (not when it is seen, nor when the Inducer emerges) |

Each Trait's values, with what each means and how the terms Sources use map onto them, grow as Sources are read. Gallformers' database holds them, published for anyone to read in [`priv/import/vocab/traits.json`](../../priv/import/vocab/traits.json).

**Generations** come in groups, each for the taxa whose life cycle it describes: *heterogony* (agamic and sexual, in Cynipini), *seasonal* (spring, summer and autumn generations, in gall midges and others), *rust stages*, and the *aphid life cycle*. The group for a Gall's Inducer is the one mapped to its nearest ancestor that has one.

**Place**, **Time**, and a **DNA Barcode** are Traits of an observed gall (see *Observations*).

### Relationships

A Relationship is the formal, general connection between a Gall and a member of its Community. Each is a Fact. The kinds are a fixed list:

| Relationship | Inverse | Meaning | Qualifiers |
|---|---|---|---|
| **inducer of** | induced by | the organism that induces the Gall | — |
| **host of** | induced on | the plant the Gall occurs on | — |
| **symbiont of** | has symbiont | an organism the Gall depends on, e.g. a fungus a gall midge carries | required for formation |
| **inquiline of** | has inquiline | lives in the Gall without having induced it | lethal / non-lethal |
| **cecidophage in** | has cecidophage | feeds on the Gall's tissue | lethal / non-lethal |
| **parasitoid in** | has parasitoid | a Parasitoid reared from the Gall, its target unknown | parasitism mode |
| **emerged from** | has emerged | emerged from the Gall, its role unknown — neutral about whether it is a Parasitoid, Inquiline, or something else | — |
| **feeds on** | fed on by | eats the Gall, without saying whether its tissue, its occupants, or both — neutral, for when the Source doesn't say | — |
| **herbivore of** | has herbivore | eats the Gall's plant tissue only — not the Inducer or other occupants | — |
| **successor in** | habitat for | moves into the vacated Gall | — |
| **modified form of** | has modified form | one Gall is a distinct form of another, produced when an Inquiline modifies it | — |
| **alternate generation of** | alternate generation of | two Galls are generations of one Inducer's life cycle | — |
| **parasitoid of** | has parasitoid | one organism parasitizes another, within a Gall | parasitism mode |
| **vectored by** | is vector for | one organism is carried by another, within a Gall | — |
| **predator of** | preyed on by | one organism eats another, within a Gall | — |

Parasitism mode covers idiobiont/koinobiont, solitary/gregarious, and ecto/endo.

**Neutral and specific kinds.** Where Sources are often vague, there's a neutral kind alongside the specific ones, so a Fact never says more than its Source: *emerged from* (role unknown) beside *parasitoid in* and *inquiline of*; *feeds on* (what it eats unspecified) beside *herbivore of* and *predator of*. An organism that eats both a Gall's tissue and its Inducer is two Facts: *herbivore of* the Gall and *predator of* the Inducer, in the Gall.

**Rules:**

- **A Gall has at most one Inducer**, at any rank. No Inducer means it's unknown; competing candidates map to their shared higher Taxon. A fungus required for formation is a symbiont, not a second Inducer.
- **Every Relationship between two organisms happens in a Gall.** Gallformers records "this wasp parasitizes that wasp *in this Gall*," never a free-standing interaction. This keeps Gallformers a gall database rather than a general species-interaction database.
- **A genus-level Host** means the Host was identified only to genus, not that the Gall occurs on every species in it.
- **Hyperparasitism** follows from chains of *parasitoid of*; it isn't a Relationship of its own.
- **Alternate generations are stated on their own evidence,** not inferred from a shared Inducer: research often shows two Galls alternate before the Taxonomy merges their names. Gallformers flags for a curator two generations of one Inducer that no *alternate generation of* links, and alternate generations whose Inducers differ.
- **Uncertainty lives in the Source**, not in the Relationship: there are no "suspected" or "confirmed" kinds.

**Worked cases:**

| Situation | Relationships |
|---|---|
| A wasp induces a bud gall on an oak | wasp *inducer of* bud gall; oak *host of* bud gall |
| An inquiline modifies the oak's bud gall (induced by the original wasp) into a distinct modified gall | inquiline *inducer of* modified gall; modified gall *modified form of* bud gall; original wasp *inducer of* bud gall |
| A midge and a fungus are both required to form a gall | midge *inducer of* gall; fungus *symbiont of* gall (required for formation); fungus *vectored by* midge, in the gall |
| A parasitoid attacks the inducing wasp inside its gall | parasitoid *parasitoid of* wasp, in the gall; if what it attacked is unknown, parasitoid *parasitoid in* the gall |
| A hyperparasitoid attacks a parasitoid, which attacks the inducing wasp, in one gall | parasitoid *parasitoid of* wasp, and hyperparasitoid *parasitoid of* parasitoid, both in the gall; the hyperparasitism follows |
| A cecidophage feeds inside a gall without killing the inducer or changing the gall's form | cecidophage *cecidophage in* gall (non-lethal) |
| An inquiline wasp lives in a gall without changing its form | inquiline *inquiline of* gall (non-lethal, if the Source says so) |
| A chalcid emerges from a reared gall, its role unknown | chalcid *emerged from* gall |
| A caterpillar eats a gall's tissue | caterpillar *herbivore of* gall; a woodpecker eating the larva inside: woodpecker *predator of* larva, in the gall |
| A Source says only "squirrels eat these galls" | squirrel *feeds on* gall |
| A Source says a caterpillar eats the gall tissue and the larva inside | caterpillar *herbivore of* gall; caterpillar *predator of* larva, in the gall |
| An ant colony moves into a vacated gall | ant *successor in* gall |
| A study shows an agamic gall and a sexual gall alternate | agamic gall *alternate generation of* sexual gall, sourced to the study |

### Cataloging

- **Gall entry** — how Gallformers catalogs one Gall together with its Community. Curators decide where one entry ends and another begins.

| Case | Entries |
|---|---|
| Two generations of one species | Two |
| One species, the same Gall on many Hosts | One |
| One species, form varies by plant part or Host | Separate only if truly morphologically different (curator judgment) |
| Two species, indistinguishable Galls, same Hosts | Two |
| Unknown Inducer, a Gall on a different Host from a lookalike | A new entry |
| Unknown Inducer, a different region | Depends: adjacent regions no; widely disjunct populations possibly |
| An unknown-inducer Gall later shown to be made by a known species | Curator decides: merge with that species' Gall if the same form, otherwise keep separate and link it to the species |

## How the concepts relate

- An Inducer induces Galls on Hosts. One Inducer can induce several Galls (one per generation, sometimes different forms).
- An Observation is one observed gall; Facts are about the abstract Gall. Sources state Facts; Observations support them, and a Gall's occurrences cite them.
- Identification goes from an Observation's Traits to a Gall, and through the Gall to the best-known Taxon for its Inducer.
- Taxonomic changes change names and placements; the Galls an organism induces don't change because its name did.
- A Gall's potential range follows from its Hosts; its observed range from its occurrences.

## Being discovered

- **Taxonomy in detail** — names, placement, and taxonomic changes as researchers experience them, and how a curator works through them. Later, in the taxonomy design session.
- Snapshot of the earlier draft, for reference: `docs/plans/domain-model-v1-2026-10-04.md` (local).

## Where the decisions came from

The concepts came from discovery with Jeff and Adam, 2026-09-30 to 2026-10-04. Decisions since then, with their old-tracker IDs (read with git; see AGENTS.md, "Old IDs"):

- Gallformers owns its taxonomy, sourced like every other Fact (Adam and Jeff, 2026-10-03/04; matter 8567).
- A Gall's range never extends beyond its Hosts' ranges (Jeff, 2026-10-26; matter 3272).
- Gallformers as two Sources, legacy data and Gallformers (Jeff, 2026-11-14).
- Curated and imported taxa; Traits never vary by Host (Jeff, 2026-11-15).
- Plants, what is a Fact and what is editorial, and ranges (Jeff, 2026-11-16; d178 for what is a Fact).
- Galls, not lookalikes; every Fact traced to its Source and never edited or deleted; curation is review (Jeff and Adam to curators, 2026-11-17; [the summary](../presentations/2026-11-reboot-summary.md)).
