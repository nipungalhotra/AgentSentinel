#!/usr/bin/env sh
# ==============================================================================
# loggdin — Linux installer (also works on macOS for the headless daemon).
# Installs the cross-platform daemon + CLI for the current user. No root needed.
#
#   sh install.sh                install, enable autostart, hook detected agents
#   sh install.sh --no-agents    install without touching agent configs
#   sh install.sh --uninstall    remove integrations, autostart, app menu entry and CLI shim
#   sh install.sh --desktop      what "Install loggdin" (double-click) runs: keeps the window open
# ("sh install.sh" works even when a desktop archive tool dropped the executable bit.)
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
DESKTOP=0
for a in "$@"; do
  case "$a" in
    --no-agents) AGENTS=0 ;;
    --uninstall) UNINSTALL=1 ;;
    --desktop) DESKTOP=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
  esac
done

if [ "$DESKTOP" = 1 ]; then
  # Started by double-clicking "Install loggdin": keep the window open so the result can be read.
  trap 'rc=$?; [ "$rc" = 0 ] || { echo ""; echo "❌ loggdin was not installed (error $rc). See the messages above."; printf "Press Enter to close this window. "; read _ || true; }' EXIT
fi

STATE_DIR="$("$PYTHON" -c 'import importlib.util,sys; s=importlib.util.spec_from_file_location("l", sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print(m.state_dir())' "$BIN_SRC/loggdin.py")"
SHIM_DIR="$HOME/.local/bin"
SHIM="$SHIM_DIR/loggdin"

if [ "$UNINSTALL" = 1 ]; then
  if [ -f "$STATE_DIR/loggdin.py" ]; then
    "$PYTHON" "$STATE_DIR/loggdin.py" uninstall all || true
    "$PYTHON" "$STATE_DIR/loggdin.py" autostart off || true
    "$PYTHON" "$STATE_DIR/loggdin.py" stop || true
  fi
  rm -f "$SHIM" "${XDG_DATA_HOME:-$HOME/.local/share}/applications/loggdin.desktop"
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
"$PYTHON" "$STATE_DIR/loggdin.py" menu on      # "loggdin" in the app menu (Linux), opens the approval page
"$PYTHON" "$STATE_DIR/loggdin.py" restart   # an upgrade runs the new code now, not after the next login

if [ "$AGENTS" = 1 ]; then
  "$PYTHON" "$STATE_DIR/loggdin.py" install detected || true
fi

case ":$PATH:" in
  *":$SHIM_DIR:"*) ;;
  *) grep -qs '\.local/bin' "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zprofile" ||   # most distros add it at login
     echo "ℹ️  Add $SHIM_DIR to your PATH, e.g.: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.profile" ;;
esac
command -v node >/dev/null 2>&1 || echo "ℹ️  Node.js not found: needed only for the MCP integration (Cursor / Claude Desktop)."
[ "$(uname -s)" != "Linux" ] || command -v notify-send >/dev/null 2>&1 || echo "ℹ️  'notify-send' not found: install libnotify-bin for desktop notifications."

echo ""
echo "🎉 Done. Approve requests with:  loggdin ui   (or: loggdin allow / loggdin deny)"
if [ "$DESKTOP" = 1 ]; then
  echo ""
  echo "loggdin is running and starts when you log in. Open it any time from your app menu: \"loggdin\"."
  echo "To answer from your phone: on the loggdin page that just opened, use \"Turn on phone approvals\"."
  "$PYTHON" "$STATE_DIR/loggdin.py" ui >/dev/null 2>&1 || true
  printf "Press Enter to close this window. "
  read _ || true
fi
