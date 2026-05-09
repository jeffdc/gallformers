---
status: done
created: 2026-04-25
updated: 2026-04-25
epic: source-ingestion
---

# Refactor source-ingestion text processing into a heuristic rule system

## Scope
Refactor source-ingestion text preprocessing so it uses a maintainable heuristic rule system instead of accumulating ad hoc hard-coded rules in one module.

## Problem
`Gallformers.IngestionPipeline.TextProcessing` currently mixes:
- the preprocessing pipeline
- the mechanism for applying heuristics
- the heuristic definitions themselves

That structure does not scale. As new corpus quirks are discovered, the current design encourages piling more rules into a single module.

## Explicit non-goal / constraint
Do not put source-specific or publication-specific hard-coded rules into the core pipeline.

In particular, hard-coded rules like matching a specific publication title such as `Philippine Journal of Science` do not belong in the general preprocessing path. Ever.

## Required architectural direction
1. Make `TextProcessing` a coordinator rather than the place where every heuristic lives.
2. Introduce a small internal rule/heuristic framework that separates rule execution from rule definitions.
3. Represent heuristics as discrete named rules or rule sets with clear intent and focused tests.
4. Keep general heuristics general.
5. If corpus-specific heuristics are ever allowed, isolate and gate them explicitly rather than mixing them into the default path.

## Refactor targets
- Page header/footer stripping
- Plate-page handling
- BHL boilerplate handling
- Line rejoining / continuation heuristics
- Cheap bibliographic sniffing where appropriate

## Open questions
- What is the right internal shape for rule execution: behaviour modules, plain data-driven rule structs, ordered function lists, or a hybrid?
- Which existing heuristics are truly general and should stay in the default pipeline?
- Should corpus-specific heuristics be forbidden entirely, or supported only through an explicit opt-in rule set?
- How should rule ordering and conflict handling be expressed and tested?

## Notes
- This is a maintainability and extensibility refactor, not a request for more comments on the current design.
- The current issue is not just readability. It is that the architecture makes future heuristic growth messy by default.
