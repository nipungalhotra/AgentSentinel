#!/usr/bin/env bash
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "================================================================"
echo "      LOGGDIN / AGENT SENTINEL — COMPREHENSIVE TEST SUITE       "
echo "================================================================"
echo ""

FAILED_TESTS=0

run_test() {
  local name="$1"
  shift
  echo "▶ Running ${name}..."
  if "$@"; then
    echo "  ✅ ${name} PASSED"
  else
    echo "  ❌ ${name} FAILED"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
  echo "----------------------------------------------------------------"
}

run_test "Packaging & Portability Integrity" bash tests/test_packaging_integrity.sh
run_test "RulesEngine Logic & Merkle Audit" python3 tests/test_rules_engine_logic.py
run_test "Component Robustness (Rules & Hooks)" python3 tests/test_components_robustness.py
run_test "Python SDK (sentinel.py & loggdin.py)" python3 tests/test_sdk_python.py
run_test "Node.js SDK (sentinel.js)" node tests/test_sdk_node.js
run_test "MCP Server Protocol & Tools" python3 tests/test_mcp_server.py

echo ""
if [[ $FAILED_TESTS -eq 0 ]]; then
  echo "🎉 ALL TEST SUITES PASSED CLEANLY! (6/6 suites successful)"
  exit 0
else
  echo "⚠️ TEST SUITE FAILED with ${FAILED_TESTS} failures."
  exit 1
fi
