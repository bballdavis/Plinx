#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/plinx-release-screenshot-tests.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
  echo "release screenshot tooling test failed: $1" >&2
  exit 1
}

expect_failure() {
  if "$@" >"$TEMP_ROOT/command.log" 2>&1; then
    fail "expected command to fail: $*"
  fi
}

bash -n "$REPO_ROOT/scripts/capture_release_screenshots.sh"
bash -n "$REPO_ROOT/scripts/tests/validate_app_store_screenshots.sh"
python3 -m py_compile "$REPO_ROOT/scripts/release_screenshot_preflight.py"
python3 -m py_compile "$REPO_ROOT/scripts/strip_png_metadata.py"
grep -q -- '--release-screenshot-capture' "$REPO_ROOT/scripts/capture_release_screenshots.sh" \
  || fail "capture launcher does not enable read-only release mode"
grep -q 'shouldBlockWatchMutation' "$REPO_ROOT/PlinxApp/App/ReleaseScreenshotCaptureMode.swift" \
  || fail "app capture mode does not block watch-state mutations"
grep -q 'PLINX_RELEASE_CAPTURE_SEARCH_QUERY' "$REPO_ROOT/PlinxApp/App/ReleaseScreenshotCaptureMode.swift" \
  || fail "app capture mode does not consume approved selectors"

metadata_png="$TEMP_ROOT/metadata.png"
cp "$REPO_ROOT/screenshots/fixtures/app-store/iphone-6.9/01-loading.png" "$metadata_png"
python3 "$REPO_ROOT/scripts/strip_png_metadata.py" "$metadata_png"
[[ "$(sips -g pixelWidth -g pixelHeight "$metadata_png" | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w "x" h}')" == "1320x2868" ]] \
  || fail "metadata stripping changed PNG dimensions"

# The committed template is intentionally not executable until a release owner
# replaces its sample selectors with a local, curated selection.
expect_failure python3 "$REPO_ROOT/scripts/release_screenshot_preflight.py" \
  --selection "$REPO_ROOT/screenshot_capture.yaml.example"

selection="$TEMP_ROOT/selection.yaml"
sed \
  -e 's/sample-movies/capture-movies/g' \
  -e 's/sample-shows/capture-shows/g' \
  -e 's/approved-movie-001/movie-001/g' \
  -e 's/approved-show-001/show-001/g' \
  -e 's/replace-with-private-name/blocked-private-label/g' \
  "$REPO_ROOT/screenshot_capture.yaml.example" >"$selection"
python3 "$REPO_ROOT/scripts/release_screenshot_preflight.py" --selection "$selection" >/dev/null
[[ "$(python3 "$REPO_ROOT/scripts/release_screenshot_preflight.py" --selection "$selection" --print-value locale)" == "en_US" ]] \
  || fail "validated locale was not available to the capture launcher"

printf '\nunknown: value\n' >>"$selection"
expect_failure python3 "$REPO_ROOT/scripts/release_screenshot_preflight.py" --selection "$selection"

# Existing fixture/public inventory remains the default validation contract.
bash "$REPO_ROOT/scripts/tests/validate_app_store_screenshots.sh" \
  "$REPO_ROOT/screenshots/fixtures/app-store" >/dev/null

# The release-only tvOS inventory has a separate eight-frame contract without
# changing the existing fourteen-file public fixture inventory.
mkdir -p "$TEMP_ROOT/tvos-stage/tvos-4k"
for name in 01-home 02-library-root 03-library-browse 04-media-detail 05-search 06-player-controls 07-parental-gate 08-content-settings; do
  sips -z 2160 3840 "$REPO_ROOT/screenshots/fixtures/app-store/ipad-13/01-loading.png" \
    --out "$TEMP_ROOT/tvos-stage/tvos-4k/$name.png" >/dev/null
  python3 "$REPO_ROOT/scripts/strip_png_metadata.py" "$TEMP_ROOT/tvos-stage/tvos-4k/$name.png"
done
bash "$REPO_ROOT/scripts/tests/validate_app_store_screenshots.sh" --tvos-only \
  "$TEMP_ROOT/tvos-stage" >/dev/null

# Capture must fail before it could inspect files, create a simulator, or run a
# network preflight in non-local contexts and when aimed at public assets.
expect_failure env CI=true bash "$REPO_ROOT/scripts/capture_release_screenshots.sh" \
  --platform ios --credentials-file "$TEMP_ROOT/missing-creds.yaml" \
  --selection-file "$TEMP_ROOT/missing-selection.yaml" --output "$TEMP_ROOT/output"
expect_failure bash "$REPO_ROOT/scripts/capture_release_screenshots.sh" \
  --platform ios --credentials-file "$TEMP_ROOT/missing-creds.yaml" \
  --selection-file "$TEMP_ROOT/missing-selection.yaml" --output "$REPO_ROOT/screenshots/app-store"

echo "Release screenshot tooling checks passed"
