#!/bin/bash
# Verifies vendor/strimr is on the plinx-patches branch with no local changes.
# Does NOT pull from remote; syncing is the developer's responsibility.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SUBMODULE_DIR="$PROJECT_ROOT/vendor/strimr"
TARGET_BRANCH="plinx-patches"

if [[ "${PLINX_SKIP_STRIMR_SYNC:-0}" == "1" ]]; then
  echo "[strimr-verify] Skipped (PLINX_SKIP_STRIMR_SYNC=1)."
  exit 0
fi

if ! git -C "$SUBMODULE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "[strimr-verify] Missing submodule at $SUBMODULE_DIR"
  echo "[strimr-verify] Run: git submodule update --init --recursive"
  exit 1
fi

cd "$SUBMODULE_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "[strimr-verify] Error: vendor/strimr has uncommitted changes."
  echo "[strimr-verify] Commit or stash changes before building."
  exit 1
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "$TARGET_BRANCH" ]]; then
  echo "[strimr-verify] Error: vendor/strimr is on '$current_branch', not '$TARGET_BRANCH'."
  echo "[strimr-verify] Switch to $TARGET_BRANCH and sync with remote as needed."
  exit 1
fi

echo "[strimr-verify] vendor/strimr is on $(git rev-parse --short HEAD) ($TARGET_BRANCH) ✓"
