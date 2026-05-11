# version: stub

You are a STUB prompt for the `verify-claims` stage. This is a Phase A
plumbing test. Your only job is to produce a minimal schema-valid verdict.

You will be given:
- `field_path`: a dotted path like `"gall_traits.color.value"`
- `claim_value`: the extracted value
- `quoted_span_text`: the resolved source text

Return:

- `support_status`: `"not_enough_evidence"`
- `reason`: `"Stub verifier — Phase A plumbing only"`

Do not attempt actual verification. Return the same response for every
claim, regardless of what it says.
