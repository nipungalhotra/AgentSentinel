#!/usr/bin/env bash
set -e

VERSION="1.2.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/dmg-root"
DMG_NAME="loggdin-v${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "=================================================="
echo "  Packaging loggdin v${VERSION} for Release"
echo "=================================================="

# 1. Clean previous build staging
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"

# 2. Copy application bundle
if [ -d "/Applications/Loggdin.app" ]; then
    APP_SRC="/Applications/Loggdin.app"
elif [ -d "$ROOT_DIR/Loggdin.app" ]; then
    APP_SRC="$ROOT_DIR/Loggdin.app"
elif [ -d "/Applications/AgentSentinel.app" ]; then
    APP_SRC="/Applications/AgentSentinel.app"
else
    echo "❌ Error: Loggdin.app not found."
    exit 1
fi

echo "📦 Staging application from: $APP_SRC"
cp -R "$APP_SRC" "$STAGE_DIR/"

# 3. Create Applications symlink for drag-and-drop install
ln -s /Applications "$STAGE_DIR/Applications"

# 4. Include CLI setup shortcut
cat << 'EOF' > "$STAGE_DIR/Install CLI.command"
#!/usr/bin/env bash
echo "🛡️ Installing loggdin CLI..."
mkdir -p "$HOME/.local/bin"
cp "/Applications/Loggdin.app/Contents/MacOS/loggdin" "$HOME/.local/bin/loggdin" 2>/dev/null || true
chmod +x "$HOME/.local/bin/loggdin"
ln -sf "$HOME/.local/bin/loggdin" "$HOME/.local/bin/sentinel"
echo "✓ Installed to $HOME/.local/bin/loggdin (and aliased as sentinel)"
echo "🎉 Setup complete! Try running 'loggdin status' in your terminal."
read -p "Press Enter to exit..."
EOF
chmod +x "$STAGE_DIR/Install CLI.command"

# 5. Build DMG with hdiutil
echo "💿 Creating compressed disk image: $DMG_PATH"
hdiutil create \
    -volname "loggdin" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# 6. Compute SHA256 checksum
echo "🔒 Computing SHA256 Checksum..."
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "$SHA256" > "$DIST_DIR/${DMG_NAME}.sha256"

echo ""
echo "=================================================="
echo "✅ Release DMG built successfully!"
echo "   File:   $DMG_PATH"
echo "   Size:   $(du -h "$DMG_PATH" | awk '{print $1}')"
echo "   SHA256: $SHA256"
echo "=================================================="
