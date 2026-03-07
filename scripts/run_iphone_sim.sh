#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# run_iphone_sim.sh — Build and run Plinx on iOS Simulator
# ─────────────────────────────────────────────────────────────────────────────
#
# Usage:
#   ./scripts/run_iphone_sim.sh              # iPhone 16 Pro Max (default)
#   ./scripts/run_iphone_sim.sh "iPhone 15" # Custom device name
#
# The script:
#   1. Generates Plinx.xcodeproj from project.yml via XcodeGen
#   2. Builds the Plinx-iOS target for iOS Simulator
#   3. Installs the app on the specified simulator
#   4. Launches the app
#
# ─────────────────────────────────────────────────────────────────────────────

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLINX_APP_DIR="$PROJECT_ROOT/PlinxApp"

# Configuration
DEVICE_NAME="${1:-iPhone 16 Pro Max}"
# We used to hardcode the bundle identifier here, which could
# be incorrect and also caused uninstall/launch commands to fail if
# the app changed.  Instead we will infer it from the built product
# after the build completes.
# BUNDLE_ID="com.example.plinx"
SCHEME="Plinx-iOS"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Plinx iOS Simulator Build & Run"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Device: $DEVICE_NAME"
echo "Bundle: $BUNDLE_ID"
echo ""

# Step 1: Determine destination for build.  The user may pass
# the literal string "generic" to request a generic iOS Simulator
# destination, avoiding the need to look up a specific device UUID.
# This is handy when running in CI or when you don't care about a
# particular simulator instance.
echo "📱 Determining destination..."
if [ "$DEVICE_NAME" = "generic" ]; then
    echo "→ using generic iOS Simulator destination"
    DEST="platform=iOS Simulator"
else
    UDID=$(xcrun simctl list devices available | grep "$DEVICE_NAME" | grep -oE '\(([A-F0-9-]+)\)' | head -1 | tr -d '()')

    if [ -z "$UDID" ]; then
        echo "❌ Simulator '$DEVICE_NAME' not found."
        echo ""
        echo "Available devices:"
        xcrun simctl list devices available | grep "iPhone\|iPad"
        exit 1
    fi

    echo "✓ Found: $DEVICE_NAME ($UDID)"
    DEST="platform=iOS Simulator,id=$UDID"
fi

echo ""

# Step 2: Boot simulator if not running
echo "🔌 Checking simulator status..."
STATUS=$(xcrun simctl list devices | grep "$UDID" | grep -oE "(Booted|Shutdown)" | head -1)

if [ "$STATUS" != "Booted" ]; then
    echo "⏳ Booting simulator..."
    xcrun simctl boot "$UDID"
    # Wait for simulator to fully boot
    sleep 5
fi

echo "✓ Simulator is running"
echo ""

# Step 3: Generate project.yml → Plinx.xcodeproj
echo "⚙️  Generating Xcode project..."
cd "$PLINX_APP_DIR"
XGEN_LOG="/tmp/plinx_xcodegen_iphone.log"
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
BUILD_LOG="/tmp/plinx_build_iphone.log"
# use the computed destination string (may be generic)
xcodebuild build \
    -project Plinx.xcodeproj \
    -scheme "$SCHEME" \
    -destination "$DEST" \
    -configuration Debug \
    2>&1 | tee "$BUILD_LOG" | grep -E "error:|warning:|Build succeeded|BUILD FAILED" || true

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo ""
    echo "❌ Build failed. Detailed errors:"
    grep -A 5 "error:" "$BUILD_LOG" | head -30
    exit 1
fi

echo "✓ Build succeeded"
echo ""

# Step 5: Find the built app.  Avoid returning the stub inside
# Index.noindex which frequently lacks a valid Info.plist and causes
# "Missing bundle ID" install errors.
APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "Plinx.app" -type d 2>/dev/null \
    | grep -E "Debug-iphonesimulator" \
    | grep -v "Index\.noindex" \
    | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Could not find built Plinx.app in DerivedData"
    exit 1
fi

echo "📦 App location: $APP_PATH"
echo ""

# derive the bundle identifier from the built app rather than relying on
# a hardcoded constant.  this also avoids the placeholder value used
# earlier in the script.
BUNDLE_ID=$(defaults read "$APP_PATH/Info" CFBundleIdentifier 2>/dev/null || true)
if [ -z "$BUNDLE_ID" ]; then
    echo "❌ could not read bundle identifier from built app"
    exit 1
fi

echo "Bundle ID: $BUNDLE_ID"
echo ""

# Step 6: Uninstall previous version (if present)
echo "🧹 Uninstalling previous version..."
# when using a generic destination UDID may be empty but uninstall
# still works if we omit it.
if [ -n "$UDID" ]; then
    xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
else
    # try uninstalling from all simulators (harmless if not installed)
    for d in $(xcrun simctl list devices available | grep -oE '\(([A-F0-9-]+)\)' | tr -d '()'); do
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
