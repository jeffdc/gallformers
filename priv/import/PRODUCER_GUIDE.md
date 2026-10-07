# Gallformers import — producer guide

**Status: DRAFT, format v3 (2026-10-07).** This guide and the schemas in `schema/` are the contract for delivering data into Gallformers. Anything — an LLM pipeline, a script, a form, a person — that produces files meeting this contract can deliver data. Decisions behind it are recorded in mull matter `e381`; the domain's words (Gall, Source, Fact, Relationship, Trait) are defined in `docs/domain/domain-model.md`.

Each section gives **rules first**, then *why*. An LLM producing batches should follow the rules exactly; a developer should read the why.

## 1. What you produce

For each Source, a package directory:

```
<package>/
  document.json   phase 0: the Source as a structured document (a DoclingDocument)
  taxonomy.json   phase 1: taxonomic acts the Source states (omit if none)
  gall.json       phase 2: what the Source states about Galls
```

Rules:

- **Phase 0** turns the Source into a DoclingDocument (`document.json`). Both later phases read this document, not the original PDF or web page.
- **Phase 1** produces a taxonomy batch (`schema/taxonomy.schema.json`) if, and only if, the Source states taxonomic acts.
- **Phase 2** produces a gall batch (`schema/gall.schema.json`). Resolve taxon names as they stand **after** phase 1.
- Every batch validates against its schema before delivery.
- Gallformers approves the taxonomy batch before the gall batch.

*Why:* each phase is a smaller, more reliable task, and each output can be checked on its own. The document gives every quote a stable anchor.

## 2. Rules for every batch

1. **One Source per batch.** Describe it in `source`, or use `{ "gallformers": true }` for Gallformers' own statements.
2. **Choose `mode` deliberately.**
   - Use `replace` for a full run over a Source. It replaces everything that Source previously contributed in this batch type.
   - Use `add` for extra statements. Gallformers batches are always `add`.
3. **Write names exactly as the Source writes them** (`name_as_written`), including abbreviations like "Q. lobata". Do not correct, expand, or modernize them. Give the rank the Source implies.
4. **Never look up or guess Gallformers IDs.** Gallformers resolves names and Galls itself. An ID field may be filled only if you are certain; a wrong ID is worse than none.
5. **A name that you can't match to anything is not new.** Set `new` only when the Source itself claims novelty: *sp. nov.*, *gen. nov.*, *comb. nov.*, *stat. nov.* for taxa, or a Gall described as previously unknown. Unknown names are left for Gallformers to flag.
6. **Every controlled value carries `as_written`:** the mapped value from the vocabulary plus the Source's own words, e.g. `{ "value": "tan", "as_written": "pale tan" }`.
   - If no vocabulary value fits, **do not force one**. Leave the Fact out and add the term to the batch's `unmapped` list with:
     - `term`;
     - `slot` (which vocabulary it would belong to);
     - the Gall, if any;
     - evidence;
     - an optional note.
7. **Deny only what the Source explicitly denies.** `stance: "deny"` needs words like "not", "misidentified", "erroneous", "never found". **Omission is never denial:** a Source listing three hosts does not deny a fourth.
8. **Every Fact and act has evidence** (see §6).
9. **Batch-local references** use fixed prefixes: taxa `t1, t2, …`; Galls `g1, g2, …`; Facts `f1, f2, …`; acts `a1, a2, …`. Declare each taxon and Gall once and refer to it by ref.
10. **The Source's date.** Set `source.authored.date` to the single date that decides recency, and keep the original wording in `as_written`.
    - Publications: the publication date, as precise as known (year at minimum).
    - Websites: the date of the version read. Use the stated last-modified date if given, otherwise the access date.

*Why:* when Sources disagree, Gallformers decides between them by authorship date (newest wins) and by explicit stances. Guessing IDs, inventing novelty, or inferring denials from silence would all create errors that pass validation unnoticed. `as_written` makes every mapping reviewable, and shows where the vocabulary should grow.

## 3. The Source block

