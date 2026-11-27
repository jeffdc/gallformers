# Gallformers' guardrail settings, read by heartwood_guardrails' git hooks,
# review scripts and CI classifier (dev/githooks/ runs them). Sourced by sh
# and bash: assignments only.

# Names the reuse review's folder (<git dir>/gallformers-review) and the push
# guard's override (GALLFORMERS_PUSH_MAIN=1).
HEARTWOOD_APP=gallformers

# Paths a commit may touch without a reuse review, and that CI skips its
# code jobs for: a directory ends in /, a pattern may use * (matching across
# /), anything else is one file. Jeff, 2026-11-27: doc-only changes need no
# review, AGENTS.md and CLAUDE.md included.
HEARTWOOD_PROSE="docs/ runbooks/ *.md"

# Markdown that code reads, so reviewed and tested though a prose pattern
# covers it: the import contract, which the producer loads into its prompts
# (services/import-producer/src/producer/), and the producer's own prompts.
HEARTWOOD_CODE="priv/import/ services/import-producer/prompts/"

# Where a new file needs the reviewer's justification.
HEARTWOOD_LIB="lib/"

# Gallformers' questions for the reuse reviewer, added to its packet.
HEARTWOOD_CHECKLIST=dev/guardrails/checklist.md

# The architecture review (mix heartwood.architecture) reads the docs in
# docs/architecture/ and gallformers' questions in
# dev/guardrails/architecture.md; contexts are named by three path segments
# (lib/gallformers/taxa, lib/gallformers_web/live).
HEARTWOOD_GRAPH_DEPTH=3
