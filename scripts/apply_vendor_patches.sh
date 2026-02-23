#!/bin/bash

# Plinx Vendor Patch Coordinator (Migration-Style)
# This script applies Plinx-specific patches to the Strimr submodule.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRIMR_DIR="$REPO_ROOT/vendor/strimr"
PATCH_DIR="$REPO_ROOT/vendor/patches/strimr"

echo "⚡ Plinx Vendor Migrations: Applying patches to Strimr..."

if [ ! -d "$STRIMR_DIR" ]; then
    echo "❌ Error: Strimr directory not found at $STRIMR_DIR"
    exit 1
fi

pushd "$STRIMR_DIR" > /dev/null

# 1. Reset Strimr to its pinned submodule commit to ensure a clean slate
echo "🧹 Cleaning Strimr state..."
git reset --hard HEAD
git clean -fd

# 2. Apply patches in numeric order
for patch in "$PATCH_DIR"/*.patch; do
    if [ -f "$patch" ]; then
        echo "🔄 Applying $(basename "$patch")..."
        if git apply --check "$patch" > /dev/null 2>&1; then
            git apply "$patch"
        else
            echo "⚠️  Conflict detected in $(basename "$patch")."
            echo "   Attempting to apply with 3-way merge or manual intervention may be required."
            git apply --reject "$patch" || true
            echo "❌ Patch $(basename "$patch") failed to apply cleanly. See .rej files in Vendor/Strimr."
            exit 1
        fi
    fi
done

popd > /dev/null

echo "✅ All patches applied successfully."
