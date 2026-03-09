#!/bin/bash
# Verifies the sibling Strimr checkout exists and is on the plinx-patches
# branch with no local changes. Does NOT pull from remote; syncing is the
# developer's responsibility.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STRIMR_DIR="${PLINX_STRIMR_DIR:-$PROJECT_ROOT/../strimr}"
TARGET_BRANCH="plinx-patches"

if [[ "${PLINX_SKIP_STRIMR_SYNC:-0}" == "1" ]]; then
  echo "[strimr-verify] Skipped (PLINX_SKIP_STRIMR_SYNC=1)."
  exit 0
fi

if ! git -C "$STRIMR_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "[strimr-verify] Missing sibling Strimr checkout at $STRIMR_DIR"
  echo "[strimr-verify] Set PLINX_STRIMR_DIR or clone the fork to ../strimr"
  exit 1
fi

cd "$STRIMR_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "[strimr-verify] Error: sibling Strimr checkout has uncommitted changes."
  echo "[strimr-verify] Commit or stash changes before building."
  exit 1
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "$TARGET_BRANCH" ]]; then
  echo "[strimr-verify] Error: sibling Strimr checkout is on '$current_branch', not '$TARGET_BRANCH'."
  echo "[strimr-verify] Switch to $TARGET_BRANCH and sync with remote as needed."
  exit 1
fi

echo "[strimr-verify] sibling Strimr checkout is on $(git rev-parse --short HEAD) ($TARGET_BRANCH) ✓"
