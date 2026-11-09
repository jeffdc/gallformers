#!/usr/bin/env bash
# New-file prompt (matter c800): a PreToolUse hook on Write.
#
# The first Write of a file that doesn't exist yet under a repository's lib/
# is blocked once (exit 2; stderr goes to Claude) with a question: which
# existing modules were checked, and why none fits. The next Write of that
# path goes through. Asked paths are kept in <git dir>/gallformers-new-files.
set -uo pipefail

input=$(cat)
path=$(jq -r '.tool_input.file_path // empty' <<<"$input")
cwd=$(jq -r '.cwd // "."' <<<"$input")
[[ -n "$path" ]] || exit 0
[[ "$path" = /* ]] || path="$cwd/$path"
[[ -e "$path" ]] && exit 0

# The repository the file goes in, from the nearest directory that exists;
# the path with that directory's links resolved, so it compares with the top.
existing=$(dirname "$path")
while [[ ! -d "$existing" ]]; do existing=$(dirname "$existing"); done
top=$(git -C "$existing" rev-parse --show-toplevel 2>/dev/null) || exit 0
top=$(cd "$top" && pwd -P)
real="$(cd "$existing" && pwd -P)${path#"$existing"}"

case "$real" in
  "$top"/lib/*) ;;
  *) exit 0 ;;
esac

git_dir=$(git -C "$top" rev-parse --git-dir)
[[ "$git_dir" = /* ]] || git_dir="$top/$git_dir"
asked="$git_dir/gallformers-new-files"
mkdir -p "$asked"
key=$(printf '%s' "$real" | shasum | cut -d' ' -f1)

[[ -f "$asked/$key" ]] && exit 0
printf '%s\n' "$real" > "$asked/$key"

echo "New file under lib/: ${real#"$top"/}. Name the existing modules you checked and why none fits (search for the job it does, not just its name), then write it again." >&2
exit 2
