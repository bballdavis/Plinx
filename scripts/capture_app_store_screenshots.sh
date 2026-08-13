#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$REPO_ROOT/PlinxApp/Plinx.xcodeproj"
SCHEME="Plinx-iOS"
BUNDLE_ID="com.bballdavis.plinx"
FIXTURE_PORT="${PLINX_FIXTURE_PORT:-8765}"
FIXTURE_URL="http://127.0.0.1:$FIXTURE_PORT"
OUTPUT_ROOT="$REPO_ROOT/screenshots/fixtures/app-store"
DERIVED_DATA="${PLINX_SCREENSHOT_DERIVED_DATA:-/tmp/plinx-app-store-derived}"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/plinx-app-store.XXXXXX")"
SERVER_PID=""
CAPTURE_LANDSCAPE=0
CAPTURE_ONLY="${PLINX_SCREENSHOT_CAPTURE_ONLY:-all}"

if [[ "${1:-}" == "--only" ]]; then
  CAPTURE_ONLY="${2:?Pass a comma-separated list after --only}"
  shift 2
fi
if [[ "$#" -ne 0 ]]; then
  echo "Usage: $0 [--only home,youtarr]" >&2
  exit 2
fi

capture_requested() {
  local screen="$1"
  [[ ",$CAPTURE_ONLY," == *,all,* || ",$CAPTURE_ONLY," == *",$screen,"* ]]
}

validate_capture_selection() {
  local selection=",${CAPTURE_ONLY},"
  local valid
  for valid in all loading connect home more-info settings parent-lock youtarr; do
    selection="${selection//,$valid,/,}"
  done
  if [[ "$selection" != "," ]]; then
    echo "Unknown capture selection: $CAPTURE_ONLY" >&2
    exit 2
  fi
}

run_best_effort_with_timeout() {
  local timeout_seconds="$1"
  local label="$2"
  shift 2
  "$@" &
  local command_pid=$!
  local attempts=$((timeout_seconds * 4))
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if ! kill -0 "$command_pid" >/dev/null 2>&1; then
      wait "$command_pid" || true
      return 0
    fi
    sleep 0.25
  done
  kill "$command_pid" >/dev/null 2>&1 || true
  wait "$command_pid" >/dev/null 2>&1 || true
  echo "Warning: timed out while setting $label; continuing." >&2
}

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
  local is_ready=0
  for attempt in {1..120}; do
    if xcrun simctl list devices \
      | grep -F "$device_id" \
      | grep -q "(Booted)"; then
      is_ready=1
      break
    fi
    sleep 1
  done
  if [[ "$is_ready" -ne 1 ]]; then
    echo "Simulator $device_id did not reach the booted state within 120 seconds." >&2
    exit 1
  fi
  sleep 2
  # The app forces dark appearance. The status override is presentation-only
  # and must not block an otherwise ready simulator.
  run_best_effort_with_timeout 10 "status bar" \
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
    # simctl returns the iPad display in its native portrait framebuffer even
    # after UIKit has laid out the app in landscape. Rotate the captured
    # framebuffer counter-clockwise to produce the App Store landscape bitmap.
    sips -r -90 "$destination" >/dev/null
  fi
  python3 "$REPO_ROOT/scripts/strip_png_metadata.py" "$destination"
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
  if capture_requested "all"; then
    rm -f "$output_dir"/*.png
  fi

  xcrun simctl uninstall "$device_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$device_id" "$APP_PATH"
  set_review_defaults "$device_id"

  if capture_requested "loading"; then
    capture_loading "$device_id" "$output_dir/01-loading.png"
  fi

  if capture_requested "connect"; then
    launch_fixture_app "$device_id" "signIn"
    sleep 6
    capture_opaque "$device_id" "$output_dir/02-connect.png"
  fi

  if capture_requested "home"; then
    # Warm the live session and fixture artwork cache before the retained frame.
    launch_fixture_app "$device_id"
    sleep 10
    launch_fixture_app "$device_id"
    sleep 12
    capture_opaque "$device_id" "$output_dir/03-home.png"
  fi

  if capture_requested "more-info"; then
    launch_fixture_app "$device_id" "appStoreMediaDetail"
    sleep 8
    capture_opaque "$device_id" "$output_dir/04-more-info.png"
  fi

  if capture_requested "settings"; then
    launch_fixture_app "$device_id" "settings"
    sleep 10
    capture_opaque "$device_id" "$output_dir/05-settings.png"
  fi

  if capture_requested "parent-lock"; then
    launch_fixture_app "$device_id" "parentalGate"
    sleep 10
    capture_opaque "$device_id" "$output_dir/06-parent-lock.png"
  fi

  if capture_requested "youtarr"; then
    launch_fixture_app "$device_id" "youtarrExploreLive"
    sleep 6
    capture_opaque "$device_id" "$output_dir/07-youtarr.png"
  fi
}

IPHONE_ID="$(find_device "iPhone 17 Pro Max")"
IPAD_ID="$(find_device "iPad Air 13-inch (M4)")"

if [[ -z "$IPHONE_ID" || -z "$IPAD_ID" ]]; then
  echo "Required iPhone 17 Pro Max and iPad Air 13-inch (M4) simulators are unavailable." >&2
  exit 1
fi

validate_capture_selection
python3 "$REPO_ROOT/scripts/app_store_fixture_server.py" --validate

python3 "$REPO_ROOT/scripts/app_store_fixture_server.py" \
  --port "$FIXTURE_PORT" >"$TEMP_ROOT/fixture-server.log" 2>&1 &
SERVER_PID=$!

for attempt in {1..30}; do
  if curl -fsS "$FIXTURE_URL/healthz" >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    cat "$TEMP_ROOT/fixture-server.log" >&2
    exit 1
  fi
  sleep 0.2
done

bash "$REPO_ROOT/scripts/generate_xcodeproj.sh" \
  >"$TEMP_ROOT/xcodegen.log" 2>&1

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
echo "Captured deterministic screenshot fixtures in $OUTPUT_ROOT"
