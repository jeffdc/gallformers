# Gallformers import — producer guide

How to turn one Source into a Gallformers import package. Follow these rules exactly. The schemas in `schema/` define the shape of every file; this guide says what goes in them.

**Terms.** A *Source* is a publication, website or dataset. A *Gall* is a kind of gall (two generations of one species are two Galls). The *Inducer* makes the Gall; a *Host* is a plant it grows on. A *Fact* is one statement about a Gall; an *act* is one taxonomic statement.

## The phases

```
<package>/
  document.json   Phase 1  Document
  taxonomy.json   Phase 2  Taxonomy batch
  gall.json       Phase 3  Gall batch
                  Phase 4  Validate (validate.py)
  review.json     Phase 5  Review
                  Phase 6  Respond
```

Run the phases in order. Phase 4 must pass before phase 5 runs. The package is ready when `validate.py --review` passes; deliver all four files.

## Phase 1 — Document

Convert the Source into a DoclingDocument, `document.json`. Every later phase reads this document.

## Writing a batch (phases 2 and 3)

### Rules for every batch

1. **One Source per batch,** described in `source` (see "The Source block").
2. **`mode`:** `replace` for a full run over a Source; `add` for statements that supplement an earlier run.
3. **Names exactly as the Source writes them** (`name_as_written`), abbreviations included ("Q. lobata"), with the rank the Source implies. Identify every taxon by its name and rank, and every Gall by `identified_by` (Phase 3, "Galls").
   - When the document's text of a name is damaged by OCR or extraction ("Cynips Jlocossa" where the page evidently prints *flocossa*), keep `name_as_written` verbatim and give the evident printed name as `name_reading`. `name_reading` repairs damaged letters only: the author's own spelling stays as written, and capitals from small caps ("ANDRICUS RILEYI") stay too, since Gallformers normalises case.
   - When a passage names an organism by a common name only and the Source pairs that common name with a scientific name anywhere ("the red oak, Quercus rubrum"), declare the taxon by the scientific name and cite both passages. A common name the Source never pairs with a scientific name ("rose", with *Rosa* never printed) goes to `unmapped`.
   - A named hybrid ("Populus deltoides × P. angustifolia") is a taxon at rank species; an unnamed one ("hybrid intermediates") goes to `unmapped`.
4. **`new`** marks novelty the Source itself claims: *sp. nov.*, *gen. nov.*, *comb. nov.*, *comb. rev.*, *stat. nov.*, *stat. rev.*, *nom. nov.* for taxa; for Galls, see Phase 3, "Galls". A formal description of a taxon the Source names as its own counts, with or without those words, and so does a provisional name ("I call it provisionally…"); `new.status` holds the Source's words, or "described here".
5. **Controlled values** carry `as_written`: the vocabulary value plus the Source's own words, e.g. `{ "value": "tan", "as_written": "pale tan" }`. Choose values by their definitions (Phase 3, "Traits"). When no value's definition fits, record the term in `unmapped` with `term`, `slot`, the Gall if any, evidence, and an optional note. Every `as_written` field (authorship and status words included) is verbatim, OCR errors and all.
6. **Deny** where the Source corrects a published statement: another Source's Fact or act, or earlier records it calls wrong ("earlier records from Q. douglasii are misidentifications", "erroneously synonymized"). Any Fact or act can be denied this way, Trait values included. Leave other negatives out of the batch, `unmapped` included: contrasts within a description ("not woody"), absences ("no inquilines were reared"), rejected unpublished reports. State only what the Source says: a list of three Hosts says nothing about a fourth. A record the Source reassigns to another Gall ("the latter reference concerns N. quercusminutissimus") is a `confirm` on that Gall.
7. **Assertions only.** Hedged or doubted statements ("putative", "probably", "may", "must be confirmed", "not clear if", "is said to") go to `unmapped` (slot `other`) with their quote, in place of a Fact, act, or flag.
   - A hedged correction ("this report has been questioned") is a hedge: `unmapped`, not a `deny`.
   - A statement made outright stays a statement when the Source adds that later work may revise it ("further research may call this into question").
   - A named person's record the Source reports ("Professor Riley says: …") is stated, with `cites`.
