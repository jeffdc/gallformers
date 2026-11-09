#!/usr/bin/env bash
# Records the reuse review's verdict for the staged tree (matter c800).
#
#     dev/guardrails/record_review.sh pass|block REPORT
#
# Writes <git dir>/gallformers-review/<tree>.md: the verdict, then the
# report. The commit gate (.claude/hooks/require_review.sh) lets a commit
# through only when the staged tree has a file with "verdict: pass".
#
# Refuses when the staging has changed since the packet was made: that
# change hasn't been reviewed.
set -euo pipefail

verdict=${1:-}
report=${2:-}

if [[ "$verdict" != "pass" && "$verdict" != "block" ]] || [[ ! -f "$report" ]]; then
  echo "usage: $0 pass|block REPORT" >&2
  exit 1
fi

git_dir=$(cd "$(git rev-parse --git-dir)" && pwd)
dir="$git_dir/gallformers-review"
packet="$dir/packet.md"
tree=$(git write-tree)

reviewed=$(sed -n 's/^tree: //p' "$packet" 2>/dev/null | head -1)
if [[ "$reviewed" != "$tree" ]]; then
  echo "The staging changed since the packet was made (packet ${reviewed:-missing}, staged $tree)." >&2
  echo "Make a new packet with dev/guardrails/review_packet.sh and review that." >&2
  exit 1
fi

{
  echo "verdict: $verdict"
  echo "tree: $tree"
  echo
  cat "$report"
} > "$dir/$tree.md"

echo "$dir/$tree.md"
