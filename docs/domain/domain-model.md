# Gallformers Domain Model

> **In discovery.** This document records the language of the domain — galls, the organisms connected to them, and the work of studying and cataloging them — as discovered from domain experts. It holds only concepts confirmed so far and how they relate. **It says nothing about software.** Mapping these concepts onto the system is separate work; the current design draft lives in mull matter `8567`. The current code follows [general.md](general.md) and [admin-domain-reference.md](admin-domain-reference.md).

## How this document is built

Discovery first: find the words the domain actually uses, what they mean, and how they relate — then, separately, map them onto software. A term lands here only once a domain expert has confirmed it. Where a word's meaning is still being worked out, it is listed under *Being discovered*, not defined.

## What Gallformers is

A website and database to aid the **Identification** and **Cataloging** of gall-inducing organisms. Gallformers aims to **Source** every **Fact** it states about Galls.

## Confirmed concepts

### Galls

- **Gall** — a novel structure on a plant, induced by another organism in a repeatable way. The word means both the individual one you find and the abstract thing all such finds are instances of; context tells you which. (In this document, "Gall" alone means the abstract one; an individual gall is an *observed gall*, part of an Observation.)
- **Host** — the plant a Gall forms on.
- **Inducer** — the organism that **induces** a Gall. Inducers come from any of the kingdoms of life.
- **Generation** — some Inducers are multivoltine, and each generation produces a distinct Gall (in Cynipini, an agamic and a sexual generation). Terms vary by group.
- **Gall Community** — all the organisms involved in a Gall's existence: the Inducer, the Host, Parasitoids, Inquilines, herbivores, organisms that move into a vacant Gall, and so on.
- **Inquiline** — lives in a Gall it didn't induce; some change the Gall's form.
- **Parasitoid** — kills its host organism within the Gall; hyperparasitoids parasitize Parasitoids.
- **Non-Gall** — something that looks like a Gall but isn't: a plant's damage response, or a structure an arthropod builds for eggs or pupation. Outside what Gallformers catalogs.

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
- **Gallformers' Taxonomy** is best-effort and opinionated. Where the literature settles a name or placement, the literature is the Source; where Gallformers takes its own position, the Source is Gallformers.
- **Host Taxonomy** — plant taxonomy generally comes from POWO.

### Knowledge, Sources, and Facts

- **Source** — documented scientific discovery: a paper, book, website, or database (iNaturalist, as a database, is a Source), research data from pending (unpublished) research — such as a lab's records of galls it is still describing — or other documented work. **Gallformers itself is a Source**, authored by "Gallformers Contributors," for curator knowledge and for the positions Gallformers takes.
- **Citation** — a Source is cited on a Gall's page (today, e.g., `/gall/587?source=58`); individual Facts may later get their own links.
- **Fact** — a statement about a Gall (its Traits, the Species that induces it, its Hosts, the Places it occurs, its Inducer's placement in the Taxonomy — what the literature and research tell us). A Fact stands on its own; Sources **confirm** or **deny** it. Every Fact is attributed to at least one Source.
- **Newer work wins** — what Gallformers currently holds is decided by the most recently authored Source to confirm or deny a Fact, not by when Gallformers learned of it. A Fact a newer Source denies is **withdrawn**; where a Fact has one value (a placement, a current name), a newer value **supersedes** the older one. Both stay visible as history. Gallformers states its own position by making a newer statement as a Source.
- **Correction** and **retraction** — a published correction (erratum, corrigendum) or a later revision is simply a newer Source. A **retracted** Source can no longer be relied on: everything it confirmed or denied stops counting, and it stays visible, marked as retracted.
- **Relationship** — the formal, general connection between a Gall and another member of its Community, e.g. "the *Andricus weldi* gall has Parasitoid *Torymus* sp." A Relationship is a Fact. The word is not used for connections between individual Observations.
- **Observations and Facts** — Observations are not Facts and are never Sources, but they can support Facts: a Source's statement can cite them. Typically the Source is Gallformers — e.g. "the *Andricus weldi* gall has Parasitoid *Torymus* sp., according to iNaturalist Observations 12345 and 67890."
- **Observational data** — Observations shown as what they are, without a Fact per Observation. For example, Research Grade locations overlaid on a range map show where a Gall has actually been seen. At most, the body of Research Grade iNaturalist Observations counts as one Source.
- **Potential range** — where a Gall *could* occur: the union of its Hosts' ranges. Every Gall has one, and it follows from its Host Facts (a Gall linked to a Host inherits that Host's range). A Host's range is outside Gallformers' Facts: it comes from POWO, and curators can adjust it. For most Galls this is the best information there is, and the site says so.
- **Range exclusion** — a Fact that removes a region from a Gall's potential range: a region within its Hosts' ranges where the Gall doesn't occur. Sources can state them; a curator removing a region is an exclusion attributed to Gallformers. A Source can also say the Gall occurs *only* in certain regions.
- **A Gall's range never extends beyond its Hosts' ranges** (native or introduced). A Gall recorded where none of its Hosts grows is a statement about a Host's range — the Host grows there, perhaps introduced or planted — not about the Gall's.
- **Observed range** — where a Gall has actually been found, from observational data. Future.
- **Attribution vs. audit** — **attribution** is whose authority stands behind a Fact (for curator knowledge, Gallformers); **audit** is which person made a change. They are different questions.

