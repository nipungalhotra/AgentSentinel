#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "  PACKAGING & PORTABILITY INTEGRITY TESTS"
echo "=========================================="

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "1. Checking for forbidden hardcoded personal paths..."
TARGET_STR="/Users/""nipun"
if grep -rn "$TARGET_STR" Sources Casks bin packaging sdk tests \
    --exclude="*.log" --exclude="*.dmg" --exclude="*.icns" --exclude="*.pyc" \
    --exclude-dir="__pycache__" --exclude="test_packaging_integrity.sh" 2>/dev/null; then
  echo "❌ FAILED: Found hardcoded personal paths in codebase!"
  exit 1
fi
echo "✓ No hardcoded personal paths found in code, scripts, or casks."

echo "2. Checking CLI script syntax..."
bash -n bin/sentinel
bash -n bin/loggdin
bash -n packaging/create_dmg.sh
python3 -m py_compile bin/sentinel-hook
echo "✓ All CLI scripts passed syntax checks."

echo "3. Checking Node.js MCP server syntax..."
node -c bin/sentinel-mcp.js
echo "✓ bin/sentinel-mcp.js passed syntax check."

echo "4. Checking Homebrew Casks for supply chain safety..."
if grep -r "curl " Casks packaging/loggdin.rb 2>/dev/null; then
  echo "❌ FAILED: Found unverified curl in Homebrew Cask files!"
  exit 1
fi
echo "✓ Homebrew casks use safe, hermetic binary distribution."

echo "5. Verifying Info.plist exists..."
if [[ ! -f "packaging/Info.plist" ]]; then
  echo "❌ FAILED: packaging/Info.plist is missing!"
  exit 1
fi
echo "✓ packaging/Info.plist exists and is ready for DMG creation."

echo ""
echo "🎉 ALL PACKAGING & PORTABILITY INTEGRITY CHECKS PASSED!"
