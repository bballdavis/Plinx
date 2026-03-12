#!/bin/bash
set -euo pipefail

ARCHIVE_PATH="${1:-./build/Plinx.xcarchive}"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/Plinx.app"
INFO_PLIST="${APP_PATH}/Info.plist"

fail() {
  echo "Validation failed: $1" >&2
  exit 1
}

[[ -d "$ARCHIVE_PATH" ]] || fail "Archive not found at $ARCHIVE_PATH"
[[ -d "$APP_PATH" ]] || fail "App bundle not found at $APP_PATH"
[[ -f "$INFO_PLIST" ]] || fail "Info.plist not found at $INFO_PLIST"

launch_storyboard_name=$(/usr/libexec/PlistBuddy -c 'Print :UILaunchStoryboardName' "$INFO_PLIST" 2>/dev/null || true)
bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || true)
short_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || true)

[[ -n "$bundle_version" ]] || fail "CFBundleVersion is missing"
[[ -n "$short_version" ]] || fail "CFBundleShortVersionString is missing"
[[ -n "$launch_storyboard_name" ]] || fail "UILaunchStoryboardName is missing"
[[ -d "$APP_PATH/${launch_storyboard_name}.storyboardc" ]] || fail "Compiled launch storyboard missing: $APP_PATH/${launch_storyboard_name}.storyboardc"
[[ -f "$APP_PATH/PrivacyInfo.xcprivacy" ]] || fail "Privacy manifest missing: $APP_PATH/PrivacyInfo.xcprivacy"
[[ -f "$APP_PATH/Assets.car" ]] || fail "Compiled asset catalog missing: $APP_PATH/Assets.car"

echo "Archive validation passed"
echo "  Archive: $ARCHIVE_PATH"
echo "  App: $APP_PATH"
echo "  Version: $short_version ($bundle_version)"
echo "  Launch storyboard: $launch_storyboard_name.storyboardc"
echo "  Privacy manifest: present"