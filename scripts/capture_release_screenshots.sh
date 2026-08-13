#!/usr/bin/env bash
# Local-only capture for a dedicated, curated Plex release account.
#
# This intentionally does not share the fixture service or public screenshot
# directory. It is interactive because the release owner must visually approve
# every private staging frame before any later promotion.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/test_credentials.sh"
PROJECT_PATH="$REPO_ROOT/PlinxApp/Plinx.xcodeproj"
BUNDLE_ID="com.bballdavis.plinx"
PLATFORM=""
CREDENTIALS_FILE=""
SELECTION_FILE=""
OUTPUT_ROOT=""
DERIVED_DATA="${PLINX_RELEASE_SCREENSHOT_DERIVED_DATA:-/tmp/plinx-release-screenshots-derived}"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/plinx-release-screenshots.XXXXXX")"
CREATED_DEVICES=()
CAPTURE_LOCALE=""
MAXIMUM_MOVIE_RATING=""
MAXIMUM_TV_RATING=""
DETAIL_RATING_KEY=""
PLAYBACK_RATING_KEY=""
SEARCH_QUERY=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/capture_release_screenshots.sh \
    --platform ios|tvos|all \
    --credentials-file test_creds.yaml \
    --selection-file screenshot_capture.yaml \
    --output /absolute/private/staging/path

The output must be outside this repository. This command only captures to a
private staging directory; it never writes public App Store or documentation
assets. It requires a dedicated curated Plex server and human review.
USAGE
}

fail() {
  echo "release screenshot capture failed: $1" >&2
  exit 1
}

