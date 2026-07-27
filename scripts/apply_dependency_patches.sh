#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STRIMR_DIR="$(dirname "$PROJECT_ROOT")/strimr"
PATCH_FILE="$PROJECT_ROOT/patches/strimr-volume-cap.patch"

[[ -d "$STRIMR_DIR/.git" ]] || {
  echo "Missing Strimr sibling repository at $STRIMR_DIR" >&2
  exit 1
}

if git -C "$STRIMR_DIR" apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
  echo "Strimr volume-cap patch is already applied."
elif git -C "$STRIMR_DIR" apply --check "$PATCH_FILE"; then
  git -C "$STRIMR_DIR" apply "$PATCH_FILE"
  echo "Applied Strimr volume-cap patch."
else
  echo "Strimr volume-cap patch does not apply cleanly. Check the pinned revision and local changes." >&2
  exit 1
fi