- Required: `kind`, `title`, `authors`, `authored`, `citation`, `license`, `document`.
- `kind` is one of: `publication`, `website`, `database`, `unpublished`, `research_data`.
- `authors` is a list of names exactly as written, in order.
- `license`: the value comes from `vocab/licenses.schema.json`. A Source with no stated license is `All Rights Reserved`. Put the rights statement as found in `as_written`, or "not stated".
- `document`: `{ "file": "document.json", "sha256": … }`, or `{ "none": "<reason>" }` when no document could be made (e.g. an unreadable scan).
- `retracts`: only on a retraction notice. Name the retracted Source, with its citation as written and its ID if known.
  - Retraction is a status on the retracted Source as a whole. It cancels everything that Source contributed, in both batch types. The notice's own batch usually has no Facts.
- Do not include editorial fields such as data-completeness flags.

## 4. Taxonomy batches

Acts (`acts[]`), each with `id`, `stance`, `kind`, and `evidence`:

| kind | Fields | Meaning |
|---|---|---|
| `name` | `taxon`, optional `authorship.as_written` | The taxon exists with this name and rank. With `taxa[].new`, the Source describes it as new. |
| `placement` | `taxon`, `parent` | The taxon sits under this parent. A placement different from the current one is a move. |
| `synonymy` | `name`, `accepted` | `name` is a synonym of `accepted`. |
| `split` | `taxon`, `into` | The taxon was divided into these taxa. |

Rules:

- **Compose, don't invent kinds:**
  - **New species:** `taxa[].new` + `name` + `placement`.
  - **Recombination (comb. nov.):** `placement` of the new combination + its `name` (with `new.status: "comb. nov."`) + `synonymy` of the old combination to the new one.
  - **Lump:** one `synonymy` per lumped name.
  - **New intermediate rank (e.g. a tribe):** a `name` for it + `placement`s of its members.
- **Split:** state the division only. Do not try to assign existing records to the daughter taxa.
- **Authorship:** keep it exactly as written, e.g. "(Ashmead, 1881)". Do not parse it.
- **Ranks:** family, subfamily, tribe, subtribe, genus, subgenus, section, species, subspecies, variety, form. Nothing above family.
- **Never state acts on plant taxa.** Plants come from POWO; the only exception is a plant that is itself a gall-former.
- **Never put Galls or gall Facts in a taxonomy batch.**

*Why:* four composable kinds cover everything papers do, and each maps to one checkable statement. Assigning old records after a split needs judgement the Source rarely supports.

## 5. Gall batches

### 5.1 Identifying Galls

**Rules:**
- Declare each Gall in `galls[]` with `name_as_written` and `identified_by`:
  - `inducer`: a taxon ref, at the rank the Source gives (genus or family for undescribed Galls);
  - `generation`: when the Source distinguishes generations;
  - `host`: when the Host distinguishes the Gall, e.g. an undescribed Gall known only from its Host.
- At least one of `inducer` or `host` is required.
- Gallformers matches this description to its Gall entries. Never supply a Gall ID unless certain.
- `new: true` only for a Gall the Source presents as previously unknown, and the batch must contain at least one Fact about it.
- `identified_by` is for matching only. **State the Relationships themselves as Facts** (e.g. `inducer_of`, `host_of`) when the Source states them.

*Why:* Gallformers catalogs Galls as entries (two generations of one species are two entries). The Source knows the Inducer, the generation, and sometimes the Host, which is enough for Gallformers to find the entry.

### 5.2 Relationships

Subject → object; endpoint kinds are enforced by the schema.

