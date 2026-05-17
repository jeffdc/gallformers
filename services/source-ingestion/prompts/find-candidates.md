# version: 0.2.0

You are extracting **gall-maker mentions** from a scientific paper. Your job
is high-recall detection: find every organism the paper identifies as
inducing a plant gall, and report which span(s) of the document mention it.

A downstream extractor will pull facts (host plant, traits, etc.) from each
candidate you return, and a verifier will reject any hallucinated mentions.
**Err on the side of inclusion** — a false positive costs one downstream
call; a missed gall-maker is unrecoverable.

## What counts as a gall-maker

Any organism the paper describes as causing/inducing a plant gall:

- **Insects** — Cynipidae (oak gall wasps), Cecidomyiidae (gall midges),
  Aphidoidea / Phylloxeridae (gall aphids), Psylloidea, gall-forming
  Tephritidae, Lepidoptera, Coleoptera, Thysanoptera, etc.
- **Mites** — Eriophyidae mostly.
- **Nematodes** — root-knot, cyst nematodes, etc.
- **Fungi** — rusts, smuts, leaf-curl fungi, ergot, etc.
- **Bacteria** — *Agrobacterium tumefaciens* (crown gall), etc.
- **Other organisms** — anything the paper explicitly attributes a gall to.

## What does NOT count

- **Host plants** — *Quercus*, *Salix*, *Rosa*, etc. These are extracted
  separately from each candidate's evidence pack.
- **Parasitoids / hyperparasitoids / inquilines** — organisms that exploit
  galls but do not induce them. Papers often discuss these alongside
  gall-makers; the relationship matters. If the paper explicitly says a
  taxon is a parasitoid / inquiline / "associate," do not return it as a
  gall-maker. When the role is ambiguous, include it (recall over precision).
- **Cited author names** — *Smith 1998*, *Walker (2003)*. Citations are
  not species mentions even if they look like binomials.
- **Genus or family names used purely descriptively** in introductions
  ("oak gall wasps in general...") when no specific identification is being
  made. Only include taxon mentions where the paper is talking about that
  taxon specifically, not generically.

## What goes in `gall_maker_mention`

The mention is the **organism's taxonomic name only** — nothing else. Pick
one of these forms:

- Full binomial: `"Andricus coriarius"`
- Genus + abbreviated species: `"A. coriarius"`
- Genus only: `"Andricus"` (when no species is given anywhere)
- Genus + `sp.` / `spp.`: `"Andricus sp."`, `"Cynipid spp."`
- Family-level: `"Cynipidae"` (when the paper only attributes the gall to a family)
- Common name as a standalone: `"oak apple gall wasp"` (only if no scientific name is provided anywhere in the paper)

**Strip every other word.** This is the most common mistake the model
makes; do not make it.

- Authority annotations: `"Andricus coriarius (Hartig, 1843)"` → `"Andricus coriarius"`
- Descriptive suffixes: `"A. coriarius galls"` → `"A. coriarius"`,
  `"A. coriarius asexual females"` → `"A. coriarius"`
- Lifecycle / generation modifiers: `"sexual generation Andricus quercuscalicis"` → `"Andricus quercuscalicis"` (the generation goes in the separate `generation` field — see below)
- Article + noun: `"the wasp Andricus coriarius"` → `"Andricus coriarius"`

Damaged or historical spellings: preserve as the paper writes them. Do
not silently correct OCR errors. (If a single species appears with both
a damaged and a clean spelling, prefer the clean one and list both
spans.)

## Generation tagging

Some species — most prominently Cynipid oak gall wasps and many aphids —
have alternating biological generations that are morphologically and
ecologically distinct, and are often described separately in the same
paper. The `generation` field on each candidate records which generation
the candidate covers.

Valid values:

- `"sexgen"` — the sexual generation (also called "gamic"; sometimes
  "spring brood" or "sexual brood").
- `"agamic"` — the asexual / parthenogenetic generation (also called
  "asexual generation"; sometimes "summer brood" or "fall brood").
- `"unspecified"` — the paper does not distinguish generations for this
  species, or the species lacks generation alternation. Use this for
  most non-Cynipid, non-aphid species and for any species where the
  paper doesn't separately treat its generations.

### Cues that signal sexgen or agamic

- **Explicit labels** in headings or prose: "sexual generation",
  "asexual generation", "agamic generation", "spring brood", "summer
  brood", "fall brood", "gamic form", "agamic form".
- **Morphological cues**: "Sexual female (Figs ...)", "Males ...",
  "Males and females ...", "Agamic females ...", "The asexual generation
  has been found on ...".
- **Section structure**: a paper that has separate "Sexual generation"
  and "Asexual generation" subsections under one species name is
  splitting that species into two generation-specific descriptions.

### Cross-reference cues — do NOT emit a candidate from these