### Traits

Traits describe a Gall. Traits of the abstract Gall are Facts; the Traits of an observed gall are part of its Observation. Except for generation and detachable, a Gall can have several values of each Trait.

| Trait | What it describes | Values supported today |
|---|---|---|
| **Generation** | which generation of the Inducer's life cycle the Gall belongs to | terms vary by group. Provisional list: agamic, sexual, spring, summer, autumn (aphid host-alternation phases still open) |
| **Detachable** | whether the Gall separates from the plant | integral, detachable, both, unknown |
| **Plant part** | where on the Host the Gall forms | at leaf vein angles, between leaf veins, bud, flower, fruit, leaf edge, leaf midrib, lower leaf, on leaf veins, petiole, stem, underground (roots+), upper leaf |
| **Form** | the Gall's overall type | abrupt swelling, bullet, hat, hidden cell, jacket, leaf blister, leaf curl, leaf edge fold, leaf edge roll, leaf snap, leaf spot, modified capitulum, oak apple, pip, plum, pocket, rust, scale, stem club, tapered swelling, wig, witches broom |
| **Shape** | its geometry | cluster, conical, cup, cylindrical, globular, hemispherical, linear, numerous, rosette, spangle/button, sphere, spindle, tuft |
| **Color** | its colors | black, brown, gray, green, orange, pink, purple, red, tan, UV, white, yellow |
| **Texture** | its surface | areola, bumpy, erineum, glaucous, hairless, hairy, honeydew, leafy, mealy, mottled, pubescent, resinous dots, ribbed, ruptured/split, spiky/thorny, spotted, stiff, striped, succulent, woolly, wrinkly |
| **Alignment** | how it sits on the plant | drooping, erect, integral, leaning, supine |
| **Walls** | its wall structure | false chamber, mycelium lining, ostiole, radiating-fibers, slit, spongy, thick, thin |
| **Cells** | its larval chambers | monothalamous (one), polythalamous (many), free-rolling, not applicable |
| **Season** | when it forms and grows (not when it is seen, nor when the Inducer emerges) | Spring, Summer, Fall, Winter |

**Place**, **Time**, and a **DNA Barcode** are Traits of an observed gall (see *Observations*).

### Relationships

A Relationship is the formal, general connection between a Gall and a member of its Community. Each is a Fact. The kinds:

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
- **Alternate generations are stated on their own evidence,** not inferred from a shared Inducer: research often shows two Galls alternate before the Taxonomy merges their names.
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
- An Observation is one observed gall; Facts are about the abstract Gall. Sources state Facts; Observations support them, or are shown directly as observational data.
- Identification goes from an Observation's Traits to a Gall, and through the Gall to the best-known Taxon for its Inducer.
- Taxonomic changes change names and placements; the Galls an organism induces don't change because its name did.

## Being discovered

- **Traits that vary by Host** — can a Trait (plant part, timing, minor form) apply only on a particular Host ("petiole on *Q. rubra*, leaf on *Q. velutina*")? Leaning no: real host-dependent differences go in a Source's statement or justify a separate Gall entry. Needs a definitive answer.
- **Taxonomy in detail** — names, placement, and taxonomic changes as researchers experience them. Later.
- Snapshot of the earlier draft, for reference: `docs/plans/domain-model-v1-2026-10-04.md` (local).
