#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YOUTARR_URL="${PLINX_YOUTARR_URL:-http://127.0.0.1:3087}"
KEYCHAIN_SERVICE="${PLINX_YOUTARR_KEYCHAIN_SERVICE:-com.bballdavis.plinx.integration-test}"
KEYCHAIN_ACCOUNT="${PLINX_YOUTARR_KEYCHAIN_ACCOUNT:-plinx.youtarr.apiKey}"
MAX_TV_RATING="${PLINX_YOUTARR_MAX_TV_RATING:-TV-Y}"
MAIN_TAB_ENABLED="${PLINX_YOUTARR_LIVE_MAIN_TAB:-0}"
WRITE_ENABLED=0

if [[ "${1:-}" == "--write" ]]; then
  WRITE_ENABLED=1
fi

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
