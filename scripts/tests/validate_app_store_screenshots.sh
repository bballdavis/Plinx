#!/bin/bash
set -euo pipefail

SCREENSHOT_DIR="${1:-screenshots/app-store}"

fail() {
  echo "Screenshot validation failed: $1" >&2
  exit 1
}

[[ -d "$SCREENSHOT_DIR" ]] || fail "directory not found: $SCREENSHOT_DIR"

expected_files=(
  "01-loading.png"
  "02-connect.png"
  "03-home.png"
  "04-more-info.png"
  "05-settings.png"
  "06-parent-lock.png"
  "07-youtarr.png"
)

validate_screenshot() {
  local screenshot="$1"
  local expected_dimensions="$2"
  width=$(sips -g pixelWidth "$screenshot" 2>/dev/null | awk '/pixelWidth/{print $2}')
  height=$(sips -g pixelHeight "$screenshot" 2>/dev/null | awk '/pixelHeight/{print $2}')
  has_alpha=$(sips -g hasAlpha "$screenshot" 2>/dev/null | awk '/hasAlpha/{print $2}')

  [[ "${width}x${height}" == "$expected_dimensions" ]] \
    || fail "$screenshot is ${width}x${height}; expected $expected_dimensions"
  [[ "$has_alpha" == "no" ]] || fail "$screenshot contains an alpha channel"
  echo "Valid: $screenshot (${width}x${height})"
}

for relative_path in "${expected_files[@]}"; do
  iphone="$SCREENSHOT_DIR/iphone-6.9/$relative_path"
  ipad="$SCREENSHOT_DIR/ipad-13/$relative_path"
  [[ -f "$iphone" ]] || fail "missing $iphone"
  [[ -f "$ipad" ]] || fail "missing $ipad"
  validate_screenshot "$iphone" "1320x2868"
  validate_screenshot "$ipad" "2732x2048"
done

actual_count=$(find "$SCREENSHOT_DIR" -type f -iname '*.png' | wc -l | tr -d ' ')
[[ "$actual_count" == "14" ]] || fail "expected exactly 14 PNG files, found $actual_count"