| type | Subject → object | Meaning |
|---|---|---|
| `inducer_of` | taxon → Gall | the organism that induces the Gall |
| `host_of` | plant taxon → Gall | the plant the Gall occurs on (genus-level allowed, e.g. "Quercus spp.") |
| `symbiont_of` | taxon → Gall | an organism the Gall depends on, e.g. a fungus a gall midge carries |
| `inquiline_of` | taxon → Gall | lives in the Gall without having induced it |
| `cecidophage_in` | taxon → Gall | feeds on the Gall's tissue |
| `parasitoid_in` | taxon → Gall | a parasitoid reared from the Gall, its target unknown |
| `emerged_from` | taxon → Gall | emerged from the Gall, its role unknown (neutral) |
| `feeds_on` | taxon → Gall | eats the Gall, unspecified whether tissue or occupants (neutral) |
| `herbivore_of` | taxon → Gall | eats the Gall's plant tissue only |
| `successor_in` | taxon → Gall | moves into the vacated Gall |
| `modified_form_of` | Gall → Gall | a distinct form produced when an inquiline modifies the other Gall |
| `alternate_generation_of` | Gall → Gall | two Galls are generations of one Inducer's life cycle |
| `parasitoid_of` | taxon → taxon, in a Gall | one organism parasitizes another, within `gall_context` |
| `vectored_by` | taxon → taxon, in a Gall | one organism is carried by another, within `gall_context` |
| `predator_of` | taxon → taxon, in a Gall | one organism eats another, within `gall_context` |

Rules:
- **Use the most specific type the Source supports, and no more.**
  - "Reared from the gall" with no stated role is `emerged_from`, not `parasitoid_in`.
  - "Squirrels eat these galls" is `feeds_on`.
  - A Source can support both a neutral and a specific type. For example, a caterpillar eating gall tissue and the larva inside is `herbivore_of` plus `predator_of` (in the Gall).
- **At most one Inducer per Gall.**
- **Do not state hyperparasitism.** Gallformers derives it from chains of `parasitoid_of`.

### 5.3 Qualifiers

A qualifier is its own Fact pointing at a Relationship Fact in the same batch (`of`):

| qualifier | Allowed on | Values |
|---|---|---|
| `required_for_formation` | `symbiont_of` | `true` |
| `lethality` | `inquiline_of`, `cecidophage_in` | `lethal`, `non-lethal` |
| `parasitism_mode` | `parasitoid_in`, `parasitoid_of` | `idiobiont`, `koinobiont`, `solitary`, `gregarious`, `ecto`, `endo` (one Fact per value) |

### 5.4 Traits

**Rules:**
- One Fact per value. Values come from `vocab/traits.schema.json`.
- Traits: `detachable`, `plant_part`, `form`, `shape`, `color`, `texture`, `alignment`, `walls`, `cells`, `season`.
- `detachable` is single-valued; all others may have several values.
- Generation is not a Trait Fact: it belongs in `galls[].identified_by`.
- If the Source's term has no fitting value, put it in `unmapped` (rule 2.6). Never pick the nearest value just to fill a slot.

### 5.5 Range adjustments

**Rules:**
- Gallformers computes a Gall's potential range from its Hosts. **Do not list where the Gall occurs in general.** State only adjustments:
  - `include`: the Gall occurs in a place outside its Hosts' ranges;
  - `exclude`: the Source states it does not occur in a place within them.
- `place.value` is a code from `vocab/place-codes.schema.json`. Look the name up in `vocab/places.json`.

*Why:* nearly all of a Gall's range follows from its Hosts. Storing only the exceptions avoids copying the Hosts' ranges into every Gall.

### 5.6 Common names

`alias` Facts carry common names only. Scientific names, including synonyms and old combinations, belong in taxonomy batches.

### 5.7 Descriptions

**Rules:**
- A `description` Fact is the Source's description of a Gall, as a **collage of direct quotes** in reading order. The quotes in `evidence` *are* the description.
- **Never summarize or paraphrase.**
- At most one per Gall per Source.

*Why:* quotes are verifiable against the document, and the Source's words stay the Source's. Any summary Gallformers shows, it generates itself.

### 5.8 Not in batches

Never include: abundance, "undescribed" flags (derived), range-confirmed or data-complete flags, images, Gall names (Gallformers derives them), the Hosts' ranges, or anything Gallformers computes.

## 6. Evidence

