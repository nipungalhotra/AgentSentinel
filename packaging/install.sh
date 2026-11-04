#!/usr/bin/env sh
# ==============================================================================
# loggdin — Linux installer (also works on macOS for the headless daemon).
# Installs the cross-platform daemon + CLI for the current user. No root needed.
#
#   ./install.sh                 install, enable autostart, hook detected agents
#   ./install.sh --no-agents     install without touching agent configs
#   ./install.sh --uninstall     remove integrations, autostart and CLI shim
# ==============================================================================
set -eu

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
# Accept both the release zip layout (files next to this script) and the repo layout (../bin).
if [ -f "$SRC_DIR/loggdin.py" ]; then BIN_SRC="$SRC_DIR"; else BIN_SRC="$SRC_DIR/../bin"; fi

PYTHON="${PYTHON:-}"
if [ -z "$PYTHON" ]; then
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
      PYTHON="$(command -v "$c")"; break
    fi
  done
fi
if [ -z "$PYTHON" ]; then
  echo "❌ Python 3.9+ is required. Install it with your package manager (e.g. 'sudo apt install python3') and re-run." >&2
  exit 1
fi

AGENTS=1
UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --no-agents) AGENTS=0 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
  esac
done

STATE_DIR="$("$PYTHON" -c 'import importlib.util,sys; s=importlib.util.spec_from_file_location("l", sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print(m.state_dir())' "$BIN_SRC/loggdin.py")"
SHIM_DIR="$HOME/.local/bin"
SHIM="$SHIM_DIR/loggdin"

if [ "$UNINSTALL" = 1 ]; then
  if [ -f "$STATE_DIR/loggdin.py" ]; then
    "$PYTHON" "$STATE_DIR/loggdin.py" uninstall all || true
    "$PYTHON" "$STATE_DIR/loggdin.py" autostart off || true
    "$PYTHON" "$STATE_DIR/loggdin.py" stop || true
  fi
  rm -f "$SHIM"
  echo "✓ loggdin removed. Your rules and audit log are kept in $STATE_DIR (delete it to erase them)."
  exit 0
fi

echo "🛡️  Installing loggdin for $(uname -s) with $PYTHON"
"$PYTHON" "$BIN_SRC/loggdin.py" deploy

mkdir -p "$SHIM_DIR"
cat > "$SHIM" <<EOF
#!/usr/bin/env sh
exec "$PYTHON" "$STATE_DIR/loggdin.py" "\$@"
EOF
chmod 755 "$SHIM"
echo "✓ CLI installed: $SHIM"

"$PYTHON" "$STATE_DIR/loggdin.py" autostart on
"$PYTHON" "$STATE_DIR/loggdin.py" start

if [ "$AGENTS" = 1 ]; then
  "$PYTHON" "$STATE_DIR/loggdin.py" install detected || true
fi

case ":$PATH:" in
  *":$SHIM_DIR:"*) ;;
  *) echo "ℹ️  Add $SHIM_DIR to your PATH, e.g.: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.profile" ;;
esac
command -v node >/dev/null 2>&1 || echo "ℹ️  Node.js not found: needed only for the MCP integration (Cursor / Claude Desktop)."
[ "$(uname -s)" != "Linux" ] || command -v notify-send >/dev/null 2>&1 || echo "ℹ️  'notify-send' not found: install libnotify-bin for desktop notifications."

echo ""
echo "🎉 Done. Approve requests with:  loggdin ui   (or: loggdin allow / loggdin deny)"
