#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

# ─────────────────────────────────────────────────────────────────────────────
# run_appletv_sim.sh — Build and run Plinx on Apple TV Simulator
# ─────────────────────────────────────────────────────────────────────────────
#
# Usage:
#   ./scripts/run_appletv_sim.sh                          # Apple TV (default)
#   ./scripts/run_appletv_sim.sh "Apple TV 4K (3rd generation)"
#   ./scripts/run_appletv_sim.sh --compile-only           # Build only, no signing/install
#
# The script:
#   1. Generates Plinx.xcodeproj from project.yml via XcodeGen
#   2. Builds the Plinx-tvOS target for tvOS Simulator
#   3. Installs the app on the specified Apple TV simulator
#   4. Launches the app
#
# This is the supported local build-and-run path for the Plinx tvOS target.
# Build output is captured so release-candidate failures can be diagnosed.
#
# ─────────────────────────────────────────────────────────────────────────────

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLINX_APP_DIR="$PROJECT_ROOT/PlinxApp"
source "$PROJECT_ROOT/scripts/build_environment.sh"
source "$PROJECT_ROOT/scripts/sim_destination.sh"

# Configuration
COMPILE_ONLY=false
if [ "${1:-}" = "--compile-only" ] || [ "${1:-}" = "--build-only" ]; then
    COMPILE_ONLY=true
    DEVICE_NAME="${2:-generic}"
else
    DEVICE_NAME="${1:-Apple TV}"
fi
SCHEME="Plinx-tvOS"
DERIVED_DATA_PATH="${PLINX_SIM_ATV_DERIVED_DATA_PATH:-$PLINX_XCODE_DERIVED_DATA_PATH}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📺 Plinx Apple TV Simulator Build & Run"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Device : $DEVICE_NAME"
echo "Scheme : $SCHEME"
if [ "$COMPILE_ONLY" = true ]; then
    echo "Mode   : compile only"
fi
echo ""

# Step 1: Determine destination
echo "📡 Determining destination..."
if [ "$DEVICE_NAME" = "generic" ]; then
    if [ "$COMPILE_ONLY" = true ]; then
        echo "→ using generic tvOS destination"
        DEST="generic/platform=tvOS"
    else
        echo "→ using generic tvOS Simulator destination"
        DEST="generic/platform=tvOS Simulator"
    fi
    UDID=""
else
    if select_simulator_destination "$DEVICE_NAME" "tvOS"; then
        DEST="$SIM_DESTINATION"
        UDID="$SIM_UDID"
        if [ "$SIM_NAME" = "$DEVICE_NAME" ]; then
            echo "✓ Found: $SIM_NAME ($UDID)"
        else
            echo "⚠️  Exact simulator '$DEVICE_NAME' not found. Using '$SIM_NAME' ($UDID) instead."
        fi
    elif [ "$COMPILE_ONLY" = true ]; then
        echo "⚠️  Simulator '$DEVICE_NAME' not found. Falling back to generic tvOS compile destination."
        DEST="generic/platform=tvOS"
        UDID=""
    else
        echo "❌ Simulator '$DEVICE_NAME' not found."
        echo ""
        echo "Available Apple TV devices:"
        xcrun simctl list devices available | grep -i "apple tv" || echo "  (none found — install tvOS simulator runtime in Xcode)"
        exit 1
    fi
fi

echo ""

# Step 2: Boot simulator if not running
if [ -n "$UDID" ]; then
    echo "🔌 Checking simulator status..."
    STATUS="$SIM_STATUS"

    if [ "$STATUS" != "Booted" ]; then
        echo "⏳ Booting simulator..."
        xcrun simctl boot "$UDID"
        xcrun simctl bootstatus "$UDID" -b
    fi
    echo "✓ Simulator is running"
    echo ""
fi

# Step 3: Generate Plinx.xcodeproj
echo "⚙️  Generating Xcode project..."
cd "$PLINX_APP_DIR"
XGEN_LOG="/tmp/plinx_xcodegen_atv.log"
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

# Step 4: Build
echo "🔨 Building $SCHEME..."
BUILD_LOG="/tmp/plinx_build_atv.log"
echo "→ Streaming full xcodebuild output (log: $BUILD_LOG)"
BUILD_SETTINGS=()
if [ "$COMPILE_ONLY" = true ]; then
    BUILD_SETTINGS+=(CODE_SIGNING_ALLOWED=NO)
fi
set +e
xcodebuild build \
    -project Plinx.xcodeproj \
    -scheme "$SCHEME" \
    -destination "$DEST" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "${BUILD_SETTINGS[@]}" \
    2>&1 | tee "$BUILD_LOG"

BUILD_STATUS=${PIPESTATUS[0]}
set -e

if [ "$BUILD_STATUS" -ne 0 ]; then
    echo ""
    echo "❌ Build failed. Full log: $BUILD_LOG"
    echo ""
    echo "── Compiler errors ─────────────────────────────────────────────────"
    grep -E "^.*error:.*$" "$BUILD_LOG" | grep -v "^note:" | head -40 || true
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    echo "💡 The tvOS target is release-supported; treat compiler errors as"
    echo "   regressions and inspect the full build log above."
    exit 1
fi

echo "✓ Build succeeded"
echo ""

if [ "$COMPILE_ONLY" = true ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓ Plinx-tvOS compile-only build succeeded"
    echo "   Build log : $BUILD_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
fi

# Step 5: Locate built .app
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-appletvsimulator/Plinx.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Could not find built Plinx.app at: $APP_PATH"
    exit 1
fi

echo "📦 App location: $APP_PATH"
echo ""

BUNDLE_ID=$(defaults read "$APP_PATH/Info" CFBundleIdentifier 2>/dev/null || true)
if [ -z "$BUNDLE_ID" ]; then
    echo "❌ Could not read bundle identifier from built app"
    exit 1
fi

echo "Bundle ID: $BUNDLE_ID"
echo ""

# Step 6: Install
echo "🧹 Uninstalling previous version..."
if [ -n "$UDID" ]; then
    xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
fi

echo "📥 Installing app..."
xcrun simctl install "$UDID" "$APP_PATH"
echo "✓ App installed"
echo ""

# Step 7: Launch
echo "▶️  Launching app..."
xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Plinx is running on $DEVICE_NAME"
echo "   Build log : $BUILD_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
