Gallformers' rules are in `docs/architecture/rules.md`, each with its source and its check; the [2026-11-26 baseline review](../../docs/architecture/reviews.md) recorded the violations and the gaps in the checks. These questions cover the rules that need judgement, or whose checks see only part of them. For each, report violations beyond its baseline, and say whether a check could now hold the rule.

1. **Contexts and their tables (S1, S4).** Has any module started querying another context's schemas, associations or string table names, beyond S1's accepted exceptions? Is each accepted exception still needed (`facts` and `attributions`, to become Facts exports)? Does the gall system still reach taxonomy other than through its API?
2. **One write path and audit (S5, S6).** Does any new write path bypass the code the editing screen and the import share? Does any write to a tracked table lack an actor? Has a new table been left out of the audit layer?
3. **The old tables (S10).** Does anything read the old `species`-centric tables outside the catalog migration, beyond the recorded exceptions?
4. **The web layer (W1, W3, W4).** Is orchestration growing in LiveViews (the web files over 1,000 lines)? Are there near-copies across LiveViews that the duplicate-code ratchet misses?
5. **Names and SQL (D1, D2).** Is a name parsed outside `Gallformers.TaxonName`? Is there raw SQL or a schemaless query beyond the baseline, or input interpolated into SQL?
6. **Durable work (D3).** Is there a new unsupervised `Task.start` or `Process.send_after` for work that must survive a restart?
7. **Security (X1–X7).** A new `String.to_atom` on input, `raw/1`, inline script or `on*=` handler? A new write screen without an `on_mount` role guard, or outside read-only mode?
8. **The component library (U1, U3).** Does a page build its own version of a catalog component in a way the conformance ratchet doesn't catch? Is a scientific name rendered outside `<.taxon_name>` and `<.gall_name>`?
9. **Tests (T3, T5, T6).** Hard-coded seed IDs, `Process.sleep`, flash-only assertions?
10. **Configuration (O5).** Is an environment variable read outside `config/runtime.exs`?
11. **Shared code.** Is there code gallformers has that Oak Compendium has too and that should move to heartwood? Is any guardrail code copied rather than used from the dependency?
12. **The gaps.** Which of the baseline review's gaps in the checks are closed, and which could close now?
