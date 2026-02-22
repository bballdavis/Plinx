#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# clean.sh — Clean Plinx build artifacts
# ─────────────────────────────────────────────────────────────────────────────
#
# Removes:
#   - Plinx.xcodeproj (regenerated from project.yml)
#   - Plinx entries in ~/Library/Developer/Xcode/DerivedData
#
# ─────────────────────────────────────────────────────────────────────────────

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLINX_APP_DIR="$PROJECT_ROOT/PlinxApp"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 Cleaning Plinx Build Artifacts"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Clean generated project
if [ -d "$PLINX_APP_DIR/Plinx.xcodeproj" ]; then
    echo "🗑️  Removing Plinx.xcodeproj..."
    rm -rf "$PLINX_APP_DIR/Plinx.xcodeproj"
    echo "✓ Removed"
fi

# Clean DerivedData at repo root (if any legacy builds)
if [ -d "$PROJECT_ROOT/DerivedData" ]; then
    echo "🗑️  Removing $PROJECT_ROOT/DerivedData (legacy)..."
    rm -rf "$PROJECT_ROOT/DerivedData"
    echo "✓ Removed"
fi

# Clean Xcode build cache (user level) — this is where actual builds go
BUILD_CACHE="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$BUILD_CACHE" ]; then
    echo "🗑️  Cleaning ~/Library/Developer/Xcode/DerivedData (Plinx entries)..."
    # Only remove paths containing "Plinx" to avoid nuking other project caches
    find "$BUILD_CACHE" -maxdepth 1 -type d -name "*Plinx*" -exec rm -rf {} + 2>/dev/null || true
    echo "✓ Cleaned"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Clean complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
