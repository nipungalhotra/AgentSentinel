#!/usr/bin/env bash
# ==============================================================================
# loggdin — Hermetic Production DMG Creator & Packager
# Builds a self-contained release .app and .dmg installer ready for distribution.
# Does NOT require pre-existing /Applications/Loggdin.app or root artifacts.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/Loggdin.app"
DMG_OUTPUT="$DIST_DIR/Loggdin.dmg"
# Single source of truth for the version: packaging/Info.plist
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/packaging/Info.plist")"

# Optional release signing / notarization (required for smooth installs on other Macs):
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="loggdin-notary"   # created once with: xcrun notarytool store-credentials
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

echo "=========================================================="
echo "🛡️  loggdin Production Release Packager (v${VERSION})"
echo "=========================================================="

echo "🔨 [1/5] Compiling universal (arm64 + x86_64) release binary..."
cd "$PROJECT_ROOT"
swift build -c release --arch arm64 --arch x86_64

RELEASE_BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/loggdin"
if [ ! -x "$RELEASE_BIN" ]; then
    echo "❌ Error: Could not locate compiled loggdin release binary at $RELEASE_BIN"
    exit 1
fi
ARCHS="$(lipo -archs "$RELEASE_BIN")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
    echo "❌ Error: release binary is not universal (archs: $ARCHS)"
    exit 1
fi
echo "✓ Found compiled release binary: $RELEASE_BIN"

echo "📦 [2/5] Constructing hermetic Loggdin.app bundle..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/bin"

# 1. Main executable
cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/loggdin"
chmod 755 "$APP_BUNDLE/Contents/MacOS/loggdin"

# 2. Info.plist from canonical source
if [ -f "$PROJECT_ROOT/packaging/Info.plist" ]; then
    cp "$PROJECT_ROOT/packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
elif [ -f "$PROJECT_ROOT/assets/Info.plist" ]; then
    cp "$PROJECT_ROOT/assets/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
else
    echo "❌ Error: Info.plist not found in packaging/ or assets/"
    exit 1
fi

# 3. Application icon
if [ -f "$PROJECT_ROOT/assets/AppIcon.icns" ]; then
    cp "$PROJECT_ROOT/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 4. Bundle CLI helper scripts inside app bundle resources
if [ -f "$PROJECT_ROOT/bin/loggdin" ]; then
    cp "$PROJECT_ROOT/bin/loggdin" "$APP_BUNDLE/Contents/Resources/bin/loggdin"
    chmod 755 "$APP_BUNDLE/Contents/Resources/bin/loggdin"
fi
if [ -f "$PROJECT_ROOT/bin/sentinel-hook" ]; then
    cp "$PROJECT_ROOT/bin/sentinel-hook" "$APP_BUNDLE/Contents/Resources/bin/sentinel-hook"
    cp "$PROJECT_ROOT/bin/sentinel-hook" "$APP_BUNDLE/Contents/Resources/sentinel-hook"
    chmod 755 "$APP_BUNDLE/Contents/Resources/bin/sentinel-hook" "$APP_BUNDLE/Contents/Resources/sentinel-hook"
fi
if [ -f "$PROJECT_ROOT/bin/sentinel-mcp.js" ]; then
    cp "$PROJECT_ROOT/bin/sentinel-mcp.js" "$APP_BUNDLE/Contents/Resources/bin/sentinel-mcp.js"
    cp "$PROJECT_ROOT/bin/sentinel-mcp.js" "$APP_BUNDLE/Contents/Resources/sentinel-mcp.js"
    chmod 755 "$APP_BUNDLE/Contents/Resources/bin/sentinel-mcp.js" "$APP_BUNDLE/Contents/Resources/sentinel-mcp.js"
fi
if [ -f "$PROJECT_ROOT/bin/loggdin.py" ]; then
    cp "$PROJECT_ROOT/bin/loggdin.py" "$APP_BUNDLE/Contents/Resources/bin/loggdin.py"
    chmod 755 "$APP_BUNDLE/Contents/Resources/bin/loggdin.py"
fi
# The original sentinel script is kept as sentinel-installer (zsh integration);
# `sentinel` itself is an alias of the loggdin CLI.
if [ -f "$PROJECT_ROOT/bin/sentinel" ]; then
    cp "$PROJECT_ROOT/bin/sentinel" "$APP_BUNDLE/Contents/Resources/bin/sentinel-installer"
    chmod 755 "$APP_BUNDLE/Contents/Resources/bin/sentinel-installer"
