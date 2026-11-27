# Gallformers' guardrail settings, read by heartwood_guardrails' git hooks,
# review scripts and CI classifier (dev/githooks/ runs them). Sourced by sh
# and bash: assignments only.

# Names the reuse review's folder (<git dir>/gallformers-review) and the push
# guard's override (GALLFORMERS_PUSH_MAIN=1).
HEARTWOOD_APP=gallformers

# Paths a commit may touch without a reuse review: a directory ends in /,
# anything else is one file. Jeff, 2026-11-27: doc-only changes need no
# review. AGENTS.md and CLAUDE.md are always reviewed (heartwood's hook).
# Each file is named rather than *.md: some Markdown is code (priv/import/,
# the producer's prompts), and the gate has no exception list.
HEARTWOOD_PROSE="docs/ runbooks/ README.md CODING_STANDARDS.md DESIGN.md PRODUCT.md infra/README.md prompts/"

# Prose to CI only: a pull request that changes nothing but these and the
# paths above skips the jobs that test code (heartwood's actions/changes, in
# ci.yml and security.yml). *.md is every Markdown file (* matches across /).
HEARTWOOD_CI_PROSE="*.md"

# Markdown that code reads, so code to CI: the import contract, which the
# producer loads into its prompts (services/import-producer/src/producer/),
# and the producer's own prompts.
HEARTWOOD_CI_CODE="priv/import/ services/import-producer/prompts/"

# Where a new file needs the reviewer's justification.
HEARTWOOD_LIB="lib/"

# Gallformers' questions for the reuse reviewer, added to its packet.
HEARTWOOD_CHECKLIST=dev/guardrails/checklist.md

# The architecture review (mix heartwood.architecture) reads the docs in
# docs/architecture/ and gallformers' questions in
# dev/guardrails/architecture.md; contexts are named by three path segments
# (lib/gallformers/taxa, lib/gallformers_web/live).
HEARTWOOD_GRAPH_DEPTH=3
