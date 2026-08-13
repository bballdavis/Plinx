#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/build_release_archive.sh"
INTERNAL_EXPORT_OPTIONS="$REPO_ROOT/scripts/testflight_export_options.plist"
APP_STORE_EXPORT_OPTIONS="$REPO_ROOT/scripts/app_store_export_options.plist"

fail() {
  echo "Release archive CLI test failed: $1" >&2
  exit 1
}

ios_plan=$("$SCRIPT" --dry-run --build-number 100)
[[ "$ios_plan" == *"Platform: ios"* ]] || fail "default platform is not ios"
[[ "$ios_plan" == *"Scheme: Plinx-iOS"* ]] || fail "iOS scheme was not resolved"
[[ "$ios_plan" == *"Destination: generic/platform=iOS"* ]] || fail "iOS destination was not resolved"
[[ "$ios_plan" == *"Distribution: archive"* ]] || fail "default distribution is not archive"
[[ "$ios_plan" == *"Archive path: $REPO_ROOT/build/Plinx.xcarchive"* ]] || fail "legacy iOS archive path was not preserved"

tvos_internal_plan=$(
  "$SCRIPT" \
    --platform tvos \
    --upload-testflight \
    --api-key-path /not/read/during/dry-run.p8 \
    --api-key-id TESTKEY \
    --api-key-issuer-id TESTISSUER \
    --dry-run \
    --build-number 101
)
[[ "$tvos_internal_plan" == *"Scheme: Plinx-tvOS"* ]] || fail "tvOS scheme was not resolved"
[[ "$tvos_internal_plan" == *"Destination: generic/platform=tvOS"* ]] || fail "tvOS destination was not resolved"
[[ "$tvos_internal_plan" == *"Distribution: testflight-internal"* ]] || fail "compatibility alias was not resolved"
[[ "$tvos_internal_plan" == *"testflight_export_options.plist"* ]] || fail "internal export options were not selected"
[[ "$tvos_internal_plan" == *"Archive path: $REPO_ROOT/build/Plinx-tvOS.xcarchive"* ]] || fail "tvOS archive path was not platform-specific"

tvos_store_plan=$(
  "$SCRIPT" \
    --platform tvos \
    --distribution app-store \
    --api-key-path /not/read/during/dry-run.p8 \
    --api-key-id TESTKEY \
    --api-key-issuer-id TESTISSUER \
    --dry-run \
    --build-number 102
)
[[ "$tvos_store_plan" == *"Distribution: app-store"* ]] || fail "App Store distribution was not resolved"
[[ "$tvos_store_plan" == *"app_store_export_options.plist"* ]] || fail "App Store export options were not selected"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :destination' "$APP_STORE_EXPORT_OPTIONS")" == "upload" ]] \
  || fail "App Store export options do not upload"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :method' "$APP_STORE_EXPORT_OPTIONS")" == "app-store-connect" ]] \
  || fail "App Store export options do not use App Store Connect"
if /usr/libexec/PlistBuddy -c 'Print :testFlightInternalTestingOnly' "$APP_STORE_EXPORT_OPTIONS" >/dev/null 2>&1; then
  fail "production App Store export options are restricted to internal TestFlight"
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :testFlightInternalTestingOnly' "$INTERNAL_EXPORT_OPTIONS")" == "true" ]] \
  || fail "internal TestFlight export options are not internal-only"

if "$SCRIPT" --platform invalid --dry-run >/dev/null 2>&1; then
  fail "invalid platform was accepted"
fi
if "$SCRIPT" --distribution invalid --dry-run >/dev/null 2>&1; then
  fail "invalid distribution was accepted"
fi
if "$SCRIPT" --distribution app-store --upload-testflight --dry-run >/dev/null 2>&1; then
  fail "conflicting distribution options were accepted"
fi

echo "Release archive CLI tests passed"
