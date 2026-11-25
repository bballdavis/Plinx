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
source "$PROJECT_ROOT/scripts/support/test_credentials.sh"
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

# The corresponding-source bundle is the clean Plinx commit plus a manifest of
# the absorbed Strimr base and the exact Swift package pins. It needs no
# sibling checkout and refuses a dirty tree or a loosely pinned package.
bundle_repo="$TEMP_ROOT/compliance/Plinx"
bundle_output="$TEMP_ROOT/compliance/output"
mkdir -p "$bundle_repo/scripts" "$bundle_repo/config" "$bundle_repo/PlinxApp" \
  "$bundle_repo/docs/release" "$bundle_output"
cp "$PROJECT_ROOT/scripts/build_compliance_bundle.sh" "$bundle_repo/scripts/"
printf 'STRIMR_FORK_BASE=%s\n' "$(printf 'a%.0s' {1..40})" \
  >"$bundle_repo/config/release-dependencies.env"
printf '%s\n' '# Compliance fixture' >"$bundle_repo/docs/release/open-source-compliance.md"
printf '%s\n' 'Absorbed source' >"$bundle_repo/PlinxApp/Engine.swift"
cat >"$bundle_repo/PlinxApp/project.yml" <<'YAML'
name: Plinx

packages:
  PlinxCore:
    path: ../Packages/PlinxCore
  AetherEngine:
    url: https://example.invalid/AetherEngine
    revision: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  GRDB:
    url: https://example.invalid/GRDB.swift
    exactVersion: 7.12.0

settings:
  base:
    PRODUCT_NAME: Plinx
YAML
git -C "$bundle_repo" init --quiet
git -C "$bundle_repo" add .
git -C "$bundle_repo" -c user.name=Fixture -c user.email=fixture@example.invalid \
  commit --quiet -m 'Release fixture'
bash "$bundle_repo/scripts/build_compliance_bundle.sh" "$bundle_output" \
  >"$TEMP_ROOT/compliance.log" 2>&1 \
  || fail "compliance bundle rejected a clean release checkout"
bundle_dir="$bundle_output/Plinx-$(git -C "$bundle_repo" rev-parse --short=12 HEAD)-corresponding-source"
[[ -f "$bundle_dir.tar.gz" ]] || fail "compliance bundle archive was not written"
[[ -f "$bundle_dir/PlinxApp/Engine.swift" ]] || fail "compliance bundle omitted the Plinx source tree"
[[ -f "$bundle_dir/open-source-compliance.md" ]] || fail "compliance bundle omitted the compliance guide"
[[ ! -e "$bundle_dir/Dependencies" ]] || fail "compliance bundle still packages a sibling dependency"
manifest="$bundle_dir/SOURCE-MANIFEST.txt"
grep -q "Plinx commit: $(git -C "$bundle_repo" rev-parse HEAD)" "$manifest" \
  || fail "manifest does not name the Plinx commit"
grep -q "Absorbed Strimr base (wunax/strimr): $(printf 'a%.0s' {1..40})" "$manifest" \
  || fail "manifest does not name the absorbed Strimr base"
grep -q "AetherEngine https://example.invalid/AetherEngine revision $(printf 'b%.0s' {1..40})" "$manifest" \
  || fail "manifest does not pin AetherEngine"
grep -q "GRDB https://example.invalid/GRDB.swift exactVersion 7.12.0" "$manifest" \
  || fail "manifest does not pin GRDB"
if grep -q "PlinxCore" "$manifest"; then
  fail "manifest lists a local package that is already in the source tree"
fi

printf '%s\n' 'uncommitted edit' >>"$bundle_repo/PlinxApp/Engine.swift"
if bash "$bundle_repo/scripts/build_compliance_bundle.sh" "$bundle_output" >"$TEMP_ROOT/compliance.log" 2>&1; then
  fail "compliance bundle accepted a dirty release checkout"
fi
git -C "$bundle_repo" checkout --quiet -- PlinxApp/Engine.swift

sed -i.bak 's/exactVersion: 7.12.0/from: 7.0.0/' "$bundle_repo/PlinxApp/project.yml"
rm "$bundle_repo/PlinxApp/project.yml.bak"
git -C "$bundle_repo" -c user.name=Fixture -c user.email=fixture@example.invalid \
  commit --quiet -am 'Loosen a package pin'
if bash "$bundle_repo/scripts/build_compliance_bundle.sh" "$bundle_output" >"$TEMP_ROOT/compliance.log" 2>&1; then
  fail "compliance bundle accepted a package without an exact pin"
fi

echo "Tooling contracts passed"
