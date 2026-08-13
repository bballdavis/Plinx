#!/bin/bash
set -euo pipefail

REQUIRE_TVOS=0
TVOS_ONLY=0
if [[ "${1:-}" == "--require-tvos" ]]; then
  REQUIRE_TVOS=1
  shift
elif [[ "${1:-}" == "--tvos-only" ]]; then
  TVOS_ONLY=1
  shift
fi

SCREENSHOT_DIR="${1:-screenshots/app-store}"

fail() {
  echo "Screenshot validation failed: $1" >&2
  exit 1
}

[[ -d "$SCREENSHOT_DIR" ]] || fail "directory not found: $SCREENSHOT_DIR"

fixture_files=(
  "01-loading.png"
  "02-connect.png"
  "03-home.png"
  "04-more-info.png"
  "05-settings.png"
  "06-parent-lock.png"
  "07-youtarr.png"
)

release_files=(
  "01-loading.png"
  "02-connect.png"
  "03-home.png"
  "04-media-detail.png"
  "05-settings.png"
  "06-parental-gate.png"
  "07-library-browse.png"
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
  python3 - "$screenshot" <<'PY' || fail "$screenshot contains forbidden PNG metadata"
import struct
import sys

payload = open(sys.argv[1], "rb").read()
offset = 8
forbidden = {b"tEXt", b"zTXt", b"iTXt", b"eXIf", b"tIME"}
while offset + 12 <= len(payload):
    length = struct.unpack(">I", payload[offset:offset + 4])[0]
    kind = payload[offset + 4:offset + 8]
    if kind in forbidden:
        raise SystemExit(1)
    offset += length + 12
    if kind == b"IEND":
        break
PY
  echo "Valid: $screenshot (${width}x${height})"
}

if [[ "$TVOS_ONLY" -eq 0 ]]; then
  expected_files=("${fixture_files[@]}")
  if [[ -f "$SCREENSHOT_DIR/iphone-6.9/04-media-detail.png" ]]; then
    expected_files=("${release_files[@]}")
  fi
  for relative_path in "${expected_files[@]}"; do
    iphone="$SCREENSHOT_DIR/iphone-6.9/$relative_path"
    ipad="$SCREENSHOT_DIR/ipad-13/$relative_path"
    [[ -f "$iphone" ]] || fail "missing $iphone"
    [[ -f "$ipad" ]] || fail "missing $ipad"
    validate_screenshot "$iphone" "1320x2868"
    validate_screenshot "$ipad" "2732x2048"
  done
fi

if [[ "$REQUIRE_TVOS" -eq 1 || "$TVOS_ONLY" -eq 1 ]]; then
  tvos_files=(
    "01-home.png" "02-library-root.png" "03-library-browse.png" "04-media-detail.png"
    "05-search.png" "06-player-controls.png" "07-parental-gate.png" "08-content-settings.png"
  )
  for relative_path in "${tvos_files[@]}"; do
    tvos="$SCREENSHOT_DIR/tvos-4k/$relative_path"
    [[ -f "$tvos" ]] || fail "missing $tvos"
    validate_screenshot "$tvos" "3840x2160"
  done
fi

actual_count=$(find "$SCREENSHOT_DIR" -type f -iname '*.png' | wc -l | tr -d ' ')
expected_count=14
if [[ "$TVOS_ONLY" -eq 1 ]]; then
  expected_count=8
elif [[ "$REQUIRE_TVOS" -eq 1 ]]; then
  expected_count=22
fi
[[ "$actual_count" == "$expected_count" ]] || fail "expected exactly $expected_count PNG files, found $actual_count"
