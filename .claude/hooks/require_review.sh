#!/usr/bin/env bash
# The commit gate (matter c800): a PreToolUse hook on Bash.
#
# Blocks a `git commit` until the staged tree has a passing reuse review
# (<git dir>/gallformers-review/<tree>.md with "verdict: pass"). Merges pass.
# Restaging changes the tree, so a fixed diff is reviewed again.
#
# Reads the hook's JSON on stdin; exit 2 blocks, and stderr goes to Claude.
set -uo pipefail

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // "."' <<<"$input")

commit_re='(^|[;&|(]|[[:space:]])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'
[[ "$command" =~ $commit_re ]] || exit 0

# `git -C path commit` acts on path.
if [[ "$command" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  repo="${BASH_REMATCH[1]}"
  [[ "$repo" = /* ]] || repo="$cwd/$repo"
else
  repo="$cwd"
fi

git_dir=$(git -C "$repo" rev-parse --git-dir 2>/dev/null) || exit 0
[[ "$git_dir" = /* ]] || git_dir="$repo/$git_dir"

[[ -f "$git_dir/MERGE_HEAD" ]] && exit 0

if [[ "$command" =~ [[:space:]](-a|--all|-[a-zA-Z]*a[a-zA-Z]*)([[:space:]]|$) ]]; then
  echo "Commit gate: stage files by name and commit what's staged; don't commit with -a/--all." >&2
  exit 2
fi

tree=$(git -C "$repo" write-tree)
review="$git_dir/gallformers-review/$tree.md"

if [[ -f "$review" ]] && grep -qx "verdict: pass" "$review"; then
  exit 0
fi

if [[ -f "$review" ]]; then
  echo "Commit gate: the reuse review blocked this staged change ($review). Fix what it found and restage, then review again. If you dispute the finding, ask Jeff; don't re-run the review for a different answer." >&2
else
  echo "Commit gate: this staged change hasn't had a reuse review. Run dev/guardrails/review_packet.sh, spawn the reuse-reviewer agent on the packet it prints, and commit once it records a pass." >&2
fi
exit 2
