#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec /bin/bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_ROOT/PlinxApp"
CHECK_ONLY=false

if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=true
  shift
fi

cd "$APP_DIR"
xcodegen generate "$@"

if [[ "$CHECK_ONLY" == true ]]; then
  # Xcode normalizes shared scheme XML to the current schema when it first
  # opens a freshly generated project. Compare that representation because it
  # is the one Xcode Cloud reads and the one developers see locally.
  xcodebuild \
    -list \
    -project "$APP_DIR/Plinx.xcodeproj" \
    >/dev/null
  git -C "$PROJECT_ROOT" diff --exit-code -- PlinxApp/Plinx.xcodeproj
fi
