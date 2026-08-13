#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_DIR="$SCRIPT_DIR/fixtures"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/plinx-tooling-contracts.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
  echo "tooling contract failed: $1" >&2
  exit 1
}

run_ui_tests() {
  env \
    PLINX_SWIFT_COMMAND="$FIXTURE_DIR/fake_swift.sh" \
    PLINX_FAKE_CORE_STATUS="${1:-0}" \
    PLINX_FAKE_UI_STATUS="${2:-0}" \
    bash "$PROJECT_ROOT/scripts/tests/ui_tests.sh" "${3:-all}" \
    >"$TEMP_ROOT/ui-tests.log" 2>&1
}

run_ui_tests 0 0 --ui || fail "--ui rejected passing tests"
grep -q "fake PlinxUI tests executed" "$TEMP_ROOT/ui-tests.log" \
  || fail "--ui did not execute PlinxUI tests"
run_ui_tests 0 0 all || fail "combined mode rejected passing suites"
if run_ui_tests 1 0 all; then
  fail "combined mode hid a PlinxCore failure"
fi
if run_ui_tests 0 1 all; then
  fail "combined mode hid a PlinxUI failure"
fi

credentials="$TEMP_ROOT/test_creds.yaml"
printf '%s\n' \
  'PLINX_PLEX_SERVER_URL: "https://plex.invalid:32400"' \
  "PLINX_PLEX_TOKEN: 'secret-value'" \
  'UNRELATED_SECRET: must-not-load' >"$credentials"
unset PLINX_PLEX_SERVER_URL PLINX_PLEX_TOKEN UNRELATED_SECRET || true
source "$PROJECT_ROOT/scripts/test_credentials.sh"
load_plinx_test_credentials "$credentials" || fail "valid credentials were rejected"
[[ "$PLINX_PLEX_SERVER_URL" == "https://plex.invalid:32400" ]] \
  || fail "server URL was parsed incorrectly"
[[ "$PLINX_PLEX_TOKEN" == "secret-value" ]] || fail "token was parsed incorrectly"
[[ -z "${UNRELATED_SECRET:-}" ]] || fail "unapproved credential key was exported"

mkdir -p "$TEMP_ROOT/bin"
ln -s "$FIXTURE_DIR/fake_xcrun.sh" "$TEMP_ROOT/bin/xcrun"
for runner in run_iphone_sim.sh run_ipad_sim.sh; do
  env PATH="$TEMP_ROOT/bin:$PATH" PLINX_SIM_RUNNER_PREFLIGHT=1 \
    bash "$PROJECT_ROOT/scripts/$runner" >"$TEMP_ROOT/$runner.default.log" 2>&1 \
    || fail "$runner default preflight failed"
  env PATH="$TEMP_ROOT/bin:$PATH" PLINX_SIM_RUNNER_PREFLIGHT=1 \
    bash "$PROJECT_ROOT/scripts/$runner" generic >"$TEMP_ROOT/$runner.generic.log" 2>&1 \
    || fail "$runner generic preflight failed"
done

echo "Tooling contracts passed"
