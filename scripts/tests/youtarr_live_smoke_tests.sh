#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YOUTARR_URL="${PLINX_YOUTARR_URL:-}"
KEYCHAIN_SERVICE="${PLINX_YOUTARR_KEYCHAIN_SERVICE:-com.bballdavis.plinx.integration-test}"
KEYCHAIN_ACCOUNT="${PLINX_YOUTARR_KEYCHAIN_ACCOUNT:-plinx.youtarr.apiKey}"
MAX_TV_RATING="${PLINX_YOUTARR_MAX_TV_RATING:-TV-Y}"
MAIN_TAB_ENABLED="${PLINX_YOUTARR_LIVE_MAIN_TAB:-0}"
WRITE_ENABLED=0

case "${1:-}" in
  "") ;;
  --write) WRITE_ENABLED=1 ;;
  *) echo "Usage: $0 [--write]" >&2; exit 2 ;;
esac

if [[ -n "${PLINX_YOUTARR_API_KEY:-}" ]]; then
  API_KEY="$PLINX_YOUTARR_API_KEY"
else
  API_KEY="$(security find-generic-password \
    -s "$KEYCHAIN_SERVICE" \
    -a "$KEYCHAIN_ACCOUNT" \
    -w 2>/dev/null || true)"
fi

if [[ -z "$API_KEY" ]]; then
  echo "Missing live Youtarr API key in the environment or macOS Keychain." >&2
  exit 1
fi

SIMULATOR_ID="${PLINX_YOUTARR_SIMULATOR_ID:-}"
if [[ -z "$SIMULATOR_ID" ]]; then
  SIMULATOR_ID="$(python3 - <<'PY'
import json
import subprocess

data = json.loads(
    subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        text=True,
    )
)
preferred = ("iPhone 17 Pro Max", "iPhone 17 Pro", "iPhone 17")
devices = [
    device
    for runtime, values in data["devices"].items()
    if "iOS" in runtime
    for device in values
    if device.get("isAvailable", True) and device.get("name", "").startswith("iPhone")
]
for name in preferred:
    for device in devices:
        if device["name"] == name:
            print(device["udid"])
            raise SystemExit
if devices:
    print(devices[0]["udid"])
PY
  )"
fi

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "No available iPhone simulator was found." >&2
  exit 1
fi

if [[ -z "$YOUTARR_URL" ]]; then
  APP_DATA_CONTAINER="$(
    xcrun simctl get_app_container "$SIMULATOR_ID" com.bballdavis.plinx data 2>/dev/null || true
  )"
  if [[ -n "$APP_DATA_CONTAINER" ]]; then
    PREFERENCES="$APP_DATA_CONTAINER/Library/Preferences/com.bballdavis.plinx.plist"
    if [[ -f "$PREFERENCES" ]]; then
      YOUTARR_URL="$(
        /usr/libexec/PlistBuddy \
          -c 'Print :plinx.youtarr.baseURL' \
          "$PREFERENCES" 2>/dev/null || true
      )"
    fi
  fi
fi

if [[ -z "$YOUTARR_URL" ]]; then
  echo "Set PLINX_YOUTARR_URL or select a simulator with saved Youtarr configuration." >&2
  exit 1
fi

PREFLIGHT_BASE_URL="${YOUTARR_URL%/}"
PREFLIGHT_BASE_URL="${PREFLIGHT_BASE_URL%/external-api/v1}"
preflight_status() {
  curl --silent --show-error \
    --output /dev/null \
    --write-out '%{http_code}' \
    --max-time 10 \
    --header "x-api-key: $API_KEY" \
    "$1" || true
}

preflight_total() {
  curl --silent --show-error \
    --max-time 10 \
    --header "x-api-key: $API_KEY" \
    "$1" | python3 -c '
import json
import sys
print(json.load(sys.stdin)["pagination"]["total"])
'
}

PREFLIGHT_STATUS="$(preflight_status "$PREFLIGHT_BASE_URL/external-api/v1/capabilities")"
case "$PREFLIGHT_STATUS" in
  2??) ;;
  401|403)
    echo "Youtarr preflight rejected the dedicated API key (HTTP $PREFLIGHT_STATUS)." >&2
    echo "A parent must replace or reconfigure the integration-test key." >&2
    exit 1
    ;;
  000)
    echo "Youtarr preflight could not reach the configured endpoint." >&2
    exit 1
    ;;
  *)
    echo "Youtarr preflight failed (HTTP $PREFLIGHT_STATUS)." >&2
    exit 1
    ;;
