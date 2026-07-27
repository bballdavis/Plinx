#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

# ─────────────────────────────────────────────────────────────────────────────
# run_ipad_sim.sh — Build and run Plinx on iPad Simulator
# ─────────────────────────────────────────────────────────────────────────────
#
# Usage:
#   ./scripts/run_ipad_sim.sh                      # iPad Pro 12.9" (default)
#   ./scripts/run_ipad_sim.sh "iPad (10th gen)"    # Custom device name
#
# The script:
#   1. Generates Plinx.xcodeproj from project.yml via XcodeGen
#   2. Builds the Plinx-iOS target for iOS Simulator
#   3. Installs the app on the specified iPad simulator
#   4. Launches the app
#
# ─────────────────────────────────────────────────────────────────────────────

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLINX_APP_DIR="$PROJECT_ROOT/PlinxApp"
source "$PROJECT_ROOT/scripts/sim_destination.sh"

# Configuration
DEVICE_NAME="${1:-iPad (10th generation)}"
# bundle identifier will be read from the built product later
# BUNDLE_ID="com.example.plinx"
SCHEME="Plinx-iOS"
DERIVED_DATA_PATH="${PLINX_SIM_DERIVED_DATA_PATH:-/tmp/plinx-run-ipad-derived-data}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Plinx iPad Simulator Build & Run"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Device: $DEVICE_NAME"
echo "Bundle: $BUNDLE_ID"
echo ""

# Step 1: Determine destination (supports generic keyword)
echo "📱 Determining destination..."
if [ "$DEVICE_NAME" = "generic" ]; then
    echo "→ using generic iOS Simulator destination"
    DEST="platform=iOS Simulator"
else
    if select_simulator_destination "$DEVICE_NAME"; then
        DEST="$SIM_DESTINATION"
        UDID="$SIM_UDID"
        if [ "$SIM_NAME" = "$DEVICE_NAME" ]; then
            echo "✓ Found: $SIM_NAME ($UDID)"
        else
            echo "⚠️  Exact simulator '$DEVICE_NAME' not found. Using '$SIM_NAME' ($UDID) instead."
        fi
    else
        echo "❌ Simulator '$DEVICE_NAME' not found."
        echo ""
        echo "Available iPad devices:"
        xcrun simctl list devices available | grep "iPad"
        exit 1
    fi
fi

echo ""

# Step 2: Boot simulator if not running
echo "🔌 Checking simulator status..."
STATUS="$SIM_STATUS"

if [ "$STATUS" != "Booted" ]; then
    echo "⏳ Booting simulator..."
    xcrun simctl boot "$UDID"
    xcrun simctl bootstatus "$UDID" -b
fi

echo "✓ Simulator is running"
echo ""

# Step 3: Generate project.yml → Plinx.xcodeproj
echo "⚙️  Generating Xcode project..."
cd "$PLINX_APP_DIR"
XGEN_LOG="/tmp/plinx_xcodegen_ipad.log"
bash "$PROJECT_ROOT/scripts/generate_xcodeproj.sh" 2>&1 | tee "$XGEN_LOG"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "❌ XcodeGen failed"
    exit 1
fi

if [ ! -d "Plinx.xcodeproj" ]; then
    echo "❌ XcodeGen failed to generate project"
    exit 1
fi

echo "✓ Project generated"
echo ""

# Step 4: Build the app
echo "🔨 Building Plinx-iOS..."
BUILD_LOG="/tmp/plinx_build_ipad.log"
/bin/rm -rf "$DERIVED_DATA_PATH"
xcodebuild build \
    -project Plinx.xcodeproj \
    -scheme "$SCHEME" \
    -destination "$DEST" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    2>&1 | tee "$BUILD_LOG" | grep -E "error:|warning:|Build succeeded|BUILD FAILED" || true

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo ""
    echo "❌ Build failed. Detailed errors:"
    grep -A 5 "error:" "$BUILD_LOG" | head -30
    exit 1
fi

echo "✓ Build succeeded"
echo ""

# Step 5: Find the built app
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/Plinx.app"

if [ -z "$APP_PATH" ]; then
    echo "❌ Could not find built Plinx.app in DerivedData"
    exit 1
fi

echo "📦 App location: $APP_PATH"
echo ""

BUNDLE_ID=$(defaults read "$APP_PATH/Info" CFBundleIdentifier 2>/dev/null || true)
if [ -z "$BUNDLE_ID" ]; then
    echo "❌ could not read bundle identifier from built app"
    exit 1
fi

echo "Bundle ID: $BUNDLE_ID"
echo ""

echo "🧹 Uninstalling previous version..."
if [ -n "$UDID" ]; then
    xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
else
    for d in $(xcrun simctl list devices available | grep -oE '\([A-F0-9-]+\)' | tr -d '()'); do
        xcrun simctl uninstall "$d" "$BUNDLE_ID" 2>/dev/null || true
    done
fi

# Step 7: Install app
echo "📥 Installing app..."
xcrun simctl install "$UDID" "$APP_PATH"

echo "✓ App installed"
echo ""

# Step 8: Launch app
echo "▶️  Launching app..."
xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Plinx is running on $DEVICE_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
