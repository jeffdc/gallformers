# Gallformers import: decisions

The decisions behind the import contract in `priv/import/`, each with its reason, for the people who own the contract. The contract itself (`PRODUCER_GUIDE.md`, the schemas, the vocabularies) holds the rules a producer follows; this document holds why, and what Gallformers does on its side. The evidence for most of these decisions is the pipeline trial (matter `8546`).

## The package and its phases

- **Six phases:** 1 Document, 2 Taxonomy batch, 3 Gall batch, 4 Validate, 5 Review, 6 Respond. Each is a smaller, checkable task.
- **Phase 4 (`validate.py`) runs before phase 5** so the paid review never spends effort on batches with mechanical errors.
- **`document.json` is required.** Every quote names the document item it comes from, so every quote can be verified mechanically. A Source that can't be converted doesn't produce a package.
- **Phase 5 reviews with two models** (Opus and Sonnet) and merges their findings: on planted errors each caught nearly all, but on real batches they caught different problems.
- **Phase 5 reports; phase 6 decides.** The producer answers each finding once: agree → it fixes the statement; disagree → the statement stands and the finding goes to a human at intake. Fix-and-re-review loops made two models trade fixes on the same statements without converging; phase 6 settles every finding in one pass and sends real disagreements to the person who decides them anyway.
- **Agreed fixes are not reviewed again.** Accepted risk; add a short review of changed statements if human checks show agreed fixes going wrong.
- **`review.json` is delivered** with the package: it carries the disputes to intake.
- **Ready = `validate.py --review` passes.**
- **An empty taxonomy batch** tells "phase 2 ran and found no acts" apart from "never ran"; with `replace` it also clears acts an earlier run wrongly attributed to the Source.
- **Gallformers approves the taxonomy batch before the gall batch.** A gall batch whose names depend on a pending taxonomy batch waits for it.
- **Operator inputs:** a website's access date and URL come from whoever fetches the page; the producer can't know them.

## Rules for every batch

