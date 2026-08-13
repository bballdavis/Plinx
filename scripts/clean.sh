#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/build_environment.sh"

remove_tree() {
    local target="$1"
    local resolved_target resolved_project resolved_home

    if [[ -z "$target" || "$target" != /* || "$target" == "/" ]]; then
        echo "Refusing unsafe cleanup target: ${target:-<empty>}" >&2
        exit 1
    fi

    resolved_target="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)/$(basename "$target")"
    resolved_project="$(cd "$PROJECT_ROOT" && pwd -P)"
    resolved_home="$(cd "$PLINX_USER_HOME" && pwd -P)"

    if [[ "$resolved_target" == "$resolved_home" ||
          "$resolved_target" == "$resolved_project" ||
          "$resolved_project" == "$resolved_target"/* ]]; then
        echo "Refusing cleanup target that contains source or user data: $resolved_target" >&2
        exit 1
    fi

    if [[ -e "$target" ]]; then
        echo "Removing $target"
        find "$target" -depth -delete
    fi
}

# These are disposable outputs only. Source, Git metadata, credentials, the
# checked-in Xcode Cloud project, the sibling Strimr checkout, and user-created
# files are intentionally excluded.
remove_tree "$PROJECT_ROOT/build"
remove_tree "$PROJECT_ROOT/Packages/PlinxCore/.build"
remove_tree "$PROJECT_ROOT/Packages/PlinxCore/build"
remove_tree "$PROJECT_ROOT/Packages/PlinxCore/.swiftpm"
remove_tree "$PROJECT_ROOT/Packages/PlinxUI/.build"
remove_tree "$PROJECT_ROOT/Packages/PlinxUI/build"
remove_tree "$PROJECT_ROOT/Packages/PlinxUI/.swiftpm"
remove_tree "$PROJECT_ROOT/website/node_modules"
remove_tree "$PROJECT_ROOT/website/build"
remove_tree "$PROJECT_ROOT/website/.docusaurus"
remove_tree "$PROJECT_ROOT/website/.generated"
remove_tree "$PLINX_XCODE_DERIVED_DATA_PATH"
remove_tree "$PLINX_SWIFTPM_SCRATCH_ROOT"

echo "Plinx disposable artifacts and shared caches removed."
