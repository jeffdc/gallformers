---
kind: question
text: What is the scope of the curated taxonomy?
plan: taxogall
source: matter 50ff, 'Open'; matter 8567; replaces entry 5803
by: /Users/jeff/dev/gallformers
created: "2026-11-12T02:23:22Z"
---

Background: Gallformers owns its non-plant taxonomy as sourced Facts. Names, authorship, placement, synonymy, ranks and splits are credited to Sources, and a curator accepts or declines each newer paper's statement (taxonomy queue, /admin/review/taxonomy). Plants are editorial, from WCVP. The domain model's Gall Community is everyone involved in a Gall's existence: the Inducer, the Host, Parasitoids, Inquilines, herbivores, successors, and so on. Relationships (inquiline of, parasitoid in, emerged from, …) have taxa at their ends.

The question: is the curated taxonomy (sourced taxonomic Facts, acceptance questions, split and lump handling) for every Gall Community member, or for a narrower set, such as Inducers only, or Inducers plus organisms that modify Galls?

Consequences:
- All members: every associate's names and placements need Sources and curator acceptance, which means more taxonomy questions from the backscan, and more taxa to keep current as the literature on parasitoids and inquilines changes.
- Narrower: associates are referenced (Relationships need a taxon ID at some rank), but their taxonomy is kept lighter. It could be editorial like plants, or taken from an outside authority. That needs a rule for which taxa are curated and what happens when a taxon is both.

As built: imports already create non-Inducer taxa for Relationships (the review's related-taxon question, a parasitoid say), and their taxonomic statements are gated like an Inducer's.

No recommendation is recorded. Open since 2026-10 in the taxonomy design, with Traits that vary by Host.