esac

CHANNELS_ENDPOINT="$PREFLIGHT_BASE_URL/external-api/v1/channels?page=1&pageSize=1"
VIDEOS_ENDPOINT="$PREFLIGHT_BASE_URL/external-api/v1/videos?pageSize=1&status=requestable"
for endpoint_name in CHANNELS VIDEOS; do
  endpoint_variable="${endpoint_name}_ENDPOINT"
  endpoint="${!endpoint_variable}"
  status="$(preflight_status "$endpoint")"
  case "$status" in
    2??) ;;
    401|403)
      echo "Youtarr preflight rejected the dedicated API key while checking ${endpoint_name,,} (HTTP $status)." >&2
      exit 1
      ;;
    000)
      echo "Youtarr preflight could not reach ${endpoint_name,,}." >&2
      exit 1
      ;;
    *)
      echo "Youtarr preflight failed while checking ${endpoint_name,,} (HTTP $status)." >&2
      exit 1
      ;;
  esac
done

CHANNELS_TOTAL="$(preflight_total "$CHANNELS_ENDPOINT")" || {
  echo "Youtarr preflight could not read the approved-channel count." >&2
  exit 1
}
VIDEOS_TOTAL="$(preflight_total "$VIDEOS_ENDPOINT")" || {
  echo "Youtarr preflight could not read the requestable-video count." >&2
  exit 1
}
if [[ "$CHANNELS_TOTAL" == "0" ]]; then
  echo "Youtarr preflight found zero approved channels for the dedicated API key." >&2
  exit 1
fi
if [[ "$VIDEOS_TOTAL" == "0" ]]; then
  echo "Youtarr preflight found zero requestable videos for the dedicated API key." >&2
  exit 1
fi
echo "Youtarr preflight passed (approved channels: $CHANNELS_TOTAL; requestable videos: $VIDEOS_TOTAL)."

xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b >/dev/null

set_simulator_value() {
  xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv "$1" "$2"
}

unset_simulator_value() {
  xcrun simctl spawn "$SIMULATOR_ID" launchctl unsetenv "$1" >/dev/null 2>&1 || true
}

cleanup() {
  for key in \
    PLINX_YOUTARR_LIVE \
    PLINX_YOUTARR_URL \
    PLINX_YOUTARR_API_KEY \
    PLINX_YOUTARR_MAX_TV_RATING \
    PLINX_YOUTARR_LIVE_MAIN_TAB \
    PLINX_YOUTARR_LIVE_WRITE; do
    unset_simulator_value "$key"
  done
}
trap cleanup EXIT

set_simulator_value PLINX_YOUTARR_LIVE 1
set_simulator_value PLINX_YOUTARR_URL "$YOUTARR_URL"
set_simulator_value PLINX_YOUTARR_API_KEY "$API_KEY"
set_simulator_value PLINX_YOUTARR_MAX_TV_RATING "$MAX_TV_RATING"
set_simulator_value PLINX_YOUTARR_LIVE_MAIN_TAB "$MAIN_TAB_ENABLED"
set_simulator_value PLINX_YOUTARR_LIVE_WRITE "$WRITE_ENABLED"

bash "$PROJECT_ROOT/scripts/generate_xcodeproj.sh" >/tmp/plinx_youtarr_xcodegen.log
git -C "$PROJECT_ROOT" diff --quiet -- PlinxApp/Plinx.xcodeproj || {
  echo "Xcode project generation changed PlinxApp/Plinx.xcodeproj." >&2
  echo "Regenerate and commit the project before running the live gate." >&2
  exit 1
}

RESULT_BUNDLE="/tmp/Plinx_youtarr_live_$(date +%Y%m%d_%H%M%S).xcresult"

xcodebuild test \
  -project "$PROJECT_ROOT/PlinxApp/Plinx.xcodeproj" \
  -scheme Plinx-iOS \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:Plinx-iOS-UnitTests/YoutarrLiveSmokeTests \
  -only-testing:Plinx-iOS-UITests/YoutarrLiveSmokeUITests

echo "Live Youtarr smoke tests passed."
echo "Result bundle: $RESULT_BUNDLE"
