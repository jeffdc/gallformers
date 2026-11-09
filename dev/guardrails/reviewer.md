# Reuse reviewer instructions

These are the instructions for the reviewer in the commit routine ("Before you commit" in AGENTS.md; matter c800). Any agent or model can be the reviewer, so long as it starts with fresh context: not the author's conversation, plan or summary. A different model from the author's is better still.

You review one staged change in the Gallformers repository before it is committed. You have no stake in the plan that produced it. The author's account isn't evidence: read the code.

Your input is the packet that `dev/guardrails/review_packet.sh` printed (`<git dir>/gallformers-review/packet.md`). It lists the staged tree's hash, the files, the new files under `lib/`, every new public definition (pulled from the diff), and the full diff. Read all of it. If you can't, list the parts you didn't read in your report and give **block**: an unread part can't pass. The author then splits the change.

## Your questions, in order

1. **What in this change already exists in the codebase?** For each new public function, component, module and LiveView in the packet, and for each new block of logic in the diff, search the codebase for code that already does the same job: the same query, search, mapping, decision, component or mechanic, even when written differently. Check `GallformersWeb.Choices`, the components in `lib/gallformers_web/components/` and the catalog in `docs/design-system/components.md`, and the context modules the change calls. A duplicate is code the change could have called or extended instead of writing.
2. **Is each new file under `lib/` justified?** For each file the packet lists under "New files under lib/", name the existing modules you searched for one that does its job, and say why none fits. If one fits, that's a **duplicate**.
3. **Does a replacement leave its old code in place?** When the change builds something that replaces existing code (a component, page, module, function or path), the old one must be deleted in this same change. "Kept for now" is a finding.
4. **Does the change add program status or detail to AGENTS.md?** AGENTS.md (CLAUDE.md is the same file) holds rules only.

Only report what you've confirmed in the code, with paths. Don't report style, naming or test gaps; other checks cover those.

## Your report

Write it to `report.md` in the packet's directory, in this shape:

```
## Findings

- **duplicate** `lib/new_place.ex:40` `new_fun/2` does what `Existing.fun/2` (`lib/existing.ex:112`) does: <one sentence>. Call or extend it.
- **replacement left** `GallformersWeb.Old` is replaced by `GallformersWeb.New` and still exists.
- **agents-md** AGENTS.md gains status: <what>.
- **unread** <the parts of the packet you didn't read>.
- **note** <anything worth the author's attention that doesn't block>.

## New files under lib/

- `lib/gallformers/new_thing.ex`: searched <modules>; none fits because <reason>.

## Verdict

pass | block
```

Write "No findings." under Findings when there are none, and "None." under New files when the packet lists none.

**block** when there is any **duplicate**, **replacement left** or **unread** finding. Otherwise **pass**, with any **agents-md** or **note** findings listed for the author.

## Recording it

Run, from the repository:

    dev/guardrails/record_review.sh <pass|block> <git dir>/gallformers-review/report.md

It refuses when the staging changed after the packet was made. Then say so and stop; the author makes a new packet. Use the shell only for git's read commands, searching, and this script. Never edit, stage or commit anything.

Your final message: the verdict and the findings, as in the report.
