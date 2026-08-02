#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YOUTARR_ROOT="${YOUTARR_DIR:-$PROJECT_ROOT/../Youtarr}"
SERVER_LOG="$(mktemp -t plinx-youtarr-contract-server.XXXXXX)"
SERVER_PID=""
SIMULATOR_ID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

[[ -f "$YOUTARR_ROOT/scripts/external-api-contract-server.js" ]] || {
  echo "Missing Youtarr contract server under $YOUTARR_ROOT" >&2
  exit 1
}

bash "$PROJECT_ROOT/scripts/verify_youtarr_contract_fixture.sh" \
  --check \
  --youtarr-dir "$YOUTARR_ROOT"

YOUTARR_CONTRACT_PORT=39087 \
node "$YOUTARR_ROOT/scripts/external-api-contract-server.js" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for _ in {1..100}; do
  if [[ -s "$SERVER_LOG" ]]; then
    SERVER_CONFIGURATION="$(head -n 1 "$SERVER_LOG")"
    if jq -e '.baseURL and .apiKey' >/dev/null 2>&1 <<<"$SERVER_CONFIGURATION"; then
      break
    fi
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "Youtarr contract server exited before becoming ready." >&2
    sed -n '1,80p' "$SERVER_LOG" >&2
    exit 1
  fi
  sleep 0.1
done

SYNTHETIC_URL="$(jq -r '.baseURL // empty' <<<"${SERVER_CONFIGURATION:-}")"
SYNTHETIC_API_KEY="$(jq -r '.apiKey // empty' <<<"${SERVER_CONFIGURATION:-}")"
[[ -n "$SYNTHETIC_URL" && -n "$SYNTHETIC_API_KEY" ]] || {
  echo "Youtarr contract server did not publish a valid configuration." >&2
  exit 1
}

curl --silent --show-error --fail \
  "$SYNTHETIC_URL/__contract/ready" >/dev/null

SIMULATOR_ID="${PLINX_YOUTARR_SIMULATOR_ID:-}"
if [[ -z "$SIMULATOR_ID" ]]; then
  SIMULATOR_ID="$(python3 - <<'PY'
import json
import subprocess

data = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"], text=True
))
preferred = ("Plinx iPhone 17 Pro Max (26.5)", "Plinx iPhone 17 Pro (26.5)", "iPhone 17 Pro Max", "iPhone 17 Pro", "iPhone 17")
devices = [
    device
    for runtime, values in data["devices"].items()
    if "iOS" in runtime
    for device in values
    if device.get("isAvailable", True) and "iPhone" in device.get("name", "")
]
for name in preferred:
    match = next((device for device in devices if device["name"] == name), None)
    if match:
        print(match["udid"])
        raise SystemExit
if devices:
    print(devices[0]["udid"])
PY
  )"
fi
[[ -n "$SIMULATOR_ID" ]] || { echo "No available iPhone simulator was found." >&2; exit 1; }

xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b >/dev/null

RESULT_BUNDLE="${PLINX_YOUTARR_RESULT_BUNDLE:-/tmp/Plinx_youtarr_synthetic_$(date +%Y%m%d_%H%M%S).xcresult}"
DERIVED_DATA="${PLINX_YOUTARR_DERIVED_DATA:-/tmp/Plinx_youtarr_synthetic_derived}"

xcodebuild test \
  -project "$PROJECT_ROOT/PlinxApp/Plinx.xcodeproj" \
  -scheme Plinx-iOS \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:Plinx-iOS-UnitTests/YoutarrContractFixtureTests \
  -only-testing:Plinx-iOS-UnitTests/YoutarrFoundationTests \
  -only-testing:Plinx-iOS-UnitTests/YoutarrExploreTests \
  -only-testing:Plinx-iOS-UnitTests/YoutarrRequestTests \
  -only-testing:Plinx-iOS-UITests/YoutarrExploreOfflineUITests \
  CODE_SIGNING_ALLOWED=NO

echo "Synthetic Youtarr integration tests passed."
echo "Result bundle: $RESULT_BUNDLE"
