# Gallformers import — Gallformers statements

How to write a batch of Gallformers' own statements: a curator's correction, confirmation or exclusion. Everything in `PRODUCER_GUIDE.md` under Phase 2 and Phase 3 applies to what a statement says; this guide covers what differs.

- **Source:** `{ "gallformers": true }`, with no bibliographic fields and no `document.json`.
- **`mode`:** always `add`. Each statement is its own dated entry.
- **Evidence** is a statement in place of a quote:
  - `statement.text`: the statement in plain words;
  - `statement.stated_on`: its date (YYYY-MM-DD);
  - `observations` (optional): the Observations that support it, e.g. `{ "provider": "inaturalist", "id": "123456789" }`.
- **Observations** appear only as cited evidence on a statement.
- Run `validate.py` on the batch file.

Example: `examples/gallformers-statement/gall.json` (a range exclusion and a Host verified from Observations).