**Rules:**
- **Quote evidence (document Sources):**
  - `item`: the DoclingDocument reference of the item the evidence is in (e.g. `#/texts/42`, `#/tables/3`). Required whenever the package has a `document.json`.
  - `quote`: verbatim text, long enough to be unambiguous within its item. Use a sentence or a clause; for a table row, the row's cells joined with " | ".
  - `whole_item: true` instead of `quote`, when the evidence is the item's entire text (typically a descriptive paragraph). This is only allowed with `item` and a document. Gallformers takes the text from the document, so nothing is copied.
  - **Never give character offsets.** Gallformers finds the quote in its item and stores the exact span itself.
  - `page`: the page number **as printed** in the Source, if known (for citations). This is not the PDF page index; Gallformers takes that from the item.
  - `url`: a deep link to this place in the Source, if one exists. Examples: a Biodiversity Heritage Library or HathiTrust page, or a website's species page.
  - `observations`: Observations the Source cites, if any.
- **Statement evidence (Gallformers batches only):**
  - `statement.text`: Gallformers' statement in plain words;
  - `statement.stated_on`: its date;
  - optional `observations`: e.g. iNaturalist observation IDs that support it.
- **Observations are never Sources.** They appear only as cited evidence.

*Why:* review of large batches can't be line-by-line, so quality rests on checks the system can make. Gallformers verifies every quote against its document item and samples Facts for audit.

## 7. Validation

**Layer 1: the schemas.**
- Validate each batch against `schema/taxonomy.schema.json` or `schema/gall.schema.json` (JSON Schema draft 2020-12).
- They reference `common.schema.json` and the files in `vocab/`.
- **Run it with `validate.py`** on batch files or package directories:
  - `uv run priv/import/validate.py <package-dir>`, or
  - `python3 priv/import/validate.py <package-dir>` (needs `jsonschema` ≥ 4.18).

  Each error names the exact field and lists the allowed values. Fix your batch from them and re-run until it is valid.

**Layer 2: the Gallformers dry run.** These checks need Gallformers' data or cross-references. A batch that fails them is reported, not imported.
1. Every taxon name resolves (current names plus synonyms), or is flagged unresolved, or is `new` with a status.
2. Every Gall resolves to one entry, or is flagged unresolved/ambiguous, or is `new` with at least one Fact.
3. Supplied IDs agree with the names and descriptions they accompany.
4. `host_of` subjects are plants; other organism subjects are not, except for gall-forming plants.
5. Qualifiers point at a Relationship Fact in the batch, of a type the qualifier allows (§5.3).
6. At most one `inducer_of` per Gall per batch.
7. Gallformers batches use `mode: "add"` and statement evidence only; document Sources use quote evidence only.
8. Taxonomy batches state no acts on plant taxa (except gall-forming plants).
9. Every quote is found in its `item` (after normalizing whitespace and hyphenation), and Gallformers records the resolved span (item + character offsets). `whole_item` evidence needs an item that exists. If there is no document, quotes are marked unverifiable and `whole_item` is an error.
10. A gall batch whose names depend on a pending taxonomy batch from the same Source waits for it.
11. `facts` / `acts` may be empty only for a retraction notice.

## 8. Vocabularies and versions

- `vocab/` holds every controlled list. Validate against `*.schema.json`; `places.json` adds names for mapping place names to codes.
- Vocabularies come from the Gallformers database. The draft files were extracted 2026-10-07; a generator task will replace them.
- Set `vocabulary_version` to the date of the vocab files you used.
- **Provisional:** the `generation` list (aphid host-alternation phases are still open).
- `format_version` changes only for breaking changes to the shape. Adding vocabulary values does not change it.

## 9. Examples

`examples/` has complete batches:
- `simple-paper`: Hosts, a denial, a parasitoid with a qualifier, Traits, a range exclusion, a common name, a description, and a new undescribed Gall.
- `revision`: a taxonomy batch (new species, recombination, placement, split, synonymy) plus its gall batch (new Galls and alternate generations).
- `gallformers-statement`: a curator's range exclusion and a Host verified from Observations.
- `retraction`: a retraction notice.

The Sources and quotes in the examples are fictional, and their `document.json` files are not included.
