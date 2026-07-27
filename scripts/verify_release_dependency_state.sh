#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PARENT_DIR="$(dirname "$PROJECT_ROOT")"
STRIMR_DIR="$PARENT_DIR/strimr"
MPVKIT_DIR="$PARENT_DIR/MPVKit"
PATCH_FILE="$PROJECT_ROOT/patches/strimr-volume-cap.patch"

source "$PROJECT_ROOT/config/release-dependencies.env"

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT

expected_strimr="$temporary_directory/strimr"
expected_mpvkit="$temporary_directory/MPVKit"
mkdir -p "$expected_strimr" "$expected_mpvkit"

git -C "$STRIMR_DIR" archive "$STRIMR_COMMIT" | tar -xf - -C "$expected_strimr"
(
  cd "$expected_strimr"
  git apply "$PATCH_FILE"
)
git -C "$MPVKIT_DIR" archive "$MPVKIT_COMMIT" | tar -xf - -C "$expected_mpvkit"

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
  echo "Strimr does not match the pinned commit plus release patch." >&2
  echo "Release builds must not include unrelated or uncommitted sibling changes." >&2
  diff "${diff_options[@]}" "$expected_strimr" "$STRIMR_DIR" | head -n 40 >&2
  exit 1
fi

if ! diff "${diff_options[@]}" "$expected_mpvkit" "$MPVKIT_DIR" >/dev/null; then
  echo "MPVKit does not match the pinned release commit." >&2
  diff "${diff_options[@]}" "$expected_mpvkit" "$MPVKIT_DIR" | head -n 40 >&2
  exit 1
fi

echo "Release dependencies match pinned source exactly."
