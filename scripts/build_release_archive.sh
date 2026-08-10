#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Build Release Archive for TestFlight
# ─────────────────────────────────────────────────────────────────────────────
#
# Creates a signed release archive suitable for uploading to TestFlight.
# With --upload-testflight, exports and submits an internal-only TestFlight
# build using an App Store Connect API key.
# Usage: ./scripts/build_release_archive.sh
#

usage() {
  cat <<EOF
Usage: ./scripts/build_release_archive.sh [options]

Options:
  --build-number N      Override CURRENT_PROJECT_VERSION for the archive.
                        Default: current UTC timestamp (guaranteed unique for uploads).
  --marketing-version V Override MARKETING_VERSION for the archive.
  --archive-path PATH   Archive output path.
  --upload-testflight   Export and submit an internal-only TestFlight build.
  --export-path PATH    Export output path used with --upload-testflight.
  --api-key-path PATH   App Store Connect API private key (.p8) path.
  --api-key-id ID       App Store Connect API key identifier.
  --api-key-issuer-id ID
                        App Store Connect API issuer identifier.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"
source "$SCRIPT_DIR/build_environment.sh"

BUNDLE_ID="com.bballdavis.plinx"
SCHEME="Plinx-iOS"
CONFIGURATION="Release"
ARCHIVE_PATH="$PLINX_REPO_BUILD_ROOT/Plinx.xcarchive"
BUILD_NUMBER="${PLINX_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
MARKETING_VERSION_OVERRIDE="${PLINX_MARKETING_VERSION:-}"
UPLOAD_TESTFLIGHT=false
EXPORT_PATH=""
API_KEY_PATH=""
API_KEY_ID=""
API_KEY_ISSUER_ID=""

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
    --upload-testflight)
      UPLOAD_TESTFLIGHT=true
      shift
      ;;
    --export-path)
      EXPORT_PATH="$2"
      shift 2
      ;;
    --api-key-path)
      API_KEY_PATH="$2"
      shift 2
      ;;
    --api-key-id)
      API_KEY_ID="$2"
      shift 2
      ;;
    --api-key-issuer-id)
      API_KEY_ISSUER_ID="$2"
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

api_key_argument_count=0
[[ -n "$API_KEY_PATH" ]] && ((api_key_argument_count += 1))
[[ -n "$API_KEY_ID" ]] && ((api_key_argument_count += 1))
[[ -n "$API_KEY_ISSUER_ID" ]] && ((api_key_argument_count += 1))

if ((api_key_argument_count != 0 && api_key_argument_count != 3)); then
  echo "Provide all three App Store Connect API key arguments together." >&2
  exit 2
fi

if [[ "$UPLOAD_TESTFLIGHT" == true ]]; then
  if ((api_key_argument_count != 3)); then
    echo "--upload-testflight requires --api-key-path, --api-key-id, and --api-key-issuer-id." >&2
    exit 2
  fi
  [[ -f "$API_KEY_PATH" ]] || {
    echo "App Store Connect API key was not found at $API_KEY_PATH." >&2
    exit 2
  }
  EXPORT_PATH="${EXPORT_PATH:-$PLINX_REPO_BUILD_ROOT/testflight-export-$BUILD_NUMBER}"
elif [[ -n "$EXPORT_PATH" ]]; then
  echo "--export-path is only valid with --upload-testflight." >&2
  exit 2
fi

echo "🔨 Building release archive for $BUNDLE_ID..."
echo "   Scheme: $SCHEME"
echo "   Configuration: $CONFIGURATION"
echo "   Archive path: $ARCHIVE_PATH"
echo "   Build number: $BUILD_NUMBER"
if [[ -n "$MARKETING_VERSION_OVERRIDE" ]]; then
  echo "   Marketing version: $MARKETING_VERSION_OVERRIDE"
fi
if [[ "$UPLOAD_TESTFLIGHT" == true ]]; then
  echo "   TestFlight distribution: internal-only"
  echo "   Export path: $EXPORT_PATH"
fi
echo ""

# Generate project from XcodeGen
echo "📋 Generating Xcode project..."
bash ./scripts/generate_xcodeproj.sh --quiet
bash ./scripts/verify_release_dependency_state.sh

# Build archive
echo "🏗️  Building archive..."
xcodebuild_args=(
  archive
  -project "PlinxApp/Plinx.xcodeproj"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=iOS"
  -archivePath "$ARCHIVE_PATH"
  -derivedDataPath "$PLINX_XCODE_DERIVED_DATA_PATH"
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
  CODE_SIGN_STYLE="Automatic"
)

if ((api_key_argument_count == 3)); then
  xcodebuild_args+=(
    -allowProvisioningUpdates
    -authenticationKeyPath "$API_KEY_PATH"
    -authenticationKeyID "$API_KEY_ID"
    -authenticationKeyIssuerID "$API_KEY_ISSUER_ID"
  )
fi

if [[ -n "$MARKETING_VERSION_OVERRIDE" ]]; then
  xcodebuild_args+=(MARKETING_VERSION="$MARKETING_VERSION_OVERRIDE")
fi

xcodebuild "${xcodebuild_args[@]}"

validation_args=(
  "$ARCHIVE_PATH"
  --expected-build "$BUILD_NUMBER"
  --expected-bundle-id "$BUNDLE_ID"
)
if [[ -n "$MARKETING_VERSION_OVERRIDE" ]]; then
  validation_args+=(--expected-version "$MARKETING_VERSION_OVERRIDE")
fi
bash ./scripts/tests/validate_testflight_archive.sh "${validation_args[@]}"

if [[ "$UPLOAD_TESTFLIGHT" == true ]]; then
  echo ""
  echo "☁️  Uploading internal-only TestFlight build..."
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$SCRIPT_DIR/testflight_export_options.plist" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$API_KEY_PATH" \
    -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_KEY_ISSUER_ID"

  echo ""
  echo "✅ TestFlight upload submitted. App Store Connect still processes the build asynchronously."
  exit 0
fi

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
