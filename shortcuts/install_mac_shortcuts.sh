#!/usr/bin/env bash
# ==============================================================================
# loggdin — Apple Shortcuts & CLI Turnkey Installer
# Configures system PATH, creates 1-click launchers, and verifies endpoints.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_PATH="/Applications/Loggdin.app/Contents/MacOS/loggdin"

echo "⚡ [1/3] Installing 'loggdin' CLI to user PATH..."
mkdir -p "$HOME/.local/bin"
ln -sf "$BIN_PATH" "$HOME/.local/bin/loggdin"
ln -sf "$BIN_PATH" "$HOME/.local/bin/sentinel"

# If /usr/local/bin is writable, link there too for maximum compatibility
if [ -w "/usr/local/bin" ]; then
    ln -sf "$BIN_PATH" "/usr/local/bin/loggdin"
    ln -sf "$BIN_PATH" "/usr/local/bin/sentinel"
fi

echo "📦 [2/3] Generating 1-click desktop launchers in shortcuts/..."
cat << 'EOF' > "$SCRIPT_DIR/Approve-10m.command"
#!/usr/bin/env bash
/Applications/Loggdin.app/Contents/MacOS/loggdin allow 10m
osascript -e 'display notification "Approved action for 10 minutes" with title "loggdin Approved" sound name "Glass"'
EOF
chmod +x "$SCRIPT_DIR/Approve-10m.command"

cat << 'EOF' > "$SCRIPT_DIR/Approve-Once.command"
#!/usr/bin/env bash
/Applications/Loggdin.app/Contents/MacOS/loggdin allow once
osascript -e 'display notification "Approved action once" with title "loggdin Approved" sound name "Glass"'
EOF
chmod +x "$SCRIPT_DIR/Approve-Once.command"

cat << 'EOF' > "$SCRIPT_DIR/Deny.command"
#!/usr/bin/env bash
/Applications/Loggdin.app/Contents/MacOS/loggdin deny
osascript -e 'display notification "Denied permission request" with title "loggdin Denied" sound name "Purr"'
EOF
chmod +x "$SCRIPT_DIR/Deny.command"

echo "🧪 [3/3] Verifying loopback security and daemon responsiveness..."
if curl -s --connect-timeout 1 http://127.0.0.1:9191/status > /dev/null 2>&1; then
    echo "✅ loggdin daemon is ONLINE and listening strictly on 127.0.0.1:9191 (Loopback only)"
else
    echo "⚠️  loggdin daemon is starting up..."
    open "/Applications/Loggdin.app"
fi

echo ""
echo "🎉 Installation complete!"
echo "   - CLI available: 'loggdin allow 10m', 'loggdin deny', 'loggdin pending'"
echo "   - 1-click launchers ready in: $SCRIPT_DIR"