- **Recency and stances decide between Sources:** newest authorship date wins, plus explicit stances. So the producer never guesses IDs, invents novelty, or infers denials from silence: those errors would pass validation unnoticed.
- **Gallformers resolves names and Galls itself;** a wrong ID is worse than none. Optional ID fields exist for producers that know them (curator forms).
- **`as_written` on every controlled value** makes each mapping reviewable and shows where the vocabulary should grow.
- **Hedges stay out of Facts** (rule 7): uncertainty belongs to the Source's wording, not to a Relationship. "Is said to" and a hedged correction are hedges; a statement made outright stays a statement even when the Source adds that later work may revise it.
- **Denials only correct published statements** (rule 6): a denial exists to withdraw something Gallformers could otherwise hold. Contrasts in descriptions, absences and rejected unpublished reports carry nothing to withdraw.
- **For a multi-valued Trait, only an explicit denial withdraws a value.**
- **Facts come from the Source's treatment of its subject.** Galls shown only in an introduction or caption outside the subject produce nothing. Deliberate contrasts within the subject still count; a broader "no passing remarks" rule was rejected as more disruptive than the problem (one case in 177 checked statements).
- **Entries the Source marks unverified** are hedged by its own heading.
- **Editorial and derived fields stay out of batches** (abundance, "undescribed", range-confirmed, data-complete, images, Gall names, Hosts' ranges): Gallformers owns or computes them.
- **Licenses:** no stated license means All Rights Reserved, unless the work is public domain by age or origin.
- **Dates:** the date the document prints; a curator may correct it.
- **Names:** `name_as_written` is verbatim (so it matches the quotes); `name_reading` repairs damaged letters only; Gallformers normalises case. A common name becomes a scientific name only where the Source itself pairs them.

## Taxonomy

- **Five act kinds** (name, placement, synonymy, split, common name) cover what papers do; each is one checkable statement.
- **`status_as_written`** keeps what the kinds can't say (new vs repeated synonymy, misspellings, nomina dubia) without a vocabulary to maintain.
- **State only acts the Source makes or adopts.** Using a name, organizing headings and classification mentioned in passing are context. Placements and reported acts were where runs disagreed most; this line made them consistent.
- **Misapplied names** carry `sensu`, so a correction ("C. confluens O. S. non Harris") doesn't sink the real species into a synonym.
- **Provisional names and formal descriptions count as new,** with or without "n. sp.".
- **Assigning old records after a split is curator work:** a Source rarely supports it.
- **Plant taxa come from POWO;** acts on them are out of scope except for gall-forming plants.
- **Taxa above family are wanted** (parasitoids are often known only to order); lumps and splits above family are not supported.

## Galls

- **Galls are catalog entries** (two generations are two entries), identified by Inducer, generation, Host, and plant part when two Galls of one Inducer share a Host.
- **Species-level statements** attach to a Gall only when the Source ties them to a generation or the species has one Gall: copying a Fact to both generations would claim something about a generation the Source didn't describe. Statements about a group the Source then separates attach to each Gall.
- **Hosts:** the species the Source lists (a genus Host only when it names none, since a genus widens the computed range). Galls found under a plant and an aphid's secondary hosts are not Hosts.
- **Range** follows from the Hosts' native and introduced ranges, so a batch states only exceptions (include, exclude, only). Gallformers computes the rest.
- **Descriptions are direct quotes only:** verifiable, and the Source's words stay its own. Any summary is Gallformers' own.
- **Hyperparasitism** is derived by Gallformers from chains of `parasitoid_of`.

## Evidence

- **Quality rests on checks the system can make,** because large batches can't be reviewed line by line: every quote is verified against its item; statements are sampled for human checks.
- **No character offsets from producers:** an LLM can't produce them reliably. Gallformers locates each quote and stores the span.
- **`page` is the printed page;** the PDF page comes from the item's provenance.
- **`cites`** keeps the origin of repeated claims visible; a cited claim counts at the citing Source's date.

## Vocabularies

- **A value means its definition;** the term is shorthand. `traits.json` holds the definitions (from the Gallformers database) and the mappings for common Source terms.
- **Mappings decided:** swelling → one of tapered swelling, abrupt swelling, stem club (or unmapped when nothing distinguishes them); inflorescence, raceme, catkin, ament → flower; woody, hard → stiff; perpendicular → erect; oval, ovate, ovoid, ellipsoid → globular; smooth, glossy, polished → hairless; rough → mealy; fleshy → succulent; pithy → spongy; a single central cell → monothalamous; a leaf Gall with no side, vein or midrib → upper leaf and lower leaf.
- **No new values** for oval, cylindrical, swellings, integral leaf thickenings (leaf blister covers them), smooth, rough or pithy; rare terms stay unmapped until counts show what recurs.
- **Oak apple** has an outer shell, very thin or somewhat thicker but never filling the gall.
- **Colour** is what you see on the Gall, covering included; several colours allowed.
- **Season and detachable** are open (below).
- **Versions:** `format_version` changes only for breaking changes to the shape. The vocabulary files share one `vocabulary_version`. A generator from the database will replace the hand extraction.
- **`non-gall`** is out of scope for import.

## What Gallformers does on import

Built in Gallformers, not by producers. A batch that fails is reported, not imported.

1. **The taxonomy batch is applied first,** and gall names resolve against the taxonomy with it applied: resolving against today's taxonomy alone would merge taxa the Source keeps apart.
2. **Every taxon name resolves** (current names, synonyms, `name_reading`; case, "var.", subgenus and hybrid sign normalised; abbreviations expanded from genera the document names, including genera printed in capitals; 19th-century "C. q. spongifica" names tried as the fused epithet *quercusspongifica*), or is flagged. **No fuzzy matching:** it joined different species.
3. **Every Gall resolves to one entry,** or goes to the admin queue. Ambiguous matches (e.g. a generation the Source never names) go with a proposed match and its reason. Undescribed Galls are matched to Gallformers' undescribed entries by genus, Host, and the descriptive words of the entry's name; one candidate is proposed for the admin to confirm, several are offered to pick from. Nothing ambiguous is applied automatically.
4. **Disputed findings** from phase 6 appear in the intake view with the statement, its quote, the reviewer's reason and the producer's reason.
5. **Supplied IDs** must agree with the names and descriptions they accompany.
6. **Structural checks:** `host_of` subjects are plants; no acts on plant taxa (except gall-formers); Gallformers statement batches use `add` and statement evidence; `include` inside the Hosts' ranges is reported as redundant.
7. **Each quote's span** is recorded.

## Open (with Adam)

- **Season:** what it means (when the gall is present on its host, when it forms, or both). Proposal in matter `294c`.
- **Detachable:** definitions of `both` and `unknown`; single- or multi-valued; galls that drop after emergence or with their organ.
- **Recorded range:** a way to state places a gall has been recorded (field guides' "Range" paragraphs), which today are dropped.
- **Aphid generations:** two agamic galls per species (stem mother, apterae); with the host-alternation work (`b5bd`).
- **Historical plant names:** where synonyms come from (proposal: POWO, then the admin queue) (`d585`).
- **Gallformers ID Notes:** look-alikes as a concept, remarks, tentative records (`20e5`).
