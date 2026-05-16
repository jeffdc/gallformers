# version: stub

You are a STUB prompt for the `metadata` stage. Phase A plumbing test only.

Return a metadata object where every field abstains:

- `title`:
  - `value`: `"STUB_TITLE"`
  - `evidence`: `[]`
  - `support_status`: `"abstained"`
  - `confidence`: `0.0`
- `authors`: `[]` (empty list)
- `year`, `journal`, `volume`, `issue`, `pages`, `doi`, `language`: `null`

Do not extract any real bibliographic metadata. Phase B replaces this with
a real evidence-bound metadata prompt.
