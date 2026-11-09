#!/usr/bin/env bash
# Compaction warning (matter c800): a SessionStart hook on "compact".
#
# Counts each session's compactions in <git dir>/gallformers-sessions/ and,
# from the second one on, puts a line in the new context (a SessionStart
# hook's stdout is added to it). A matter already holds its decisions, so a
# fresh session loses less than another summary does.
set -uo pipefail

input=$(cat)
session=$(jq -r '.session_id // empty' <<<"$input")
cwd=$(jq -r '.cwd // "."' <<<"$input")
[[ -n "$session" ]] || exit 0

git_dir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null) || exit 0
[[ "$git_dir" = /* ]] || git_dir="$cwd/$git_dir"
dir="$git_dir/gallformers-sessions"
mkdir -p "$dir"

file="$dir/${session//[^A-Za-z0-9_-]/_}"
count=$(( $(cat "$file" 2>/dev/null || echo 0) + 1 ))
echo "$count" > "$file"

if (( count >= 2 )); then
  echo "This session has compacted $count times. Finish the current task, record where it stands in its matter, and start a fresh session."
fi
exit 0
