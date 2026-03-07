#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Build Release Archive for TestFlight
# ─────────────────────────────────────────────────────────────────────────────
#
# Creates a signed release archive suitable for uploading to TestFlight.
# Usage: ./scripts/build_release_archive.sh
#

cd "$(dirname "$0")/.."

BUNDLE_ID="com.bballdavis.plinx"
SCHEME="Plinx-iOS"
CONFIGURATION="Release"
ARCHIVE_PATH="./build/Plinx.xcarchive"

echo "🔨 Building release archive for $BUNDLE_ID..."
echo "   Scheme: $SCHEME"
echo "   Configuration: $CONFIGURATION"
echo "   Archive path: $ARCHIVE_PATH"
echo ""

# Generate project from XcodeGen
echo "📋 Generating Xcode project..."
cd PlinxApp
xcodegen generate --quiet
cd ..

# Build archive
echo "🏗️  Building archive..."
xcodebuild archive \
  -project PlinxApp/Plinx.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath ./build/DerivedData \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  CODE_SIGN_STYLE="Automatic"

echo ""
echo "✅ Archive created successfully!"
echo ""
echo "📦 Archive location: $ARCHIVE_PATH"
echo ""
echo "Next steps:"
echo "  1. Open Xcode Organizer: Xcode → Window → Organizer"
echo "  2. Select the 'Plinx' archive"
echo "  3. Click 'Distribute App'"
echo "  4. Select 'TestFlight' and follow prompts"
echo ""
echo "Or use Transporter to upload directly."
