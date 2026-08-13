#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec /bin/bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/build_environment.sh"
source "$PROJECT_ROOT/scripts/test_credentials.sh"

MODE="ios"
if [[ "${1:-}" == "--appletv" || "${1:-}" == "--tvos" ]]; then
  MODE="tvos"
  shift
elif [[ "${1:-}" == "--ios" ]]; then
  MODE="ios"
  shift
fi

CREDENTIALS_FILE="$PROJECT_ROOT/test_creds.yaml"
LOG_PATH="/tmp/plinx_live_library_parity_${MODE}.log"
RESULT_BUNDLE="/tmp/Plinx_live_library_parity_${MODE}.xcresult"
LIVE_DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/plinx-live-parity-derived.XXXXXX")"
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

info() { echo "${BLUE}[info]${NC} $*"; }
warn() { echo "${YELLOW}[warn]${NC} $*"; }
pass() { echo "${GREEN}[pass]${NC} $*"; }
fail() { echo "${RED}[fail]${NC} $*"; }

cleanup() {
  rm -rf "$RESULT_BUNDLE" "$LIVE_DERIVED_DATA"
}
trap cleanup EXIT

discover_appletv_destination() {
  python3 - <<'PY'
import json
import subprocess
import sys

try:
    raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True)
    data = json.loads(raw)
except Exception:
    sys.exit(1)

candidates = []
for runtime, devices in data.get("devices", {}).items():
    if "tvOS" not in runtime:
        continue
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        name = device.get("name", "")
        if "Apple TV" not in name:
            continue
        candidates.append((name, device.get("udid", "")))

# Prefer standard Apple TV devices over 4K variants only when both exist with
# the same runtime; either is fine for these hosted unit tests.
for _, udid in candidates:
    if udid:
        print(f"platform=tvOS Simulator,id={udid}")
        sys.exit(0)

sys.exit(1)
PY
}

discover_ios_destination() {
  python3 - <<'PY'
import json
import subprocess
import sys

preferred_names = (
    "iPhone 17 Pro Max",
    "iPhone 17 Pro",
    "iPhone 17",
    "iPhone 16 Pro Max",
    "iPhone 16 Pro",
    "iPhone 16",
)

try:
    raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True)
    data = json.loads(raw)
except Exception:
    sys.exit(1)

devices = []
for runtime, runtime_devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in runtime_devices:
        if not device.get("isAvailable", True):
            continue
        name = device.get("name", "")
        udid = device.get("udid", "")
        if name.startswith("iPhone") and udid:
            devices.append((name, udid))

for preferred in preferred_names:
    for name, udid in devices:
        if name == preferred:
            print(f"platform=iOS Simulator,id={udid}")
            sys.exit(0)

if devices:
    print(f"platform=iOS Simulator,id={devices[0][1]}")
    sys.exit(0)

sys.exit(1)
PY
}

if [[ "$MODE" == "tvos" ]]; then
  SCHEME="Plinx-tvOS"
  DEFAULT_TVOS_DESTINATION="$(discover_appletv_destination || true)"
  if [[ -z "$DEFAULT_TVOS_DESTINATION" ]]; then
    DEFAULT_TVOS_DESTINATION='platform=tvOS Simulator,name=Apple TV'
  fi
  DESTINATION="${1:-$DEFAULT_TVOS_DESTINATION}"
  TEST_TARGET="${PLINX_TEST_TARGET:-Plinx-tvOS-UnitTests/AppleTVLibraryParityLiveTests}"
  REQUIRED_TEST_CASE="${PLINX_REQUIRED_TEST_CASE:-test_liveAppleTVBrowseParity_otherVideoLibrary_allowsUnratedNoneAgent}"
else
  SCHEME="Plinx-iOS"
  DEFAULT_IOS_DESTINATION="$(discover_ios_destination || true)"
  if [[ -z "$DEFAULT_IOS_DESTINATION" ]]; then
    DEFAULT_IOS_DESTINATION='platform=iOS Simulator,name=iPhone 17'
  fi
  DESTINATION="${1:-$DEFAULT_IOS_DESTINATION}"
  TEST_TARGET="${PLINX_TEST_TARGET:-Plinx-iOS-UnitTests/LibraryFilteringParityLiveTests}"
  REQUIRED_TEST_CASE="${PLINX_REQUIRED_TEST_CASE:-test_liveHomeRecentlyAdded_otherVideoHubVisibleUnderStrictPolicy}"
fi

load_credentials() {
  if ! load_plinx_test_credentials "$CREDENTIALS_FILE"; then
    fail "PLINX_PLEX_SERVER_URL and PLINX_PLEX_TOKEN must be set in test_creds.yaml"
    return 1
  fi
  pass "Credentials loaded"
}

run_tests() {
  info "Generating Xcode project"
  (
    cd "$PROJECT_ROOT/PlinxApp"
    bash "$PROJECT_ROOT/scripts/generate_xcodeproj.sh" >/tmp/plinx_xcodegen_live_parity.log 2>&1
  )

  info "Scheme: $SCHEME"
  info "Mode: $MODE"

  rm -rf "$RESULT_BUNDLE"
  : >"$LOG_PATH"

  info "Running $TEST_TARGET"
  info "Destination: $DESTINATION"

  set +e
  (
    cd "$PROJECT_ROOT"
    xcodebuild test \
      -project PlinxApp/Plinx.xcodeproj \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -derivedDataPath "$LIVE_DERIVED_DATA" \
      -resultBundlePath "$RESULT_BUNDLE" \
      -only-testing:"$TEST_TARGET"
  ) 2>&1 | tee "$LOG_PATH"
  local exit_code=${PIPESTATUS[0]}
  set -e

  if [[ $exit_code -eq 0 ]]; then
    pass "xcodebuild completed successfully"
  else
    fail "xcodebuild failed (exit $exit_code)"
  fi

  local summary
  summary="$(grep -E "Executed [0-9]+ tests" "$LOG_PATH" | tail -1 || true)"
  if [[ -n "$summary" ]]; then
    echo "$summary"
  fi

  if ! grep -q "$REQUIRED_TEST_CASE" "$LOG_PATH"; then
    fail "Required test case '$REQUIRED_TEST_CASE' was not executed"
    echo "Full log: $LOG_PATH"
    return 1
  fi
  pass "Verified required test case ran: $REQUIRED_TEST_CASE"

  if grep -q "with [1-9][0-9]* tests skipped" "$LOG_PATH"; then
    warn "One or more tests were skipped"
  fi

  if [[ $exit_code -ne 0 ]]; then
    echo
    fail "Relevant errors:"
    grep -E "error:|\\*\\* TEST FAILED \\*\\*|Failing tests:" "$LOG_PATH" | tail -30 || true
    echo
    echo "Full log: $LOG_PATH"
    echo "Result bundle: $RESULT_BUNDLE"
    return $exit_code
  fi

  echo "Log: $LOG_PATH"
  echo "Result bundle: $RESULT_BUNDLE"
}

main() {
  load_credentials
  run_tests
}

main "$@"
