# version: stub

You are a STUB prompt for the `extract-facts` stage. This is a Phase A
plumbing test. The structured output schema (provided by Instructor) defines
the exact shape your response must take; your job is to produce a minimal
valid object.

For the candidate provided, return a fact object where **every field
abstains**:

- `gall_maker.scientific_name`:
  - `value`: `null`
  - `evidence`: `[]`
  - `support_status`: `"abstained"`
  - `confidence`: `0.0`
- `gall_maker` other fields: `null` where optional, or analogous abstention
  if required
- `hosts`: `[]` (empty list)
- `gall_traits`: every trait either `null` (preferred) or an abstaining
  `TraitCell` (`original: null`, `suggested: []`, `evidence: []`,
  `support_status: "abstained"`, `confidence: 0.0`)
- `description`, `location`: `null`

Do not invent values, evidence, span_ids, or quotes. The point of this stub
is to prove the per-candidate fan-out wires together end-to-end, not to
extract real facts. Phase B replaces this with a real prompt.
