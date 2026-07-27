#!/bin/bash
set -euo pipefail

SCREENSHOT_DIR="${1:-screenshots/app-store}"

fail() {
  echo "Screenshot validation failed: $1" >&2
  exit 1
}

[[ -d "$SCREENSHOT_DIR" ]] || fail "directory not found: $SCREENSHOT_DIR"

found=0
while IFS= read -r -d '' screenshot; do
  found=1
  width=$(sips -g pixelWidth "$screenshot" 2>/dev/null | awk '/pixelWidth/{print $2}')
  height=$(sips -g pixelHeight "$screenshot" 2>/dev/null | awk '/pixelHeight/{print $2}')
  has_alpha=$(sips -g hasAlpha "$screenshot" 2>/dev/null | awk '/hasAlpha/{print $2}')

  case "${width}x${height}" in
    1320x2868|2868x1320|2064x2752|2752x2064)
      ;;
    *)
      fail "$screenshot has unsupported dimensions ${width}x${height}"
      ;;
  esac

  [[ "$has_alpha" == "no" ]] || fail "$screenshot contains an alpha channel"
  echo "Valid: $screenshot (${width}x${height})"
done < <(find "$SCREENSHOT_DIR" -type f -iname '*.png' -print0)

[[ "$found" -eq 1 ]] || fail "no PNG screenshots found"

