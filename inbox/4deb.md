---
kind: question
text: 'How should taxogall get a GitHub CI run (dialyzer included) before c800 closes: a draft PR from taxogall into main, or a workflow trigger for taxogall?'
plan: taxogall
source: 'intake 2026-11-09: .github/workflows/ci.yml runs only on push to main and PRs into main; replaces entry 29fd'
by: /Users/jeff/dev/gallformers
created: "2026-11-12T02:23:22Z"
---

Background (matter c800, 2026-11-09). Dialyzer had been out of GitHub CI since January by accident. 55aa083c added it in a second workflow, v2-ci.yml; d33fe6f0 deleted that file as legacy; the surviving ci.yml never had a dialyzer step. So 13 dialyzer errors from Nov 6–8 landed unseen; c800 fixed them, and `make ci` is green.

c800 then added a Dialyzer job to ci.yml (331c13c6, on taxogall only):
- dev environment, `mix dialyzer --format github --format dialyxir`;
- its own cache keyed on flake.lock and mix.lock;
- runs beside the Phoenix and Assets jobs;
- dev/** and .credo.exs added to the path triggers.

It passed an `act -n` dry run and the same command locally. Still unverified until it runs on GitHub: the nix dev shell in the dev environment on the runner, the cache, and the first PLT build's time (minutes; about 10 s once cached). Jeff's audit says c800 should close after one green dialyzer run on GitHub. c800 also notes the README's "make ci = same as GitHub Actions" is wrong.

How CI triggers today (as of a0434bcf):
- ci.yml runs on push to main and on pull requests into main, both filtered by paths.
- Both main's and taxogall's ci.yml also have `workflow_dispatch`.
- origin/taxogall doesn't have the Dialyzer job yet: local taxogall is 41 commits ahead. So any option first needs taxogall pushed (Jeff's step; the push carries his commits).

Options:
(a) A draft PR from taxogall into main.
- CI runs on the PR, and on every later push to taxogall.
- The cost: a long-lived open PR into main that must never be merged by accident; it is the eventual release PR anyway.
(b) A manual dispatch: `gh workflow run ci.yml --ref taxogall`.
- GitHub runs a workflow_dispatch workflow from the chosen ref's file, but the workflow must also exist on the default branch, which ci.yml does. Check GitHub's docs before relying on this.
- The cost: no ongoing CI on taxogall; a run only when asked.
(c) Add taxogall to ci.yml's push branches.
- Every push to taxogall runs CI.
- The cost: a workflow change that has to come out (or stay harmlessly) when taxogall merges into main.