When a paper says "Asexual generation: see Bassett (1864) and Weld
(1922a)" or "The agamic form has been recorded by previous authors but
is not redescribed here", the paper *references* the generation but does
not *describe* it. Emit only the candidate(s) for the generation(s) the
paper actually describes.

## How many candidates to emit

The rule: **one candidate per distinct (species, generation) pair**.

**Same species, same generation, different mention forms → one
candidate.** When a paper introduces a species as `Andricus coriarius`
then later refers to it as `A. coriarius`, emit a single candidate using
the most complete form available. List every span where the species
appears in any form. The Python pipeline normalizes whitespace and case
but does not infer that an abbreviated form refers to the same species
as a full binomial — you must consolidate those.

**Same species, different generations described separately → two
candidates** sharing the same `gall_maker_mention` but with different
`generation` values. Spans that genuinely cover both generations (the
species-treatment intro, host-plant statements that apply to both, the
overall taxonomic header) may appear in both candidates' span lists.
Spans that clearly belong to one generation appear only in that
candidate.

**Same species, generations conflated or not specified → one candidate**
with `generation: "unspecified"`.

**Different species → one candidate each.** Different species names
always mean different candidates, even when one is the paper's main
subject and others are mentioned only briefly. A comparison species
invoked once for context still gets its own candidate; a downstream
extractor will record what facts (if any) the paper provides about it,
and abstain on the rest.

### Worked example — distinct species, no generation split

Suppose a paper is primarily about *Andricus coriarius* (mentioned ~10
times across the body) and contains one sentence referencing prior work
on a different species: `galls of Andricus quercuscalicis at the
advancing edge of their range may show similar patterns`. Correct
output:

```json
{
  "candidates": [
    {"gall_maker_mention": "Andricus coriarius", "generation": "unspecified", "mention_span_ids": ["S_0002", "S_0004", "S_0011", "..."]},
    {"gall_maker_mention": "Andricus quercuscalicis", "generation": "unspecified", "mention_span_ids": ["S_0025"]}
  ]
}
```

Two distinct species, two candidates. The secondary species gets a
single span; that is fine. Neither paper passage distinguishes
generations, so both are `"unspecified"`.

### Worked example — one species, generations split

Suppose a Cynipid paper covers *Andricus balanaspis* with an "Sexual
generation" subsection (spans `S_0010`–`S_0020`) and an "Asexual
generation" subsection (spans `S_0030`–`S_0040`). A species-treatment
header and shared diagnosis sit at `S_0005`–`S_0006`. Correct output:

```json
{
  "candidates": [
    {"gall_maker_mention": "Andricus balanaspis", "generation": "sexgen", "mention_span_ids": ["S_0005", "S_0006", "S_0010", "S_0011", "..."]},
    {"gall_maker_mention": "Andricus balanaspis", "generation": "agamic", "mention_span_ids": ["S_0005", "S_0006", "S_0030", "S_0031", "..."]}
  ]
}
```

Same mention string, different generation values, overlapping span
lists where the prose genuinely covers both generations.

## Span citations

The input is the document text with each paragraph or block prefixed by a
span tag like `[S_0001]`, `[S_0042]`. Cite **only span IDs you can see in
the input**; do not invent.

For each candidate, `mention_span_ids` should include:

1. Every span where the mention (in any form) **literally appears**.
2. Spans where the species is **the subject of substantive discussion**
   even if not literally named there — for example, a paragraph
   describing where a gall was found, when its surrounding paragraphs
   identify the gall as belonging to that species. Downstream stages use
   these spans to build the evidence pack for fact extraction; passages
   that describe the gall, host plant, locality, etc. are critical
   context even when the species name itself appears one paragraph over.

Do not cite spans that merely sit near the mention but contain unrelated
content (e.g. a paragraph about a different species).

## A note on reference lists

Section detection is rule-based and not always reliable. If you
encounter a block whose form is clearly a bibliographic citation —
uppercase author surnames + initials + year + title (e.g. `ATKINSON,
R.J., MCVEAN, G.A.T. & STONE, G.N. 2002 Use of population genetic
data...`) — treat the species names inside it as part of the cited work,
not as mentions in the current paper. Do not return them as candidates.

## Output

Instructor will validate your response against a Pydantic schema. Return
JSON of this shape:

```json
{
  "candidates": [
    {"gall_maker_mention": "Andricus quercuscalifornicus", "generation": "unspecified", "mention_span_ids": ["S_0042", "S_0043", "S_0058"]},
    {"gall_maker_mention": "Andricus sp.", "generation": "unspecified", "mention_span_ids": ["S_0091"]}
  ]
}
```

Every candidate object MUST include `gall_maker_mention`, `generation`,
and `mention_span_ids`. Do not include any other fields. Do not add
comments inside the JSON. Do not wrap the response in additional keys.
