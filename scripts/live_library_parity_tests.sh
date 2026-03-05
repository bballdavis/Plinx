#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CREDENTIALS_FILE="$PROJECT_ROOT/test_creds.yaml"
LOG_PATH="/tmp/plinx_live_library_parity.log"
RESULT_BUNDLE="/tmp/Plinx_live_library_parity.xcresult"
DEFAULT_DESTINATION='platform=iOS Simulator,id=881AC958-79D3-476D-A40E-1290AC561623'
DESTINATION="${1:-$DEFAULT_DESTINATION}"
APP_BUNDLE_ID="com.example.plinx"

TEST_TARGET='Plinx-iOS-UnitTests/LibraryFilteringParityLiveTests'
REQUIRED_TEST_CASE='test_liveHomeRecentlyAdded_otherVideoHubVisibleUnderStrictPolicy'

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

info() { echo "${BLUE}[info]${NC} $*"; }
warn() { echo "${YELLOW}[warn]${NC} $*"; }
pass() { echo "${GREEN}[pass]${NC} $*"; }
fail() { echo "${RED}[fail]${NC} $*"; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

strip_quotes() {
  local s="$1"
  if [[ "$s" == \"*\" && "$s" == *\" && ${#s} -ge 2 ]]; then
    s="${s:1:${#s}-2}"
  elif [[ "$s" == \'*\' && ${#s} -ge 2 ]]; then
    s="${s:1:${#s}-2}"
  fi
  printf '%s' "$s"
}

load_credentials() {
  if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    fail "Missing $CREDENTIALS_FILE"
    return 1
  fi

  info "Loading credentials from $CREDENTIALS_FILE"
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    local line key value
    line="$(trim "$raw")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" != *:* ]] && continue

    key="$(trim "${line%%:*}")"
    value="$(trim "${line#*:}")"
    value="$(strip_quotes "$value")"

    if [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
      export "$key=$value"
    fi
  done < "$CREDENTIALS_FILE"

  if [[ -z "${PLINX_PLEX_SERVER_URL:-}" || -z "${PLINX_PLEX_TOKEN:-}" ]]; then
    fail "PLINX_PLEX_SERVER_URL and PLINX_PLEX_TOKEN must be set in test_creds.yaml"
    return 1
  fi

  export SIMCTL_CHILD_PLINX_PLEX_SERVER_URL="$PLINX_PLEX_SERVER_URL"
  export SIMCTL_CHILD_PLINX_PLEX_TOKEN="$PLINX_PLEX_TOKEN"

  pass "Credentials loaded"
}

extract_simulator_id() {
  if [[ "$DESTINATION" =~ id=([^,]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

configure_simulator_defaults() {
  local sim_id
  sim_id="$(extract_simulator_id || true)"
  if [[ -z "$sim_id" ]]; then
    warn "Destination does not include a simulator id; skipping simulator defaults injection"
    return 0
  fi

  info "Booting simulator $sim_id (if needed)"
  xcrun simctl boot "$sim_id" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$sim_id" -b >/dev/null

  info "Writing Plex credentials to simulator defaults for $APP_BUNDLE_ID"
  xcrun simctl spawn "$sim_id" defaults write "$APP_BUNDLE_ID" PLINX_PLEX_SERVER_URL "$PLINX_PLEX_SERVER_URL"
  xcrun simctl spawn "$sim_id" defaults write "$APP_BUNDLE_ID" PLINX_PLEX_TOKEN "$PLINX_PLEX_TOKEN"
}

run_tests() {
  info "Generating Xcode project"
  (
    cd "$PROJECT_ROOT/PlinxApp"
    xcodegen generate >/tmp/plinx_xcodegen_live_parity.log 2>&1
  )

  rm -rf "$RESULT_BUNDLE"
  : >"$LOG_PATH"

  info "Running $TEST_TARGET"
  info "Destination: $DESTINATION"

  set +e
  (
    cd "$PROJECT_ROOT"
    xcodebuild test \
      -project PlinxApp/Plinx.xcodeproj \
      -scheme Plinx-iOS \
      -destination "$DESTINATION" \
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
    grep -E "error:|\\*\\* TEST FAILED \\*\\*" "$LOG_PATH" | tail -20 || true
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
  configure_simulator_defaults
  run_tests
}

main "$@"
