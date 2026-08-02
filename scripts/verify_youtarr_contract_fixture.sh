#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ROOT="${YOUTARR_DIR:-$PROJECT_ROOT/../Youtarr}"
VENDORED_ROOT="$PROJECT_ROOT/PlinxApp/UnitTests/Fixtures/YoutarrExternalAPIV1"

source "$PROJECT_ROOT/config/youtarr-contract.env"

usage() {
  echo "Usage: $0 [--check | --update] [--youtarr-dir PATH]" >&2
}

mode=check
while (($#)); do
  case "$1" in
    --check) mode=check ;;
    --update) mode=update ;;
    --youtarr-dir)
      shift
      [[ $# -gt 0 ]] || { usage; exit 2; }
      SOURCE_ROOT="$1"
      ;;
    *) usage; exit 2 ;;
  esac
  shift
done

source_fixture="$SOURCE_ROOT/fixtures/external-api-v1/contract.json"
source_sums="$SOURCE_ROOT/fixtures/external-api-v1/SHA256SUMS"
vendored_fixture="$VENDORED_ROOT/contract.json"
vendored_sums="$VENDORED_ROOT/SHA256SUMS"
bundled_sums="$VENDORED_ROOT/SHA256SUMS.txt"

[[ -f "$source_fixture" && -f "$source_sums" ]] || {
  echo "Missing canonical Youtarr fixture under $SOURCE_ROOT" >&2
  exit 1
}

source_commit="$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
[[ "$source_commit" == "$YOUTARR_CONTRACT_COMMIT" ]] || {
  echo "Youtarr checkout is $source_commit; expected $YOUTARR_CONTRACT_COMMIT" >&2
  exit 1
}

actual_sha="$(shasum -a 256 "$source_fixture" | awk '{print $1}')"
published_sha="$(awk 'NR == 1 {print $1}' "$source_sums")"
[[ "$actual_sha" == "$published_sha" && "$actual_sha" == "$YOUTARR_CONTRACT_SHA256" ]] || {
  echo "Youtarr fixture checksum does not match its published Plinx pin" >&2
  exit 1
}

if [[ "$mode" == update ]]; then
  mkdir -p "$VENDORED_ROOT"
  cp "$source_fixture" "$vendored_fixture"
  cp "$source_sums" "$vendored_sums"
  cp "$source_sums" "$bundled_sums"
fi

cmp -s "$source_fixture" "$vendored_fixture" || {
  echo "Vendored contract.json differs from canonical Youtarr fixture" >&2
  exit 1
}
cmp -s "$source_sums" "$vendored_sums" || {
  echo "Vendored SHA256SUMS differs from canonical Youtarr checksum" >&2
  exit 1
}
cmp -s "$source_sums" "$bundled_sums" || {
  echo "Bundled SHA256SUMS.txt differs from canonical Youtarr checksum" >&2
  exit 1
}

echo "Youtarr external API fixture verified at $YOUTARR_CONTRACT_COMMIT"
