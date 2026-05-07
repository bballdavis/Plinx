#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/strimr/run_ipad_sim.sh — Build and run the Strimr iOS app on iPad Simulator
# ─────────────────────────────────────────────────────────────────────────────
#
# Usage:
#   ./scripts/strimr/run_ipad_sim.sh                      # iPad (10th generation) — default
#   ./scripts/strimr/run_ipad_sim.sh "iPad Pro 13-inch"   # Custom device name
#
# The script builds whatever branch is currently checked out in the sibling
# ../strimr directory, so:
#
#   cd ../strimr && git switch feat/centered-clear-logo
#   cd ../Plinx  && ./scripts/strimr/run_ipad_sim.sh
#
# Steps:
#   1. Reports the active Strimr branch so you always know what you're running
#   2. Boots the target iPad simulator
#   3. Builds Strimr-iOS directly from the Strimr.xcodeproj (no XcodeGen needed)
#   4. Installs and launches the app
#
# ─────────────────────────────────────────────────────────────────────────────

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLINX_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
STRIMR_ROOT="$(dirname "$PLINX_ROOT")/strimr"
source "$PLINX_ROOT/scripts/sim_destination.sh"

# ── Configuration ──────────────────────────────────────────────────────────
DEVICE_NAME="${1:-iPad (10th generation)}"
SCHEME="Strimr"
PROJECT="$STRIMR_ROOT/Strimr.xcodeproj"
DERIVED_DATA_PATH="${STRIMR_SIM_DERIVED_DATA_PATH:-/tmp/strimr-run-ipad-derived-data}"
BUILD_LOG="/tmp/strimr_build_ipad.log"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Strimr iPad Simulator Build & Run"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Report active Strimr branch ────────────────────────────────────
if [ ! -d "$STRIMR_ROOT/.git" ]; then
    echo "❌ Strimr repo not found at: $STRIMR_ROOT"
    echo "   Expected a sibling checkout at $(dirname "$PLINX_ROOT")/strimr"
    exit 1
fi

STRIMR_BRANCH=$(git -C "$STRIMR_ROOT" rev-parse --abbrev-ref HEAD)
STRIMR_COMMIT=$(git -C "$STRIMR_ROOT" rev-parse --short HEAD)
STRIMR_STATUS=$(git -C "$STRIMR_ROOT" status --porcelain | wc -l | tr -d ' ')

echo "📂 Strimr: $STRIMR_ROOT"
echo "🌿 Branch: $STRIMR_BRANCH  ($STRIMR_COMMIT)"
if [ "$STRIMR_STATUS" -gt 0 ]; then
    echo "⚠️  Strimr has $STRIMR_STATUS uncommitted change(s)"
fi
echo "Device:   $DEVICE_NAME"
echo ""

# ── Step 2: Resolve simulator ──────────────────────────────────────────────
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

# ── Step 3: Boot simulator ─────────────────────────────────────────────────
echo "🔌 Checking simulator status..."
if [ "$SIM_STATUS" != "Booted" ]; then
    echo "⏳ Booting simulator..."
    xcrun simctl boot "$UDID"
    xcrun simctl bootstatus "$UDID" -b
fi
echo "✓ Simulator is running"
echo ""

# ── Step 4: Build ──────────────────────────────────────────────────────────
echo "🔨 Building Strimr-iOS (branch: $STRIMR_BRANCH)..."
/bin/rm -rf "$DERIVED_DATA_PATH"
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DEST" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    2>&1 | tee "$BUILD_LOG" | grep -E "error:|warning:|Build succeeded|BUILD FAILED" || true

if grep -q "BUILD FAILED" "$BUILD_LOG"; then
    echo ""
    echo "❌ Build failed. Errors:"
    grep -A 5 "error:" "$BUILD_LOG" | head -40
    exit 1
fi

echo "✓ Build succeeded"
echo ""

# ── Step 5: Locate built app ───────────────────────────────────────────────
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/Strimr-iOS.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Could not find Strimr-iOS.app at expected path:"
    echo "   $APP_PATH"
    echo ""
    echo "Available products:"
    find "$DERIVED_DATA_PATH/Build/Products" -name "*.app" -maxdepth 3 2>/dev/null || true
    exit 1
fi

echo "📦 App: $APP_PATH"
echo ""

BUNDLE_ID=$(defaults read "$APP_PATH/Info" CFBundleIdentifier 2>/dev/null || true)
if [ -z "$BUNDLE_ID" ]; then
    echo "❌ Could not read bundle identifier from built app"
    exit 1
fi
echo "Bundle ID: $BUNDLE_ID"
echo ""

# ── Step 6: Install & launch ───────────────────────────────────────────────
echo "🧹 Uninstalling previous version..."
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true

echo "📥 Installing app..."
xcrun simctl install "$UDID" "$APP_PATH"
echo "✓ App installed"
echo ""

echo "▶️  Launching app..."
xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Strimr ($STRIMR_BRANCH) is running on $SIM_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
