#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# build_only.sh — Build Plinx for iOS Simulator (no install/run)
# ─────────────────────────────────────────────────────────────────────────────
#
# Usage:
#   ./scripts/build_only.sh              # iPhone 16 Pro Max (default)
#   ./scripts/build_only.sh "iPhone 15" # Custom device name
#
# The script:
#   1. Generates Plinx.xcodeproj from project.yml via XcodeGen
#   2. Builds the Plinx-iOS target for iOS Simulator
#   3. Reports the build path
#
# ─────────────────────────────────────────────────────────────────────────────

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLINX_APP_DIR="$PROJECT_ROOT/PlinxApp"

"$SCRIPT_DIR/sync_strimr_patches.sh"

DEVICE_NAME="${1:-iPhone 16 Pro Max}"
SCHEME="Plinx-iOS"
DESTINATION=""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔨 Plinx iOS Simulator Build"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Device: $DEVICE_NAME"
echo ""

# Find simulator when CoreSimulator is reachable; otherwise fall back to a
# generic simulator destination so compile failures can still be surfaced.
echo "📱 Finding simulator..."
UDID=""
if SIM_DEVICES=$(xcrun simctl list devices available 2>/dev/null); then
    UDID=$(echo "$SIM_DEVICES" | grep "$DEVICE_NAME" | grep -oE '\(([A-F0-9-]+)\)' | head -1 | tr -d '()')
fi

if [ -n "$UDID" ]; then
    DESTINATION="platform=iOS Simulator,id=$UDID"
    echo "✓ Found: $DEVICE_NAME"
else
    DESTINATION="generic/platform=iOS Simulator"
    echo "⚠️  Simulator '$DEVICE_NAME' not found or CoreSimulator unavailable."
    echo "   Falling back to generic iOS Simulator destination."
fi
echo ""

# Generate project
echo "⚙️  Generating Xcode project..."
cd "$PLINX_APP_DIR"
xcodegen generate

if [ ! -d "Plinx.xcodeproj" ]; then
    echo "❌ XcodeGen failed"
    exit 1
fi

echo "✓ Project generated"
echo ""

# Build
echo "🔨 Building Plinx-iOS..."
xcodebuild build \
    -project Plinx.xcodeproj \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -configuration Debug

BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then
    echo ""
    echo "❌ Build failed"
    exit 1
fi

echo ""
echo "✓ Build succeeded"
echo ""
BUILD_APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "Plinx.app" -type d 2>/dev/null | grep -E "Debug-iphonesimulator" | head -1)
if [ -n "$BUILD_APP" ]; then
    echo "📦 App location: $BUILD_APP"
else
    echo "📦 App location: ~/Library/Developer/Xcode/DerivedData/<project>/Build/Products/Debug-iphonesimulator/Plinx.app"
fi
echo ""
echo "To install and run: ./scripts/run_iphone_sim.sh \"$DEVICE_NAME\""