8. **Evidence** on every Fact and act (see "Evidence").
9. **References** use fixed prefixes: taxa `t1, t2, …`; Galls `g1, g2, …`; Facts `f1, f2, …`; acts `a1, a2, …`. Declare each taxon and Gall once and refer to it by its ref.
10. **The Source's date:** `source.authored.date` is the single date that decides recency, with the original wording in `as_written`. For a publication, the publication date the document prints, as precisely as it gives it (year at minimum); for a website, the stated last-modified date, or else the access date (the operator supplies it with the document).

### The Source block

- `kind`: `publication`, `website`, `database`, `unpublished`, or `research_data`.
- `title`, `citation`, and `authors` (names exactly as written, in order).
- `authored`: see rule 10.
- `license`: a value from `vocab/licenses.schema.json`, with the rights statement as found in `as_written`. A Source with no stated license is `All Rights Reserved`, `as_written` "not stated", unless it is in the public domain by age or origin (e.g. a US Government publication): then `Public Domain / CC0`, with the reason in `as_written`.
- `document`: `{ "file": "document.json", "sha256": "<sha256 of document.json>" }`.
- `identifiers` (`doi`, `url`, `isbn`) when the Source gives them.
- `retracts`, on a retraction notice only: the retracted Source's citation as written. A retraction cancels everything the retracted Source contributed; the notice's own batches usually hold no Facts or acts.

### Evidence

Each evidence entry quotes the document:

