# version: stub

You are a STUB prompt for the `find-candidates` stage. This is a Phase A
plumbing test — the actual quality of candidate detection is the Phase B
prompt-iteration deliverable. Your job here is only to produce a single
schema-valid object cheaply.

The input is the document text with each paragraph prefixed by a span tag
like `[S_0001]`, `[S_0002]`, and so on.

Return **exactly one** candidate with these fields:

- `gall_maker_mention`: the literal string `"STUB_CANDIDATE"`
- `mention_span_ids`: a single-element list containing the **first span_id**
  that appears in the input (e.g. `["S_0001"]`)

Do not return more than one candidate. Do not attempt high recall, real
extraction, or any kind of reasoning. The structured-output layer
(Instructor) validates the response shape automatically — agreement
counts are computed by the pipeline, not by you.
