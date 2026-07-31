#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$REPO_ROOT/PlinxApp/Plinx.xcodeproj"
SCHEME="Plinx-iOS"
BUNDLE_ID="com.bballdavis.plinx"
FIXTURE_PORT="${PLINX_FIXTURE_PORT:-8765}"
FIXTURE_URL="http://127.0.0.1:$FIXTURE_PORT"
OUTPUT_ROOT="$REPO_ROOT/screenshots/app-store"
DERIVED_DATA="${PLINX_SCREENSHOT_DERIVED_DATA:-/tmp/plinx-app-store-derived}"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/plinx-app-store.XXXXXX")"
SERVER_PID=""
CAPTURE_LANDSCAPE=0

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

find_device() {
  local name="$1"
  xcrun simctl list devices available \
    | sed -n "s/^[[:space:]]*${name} (\\([0-9A-F-]*\\)).*/\\1/p" \
    | head -n 1
}

boot_device() {
  local device_id="$1"
  xcrun simctl boot "$device_id" >/dev/null 2>&1 || true
  open -ga Simulator
  xcrun simctl bootstatus "$device_id" -b
  xcrun simctl ui "$device_id" appearance dark
  xcrun simctl status_bar "$device_id" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --wifiBars 3 \
    --cellularBars 4
}

set_review_defaults() {
  local device_id="$1"
  xcrun simctl spawn "$device_id" defaults write "$BUNDLE_ID" \
    plinx.maxMovieRating -string "PG"
  xcrun simctl spawn "$device_id" defaults write "$BUNDLE_ID" \
    plinx.maxTVRating -string "TV-PG"
  xcrun simctl spawn "$device_id" defaults write "$BUNDLE_ID" \
    plinx.excludeUnrated -bool true
}

launch_fixture_app() {
  local device_id="$1"
  local screen="${2:-}"
  local disable_animations="${3:-1}"
  xcrun simctl terminate "$device_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 1

  local -a launch_args=("--ui-testing")
  if [[ "$disable_animations" -eq 1 ]]; then
    launch_args+=("--disable-animations")
  fi
  if [[ "$CAPTURE_LANDSCAPE" -eq 1 ]]; then
    launch_args+=("--app-store-landscape")
  fi
  if [[ -n "$screen" ]]; then
    launch_args+=("--fixture-screen" "$screen")
  fi
  local plex_mode=""
  if [[ -z "$screen" || "$screen" == "appStoreMediaDetail" ]]; then
    plex_mode="live"
  fi

  SIMCTL_CHILD_PLINX_UI_TEST_MODE="$plex_mode" \
  SIMCTL_CHILD_PLINX_PLEX_TOKEN="fixture-token" \
  SIMCTL_CHILD_PLINX_PLEX_SERVER_URL="$FIXTURE_URL" \
  SIMCTL_CHILD_PLINX_YOUTARR_LIVE="1" \
  SIMCTL_CHILD_PLINX_YOUTARR_URL="$FIXTURE_URL" \
  SIMCTL_CHILD_PLINX_YOUTARR_API_KEY="fixture-key" \
  SIMCTL_CHILD_PLINX_YOUTARR_MAX_TV_RATING="TV-PG" \
  SIMCTL_CHILD_PLINX_UI_TEST_SCREEN="$screen" \
    xcrun simctl launch "$device_id" "$BUNDLE_ID" "${launch_args[@]}" >/dev/null
}

capture_opaque() {
  local device_id="$1"
  local destination="$2"
  local raw="$TEMP_ROOT/$(basename "$destination" .png)-raw.png"
  xcrun simctl io "$device_id" screenshot "$raw" >/dev/null
  "$REPO_ROOT/scripts/flatten_screenshot_alpha.sh" "$raw" "$destination" >/dev/null
  if [[ "$CAPTURE_LANDSCAPE" -eq 1 ]]; then
    sips -r -90 "$destination" >/dev/null
  fi
}

capture_loading() {
  local device_id="$1"
  local destination="$2"
  launch_fixture_app "$device_id" "homeLoading" 0
  sleep 10
  capture_opaque "$device_id" "$destination"
}

capture_device_set() {
  local device_id="$1"
  local output_dir="$2"
  local orientation="$3"
  if [[ "$orientation" == "landscape" ]]; then
    CAPTURE_LANDSCAPE=1
  else
    CAPTURE_LANDSCAPE=0
  fi
  mkdir -p "$output_dir"
  rm -f "$output_dir"/*.png

  xcrun simctl uninstall "$device_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$device_id" "$APP_PATH"
  set_review_defaults "$device_id"

  capture_loading "$device_id" "$output_dir/01-loading.png"

  launch_fixture_app "$device_id" "signIn"
  sleep 6
  capture_opaque "$device_id" "$output_dir/02-connect.png"

  # Warm the live session and fixture artwork cache before the retained frame.
  launch_fixture_app "$device_id"
  sleep 10
  launch_fixture_app "$device_id"
  sleep 12
  capture_opaque "$device_id" "$output_dir/03-home.png"

  launch_fixture_app "$device_id" "appStoreMediaDetail"
  sleep 8
  capture_opaque "$device_id" "$output_dir/04-more-info.png"

  launch_fixture_app "$device_id" "settings"
  sleep 10
  capture_opaque "$device_id" "$output_dir/05-settings.png"

  launch_fixture_app "$device_id" "parentalGate"
  sleep 10
  capture_opaque "$device_id" "$output_dir/06-parent-lock.png"

  launch_fixture_app "$device_id" "youtarrExploreLive"
  sleep 6
  capture_opaque "$device_id" "$output_dir/07-youtarr.png"
}

IPHONE_ID="$(find_device "iPhone 17 Pro Max")"
IPAD_ID="$(find_device "iPad Air 13-inch (M4)")"

if [[ -z "$IPHONE_ID" || -z "$IPAD_ID" ]]; then
  echo "Required iPhone 17 Pro Max and iPad Air 13-inch (M4) simulators are unavailable." >&2
  exit 1
fi

python3 "$REPO_ROOT/scripts/app_store_fixture_server.py" \
  --port "$FIXTURE_PORT" >"$TEMP_ROOT/fixture-server.log" 2>&1 &
SERVER_PID=$!

for attempt in {1..30}; do
  if curl -fsS "$FIXTURE_URL/healthz" >/dev/null; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    cat "$TEMP_ROOT/fixture-server.log" >&2
    exit 1
  fi
  sleep 0.2
done

xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$IPHONE_ID" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Plinx.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

boot_device "$IPHONE_ID"
boot_device "$IPAD_ID"
capture_device_set "$IPHONE_ID" "$OUTPUT_ROOT/iphone-6.9" "portrait"
capture_device_set "$IPAD_ID" "$OUTPUT_ROOT/ipad-13" "landscape"

"$REPO_ROOT/scripts/tests/validate_app_store_screenshots.sh" "$OUTPUT_ROOT"
echo "Captured App Store screenshots in $OUTPUT_ROOT"