- `item`: the reference of the document item the evidence is in (e.g. `#/texts/42`, `#/tables/3`).
- `quote`: verbatim text from that item, long enough to be unambiguous within it — a sentence or a clause. Copy the document's text as it stands, OCR errors included. For a table row, the row's cells joined with " | ".
- Cite the passage that states the Fact: the sentence that says it, in preference to a figure caption or a heading that names it.
- A statement that spans two items (a name broken over two lines, a column break) takes one evidence entry per item.
- `whole_item: true` in place of `quote` when the evidence is the item's entire text (typically a descriptive paragraph).
- `page`: the page number as printed in the Source, when known.
- `url`: a deep link to this place in the Source, when one exists (a Biodiversity Heritage Library page, a website's species page).
- `cites`: when the Source states this by citing another work ("Q. alba (Kinsey 1923)"), that citation as written.
- `observations`: Observations the Source cites, if any.

### Vocabularies

`vocab/` holds every controlled list (`*.schema.json`), plus `places.json` (place names for codes) and `traits.json` (Trait definitions and term mappings, and the generation groups). Set `vocabulary_version` to the `vocabulary_version` those files carry (they share one).

### Examples

`examples/` holds complete packages that illustrate the format. Their Sources are fictional.

- `simple-paper`: Hosts, a denial, a parasitoid with a qualifier, Traits, a range exclusion, a common name, a description, and a new undescribed Gall.
- `revision`: a taxonomy batch (new species, recombination, placement into a tribe, split, synonymy) and its gall batch (new Galls, alternate generations).
- `retraction`: a retraction notice.

## Phase 2 — Taxonomy batch

Write `taxonomy.json` (`schema/taxonomy.schema.json`). When the Source states no taxonomic acts, its `taxa` and `acts` are empty.

Acts (`acts[]`), each with `id`, `stance`, `kind`, and `evidence`:

| kind | Fields | Meaning |
|---|---|---|
| `name` | `taxon`, optional `authorship.as_written` | The taxon exists with this name and rank. With `taxa[].new`, the Source describes it as new. |
| `placement` | `taxon`, `parent` | The taxon sits under this parent. |
| `synonymy` | `name`, `accepted` | `name` is a synonym of `accepted`. |
| `split` | `taxon`, `into` | The taxon was divided into these taxa. |
| `common_name` | `taxon`, `common_name` | A common name of the organism ("Poplar vagabond aphid"). Common names of Galls are Phase 3 `alias` Facts. |

`status_as_written` on any act holds the Source's own status words for it: "syn. nov.", "stat. rev.", "incorrect spelling", "nomen dubium".

**Misapplied names.** A name the Source says was used for the wrong species ("C. confluens O. S. non Harris": Osten Sacken's use of the name, not Harris's species) is declared with `sensu`, the usage as written ("O. S. non Harris"). A `synonymy` act from it to the right taxon states the correction.

Rules:

- **State the acts the Source makes or adopts:** its own new acts, its synonymy lists, and earlier acts it says it follows ("We follow this treatment"). An earlier act the Source rejects may be a `deny`.
- **Using a name is not a name act.** A `name` act is a name the Source introduces, changes or adopts in a treatment of its own.
- **State a placement when the Source adopts the classification:** a new or changed placement, or a classification the Source states as its own. Labels that only organize the text (a title's "(Hymenoptera: Cynipidae)", a checklist's family headings) and classification mentioned in passing ("the only representatives of the tribe Phanacidini") are context.
- **A new genus** with no parent stated: its `name` act alone.
- **A placement the author doubts** goes to `unmapped` (rule 7); the binomial's `name` act stands.
- **An original genus given only in the authorship** ("Thecabius gravicornis (Patch, 1913) (Pemphigus)") stays in the authorship; the old combination isn't composed.
- **Compose:**
  - **New species:** `taxa[].new` + `name` + `placement`.
  - **Recombination (comb. nov., comb. rev.):** `placement` of the combination + its `name` (with `new.status`) + `synonymy` of the old combination to it.
  - **Change of status (stat. nov., stat. rev., a variety raised to species):** `name` at the new rank (with `new.status` when the Source writes one) + `synonymy` of the old name to it.
  - **Lump:** one `synonymy` per lumped name.
  - **New intermediate rank (e.g. a tribe):** `name` for it + `placement`s of its members.
  - **Split:** the division only (`taxon` and `into`).
- **Authorship** exactly as written, e.g. "(Ashmead, 1881)".
- **Ranks:** any rank in `vocab/ranks.schema.json`, kingdom to form. Synonymy and splits are at family rank or below.
- **Taxa:** acts concern animals, fungi and other gall-associated organisms. Plants appear as acts only when the plant is itself a gall-former.
- **Unmapped taxonomy** uses slot `taxonomic_act` (an act the contract can't express or the Source hedges) or `rank`.

## Phase 3 — Gall batch

Write `gall.json` (`schema/gall.schema.json`), using taxon names as they stand after phase 2.

### Galls

- Declare each Gall in `galls[]` with `name_as_written` and `identified_by`:
  - `inducer`: a taxon ref, at the rank the Source gives (genus or family for an undescribed Gall);
  - `generation`: when the Source shows a clearly different Gall for a stage of the Inducer's life cycle (see "Generations");
  - `host`: when the Host distinguishes the Gall, e.g. an undescribed Gall known only from its Host;
  - `plant_part`: when two Galls of one Inducer and Host differ by where they grow (a collar gall and a spindle gall of one *Antistrophus* on one plant).
  - At least one of `inducer` and `host`.
- **`new: true`** for a Gall the Source presents as previously unknown, including a newly described generation of a known species ("the first sexual generation to be described for Phylloteras") and undescribed Galls it describes as unrecorded ("Oak-galls not mentioned in the paper"). The batch states at least one Fact about it.
- **`formerly_undescribed: true`** for a Gall known before whose Inducer this Source names for the first time (a gall reported in 1959, its wasp described in 1997), with its Host in `identified_by`.
- **Declare Galls of the taxa the Source treats.** A Gall the Source only mentions (e.g. in a comparison) is declared when the Source itself states a Fact about it ("the galls of A. quercuscitriformis are … smooth and glabrous … lemon-yellow"). A taxon the Source only cites from another work ("according to Kinsey (1923), var. albipleurae induces galls on Q. breviloba") gets no Gall; its statement goes to `unmapped`.
- **Facts come from the Source's treatment of its subject.** Introductions, background sections and photo captions that show galls outside that subject (an oak gall pictured in a guide to galls on brambles and herbs) produce no Galls.
- **Entries the Source itself marks unverified or doubtful** (a section headed "Unverified galls & hosts") are hedged statements: they go to `unmapped` (rule 7).
- **Statements about a species rather than a generation** (distribution, "earlier records are from Q. alba") attach to a Gall when the Source ties them to a generation, or when the species has a single Gall in the Source. Otherwise they go to `unmapped` with the note "applies to the species".
- **Statements about a group of Galls** the Source then separates (a species group split by host in a table) attach to each of them.
- `identified_by` identifies the Gall; state its Relationships (`inducer_of`, `host_of`, …) as Facts.

### Generations

A generation is a stage of the Inducer's life cycle that induces a clearly different Gall. Each such Gall is its own Gall, with its generation in `identified_by`.

- **Give a generation only when the Source shows a clearly different Gall for that stage.** Repeated broods that induce the same Gall are multivoltine: one Gall, with no extra generation value. *Thecabius populimonilis* apterae induce galls like the stem mother's: one Gall. *Pachypappa pseudobyrsa* apterae induce a different gall: two Galls, `fundatrix` and `apterae`.
- **A multivoltine seasonal Gall** ("summer and autumn generations") takes one value, `summer`.
- **Choose from the group for the Inducer's taxon.** Generation values come in groups, listed under `traits.generation.groups` in `vocab/traits.json`; each group names its values and the taxa it applies to (the heterogony group, `agamic` and `sexual`, applies to Cynipini). The groups that apply are those of the Inducer's taxon or its nearest ancestor with groups: a group on a lower taxon takes precedence over one on a higher taxon. When neither the Inducer's taxon nor any ancestor has a group (an undescribed Gall whose Inducer is known only to family), choose from the groups of the taxa below it.
- **Choose by definition.** Each value in `traits.json` has a definition and the other names Sources use for it ("stem mother" is `fundatrix`); `as_written` carries the Source's words. A stage that fits no value of the group goes to `unmapped` (slot `generation`).

### Relationships

| type | Subject → object | Meaning |
|---|---|---|
| `inducer_of` | taxon → Gall | the organism that induces the Gall |
| `host_of` | plant taxon → Gall | the plant the Gall occurs on (genus level allowed, e.g. "Quercus spp.") |
| `symbiont_of` | taxon → Gall | an organism the Gall depends on, e.g. a fungus a gall midge carries |
| `inquiline_of` | taxon → Gall | lives in the Gall without having induced it |
| `cecidophage_in` | taxon → Gall | feeds on the Gall's tissue |
| `parasitoid_in` | taxon → Gall | a parasitoid reared from the Gall, its target unknown |
| `emerged_from` | taxon → Gall | emerged from the Gall, its role unknown |
| `feeds_on` | taxon → Gall | eats the Gall, whether tissue or occupants unspecified |
| `herbivore_of` | taxon → Gall | eats the Gall's plant tissue only |
| `successor_in` | taxon → Gall | moves into the vacated Gall |
| `modified_form_of` | Gall → Gall | a distinct form produced when an inquiline modifies the other Gall |
| `alternate_generation_of` | Gall → Gall | two Galls are generations of one Inducer's life cycle |
| `parasitoid_of` | taxon → taxon, in a Gall | one organism parasitizes another, within `gall_context` |
| `vectored_by` | taxon → taxon, in a Gall | one organism is carried by another, within `gall_context` |
| `predator_of` | taxon → taxon, in a Gall | one organism eats another, within `gall_context` |

- **Use the most specific type the Source supports.** "Reared from the gall" with no stated role is `emerged_from`; a role the Source states elsewhere counts ("stem galls of cecidomyiid flies … all of the individuals I have reared from these galls were Lasioptera solani" is `inducer_of`). A Source can support a neutral and a specific type together: a caterpillar eating gall tissue and the larva inside is `herbivore_of` plus `predator_of` (in the Gall).
- **Hosts:** when the Source lists a Gall's Host species, state those; a genus `host_of` only when it names no species. Galls found under or near a plant ("on the ground, under an oak") don't make it a Host, and plants the Inducer lives on without a Gall (an aphid's secondary hosts) aren't Hosts: both go to `unmapped`.
- **One Inducer per Gall.**
- **Hyperparasitism** is stated as `parasitoid_of` between the organisms involved.

### Qualifiers

A qualifier is its own Fact, pointing at a Relationship Fact in the same batch (`of`):

| qualifier | On | Values |
|---|---|---|
| `required_for_formation` | `symbiont_of` | `true` |
| `lethality` | `inquiline_of`, `cecidophage_in` | `lethal`, `non-lethal` |
| `parasitism_mode` | `parasitoid_in`, `parasitoid_of` | `idiobiont`, `koinobiont`, `solitary`, `gregarious`, `ecto`, `endo` (one Fact per value) |

### Traits

- Traits: `detachable`, `plant_part`, `form`, `shape`, `color`, `texture`, `alignment`, `walls`, `cells`, `season`. Values come from `vocab/traits.schema.json`.
- **A value's definition in `vocab/traits.json` decides whether it fits;** the value's name is shorthand for its definition. `traits.json` also maps common Source terms onto values.
- A Gall can have several values of each Trait, one Fact per value; `detachable` has one value.
- `season` is when the Gall forms and grows: not when it is seen or found, and not when the Inducer emerges (rearing and emergence dates don't count). `Winter` applies only where the Host grows in winter.
- `detachable` is whether the Gall can be removed from the Host without cutting it out or destroying the surrounding tissue. `both` means it is ambiguous: the Gall bursts and drops later, part of it stays behind, or it rarely comes off without major agitation.
- `texture` describes the surface.
- `color` is what you see on the Gall, its covering (hairs, wool) included; a Gall can have several colours.
- `plant_part`: the most precise location the Source supports. A usual location ("usually along the midrib") counts as the location. A leaf Gall with no side, vein or midrib stated is both `upper leaf` and `lower leaf`.
- Map by definition, not by word: a described single central cell is `monothalamous` though the Source never says "monothalamous". A value a definition merely implies (cells `not applicable` for an aphid gall) is left out unless the Source says it.
- Generation identifies the Gall (`identified_by`), not a Trait.
- A Trait the Source states for one Host only ("smooth and large when on Q. alba") goes to `unmapped`.

### Range adjustments

A Gall's range is computed from its Hosts' ranges, native and introduced. State only adjustments to it:

- `exclude`: the Source states the Gall does not occur in a place within its Hosts' ranges;
- `only`: the Source says the Gall occurs only in this place ("in Texas only"); one Fact per place.

A place where the Source says the Gall occurs but none of its Hosts grows is not an adjustment: state it as a recorded occurrence ("Recorded occurrences").

`place.value` is a code from `vocab/place-codes.schema.json`; find it by name in `vocab/places.json`.

### Recorded occurrences

An `occurrence` Fact states a place where the Source says the Gall has been recorded ("collected on Mt. Diablo in July", a field guide's "Range: California, Oregon"). One Fact per place:

- `place`: the code of the place the Source names, or of the place that contains it, with the Source's words in `as_written` (`{ "value": "US-CA", "as_written": "Mt. Diablo" }`);
- `when_as_written`: when it was recorded, as the Source gives it ("July 1961", "late summer"), if it does;
- `stage_as_written`: the Gall's or Inducer's stage at the record, as the Source gives it ("young galls", "adults emerging"), if it does.

Recorded occurrences are separate from range adjustments: state an adjustment only as "Range adjustments" describes.

### Common names

`alias` Facts carry common names. Scientific names, synonyms and old combinations are taxonomy (phase 2).

### Descriptions

A `description` Fact is the Source's description of a Gall as a collage of direct quotes, in reading order: the quotes in its `evidence` are the description. One per Gall.

## Phase 4 — Validate

Run `validate.py` on the package and fix every error it reports; warnings (e.g. a taxon declared but never used) are worth a look. Run phase 5 only once phase 4 passes.

```
uv run priv/import/validate.py <package-dir>
python3 priv/import/validate.py <package-dir>     # needs jsonschema >= 4.18, rfc3339-validator, rfc3987
```

It checks each batch against its schema, that `source.document.sha256` matches `document.json`, that every quote is found in its item, and that references, qualifiers, Inducers, descriptions and `new` Galls are consistent.

## Phase 5 — Review

A fresh reviewer, following `VERIFY_GUIDE.md`, checks every act and Fact against the document and writes `review.json` with its findings. The reviewer works from this guide, the vocabularies, `document.json` and the two batches only, and changes nothing. Several reviewers (for example, different models) may review the same batches; their findings are combined in one `review.json`, each naming its `reviewer`.

When there are no findings, the package is ready. Otherwise, run phase 6.

## Phase 6 — Respond

The producer answers every finding once, in its `response`:

- **Agree** when the finding is right by this guide and the document. Fix the statement (as suggested, or better), and say what changed in `reason`.
- **Disagree** when the statement already follows this guide and the document. Leave it as it is, and say why in `reason`, citing the document or the rule. A disputed finding goes to a human reviewer at intake.

Then run phase 4 again, and record `responded`: the sha256 of each batch as you leave it (`result`). The package is ready when this passes:

```
uv run priv/import/validate.py --review <package-dir>
```

`--review` adds to the phase 4 checks: `review.json` is well-formed; with no findings, it covers the current batches; otherwise every finding has a response and the batches are the ones `responded` names. Disputed findings are listed for intake.
