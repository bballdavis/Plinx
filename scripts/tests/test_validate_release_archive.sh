#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/tests/validate_testflight_archive.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/plinx-archive-validator.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

SHIM_DIR="$TEMP_ROOT/shims"
mkdir -p "$SHIM_DIR"

cat >"$SHIM_DIR/lipo" <<'SHIM'
#!/bin/bash
echo arm64
SHIM
cat >"$SHIM_DIR/codesign" <<'SHIM'
#!/bin/bash
exit 0
SHIM
cat >"$SHIM_DIR/xcrun" <<'SHIM'
#!/bin/bash
if [[ "${1:-}" == "assetutil" && "${2:-}" == "--info" ]]; then
  cat <<'JSON'
[
  { "Name" : "App Icon" },
  { "Name" : "Top Shelf Image" },
  { "Name" : "Top Shelf Image Wide" }
]
JSON
  exit 0
fi
exit 1
SHIM
chmod +x "$SHIM_DIR/lipo" "$SHIM_DIR/codesign" "$SHIM_DIR/xcrun"

make_privacy_manifest() {
  local destination="$1"
  cat >"$destination" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>NSPrivacyTracking</key><false/>
<key>NSPrivacyCollectedDataTypes</key><array/>
<key>NSPrivacyAccessedAPITypes</key><array>
<dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryUserDefaults</string><key>NSPrivacyAccessedAPITypeReasons</key><array><string>CA92.1</string></array></dict>
<dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryDiskSpace</string><key>NSPrivacyAccessedAPITypeReasons</key><array><string>E174.1</string></array></dict>
</array>
</dict></plist>
PLIST
}

make_archive() {
  local platform="$1"
  local archive="$TEMP_ROOT/$platform.xcarchive"
  local app="$archive/Products/Applications/Plinx.app"
  local supported dt_platform minimum_os
  mkdir -p "$app"
  if [[ "$platform" == "ios" ]]; then
    supported="iPhoneOS"
    dt_platform="iphoneos"
    minimum_os="17.5"
  else
    supported="AppleTVOS"
    dt_platform="appletvos"
    minimum_os="17.0"
  fi

  cat >"$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bballdavis.plinx</string>
<key>CFBundleVersion</key><string>123</string>
<key>CFBundleShortVersionString</key><string>2026.08.00</string>
<key>CFBundleExecutable</key><string>Plinx</string>
<key>MinimumOSVersion</key><string>$minimum_os</string>
<key>CFBundleSupportedPlatforms</key><array><string>$supported</string></array>
<key>DTPlatformName</key><string>$dt_platform</string>
<key>PlinxBuildConfiguration</key><string>Release</string>
<key>ITSAppUsesNonExemptEncryption</key><false/>
$(if [[ "$platform" == "ios" ]]; then printf '%s\n' '<key>UILaunchStoryboardName</key><string>LaunchScreen</string>'; else printf '%s\n' '<key>CFBundleIcons</key><dict><key>CFBundlePrimaryIcon</key><string>App Icon</string></dict>' '<key>TVTopShelfImage</key><dict><key>TVTopShelfPrimaryImage</key><string>Top Shelf Image</string><key>TVTopShelfPrimaryImageWide</key><string>Top Shelf Image Wide</string></dict>'; fi)
</dict></plist>
PLIST
  cat >"$archive/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>ApplicationProperties</key><dict><key>SigningIdentity</key><string>Apple Distribution</string><key>CFBundleIdentifier</key><string>com.bballdavis.plinx</string></dict></dict></plist>
PLIST
  printf '#!/bin/bash\nexit 0\n' >"$app/Plinx"
  chmod +x "$app/Plinx"
  touch "$app/Assets.car"
  make_privacy_manifest "$app/PrivacyInfo.xcprivacy"
  if [[ "$platform" == "ios" ]]; then
    mkdir "$app/LaunchScreen.storyboardc"
  fi
  printf '%s' "$archive"
}

IOS_ARCHIVE="$(make_archive ios)"
TVOS_ARCHIVE="$(make_archive tvos)"

PATH="$SHIM_DIR:$PATH" "$VALIDATOR" "$IOS_ARCHIVE" --platform ios --expected-build 123 --expected-version 2026.08.00
PATH="$SHIM_DIR:$PATH" "$VALIDATOR" "$TVOS_ARCHIVE" --platform tvos --expected-build 123 --expected-version 2026.08.00

/usr/libexec/PlistBuddy -c 'Delete :TVTopShelfImage:TVTopShelfPrimaryImageWide' "$TVOS_ARCHIVE/Products/Applications/Plinx.app/Info.plist"
if PATH="$SHIM_DIR:$PATH" "$VALIDATOR" "$TVOS_ARCHIVE" --platform tvos >/dev/null 2>&1; then
  echo "Archive validator test failed: tvOS archive without wide Top Shelf metadata passed" >&2
  exit 1
fi

echo "Release archive validator tests passed"
