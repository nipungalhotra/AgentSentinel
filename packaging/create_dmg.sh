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
VERSION="1.2.0"

echo "=========================================================="
echo "🛡️  loggdin Production Release Packager (v${VERSION})"
echo "=========================================================="

echo "🔨 [1/5] Compiling release binary with swift build..."
cd "$PROJECT_ROOT"
swift build -c release

RELEASE_BIN=""
CANDIDATE_PATHS=(
    "$PROJECT_ROOT/.build/arm64-apple-macosx/release/loggdin"
    "$PROJECT_ROOT/.build/release/loggdin"
    "$PROJECT_ROOT/.build/out/Products/Release/loggdin"
    "$PROJECT_ROOT/.build/apple/Products/Release/loggdin"
)

for p in "${CANDIDATE_PATHS[@]}"; do
    if [ -f "$p" ] && [ -x "$p" ]; then
        RELEASE_BIN="$p"
        break
    fi
done

if [ -z "$RELEASE_BIN" ]; then
    echo "❌ Error: Could not locate compiled loggdin release binary in .build/"
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
ln -sf "loggdin" "$APP_BUNDLE/Contents/Resources/bin/sentinel"

echo "✓ Loggdin.app assembled cleanly at: $APP_BUNDLE"

# Ad-hoc or Developer ID code signing
if command -v codesign >/dev/null 2>&1; then
    SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
    echo "🔏 Signing application bundle (Identity: $SIGN_IDENTITY)..."
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE" 2>/dev/null || true
fi

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
rm -f "$DMG_OUTPUT" "$DIST_DIR/loggdin-v${VERSION}.dmg"
hdiutil create -volname "loggdin" \
    -srcfolder "$TMP_DMG_DIR" \
    -ov -format UDZO \
    "$DMG_OUTPUT"

rm -rf "$TMP_DMG_DIR"

# Also symlink or copy to versioned DMG name
cp "$DMG_OUTPUT" "$DIST_DIR/loggdin-v${VERSION}.dmg"

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