cleanup() {
  local device
  for device in "${CREATED_DEVICES[@]:-}"; do
    xcrun simctl delete "$device" >/dev/null 2>&1 || true
  done
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

is_ci() {
  [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" || "${XCODE_CLOUD:-}" == "true" || "${BUILD_ID:-}" != "" ]]
}

require_absolute_safe_output() {
  [[ "$OUTPUT_ROOT" == /* ]] || fail "--output must be an absolute path"
  local resolved_root resolved_output public_root
  resolved_root="$(cd "$REPO_ROOT" && pwd -P)"
  mkdir -p "$OUTPUT_ROOT"
  resolved_output="$(cd "$OUTPUT_ROOT" && pwd -P)"
  public_root="$resolved_root/screenshots"
  [[ "$resolved_output" != "$resolved_root" && "$resolved_output" != "$resolved_root"/* ]] \
    || fail "--output must be outside the repository"
  [[ "$resolved_output" != "$public_root" && "$resolved_output" != "$public_root"/* ]] \
    || fail "--output must not target public screenshot paths"
  [[ -z "$(find "$resolved_output" -mindepth 1 -maxdepth 1 -print -quit)" ]] \
    || fail "--output must be an empty staging directory"
  OUTPUT_ROOT="$resolved_output"
}

load_credentials() {
  load_plinx_test_credentials "$CREDENTIALS_FILE" \
    || fail "credentials file must contain a server URL and token"
}

create_device() {
  local label="$1"
  local device_type="$2"
  local runtime_var="$3"
  local runtime="${!runtime_var:-}"
  local id
  if [[ -n "$runtime" ]]; then
    id="$(xcrun simctl create "Plinx Release Capture ${label} $$" "$device_type" "$runtime")"
  else
    id="$(xcrun simctl create "Plinx Release Capture ${label} $$" "$device_type")"
  fi
  CREATED_DEVICES+=("$id")
  xcrun simctl boot "$id" >/dev/null
  xcrun simctl bootstatus "$id" -b >/dev/null
  xcrun simctl status_bar "$id" override --time "9:41" --batteryState charged \
    --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true
  CREATED_DEVICE_ID="$id"
}

set_capture_policy() {
  local device="$1"
  local movie_rating="$2"
  local tv_rating="$3"
  # These are non-secret, capture-only preferences on a simulator created by
  # this script and deleted in cleanup. Credentials are never written to defaults.
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" plinx.maxMovieRating -string "$movie_rating"
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" plinx.maxTVRating -string "$tv_rating"
  xcrun simctl spawn "$device" defaults write "$BUNDLE_ID" plinx.excludeUnrated -bool true
}

build_app() {
  local scheme="$1"
  local destination="$2"
  bash "$REPO_ROOT/scripts/generate_xcodeproj.sh" >"$TEMP_ROOT/xcodegen.log" 2>&1
  xcodebuild build -project "$PROJECT_PATH" -scheme "$scheme" -destination "$destination" \
    -configuration Debug -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO -quiet
}

app_path_for() {
  local platform="$1"
  case "$platform" in
    ios) printf '%s' "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Plinx.app" ;;
    tvos) printf '%s' "$DERIVED_DATA/Build/Products/Debug-appletvsimulator/Plinx.app" ;;
  esac
}

launch_live_app() {
  local device="$1"
  local landscape="$2"
  local screen_override="${3:-}"
  xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  local language="${CAPTURE_LOCALE%%_*}"
  local -a arguments=("--ui-testing" "--release-screenshot-capture" "--disable-animations" "-AppleLanguages" "($language)" "-AppleLocale" "$CAPTURE_LOCALE")
  [[ "$landscape" == "1" ]] && arguments+=("--release-screenshot-landscape")
  SIMCTL_CHILD_PLINX_UI_TEST_MODE=live \
  SIMCTL_CHILD_PLINX_UI_TEST_SCREEN="$screen_override" \
  SIMCTL_CHILD_PLINX_PLEX_SERVER_URL="$PLINX_PLEX_SERVER_URL" \
  SIMCTL_CHILD_PLINX_PLEX_TOKEN="$PLINX_PLEX_TOKEN" \
  SIMCTL_CHILD_PLINX_RELEASE_CAPTURE_DETAIL_RATING_KEY="$DETAIL_RATING_KEY" \
  SIMCTL_CHILD_PLINX_RELEASE_CAPTURE_PLAYBACK_RATING_KEY="$PLAYBACK_RATING_KEY" \
  SIMCTL_CHILD_PLINX_RELEASE_CAPTURE_SEARCH_QUERY="$SEARCH_QUERY" \
    xcrun simctl launch "$device" "$BUNDLE_ID" "${arguments[@]}" >/dev/null
}

capture_frame() {
  local device="$1"
  local destination="$2"
  local rotate="$3"
  local raw="$TEMP_ROOT/$(basename "$destination" .png).raw.png"
  xcrun simctl io "$device" screenshot "$raw" >/dev/null
  "$REPO_ROOT/scripts/flatten_screenshot_alpha.sh" "$raw" "$destination" >/dev/null
  [[ "$rotate" == "1" ]] && sips -r -90 "$destination" >/dev/null
  python3 "$REPO_ROOT/scripts/strip_png_metadata.py" "$destination"
}

capture_interactively() {
  local device="$1"
  local destination_dir="$2"
  local rotate="$3"
  shift 3
  local -a screens=("$@")
  mkdir -p "$destination_dir"
  launch_live_app "$device" "$rotate"
  echo "Live app launched on an ephemeral simulator. Navigate only through the curated capture account."
  local screen
  for screen in "${screens[@]}"; do
    read -r -p "Review the ${screen#??-} screen on the simulator, then press Return to stage it (Ctrl-C aborts): "
    capture_frame "$device" "$destination_dir/$screen.png" "$rotate"
  done
}

capture_production_screen() {
  local device="$1"
  local destination="$2"
  local rotate="$3"
  local screen_override="$4"
  local label="$5"
  launch_live_app "$device" "$rotate" "$screen_override"
  read -r -p "Review the $label production screen on the simulator, then press Return to stage it (Ctrl-C aborts): "
  capture_frame "$device" "$destination" "$rotate"
}

capture_ios() {
  local iphone ipad app_path
  create_device "iPhone" "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max" "PLINX_RELEASE_IOS_RUNTIME"
  iphone="$CREATED_DEVICE_ID"
  create_device "iPad" "com.apple.CoreSimulator.SimDeviceType.iPad-Air-13-inch-M4" "PLINX_RELEASE_IOS_RUNTIME"
  ipad="$CREATED_DEVICE_ID"
  build_app "Plinx-iOS" "platform=iOS Simulator,id=$iphone"
  app_path="$(app_path_for ios)"
  [[ -d "$app_path" ]] || fail "iOS app build output is missing"
  xcrun simctl install "$iphone" "$app_path"
  xcrun simctl install "$ipad" "$app_path"
  set_capture_policy "$iphone" "$MAXIMUM_MOVIE_RATING" "$MAXIMUM_TV_RATING"
  set_capture_policy "$ipad" "$MAXIMUM_MOVIE_RATING" "$MAXIMUM_TV_RATING"
  mkdir -p "$OUTPUT_ROOT/iphone-6.9" "$OUTPUT_ROOT/ipad-13"
  capture_production_screen "$iphone" "$OUTPUT_ROOT/iphone-6.9/01-loading.png" 0 "appHydrating" "loading"
  capture_production_screen "$iphone" "$OUTPUT_ROOT/iphone-6.9/02-connect.png" 0 "signIn" "connect"
  capture_interactively "$iphone" "$OUTPUT_ROOT/iphone-6.9" 0 "03-home" "04-media-detail"
  capture_production_screen "$iphone" "$OUTPUT_ROOT/iphone-6.9/05-settings.png" 0 "settings" "settings"
  capture_production_screen "$iphone" "$OUTPUT_ROOT/iphone-6.9/06-parental-gate.png" 0 "parentalGate" "parental gate"
  capture_interactively "$iphone" "$OUTPUT_ROOT/iphone-6.9" 0 "07-library-browse"

  capture_production_screen "$ipad" "$OUTPUT_ROOT/ipad-13/01-loading.png" 1 "appHydrating" "loading"
  capture_production_screen "$ipad" "$OUTPUT_ROOT/ipad-13/02-connect.png" 1 "signIn" "connect"
  capture_interactively "$ipad" "$OUTPUT_ROOT/ipad-13" 1 "03-home" "04-media-detail"
  capture_production_screen "$ipad" "$OUTPUT_ROOT/ipad-13/05-settings.png" 1 "settings" "settings"
  capture_production_screen "$ipad" "$OUTPUT_ROOT/ipad-13/06-parental-gate.png" 1 "parentalGate" "parental gate"
  capture_interactively "$ipad" "$OUTPUT_ROOT/ipad-13" 1 "07-library-browse"
}

capture_tvos() {
  local device app_path
  create_device "AppleTV" "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K" "PLINX_RELEASE_TVOS_RUNTIME"
  device="$CREATED_DEVICE_ID"
  build_app "Plinx-tvOS" "platform=tvOS Simulator,id=$device"
  app_path="$(app_path_for tvos)"
  [[ -d "$app_path" ]] || fail "tvOS app build output is missing"
  xcrun simctl install "$device" "$app_path"
  set_capture_policy "$device" "$MAXIMUM_MOVIE_RATING" "$MAXIMUM_TV_RATING"
  mkdir -p "$OUTPUT_ROOT/tvos-4k"
  local -a live_screens=("01-home" "02-library-root" "03-library-browse" "04-media-detail" "05-search" "06-player-controls")
  capture_interactively "$device" "$OUTPUT_ROOT/tvos-4k" 0 "${live_screens[@]}"
  capture_production_screen "$device" "$OUTPUT_ROOT/tvos-4k/07-parental-gate.png" 0 "parentalGate" "parental gate"
  capture_production_screen "$device" "$OUTPUT_ROOT/tvos-4k/08-content-settings.png" 0 "settings" "content-only settings"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    --credentials-file) CREDENTIALS_FILE="${2:-}"; shift 2 ;;
    --selection-file) SELECTION_FILE="${2:-}"; shift 2 ;;
    --output) OUTPUT_ROOT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "unknown argument: $1" ;;
  esac
done

[[ "$PLATFORM" == "ios" || "$PLATFORM" == "tvos" || "$PLATFORM" == "all" ]] || fail "--platform must be ios, tvos, or all"
[[ -n "$CREDENTIALS_FILE" && -n "$SELECTION_FILE" && -n "$OUTPUT_ROOT" ]] || { usage; fail "all required arguments are needed"; }
is_ci && fail "release screenshot capture is local-only and refuses CI"
require_absolute_safe_output
python3 "$REPO_ROOT/scripts/release_screenshot_preflight.py" --selection "$SELECTION_FILE" --credentials "$CREDENTIALS_FILE" --verify-live
load_credentials
CAPTURE_LOCALE="$(python3 "$REPO_ROOT/scripts/release_screenshot_preflight.py" --selection "$SELECTION_FILE" --print-value locale)"
MAXIMUM_MOVIE_RATING="$(python3 "$REPO_ROOT/scripts/release_screenshot_preflight.py" --selection "$SELECTION_FILE" --print-value maximum_movie_rating)"
MAXIMUM_TV_RATING="$(python3 "$REPO_ROOT/scripts/release_screenshot_preflight.py" --selection "$SELECTION_FILE" --print-value maximum_tv_rating)"
DETAIL_RATING_KEY="$(python3 "$REPO_ROOT/scripts/release_screenshot_preflight.py" --selection "$SELECTION_FILE" --print-value detail_rating_key)"
PLAYBACK_RATING_KEY="$(python3 "$REPO_ROOT/scripts/release_screenshot_preflight.py" --selection "$SELECTION_FILE" --print-value playback_rating_key)"
SEARCH_QUERY="$(python3 "$REPO_ROOT/scripts/release_screenshot_preflight.py" --selection "$SELECTION_FILE" --print-value search_query)"

case "$PLATFORM" in
  ios) capture_ios; "$REPO_ROOT/scripts/tests/validate_app_store_screenshots.sh" "$OUTPUT_ROOT" ;;
  tvos) capture_tvos; "$REPO_ROOT/scripts/tests/validate_app_store_screenshots.sh" --tvos-only "$OUTPUT_ROOT" ;;
  all) capture_ios; capture_tvos; "$REPO_ROOT/scripts/tests/validate_app_store_screenshots.sh" --require-tvos "$OUTPUT_ROOT" ;;
esac

echo "Private staged release screenshots passed validation. Human curation approval is required before any promotion."