fi
ln -sf "loggdin" "$APP_BUNDLE/Contents/Resources/bin/sentinel"

echo "✓ Loggdin.app assembled cleanly at: $APP_BUNDLE"

# Code signing. Ad-hoc signatures are rejected by Gatekeeper on every Mac except
# the one that built the app, so a public release MUST use a Developer ID.
xattr -cr "$APP_BUNDLE"
if [ -n "$CODESIGN_IDENTITY" ]; then
    echo "🔏 Signing with Developer ID + hardened runtime: $CODESIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "⚠️  CODESIGN_IDENTITY not set — ad-hoc signing (LOCAL TESTING ONLY)."
    echo "   Other Macs will show \"Apple could not verify Loggdin\" and refuse to open it."
    codesign --force --sign - "$APP_BUNDLE"
fi
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

echo "💿 [3/5] Staging disk image contents..."
TMP_DMG_DIR="$(mktemp -d -t loggdin_dmg)"
cp -R "$APP_BUNDLE" "$TMP_DMG_DIR/"
ln -s /Applications "$TMP_DMG_DIR/Applications"

# Optional double-click terminal installer for users without Homebrew
cat << 'EOF' > "$TMP_DMG_DIR/Install CLI.command"
#!/usr/bin/env bash
set -e
echo "🛡️  Installing loggdin CLI into ~/.local/bin..."
mkdir -p "$HOME/.local/bin"
APP="/Applications/Loggdin.app"
if [ ! -d "$APP" ]; then
    APP="$(dirname "$0")/Loggdin.app"
fi
if [ -f "$APP/Contents/Resources/bin/loggdin" ]; then
    cp "$APP/Contents/Resources/bin/loggdin" "$HOME/.local/bin/loggdin"
    chmod +x "$HOME/.local/bin/loggdin"
    ln -sf "$HOME/.local/bin/loggdin" "$HOME/.local/bin/sentinel"
    echo "✓ loggdin CLI installed to $HOME/.local/bin/loggdin (and aliased as sentinel)"
else
    echo "⚠️  Could not locate Loggdin.app in /Applications. Please drag Loggdin to Applications first."
fi
echo "🎉 Setup complete! Try running 'loggdin status' in your terminal."
read -p "Press Enter to finish..."
EOF
chmod 755 "$TMP_DMG_DIR/Install CLI.command"

echo "💿 [4/5] Building compressed read-only DMG with hdiutil..."
VERSIONED_DMG="$DIST_DIR/loggdin-v${VERSION}.dmg"
rm -f "$DMG_OUTPUT" "$VERSIONED_DMG"
hdiutil create -volname "loggdin" \
    -srcfolder "$TMP_DMG_DIR" \
    -ov -format UDZO \
    "$DMG_OUTPUT"

rm -rf "$TMP_DMG_DIR"

if [ -n "$CODESIGN_IDENTITY" ]; then
    codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_OUTPUT"
    if [ -n "$NOTARY_PROFILE" ]; then
        echo "📨 Submitting DMG to Apple notary service (this can take a few minutes)..."
        xcrun notarytool submit "$DMG_OUTPUT" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG_OUTPUT"
        spctl -a -vvv -t open --context context:primary-signature "$DMG_OUTPUT"
    else
        echo "⚠️  NOTARY_PROFILE not set — DMG is signed but NOT notarized; Gatekeeper will still block it."
    fi
fi

# Versioned copy — this is the filename the Homebrew casks download
cp "$DMG_OUTPUT" "$VERSIONED_DMG"

echo "🔒 [5/5] Computing cryptographic SHA256 checksums..."
SHA256=$(shasum -a 256 "$DMG_OUTPUT" | awk '{print $1}')
echo "$SHA256  Loggdin.dmg" > "$DIST_DIR/Loggdin.dmg.sha256"
echo "$SHA256  loggdin-v${VERSION}.dmg" > "$DIST_DIR/loggdin-v${VERSION}.dmg.sha256"

echo ""
echo "=========================================================="
echo "✅ Production Release DMG Ready!"
echo "   Artifact: $DMG_OUTPUT"
echo "   Size:     $(du -h "$DMG_OUTPUT" | awk '{print $1}')"
echo "   SHA256:   $SHA256"
echo "=========================================================="
