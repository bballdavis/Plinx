#!/bin/bash

# Plinx Vendor Patch Coordinator (Migration-Style)
# This script applies Plinx-specific patches to the Strimr submodule.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRIMR_DIR="$REPO_ROOT/vendor/strimr"
PATCH_DIR="$REPO_ROOT/vendor/Patches/strimr"
MANIFEST_PATH="$PATCH_DIR/manifest.yaml"
VALIDATOR="$REPO_ROOT/scripts/validate_vendor_patches.sh"
STRICT_MODE=false

usage() {
    cat <<'EOF'
Usage: ./scripts/apply_vendor_patches.sh [--strict]

Options:
  --strict    Run validator in strict mode before applying patches
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict)
            STRICT_MODE=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ Error: unknown option '$1'"
            usage
            exit 2
            ;;
    esac
    shift
done

echo "⚡ Plinx Vendor Migrations: Applying patches to Strimr..."

if [ ! -d "$STRIMR_DIR" ]; then
    echo "❌ Error: Strimr directory not found at $STRIMR_DIR"
    exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
    echo "❌ Error: Strimr patch directory not found at $PATCH_DIR"
    echo "   Canonical path is vendor/Patches/strimr"
    exit 1
fi

if [ ! -f "$MANIFEST_PATH" ]; then
    echo "❌ Error: patch manifest not found at $MANIFEST_PATH"
    exit 1
fi

if [ ! -x "$VALIDATOR" ]; then
    echo "❌ Error: validator script is missing or not executable: $VALIDATOR"
    exit 1
fi

if [ -d "$REPO_ROOT/vendor/Patches/Strimr" ] && [ ! "$REPO_ROOT/vendor/Patches/Strimr" -ef "$PATCH_DIR" ]; then
    echo "⚠️  Legacy path detected: vendor/Patches/Strimr (canonical path is vendor/Patches/strimr)"
fi
if [ -d "$REPO_ROOT/vendor/patches/strimr" ] && [ ! "$REPO_ROOT/vendor/patches/strimr" -ef "$PATCH_DIR" ]; then
    echo "⚠️  Legacy path detected: vendor/patches/strimr (canonical path is vendor/Patches/strimr)"
fi

echo "🔎 Running patch governance validation..."
if [ "$STRICT_MODE" = true ]; then
    "$VALIDATOR" --strict-clean --compare-working-tree
else
    "$VALIDATOR"
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
applied_count=0
export LC_ALL=C
for patch in "$PATCH_DIR"/*.patch; do
    if [ -f "$patch" ]; then
        patch_name="$(basename "$patch")"
        echo "🔄 Applying $patch_name..."
        if git apply --check "$patch" > /dev/null 2>&1; then
            git apply "$patch"
            applied_count=$((applied_count + 1))
        else
            echo "⚠️  Patch check failed for $patch_name; attempting 3-way apply..."
            if git apply --3way "$patch"; then
                applied_count=$((applied_count + 1))
            else
                echo "⚠️  3-way apply failed for $patch_name; attempting --reject for diagnostics..."
                git apply --reject "$patch" || true
                echo "❌ Patch $patch_name failed to apply cleanly."
                echo "   Suggested remediation:"
                echo "   - cd vendor/strimr"
                echo "   - git status --short"
                echo "   - resolve *.rej conflicts, then refresh patch + manifest entries"
                echo "   - rerun ./scripts/validate_vendor_patches.sh --strict-clean --compare-working-tree"
                exit 1
            fi
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

manifest_version="$(awk -F ': *' '/^schema_version:/{print $2; exit}' "$MANIFEST_PATH")"
manifest_version="${manifest_version:-unknown}"
echo "✅ All patches applied successfully. Applied $applied_count patch(es). Manifest schema_version=$manifest_version"
