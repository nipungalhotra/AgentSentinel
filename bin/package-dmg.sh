#!/usr/bin/env bash
# ==============================================================================
# loggdin — Release Packaging Wrapper
# Invokes the canonical hermetic packaging script at packaging/create_dmg.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

exec "$PROJECT_ROOT/packaging/create_dmg.sh" "$@"
