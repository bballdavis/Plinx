#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec /bin/bash "$0" "$@"
fi

# Packages the complete corresponding source for a Plinx release.
#
# The Plinx commit is the whole application source, including the Strimr code
# Plinx absorbed under PlinxApp/Core and PlinxApp/Platform. The bundle adds a
# manifest naming that commit, the absorbed Strimr base, and the exact Swift
# package pins from PlinxApp/project.yml, which Swift Package Manager fetches
# as source.
#
# Usage: ./scripts/build_compliance_bundle.sh [OUTPUT_DIR]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${1:-$PROJECT_ROOT/build/compliance}"
PROJECT_SPEC="$PROJECT_ROOT/PlinxApp/project.yml"

source "$PROJECT_ROOT/config/release-dependencies.env"

[[ -z "$(git -C "$PROJECT_ROOT" status --porcelain)" ]] || {
  echo "Plinx worktree must be clean before creating corresponding source." >&2
  exit 1
}
[[ "${STRIMR_FORK_BASE:-}" =~ ^[0-9a-f]{40}$ ]] || {
  echo "STRIMR_FORK_BASE in config/release-dependencies.env must be a 40-character Git SHA." >&2
  exit 1
}

# Prints "<name> <url> <pin kind> <pin>" for each remote package in the
# top-level `packages:` block. Local `path:` packages are part of the archive.
remote_package_pins() {
  awk '
    function unquote(value) { gsub(/["\047]/, "", value); return value }
    function flush() {
      if (name != "" && url != "") printf "%s %s %s %s\n", name, url, kind, pin
      name = ""; url = ""; kind = ""; pin = ""
    }
    /^packages:[[:space:]]*$/ { in_packages = 1; next }
    in_packages && /^[^[:space:]#]/ { flush(); in_packages = 0 }
    !in_packages { next }
    /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ { flush(); name = $1; sub(/:$/, "", name); next }
    /^    url:/ { url = unquote($2); next }
    /^    (revision|exactVersion|version|from|branch):/ {
      kind = $1; sub(/:$/, "", kind); pin = unquote($2); next
    }
    END { flush() }
  ' "$PROJECT_SPEC"
}

package_pins="$(remote_package_pins)"
[[ -n "$package_pins" ]] || {
  echo "No remote Swift package pins were found in PlinxApp/project.yml." >&2
  exit 1
}
while read -r name url kind pin; do
  if [[ "$kind" != "revision" && "$kind" != "exactVersion" ]]; then
    echo "Swift package $name is not pinned exactly ($kind: $pin)." >&2
    exit 1
  fi
done <<<"$package_pins"

release_commit="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
bundle_name="Plinx-${release_commit:0:12}-corresponding-source"
bundle_dir="$OUTPUT_DIR/$bundle_name"

rm -rf "$bundle_dir"
mkdir -p "$bundle_dir"
git -C "$PROJECT_ROOT" archive --format=tar HEAD | tar -xf - -C "$bundle_dir"
cp "$PROJECT_ROOT/docs/release/open-source-compliance.md" "$bundle_dir/"

{
  echo "Plinx corresponding source"
  echo
  echo "Plinx commit: $release_commit"
  echo "Absorbed Strimr base (wunax/strimr): $STRIMR_FORK_BASE"
  echo
  echo "Swift packages (fetched as source by Swift Package Manager):"
  while read -r name url kind pin; do
    echo "  $name $url $kind $pin"
  done <<<"$package_pins"
} >"$bundle_dir/SOURCE-MANIFEST.txt"

tar -czf "$OUTPUT_DIR/$bundle_name.tar.gz" -C "$OUTPUT_DIR" "$bundle_name"
echo "$OUTPUT_DIR/$bundle_name.tar.gz"
