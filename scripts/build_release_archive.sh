#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Build Release Archive for TestFlight
# ─────────────────────────────────────────────────────────────────────────────
#
# Creates a signed release archive suitable for uploading to TestFlight.
# Usage: ./scripts/build_release_archive.sh
#

usage() {
  cat <<EOF
Usage: ./scripts/build_release_archive.sh [--build-number N] [--marketing-version V] [--archive-path PATH]

Options:
  --build-number N      Override CURRENT_PROJECT_VERSION for the archive.
                        Default: current UTC timestamp (guaranteed unique for uploads).
  --marketing-version V Override MARKETING_VERSION for the archive.
  --archive-path PATH   Archive output path.
EOF
}

cd "$(dirname "$0")/.."

BUNDLE_ID="com.bballdavis.plinx"
SCHEME="Plinx-iOS"
CONFIGURATION="Release"
ARCHIVE_PATH="./build/Plinx.xcarchive"
BUILD_NUMBER="${PLINX_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
MARKETING_VERSION_OVERRIDE="${PLINX_MARKETING_VERSION:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --marketing-version)
      MARKETING_VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --archive-path)
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

echo "🔨 Building release archive for $BUNDLE_ID..."
echo "   Scheme: $SCHEME"
echo "   Configuration: $CONFIGURATION"
echo "   Archive path: $ARCHIVE_PATH"
echo "   Build number: $BUILD_NUMBER"
if [[ -n "$MARKETING_VERSION_OVERRIDE" ]]; then
  echo "   Marketing version: $MARKETING_VERSION_OVERRIDE"
fi
echo ""

# Generate project from XcodeGen
echo "📋 Generating Xcode project..."
cd PlinxApp
xcodegen generate --quiet
cd ..

# Build archive
echo "🏗️  Building archive..."
xcodebuild_args=(
  archive
  -project "PlinxApp/Plinx.xcodeproj"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=iOS"
  -archivePath "$ARCHIVE_PATH"
  -derivedDataPath ./build/DerivedData
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
  CODE_SIGN_IDENTITY="Apple Distribution"
  CODE_SIGN_STYLE="Automatic"
)

if [[ -n "$MARKETING_VERSION_OVERRIDE" ]]; then
  xcodebuild_args+=(MARKETING_VERSION="$MARKETING_VERSION_OVERRIDE")
fi

xcodebuild "${xcodebuild_args[@]}"

bash ./scripts/validate_testflight_archive.sh "$ARCHIVE_PATH"

echo ""
echo "✅ Archive created successfully!"
echo ""
echo "📦 Archive location: $ARCHIVE_PATH"
echo ""
echo "Next steps:"
echo "  1. Open Xcode Organizer: Xcode → Window → Organizer"
echo "  2. Select the 'Plinx' archive"
echo "  3. Confirm the archive validated locally"
echo "  4. Click 'Distribute App' → 'TestFlight'"
echo ""
echo "Or use Transporter to upload directly."
