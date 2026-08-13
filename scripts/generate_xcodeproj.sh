#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec /bin/bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_ROOT/PlinxApp"
CHECK_ONLY=false
NORMALIZE_WITH_XCODE=false

case "${1:-}" in
  --check)
    CHECK_ONLY=true
    NORMALIZE_WITH_XCODE=true
    shift
    ;;
  --check-portable)
    CHECK_ONLY=true
    shift
    ;;
esac

cd "$APP_DIR"
xcodegen generate "$@"

if [[ "$CHECK_ONLY" == true ]]; then
  if [[ "$NORMALIZE_WITH_XCODE" == true ]]; then
    # Xcode normalizes shared scheme XML to the current schema when it first
    # opens a freshly generated project. Compare that representation because
    # it is the one Xcode Cloud reads and the one developers see locally.
    xcodebuild \
      -list \
      -project "$APP_DIR/Plinx.xcodeproj" \
      >/dev/null
  fi

  project_status="$(
    git -C "$PROJECT_ROOT" status \
      --porcelain \
      --untracked-files=all \
      -- PlinxApp/Plinx.xcodeproj
  )"
  if [[ -n "$project_status" ]]; then
    git -C "$PROJECT_ROOT" diff -- PlinxApp/Plinx.xcodeproj
    printf '%s\n' "$project_status" >&2
    echo "PlinxApp/Plinx.xcodeproj is stale; regenerate and commit it." >&2
    exit 1
  fi
fi
