#!/bin/bash
set -euo pipefail

ARCHIVE_PATH="./build/Plinx.xcarchive"
EXPECTED_BUILD=""
EXPECTED_VERSION=""
EXPECTED_BUNDLE_ID="com.bballdavis.plinx"
EXPECTED_CONFIGURATION="Release"
EXPECTED_MINIMUM_OS="17.5"

if [[ $# -gt 0 && "$1" != --* ]]; then
  ARCHIVE_PATH="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-build)
      EXPECTED_BUILD="$2"
      shift 2
      ;;
    --expected-version)
      EXPECTED_VERSION="$2"
      shift 2
      ;;
    --expected-bundle-id)
      EXPECTED_BUNDLE_ID="$2"
      shift 2
      ;;
    --expected-configuration)
      EXPECTED_CONFIGURATION="$2"
      shift 2
      ;;
    --expected-minimum-os)
      EXPECTED_MINIMUM_OS="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

APP_PATH="${ARCHIVE_PATH}/Products/Applications/Plinx.app"
INFO_PLIST="${APP_PATH}/Info.plist"
ARCHIVE_INFO="${ARCHIVE_PATH}/Info.plist"

fail() {
  echo "Validation failed: $1" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true
}

[[ -d "$ARCHIVE_PATH" ]] || fail "Archive not found at $ARCHIVE_PATH"
[[ -d "$APP_PATH" ]] || fail "App bundle not found at $APP_PATH"
[[ -f "$INFO_PLIST" ]] || fail "Info.plist not found at $INFO_PLIST"
[[ -f "$ARCHIVE_INFO" ]] || fail "Archive Info.plist not found at $ARCHIVE_INFO"

bundle_id=$(plist_value CFBundleIdentifier "$INFO_PLIST")
bundle_version=$(plist_value CFBundleVersion "$INFO_PLIST")
short_version=$(plist_value CFBundleShortVersionString "$INFO_PLIST")
executable_name=$(plist_value CFBundleExecutable "$INFO_PLIST")
minimum_os=$(plist_value MinimumOSVersion "$INFO_PLIST")
launch_storyboard_name=$(plist_value UILaunchStoryboardName "$INFO_PLIST")
supported_platforms=$(plist_value CFBundleSupportedPlatforms "$INFO_PLIST")
build_configuration=$(plist_value PlinxBuildConfiguration "$INFO_PLIST")
signing_identity=$(plist_value "ApplicationProperties:SigningIdentity" "$ARCHIVE_INFO")
archive_bundle_id=$(plist_value "ApplicationProperties:CFBundleIdentifier" "$ARCHIVE_INFO")

[[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || fail "Unexpected bundle id: $bundle_id"
[[ "$archive_bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || fail "Archive bundle id mismatch: $archive_bundle_id"
[[ -n "$bundle_version" ]] || fail "CFBundleVersion is missing"
[[ -n "$short_version" ]] || fail "CFBundleShortVersionString is missing"
[[ -z "$EXPECTED_BUILD" || "$bundle_version" == "$EXPECTED_BUILD" ]] || fail "Expected build $EXPECTED_BUILD, found $bundle_version"
[[ -z "$EXPECTED_VERSION" || "$short_version" == "$EXPECTED_VERSION" ]] || fail "Expected version $EXPECTED_VERSION, found $short_version"
[[ -n "$minimum_os" ]] || fail "MinimumOSVersion is missing"
[[ "$minimum_os" == "$EXPECTED_MINIMUM_OS" ]] || fail "Expected minimum OS $EXPECTED_MINIMUM_OS, found $minimum_os"
[[ "$build_configuration" == "$EXPECTED_CONFIGURATION" ]] || fail "Expected $EXPECTED_CONFIGURATION configuration, found $build_configuration"
[[ "$supported_platforms" == *"iPhoneOS"* ]] || fail "Archive is not an iOS device build"
[[ -n "$signing_identity" ]] || fail "Archive signing identity is missing"
[[ -n "$executable_name" ]] || fail "CFBundleExecutable is missing"
[[ -x "$APP_PATH/$executable_name" ]] || fail "Executable missing or not executable: $executable_name"

architectures=$(lipo -archs "$APP_PATH/$executable_name" 2>/dev/null || true)
[[ "$architectures" == *"arm64"* ]] || fail "App executable does not contain arm64: $architectures"
codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1 || fail "Code signature verification failed"

[[ -n "$launch_storyboard_name" ]] || fail "UILaunchStoryboardName is missing"
[[ -d "$APP_PATH/${launch_storyboard_name}.storyboardc" ]] || fail "Compiled launch storyboard missing"
[[ -f "$APP_PATH/PrivacyInfo.xcprivacy" ]] || fail "Privacy manifest missing"
[[ -f "$APP_PATH/Assets.car" ]] || fail "Compiled asset catalog missing"

privacy_tracking=$(plist_value NSPrivacyTracking "$APP_PATH/PrivacyInfo.xcprivacy")
[[ "$privacy_tracking" == "false" ]] || fail "Privacy manifest must declare tracking disabled"

privacy_dump=$(plutil -convert json -o - "$APP_PATH/PrivacyInfo.xcprivacy")
[[ "$privacy_dump" == *'"NSPrivacyAccessedAPIType":"NSPrivacyAccessedAPICategoryUserDefaults"'* ]] \
  || fail "UserDefaults required-reason API declaration is missing"
[[ "$privacy_dump" == *'"CA92.1"'* ]] \
  || fail "UserDefaults reason CA92.1 is missing"
[[ "$privacy_dump" == *'"NSPrivacyAccessedAPIType":"NSPrivacyAccessedAPICategoryDiskSpace"'* ]] \
  || fail "Disk-space required-reason API declaration is missing"
[[ "$privacy_dump" == *'"E174.1"'* ]] \
  || fail "Disk-space reason E174.1 is missing"

if find "$APP_PATH" -iname '*sentry*' -print -quit | grep -q .; then
  fail "Sentry artifact found in final app bundle"
fi

if rg -a -i -l 'sentry[_-]?dsn|dsn\\.sentry|api[_-]?secret' "$APP_PATH" >/dev/null 2>&1; then
  fail "Potential telemetry or secret marker found in final app bundle"
fi

echo "Archive validation passed"
echo "  Archive: $ARCHIVE_PATH"
echo "  App: $APP_PATH"
echo "  Bundle: $bundle_id"
echo "  Version: $short_version ($bundle_version)"
echo "  Minimum OS: $minimum_os"
echo "  Configuration: $build_configuration"
echo "  Architectures: $architectures"
echo "  Signing identity: $signing_identity"
