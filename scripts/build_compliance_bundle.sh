#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec /bin/bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PARENT_DIR="$(dirname "$PROJECT_ROOT")"
STRIMR_DIR="$PARENT_DIR/strimr"
OUTPUT_DIR="${1:-$PROJECT_ROOT/build/compliance}"

source "$PROJECT_ROOT/config/release-dependencies.env"

[[ -z "$(git -C "$PROJECT_ROOT" status --porcelain)" ]] || {
  echo "Plinx worktree must be clean before creating corresponding source." >&2
  exit 1
}
[[ -d "$STRIMR_DIR/.git" ]] || { echo "Missing $STRIMR_DIR" >&2; exit 1; }
git -C "$STRIMR_DIR" cat-file -e "${STRIMR_COMMIT}^{commit}"
bash "$PROJECT_ROOT/scripts/verify_release_dependency_state.sh"

release_commit="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
bundle_name="Plinx-${release_commit:0:12}-corresponding-source"
bundle_dir="$OUTPUT_DIR/$bundle_name"

mkdir -p "$bundle_dir"
git -C "$PROJECT_ROOT" archive --format=tar HEAD | tar -xf - -C "$bundle_dir"
mkdir -p "$bundle_dir/Dependencies/Strimr"
git -C "$STRIMR_DIR" archive --format=tar "$STRIMR_COMMIT" | tar -xf - -C "$bundle_dir/Dependencies/Strimr"

cp "$PROJECT_ROOT/docs/release/open-source-compliance.md" "$bundle_dir/"

tar -czf "$OUTPUT_DIR/$bundle_name.tar.gz" -C "$OUTPUT_DIR" "$bundle_name"
echo "$OUTPUT_DIR/$bundle_name.tar.gz"
