#!/usr/bin/env bash
# ==============================================================================
# loggdin — Production DMG Creator & Packager
# Builds a release .dmg installer ready for distribution and GitHub Releases.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build/release"
APP_BUNDLE="$PROJECT_ROOT/dist/Loggdin.app"
DMG_OUTPUT="$PROJECT_ROOT/dist/Loggdin.dmg"

echo "🔨 [1/4] Preparing release binary..."
cd "$PROJECT_ROOT"

# Find existing or newly built release binary
RELEASE_BIN=""
if swift build -c release 2>/dev/null; then
    if [ -f "$PROJECT_ROOT/.build/release/loggdin" ]; then
        RELEASE_BIN="$PROJECT_ROOT/.build/release/loggdin"
    elif [ -f "$PROJECT_ROOT/.build/arm64-apple-macosx/release/loggdin" ]; then
        RELEASE_BIN="$PROJECT_ROOT/.build/arm64-apple-macosx/release/loggdin"
    fi
fi

if [ -z "$RELEASE_BIN" ] || [ ! -f "$RELEASE_BIN" ]; then
    if [ -f "$PROJECT_ROOT/.build/arm64-apple-macosx/release/loggdin" ]; then
        RELEASE_BIN="$PROJECT_ROOT/.build/arm64-apple-macosx/release/loggdin"
    elif [ -f "/Applications/Loggdin.app/Contents/MacOS/loggdin" ]; then
        RELEASE_BIN="/Applications/Loggdin.app/Contents/MacOS/loggdin"
    else
        echo "❌ Error: Could not locate compiled loggdin binary."
        exit 1
    fi
fi
echo "Using release binary: $RELEASE_BIN"

echo "📦 [2/4] Packaging Loggdin.app bundle..."
mkdir -p "$PROJECT_ROOT/dist"
rm -rf "$APP_BUNDLE" "$DMG_OUTPUT"

# Copy structure from installed app or create bundle
if [ -d "/Applications/Loggdin.app" ]; then
    cp -R "/Applications/Loggdin.app" "$APP_BUNDLE"
else
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"
fi

cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/loggdin"
chmod +x "$APP_BUNDLE/Contents/MacOS/loggdin"
cp "$PROJECT_ROOT/Loggdin.app/Contents/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$PROJECT_ROOT/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "💿 [3/4] Generating disk image (.dmg)..."
TMP_DMG_DIR="$(mktemp -d -t loggdin_dmg)"
cp -R "$APP_BUNDLE" "$TMP_DMG_DIR/"
ln -s /Applications "$TMP_DMG_DIR/Applications"

# Create compressed read-only DMG with hdiutil
hdiutil create -volname "loggdin" \
    -srcfolder "$TMP_DMG_DIR" \
    -ov -format UDZO \
    "$DMG_OUTPUT"

rm -rf "$TMP_DMG_DIR"

echo "✅ [4/4] Production DMG ready at: $DMG_OUTPUT"
ls -lh "$DMG_OUTPUT"
