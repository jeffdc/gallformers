#!/usr/bin/env bash
# The reuse review's packet (matter c800): the staged change, for the
# reuse-reviewer agent to read before a commit.
#
# Writes <git dir>/gallformers-review/packet.md with the staged tree's hash,
# the new files, the new public definitions (pulled from the diff, so they
# don't depend on the author's account) and the full staged diff. Prints the
# packet's path.
set -euo pipefail

git_dir=$(cd "$(git rev-parse --git-dir)" && pwd)
dir="$git_dir/gallformers-review"
mkdir -p "$dir"
packet="$dir/packet.md"

if git diff --cached --quiet; then
  echo "Nothing is staged." >&2
  exit 1
fi

tree=$(git write-tree)

{
  echo "# Reuse review packet"
  echo
  echo "tree: $tree"
  echo
  echo "## Files"
  echo
  git diff --cached --name-status | sed 's/^/    /'
  echo
  echo "## New public definitions"
  echo
  echo "Each new def, defmacro, defdelegate, defguard, defmodule and component attr/slot added by this change:"
  echo
  git diff --cached -U0 --no-color |
    awk '
      /^\+\+\+ / { file = substr($0, 7); next }
      /^\+[[:space:]]*(def|defmacro|defdelegate|defguard|defmodule)[[:space:]]/ { sub(/^\+[[:space:]]*/, ""); print "    " file ": " $0 }
      /^\+[[:space:]]*(attr|slot)[[:space:]]+:/ { sub(/^\+[[:space:]]*/, ""); print "    " file ": " $0 }
    '
  echo
  echo "## Diff"
  echo
  echo '```diff'
  git diff --cached --no-color
  echo '```'
} > "$packet"

echo "$packet"
