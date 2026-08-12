#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STRIMR_ROOT="$PROJECT_ROOT/../strimr"
STRIMR_REPOSITORY="https://github.com/bballdavis/strimr.git"

source "$PROJECT_ROOT/config/release-dependencies.env"

if [[ ! -d "$STRIMR_ROOT/.git" ]]; then
  echo "Cloning the pinned Strimr source for Xcode Cloud."
  git clone --filter=blob:none "$STRIMR_REPOSITORY" "$STRIMR_ROOT"
fi

if ! git -C "$STRIMR_ROOT" cat-file -e "${STRIMR_COMMIT}^{commit}" 2>/dev/null; then
  echo "Fetching the pinned Strimr commit."
  git -C "$STRIMR_ROOT" fetch --depth=1 origin "$STRIMR_COMMIT"
fi

git -C "$STRIMR_ROOT" checkout --force --detach "$STRIMR_COMMIT"

actual_commit="$(git -C "$STRIMR_ROOT" rev-parse HEAD)"
if [[ "$actual_commit" != "$STRIMR_COMMIT" ]]; then
  echo "Strimr checkout mismatch: expected $STRIMR_COMMIT, found $actual_commit" >&2
  exit 1
fi

bash "$PROJECT_ROOT/scripts/verify_strimr_integration_contract.sh" --quick
