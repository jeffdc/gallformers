# Backlog

Known bugs and ideas that belong to no plan. When one is picked up it moves into a plan doc, or is fixed directly if it's small. Bugs and ideas that belong to a plan are in that plan's docs.

Mull's unphased items, captured bugs and ideas are still to be brought over (step 6 of the [cleanup](cleanup/README.md)).

## Bugs

## Ideas

- **Move onto heartwood, the code shared with Oak Compendium** (Jeff, 2026-11-26; decided in oaks' `docs/facts-expansion/architecture-groundwork.md`, section 3, and `docs/architecture/decisions.md`). A third repo, `heartwood`, holds two Mix packages that gallformers and oaks both depend on as git dependencies pinned by tag (with `sparse:`): `heartwood_guardrails` (`only: [:dev, :test], runtime: false`: the ratchet framework from `GallformersWeb.DesignSystem.Conformance`, `Guardrails.DuplicateCode`, `Guardrails.Retirements`, the pre-commit and pre-push hooks, the reuse review's packet and record scripts, the superset `check-toolchain`, and their tests) and `heartwood_ui` (the photo viewer, then the fragment-and-reader). Pick it up once oaks has tagged both: the guardrails first, then the photo viewer (oaks' fork, with rail paging, backdrop close and a configurable event). For gallformers:
  - Depend on `heartwood_guardrails`. Keep gallformers' own rules, globs and hints in its conformance module, its baselines in `test/support/`, the `duplicates` config in `.credo.exs`, `test/support/retirements.exs`, the commit gate's prose paths and the gallformers checklist in `dev/guardrails/reviewer.md`; the framework, scripts and their tests come from heartwood. The hooks in `dev/githooks/` become thin scripts that run heartwood's and fail closed when `deps/` is missing. CI runs `check-toolchain` after `mix deps.get`. Deletes: the framework half of `conformance.ex`, `test/support/guardrails/`, `Mix.Tasks.Gallformers.Guardrails.Baseline`, `scripts/check-toolchain`, the hook and review scripts' bodies, and the guardrail tests that move to heartwood.
  - Depend on `heartwood_ui` and replace `photo_viewer/1` (`domain_components.ex`) and `assets/js/hooks/photo_viewer.js` with heartwood's, imported through `NODE_PATH`. A `.gf-` adapter block maps its `--pv-*` properties to the `--gf-*` tokens (dark mode and density follow), and a gallformers wrapper keeps the admin edit links. Deletes: the old component, hook, its test and its CSS.
  - Heartwood changes reach gallformers as tags with a `CHANGELOG.md` entry whose "Upgrade:" steps say what to do, and as entries in this backlog. `mix heartwood.status` (in `done-checks`, for information only) shows the pinned tag against the latest. Fixes go to heartwood, never to `deps/`.
