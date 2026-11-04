#!/usr/bin/env bash
# ==============================================================================
# loggdin — portable package for Windows & Linux
# Produces dist/loggdin-portable-v<version>.zip (+ .sha256) containing the
# dependency-free Python daemon/CLI, hook relay, MCP server and installers.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(python3 -c 'import re,sys; print(re.search(r"^VERSION = \"([^\"]+)\"", open(sys.argv[1]).read(), re.M).group(1))' "$PROJECT_ROOT/bin/loggdin.py")"
NAME="loggdin-portable-v${VERSION}"
STAGE="$(mktemp -d)/$NAME"
DIST="$PROJECT_ROOT/dist"

mkdir -p "$STAGE" "$DIST"
cp "$PROJECT_ROOT/bin/loggdin.py" "$PROJECT_ROOT/bin/sentinel-hook" "$PROJECT_ROOT/bin/sentinel-mcp.js" "$STAGE/"
cp "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/install.ps1" "$STAGE/"
chmod 755 "$STAGE/install.sh" "$STAGE/loggdin.py" "$STAGE/sentinel-hook"
cat > "$STAGE/README.txt" <<TXT
loggdin ${VERSION} — permission gate for AI coding agents (Windows & Linux)

Requirements: Python 3.9+.  Optional: Node.js (MCP for Cursor / Claude Desktop),
notify-send on Linux for desktop notifications.

Linux:    ./install.sh
Windows:  powershell -ExecutionPolicy Bypass -File install.ps1

Then approve agent requests with:  loggdin ui   (or loggdin allow / loggdin deny)
Uninstall: ./install.sh --uninstall   |   install.ps1 -Uninstall
TXT

rm -f "$DIST/$NAME.zip"
( cd "$(dirname "$STAGE")" && python3 - "$NAME" "$DIST/$NAME.zip" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in sorted(files):
            p = os.path.join(root, f)
            info = zipfile.ZipInfo.from_file(p, p)
            info.external_attr = (0o755 if os.access(p, os.X_OK) else 0o644) << 16
            with open(p, "rb") as fh:
                z.writestr(info, fh.read(), zipfile.ZIP_DEFLATED)
PY
)
rm -rf "$(dirname "$STAGE")"
( cd "$DIST" && shasum -a 256 "$NAME.zip" 2>/dev/null || sha256sum "$NAME.zip" ) > "$DIST/$NAME.zip.sha256"
echo "✅ Portable package: $DIST/$NAME.zip"
cat "$DIST/$NAME.zip.sha256"
