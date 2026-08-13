#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Build Release Archive for Apple Platform Distribution
# ─────────────────────────────────────────────────────────────────────────────
#
# Creates a signed iOS or tvOS release archive. Distribution is explicit:
# archive-only, internal-only TestFlight, or production-eligible App Store.
# Usage: ./scripts/build_release_archive.sh
#

usage() {
  cat <<EOF
Usage: ./scripts/build_release_archive.sh [options]

Options:
  --platform PLATFORM   ios or tvos. Default: ios.
  --distribution MODE   archive, testflight-internal, or app-store.
                        Default: archive.
  --build-number N      Override CURRENT_PROJECT_VERSION for the archive.
                        Default: current UTC timestamp (guaranteed unique for uploads).
  --marketing-version V Override MARKETING_VERSION for the archive.
  --archive-path PATH   Archive output path.
  --upload-testflight   Compatibility alias for
                        --distribution testflight-internal.
  --export-path PATH    Export output path used by a distribution mode.
  --api-key-path PATH   App Store Connect API private key (.p8) path.
  --api-key-id ID       App Store Connect API key identifier.
  --api-key-issuer-id ID
                        App Store Connect API issuer identifier.
  --dry-run             Print the resolved archive/export plan without
                        generating, building, signing, exporting, or uploading.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"
source "$SCRIPT_DIR/build_environment.sh"

PLATFORM="ios"
DISTRIBUTION="archive"
CONFIGURATION="Release"
ARCHIVE_PATH=""
BUILD_NUMBER="${PLINX_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
MARKETING_VERSION_OVERRIDE="${PLINX_MARKETING_VERSION:-}"
EXPORT_PATH=""
API_KEY_PATH=""
API_KEY_ID=""
API_KEY_ISSUER_ID=""
DRY_RUN=false
COMPAT_UPLOAD_TESTFLIGHT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    --distribution)
      DISTRIBUTION="$2"
      shift 2
      ;;
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
      COMPAT_UPLOAD_TESTFLIGHT=true
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
    --dry-run)
      DRY_RUN=true
      shift
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

case "$PLATFORM" in
  ios)
    BUNDLE_ID="com.bballdavis.plinx"
    SCHEME="Plinx-iOS"
    DESTINATION="generic/platform=iOS"
    EXPECTED_MINIMUM_OS="17.5"
    ;;
  tvos)
    BUNDLE_ID="com.bballdavis.plinx"
    SCHEME="Plinx-tvOS"
    DESTINATION="generic/platform=tvOS"
    EXPECTED_MINIMUM_OS="17.0"
    ;;
  *)
    echo "Unsupported platform: $PLATFORM (expected ios or tvos)." >&2
    exit 2
    ;;
esac

if [[ "$COMPAT_UPLOAD_TESTFLIGHT" == true ]]; then
  if [[ "$DISTRIBUTION" != "archive" && "$DISTRIBUTION" != "testflight-internal" ]]; then
    echo "--upload-testflight conflicts with --distribution $DISTRIBUTION." >&2
    exit 2
  fi
  DISTRIBUTION="testflight-internal"
fi

case "$DISTRIBUTION" in
  archive)
    EXPORT_OPTIONS_PLIST=""
    ;;
  testflight-internal)
    EXPORT_OPTIONS_PLIST="$SCRIPT_DIR/testflight_export_options.plist"
    ;;
  app-store)
    EXPORT_OPTIONS_PLIST="$SCRIPT_DIR/app_store_export_options.plist"
    ;;
  *)
    echo "Unsupported distribution: $DISTRIBUTION (expected archive, testflight-internal, or app-store)." >&2
    exit 2
    ;;
esac

if [[ -z "$ARCHIVE_PATH" ]]; then
  if [[ "$PLATFORM" == "ios" ]]; then
    # Preserve the original no-argument archive path for existing automation.
    ARCHIVE_PATH="$PLINX_REPO_BUILD_ROOT/Plinx.xcarchive"
  else
    ARCHIVE_PATH="$PLINX_REPO_BUILD_ROOT/Plinx-tvOS.xcarchive"
  fi
fi

api_key_argument_count=0
[[ -n "$API_KEY_PATH" ]] && ((api_key_argument_count += 1))
[[ -n "$API_KEY_ID" ]] && ((api_key_argument_count += 1))
[[ -n "$API_KEY_ISSUER_ID" ]] && ((api_key_argument_count += 1))

if ((api_key_argument_count != 0 && api_key_argument_count != 3)); then
  echo "Provide all three App Store Connect API key arguments together." >&2
  exit 2
fi

if [[ "$DISTRIBUTION" != "archive" ]]; then
  if ((api_key_argument_count != 3)); then
    echo "--distribution $DISTRIBUTION requires --api-key-path, --api-key-id, and --api-key-issuer-id." >&2
    exit 2
  fi
  [[ "$DRY_RUN" == true || -f "$API_KEY_PATH" ]] || {
    echo "App Store Connect API key was not found at $API_KEY_PATH." >&2
    exit 2
  }
  if [[ -z "$EXPORT_PATH" ]]; then
    if [[ "$PLATFORM" == "ios" && "$DISTRIBUTION" == "testflight-internal" ]]; then
      # Preserve the legacy TestFlight export path used by existing automation.
      EXPORT_PATH="$PLINX_REPO_BUILD_ROOT/testflight-export-$BUILD_NUMBER"
    else
      EXPORT_PATH="$PLINX_REPO_BUILD_ROOT/${PLATFORM}-${DISTRIBUTION}-export-$BUILD_NUMBER"
    fi
  fi
elif [[ -n "$EXPORT_PATH" ]]; then
  echo "--export-path is only valid with a non-archive distribution." >&2
  exit 2
fi

echo "🔨 Building $PLATFORM release archive for $BUNDLE_ID..."
echo "   Platform: $PLATFORM"
echo "   Scheme: $SCHEME"
echo "   Destination: $DESTINATION"
echo "   Configuration: $CONFIGURATION"
echo "   Distribution: $DISTRIBUTION"
echo "   Archive path: $ARCHIVE_PATH"
echo "   Build number: $BUILD_NUMBER"
if [[ -n "$MARKETING_VERSION_OVERRIDE" ]]; then
  echo "   Marketing version: $MARKETING_VERSION_OVERRIDE"
fi
if [[ "$DISTRIBUTION" != "archive" ]]; then
  echo "   Export options: $EXPORT_OPTIONS_PLIST"
  echo "   Export path: $EXPORT_PATH"
fi
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run complete; no project generation, build, signing, export, or upload was performed."
  exit 0
fi

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
  -destination "$DESTINATION"
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
  --platform "$PLATFORM"
  --expected-minimum-os "$EXPECTED_MINIMUM_OS"
)
if [[ -n "$MARKETING_VERSION_OVERRIDE" ]]; then
  validation_args+=(--expected-version "$MARKETING_VERSION_OVERRIDE")
fi
bash ./scripts/tests/validate_testflight_archive.sh "${validation_args[@]}"

if [[ "$DISTRIBUTION" != "archive" ]]; then
  echo ""
  echo "☁️  Exporting $DISTRIBUTION distribution..."
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$API_KEY_PATH" \
    -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_KEY_ISSUER_ID"

  echo ""
  echo "✅ $DISTRIBUTION upload submitted. App Store Connect still processes the build asynchronously."
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
