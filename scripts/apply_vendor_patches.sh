#!/bin/bash

# Plinx Vendor Patch Coordinator (Migration-Style)
# This script applies Plinx-specific patches to the Strimr submodule.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRIMR_DIR="$REPO_ROOT/vendor/strimr"

if [ -d "$REPO_ROOT/vendor/Patches/Strimr" ]; then
    PATCH_DIR="$REPO_ROOT/vendor/Patches/Strimr"
elif [ -d "$REPO_ROOT/vendor/Patches/strimr" ]; then
    PATCH_DIR="$REPO_ROOT/vendor/Patches/strimr"
elif [ -d "$REPO_ROOT/vendor/patches/strimr" ]; then
    PATCH_DIR="$REPO_ROOT/vendor/patches/strimr"
else
    echo "❌ Error: Strimr patch directory not found. Checked:"
    echo "   - $REPO_ROOT/vendor/Patches/Strimr"
    echo "   - $REPO_ROOT/vendor/Patches/strimr"
    echo "   - $REPO_ROOT/vendor/patches/strimr"
    exit 1
fi

echo "⚡ Plinx Vendor Migrations: Applying patches to Strimr..."

if [ ! -d "$STRIMR_DIR" ]; then
    echo "❌ Error: Strimr directory not found at $STRIMR_DIR"
    exit 1
fi

BRAND_SRC_DIR="$REPO_ROOT/assets/branding"
ICON_COMPOSER_SRC_DIR="$REPO_ROOT/.local_dev/assets/Plinx_icon_Pack.icon"
APP_ICONSET_DIR="$REPO_ROOT/PlinxApp/Resources/Assets.xcassets/AppIcon.appiconset"

pushd "$STRIMR_DIR" > /dev/null

# 1. Reset Strimr to its pinned submodule commit to ensure a clean slate
echo "🧹 Cleaning Strimr state..."
git reset --hard HEAD
git clean -fd

# 2. Apply patches in numeric order
for patch in "$PATCH_DIR"/*.patch; do
    if [ -f "$patch" ]; then
        echo "🔄 Applying $(basename "$patch")..."
        if git apply --check "$patch" > /dev/null 2>&1; then
            git apply "$patch"
        else
            echo "⚠️  Conflict detected in $(basename "$patch")."
            echo "   Attempting to apply with 3-way merge or manual intervention may be required."
            git apply --reject "$patch" || true
            echo "❌ Patch $(basename "$patch") failed to apply cleanly. See .rej files in Vendor/Strimr."
            exit 1
        fi
    fi
done

popd > /dev/null

echo "🎨 Syncing Plinx branding assets..."
if [ ! -d "$BRAND_SRC_DIR" ]; then
    echo "❌ Error: branding source directory not found at $BRAND_SRC_DIR"
    exit 1
fi

copy_brand_asset() {
    local src="$1"
    local dst="$2"
    if [ ! -f "$src" ]; then
        echo "❌ Error: missing branding asset: $src"
        exit 1
    fi
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
}

sync_icon_composer_bundle() {
    if [ ! -f "$ICON_COMPOSER_SRC_DIR/icon.json" ]; then
        echo "⚠️  Icon Composer bundle not found at $ICON_COMPOSER_SRC_DIR; skipping composer sync."
        return
    fi

    mkdir -p "$APP_ICONSET_DIR/Assets"
    cp -f "$ICON_COMPOSER_SRC_DIR/icon.json" "$APP_ICONSET_DIR/icon.json"

    if [ -d "$ICON_COMPOSER_SRC_DIR/Assets" ]; then
        find "$ICON_COMPOSER_SRC_DIR/Assets" -type f | while IFS= read -r src; do
            rel="${src#"$ICON_COMPOSER_SRC_DIR/Assets/"}"
            dst="$APP_ICONSET_DIR/Assets/$rel"
            mkdir -p "$(dirname "$dst")"
            cp -f "$src" "$dst"
        done
    fi
}

# Vendor Strimr catalog assets (patched in vendor submodule)
copy_brand_asset "$BRAND_SRC_DIR/appicon_ios_1024.jpg" \
    "$STRIMR_DIR/Strimr-iOS/Assets.xcassets/AppIcon.appiconset/logo_ios-100.jpg"
copy_brand_asset "$BRAND_SRC_DIR/logo_color.png" \
    "$STRIMR_DIR/Strimr-iOS/Assets.xcassets/Icon.imageset/logo_ios.png"

# App-local icon source-of-truth from Icon Composer package
sync_icon_composer_bundle

# App-local catalog assets used by Plinx views + launch screen
copy_brand_asset "$BRAND_SRC_DIR/logo_color.png" \
    "$REPO_ROOT/PlinxApp/Resources/Assets.xcassets/LogoColor.imageset/logo_color.png"
copy_brand_asset "$BRAND_SRC_DIR/logo_dark.png" \
    "$REPO_ROOT/PlinxApp/Resources/Assets.xcassets/LogoDark.imageset/logo_dark.png"
copy_brand_asset "$BRAND_SRC_DIR/logo_white.png" \
    "$REPO_ROOT/PlinxApp/Resources/Assets.xcassets/LogoWhite.imageset/logo_white.png"
copy_brand_asset "$BRAND_SRC_DIR/logo_full_color.png" \
    "$REPO_ROOT/PlinxApp/Resources/Assets.xcassets/LogoFullColor.imageset/logo_full_color.png"
copy_brand_asset "$BRAND_SRC_DIR/logo_full_white.png" \
    "$REPO_ROOT/PlinxApp/Resources/Assets.xcassets/LogoFullWhite.imageset/logo_full_white.png"

echo "✅ All patches applied successfully."
