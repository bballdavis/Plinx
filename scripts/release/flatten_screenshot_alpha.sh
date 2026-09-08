#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 INPUT.png OUTPUT.png" >&2
  exit 2
fi

input="$1"
output="$2"
[[ -f "$input" ]] || {
  echo "Input not found: $input" >&2
  exit 1
}

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT

sips -s format jpeg -s formatOptions 100 "$input" \
  --out "$temporary_directory/flattened.jpg" >/dev/null
sips -s format png "$temporary_directory/flattened.jpg" \
  --out "$output" >/dev/null

has_alpha=$(sips -g hasAlpha "$output" | awk '/hasAlpha/{print $2}')
[[ "$has_alpha" == "no" ]] || {
  echo "Failed to remove alpha channel from $output" >&2
  exit 1
}

echo "Wrote opaque screenshot: $output"
