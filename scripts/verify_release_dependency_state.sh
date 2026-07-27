#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PARENT_DIR="$(dirname "$PROJECT_ROOT")"
STRIMR_DIR="$PARENT_DIR/strimr"

source "$PROJECT_ROOT/config/release-dependencies.env"

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT

expected_strimr="$temporary_directory/strimr"
mkdir -p "$expected_strimr"

git -C "$STRIMR_DIR" archive "$STRIMR_COMMIT" | tar -xf - -C "$expected_strimr"

diff_options=(
  -qr
  -x .git
  -x .DS_Store
  -x .build
  -x build
  -x Carthage
  -x .swiftpm
  -x xcuserdata
  -x Strimr.xcodeproj
)

if ! diff "${diff_options[@]}" "$expected_strimr" "$STRIMR_DIR" >/dev/null; then
  echo "Strimr does not match the pinned release commit." >&2
  echo "Release builds must not include unrelated or uncommitted sibling changes." >&2
  diff "${diff_options[@]}" "$expected_strimr" "$STRIMR_DIR" | head -n 40 >&2
  exit 1
fi

echo "The Strimr sibling matches the pinned source exactly."
