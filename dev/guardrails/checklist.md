Look for existing code in `GallformersWeb.Choices`, the components in `lib/gallformers_web/components/` (the catalog in `docs/design-system/components.md` says which component covers each need), the public functions of the contexts the change calls, and heartwood (`deps/heartwood_guardrails/guardrails`).

1. **The component library.** Does a page build its own version of something the catalog covers, or restyle a catalog component from page CSS? `GallformersWeb.DesignSystem.Conformance` catches some of this; the rest is yours. A finding blocks.
2. **Heartwood.** Does the change copy or edit code that heartwood holds (the ratchets, retirements, hooks, review scripts, `check-toolchain`) instead of using the dependency? A finding blocks: the fix goes into heartwood.
3. **AGENTS.md** (CLAUDE.md is the same file) holds rules, not status or plans. Status or plans added to it is a finding that blocks.
