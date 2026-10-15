#!/usr/bin/env bash
set -e

VERSION="1.2.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/dmg-root"
DMG_NAME="AgentSentinel-v${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "=================================================="
echo "  Packaging Agent Sentinel v${VERSION} for Release"
echo "=================================================="

# 1. Clean previous build staging
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"

# 2. Copy application bundle
if [ -d "/Applications/AgentSentinel.app" ]; then
    APP_SRC="/Applications/AgentSentinel.app"
elif [ -d "$ROOT_DIR/AgentSentinel.app" ]; then
    APP_SRC="$ROOT_DIR/AgentSentinel.app"
else
    echo "❌ Error: AgentSentinel.app not found in /Applications or repo root."
    exit 1
fi

echo "📦 Staging application from: $APP_SRC"
cp -R "$APP_SRC" "$STAGE_DIR/"

# 3. Create Applications symlink for drag-and-drop install
ln -s /Applications "$STAGE_DIR/Applications"

# 4. Include CLI setup shortcut
cat << 'EOF' > "$STAGE_DIR/Install CLI.command"
#!/usr/bin/env bash
echo "🛡️ Installing Agent Sentinel CLI to /usr/local/bin..."
sudo mkdir -p /usr/local/bin
sudo cp "/Applications/AgentSentinel.app/Contents/MacOS/AgentSentinel" /usr/local/bin/agent-sentinel 2>/dev/null || true
if [ -f "$HOME/.local/bin/sentinel" ]; then
    echo "✓ Global CLI already configured in ~/.local/bin/sentinel"
else
    mkdir -p "$HOME/.local/bin"
    curl -fsSL https://raw.githubusercontent.com/nipungalhotra/AgentSentinel/main/bin/sentinel -o "$HOME/.local/bin/sentinel"
    chmod +x "$HOME/.local/bin/sentinel"
    echo "✓ Installed to $HOME/.local/bin/sentinel"
fi
echo "🎉 Setup complete! Try running 'sentinel status' in your terminal."
read -p "Press Enter to exit..."
EOF
chmod +x "$STAGE_DIR/Install CLI.command"

# 5. Build DMG with hdiutil
echo "💿 Creating compressed disk image: $DMG_PATH"
hdiutil create \
    -volname "Agent Sentinel" \
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
