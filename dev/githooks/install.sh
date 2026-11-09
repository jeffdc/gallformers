#!/usr/bin/env bash
# Installs this repository's git hooks (matter c800). Run by `make hooks`
# and `make setup`; safe to run again.
#
# The hooks themselves are versioned in dev/githooks/. What's installed is a
# thin wrapper in git's hooks directory (wherever core.hooksPath points) that
# runs the checkout's own dev/githooks/<hook>, so every worktree runs its
# branch's version. Git config is not changed.
#
# - pre-commit (the commit gate): a branch without it commits as before.
# - pre-push (the push guard) must hold everywhere, so a copy is kept beside
#   the wrapper and runs on a branch without it. Running this again
#   refreshes the copy.
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
hooks_dir=$(git rev-parse --git-path hooks)
mkdir -p "$hooks_dir"

for hook in pre-commit pre-push; do
  target="$hooks_dir/$hook"
  marker="# gallformers: runs dev/githooks/$hook"

  if [[ -e "$target" ]] && ! grep -qx "$marker" "$target"; then
    echo "$target already has a $hook hook that isn't ours; leaving it alone." >&2
    echo "Call dev/githooks/$hook from it, or move it aside and run this again." >&2
    exit 1
  fi

  fallback="exit 0"
  if [[ "$hook" = "pre-push" ]]; then
    cp "$src/$hook" "$hooks_dir/$hook.gallformers"
    chmod +x "$hooks_dir/$hook.gallformers"
    fallback="exec \"\$(dirname \"\$0\")/$hook.gallformers\" \"\$@\""
  fi

  cat > "$target" <<EOF
#!/bin/sh
$marker
hook="\$(git rev-parse --show-toplevel)/dev/githooks/$hook"
[ -x "\$hook" ] && exec "\$hook" "\$@"
$fallback
EOF
  chmod +x "$target"
  echo "Installed $target"
done
