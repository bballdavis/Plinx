#!/bin/bash
# Ensures vendor/strimr is on the latest origin/plinx-patches commit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SUBMODULE_DIR="$PROJECT_ROOT/vendor/strimr"
TARGET_BRANCH="plinx-patches"

if [[ "${PLINX_SKIP_STRIMR_SYNC:-0}" == "1" ]]; then
  echo "[strimr-sync] Skipped (PLINX_SKIP_STRIMR_SYNC=1)."
  exit 0
fi

if ! git -C "$SUBMODULE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "[strimr-sync] Missing submodule at $SUBMODULE_DIR"
  echo "[strimr-sync] Run: git submodule update --init --recursive"
  exit 1
fi

cd "$SUBMODULE_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "[strimr-sync] Refusing to sync: vendor/strimr has local changes."
  echo "[strimr-sync] Commit/stash changes in vendor/strimr, then retry."
  exit 1
fi

git fetch origin "$TARGET_BRANCH"

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "$TARGET_BRANCH" ]]; then
  if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
    git checkout "$TARGET_BRANCH"
  else
    git checkout -b "$TARGET_BRANCH" "origin/$TARGET_BRANCH"
  fi
fi

git pull --ff-only origin "$TARGET_BRANCH"

echo "[strimr-sync] vendor/strimr now on $(git rev-parse --short HEAD) ($TARGET_BRANCH)"
