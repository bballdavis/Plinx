#!/bin/bash
# Regenerates PlinxApp/Resources/DemoFixture/plinx-demo-clip.mp4.
#
# The clip is original, generated media for the credential-free App Review
# demo library: an animated gradient, a "Plinx Demo Clip" title, and a running
# timestamp so reviewers can see real playback and seeking. It contains no
# third-party footage, music, or fonts beyond the system font used to render
# the overlay. Requires ffmpeg (with the lavfi `gradients` source) and Swift.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
OUTPUT="$PROJECT_ROOT/PlinxApp/Resources/DemoFixture/plinx-demo-clip.mp4"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/overlay"
swift "$SCRIPT_DIR/render_overlay.swift" "$WORK_DIR/overlay"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "gradients=s=1280x720:r=24:c0=0x1F7A5C:c1=0x0B2E2F:c2=0x2B6CB0:c3=0x6B4FBB:n=4:speed=0.004:d=120" \
  -framerate 1 -i "$WORK_DIR/overlay/f%03d.png" \
  -f lavfi -i "anullsrc=r=44100:cl=stereo" \
  -filter_complex "[1:v]fps=24,format=rgba[o];[0:v][o]overlay=0:0:shortest=1,format=yuv420p[v]" \
  -map "[v]" -map 2:a -t 120 \
  -c:v libx264 -preset slow -crf 30 -profile:v main -movflags +faststart \
  -c:a aac -b:a 32k "$OUTPUT"

echo "Wrote $OUTPUT ($(stat -f%z "$OUTPUT") bytes)"
