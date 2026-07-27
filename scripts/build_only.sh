#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

# ─────────────────────────────────────────────────────────────────────────────
# build_only.sh — Build Plinx for iOS Simulator (no install/run)
# ─────────────────────────────────────────────────────────────────────────────
#
# Usage:
#   ./scripts/build_only.sh              # iPhone 17 Pro Max (default)
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
source "$PROJECT_ROOT/scripts/sim_destination.sh"

DEVICE_NAME="${1:-iPhone 17 Pro Max}"
SCHEME="Plinx-iOS"
DESTINATION=""
DERIVED_DATA_PATH="${PLINX_SIM_DERIVED_DATA_PATH:-/tmp/plinx-build-only-derived-data}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔨 Plinx iOS Simulator Build"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Device: $DEVICE_NAME"
echo ""

# Find simulator when CoreSimulator is reachable; otherwise fall back to a
# generic simulator destination so compile failures can still be surfaced.
echo "📱 Finding simulator..."
if select_simulator_destination "$DEVICE_NAME"; then
    DESTINATION="$SIM_DESTINATION"
    UDID="$SIM_UDID"
    if [ "$SIM_NAME" = "$DEVICE_NAME" ]; then
        echo "✓ Found: $SIM_NAME"
    else
        echo "⚠️  Exact simulator '$DEVICE_NAME' not found. Using '$SIM_NAME' ($UDID) instead."
    fi
else
    DESTINATION="generic/platform=iOS Simulator"
    echo "⚠️  Simulator '$DEVICE_NAME' not found or CoreSimulator unavailable."
    echo "   Falling back to generic iOS Simulator destination."
fi
echo ""

# Generate project
echo "⚙️  Generating Xcode project..."
cd "$PLINX_APP_DIR"
bash "$PROJECT_ROOT/scripts/generate_xcodeproj.sh"

if [ ! -d "Plinx.xcodeproj" ]; then
    echo "❌ XcodeGen failed"
    exit 1
fi

echo "✓ Project generated"
echo ""

# Build
echo "🔨 Building Plinx-iOS..."
/bin/rm -rf "$DERIVED_DATA_PATH"
xcodebuild build \
    -project Plinx.xcodeproj \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH"

BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then
    echo ""
    echo "❌ Build failed"
    exit 1
fi

echo ""
echo "✓ Build succeeded"
echo ""
BUILD_APP="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/Plinx.app"
if [ -n "$BUILD_APP" ]; then
    echo "📦 App location: $BUILD_APP"
else
    echo "📦 App location: $DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/Plinx.app"
fi
echo ""
echo "To install and run: ./scripts/run_iphone_sim.sh \"$DEVICE_NAME\""
