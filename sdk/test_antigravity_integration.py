#!/usr/bin/env python3
"""
Antigravity & Antigravity IDE Integration Healthcheck & Verification Script
"""

import os
import sys
import json
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sentinel import ask_permission, guard

def check_daemon():
    print("1️⃣ Checking Sentinel Daemon Status...")
    try:
        with urllib.request.urlopen("http://127.0.0.1:9191/status", timeout=2) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            print(f"   ✓ Daemon is ACTIVE on port {data.get('port')} (socket: {data.get('socket')})")
            return True
    except Exception as e:
        print(f"   ✗ Daemon offline: {e}")
        print("   -> Starting Agent Sentinel...")
        app_path = "/Applications/AgentSentinel.app" if os.path.exists("/Applications/AgentSentinel.app") else "/Users/nipun/.gemini/antigravity-ide/scratch/AgentSentinel/AgentSentinel.app"
        os.system(f"open '{app_path}'")
        return False

def check_ide_hooks():
    print("\n2️⃣ Checking Antigravity IDE Hooks (~/.gemini/config/hooks.json)...")
    path = os.path.expanduser("~/.gemini/config/hooks.json")
    if os.path.exists(path):
        with open(path) as f:
            cfg = json.load(f)
        if "sentinel" in cfg and "PreToolUse" in cfg["sentinel"]:
            print(f"   ✓ Antigravity PreToolUse hook is registered & active in {path}")
            return True
    print("   ✗ Antigravity hook not found. Run: ./bin/sentinel install antigravity")
    return False

def check_mcp_config():
    print("\n3️⃣ Checking Antigravity MCP Server (~/.gemini/config/mcp_config.json)...")
    path = os.path.expanduser("~/.gemini/config/mcp_config.json")
    if os.path.exists(path):
        with open(path) as f:
            cfg = json.load(f)
        if "mcpServers" in cfg and "sentinel" in cfg["mcpServers"]:
            print(f"   ✓ Sentinel MCP Server is registered in {path}")
            return True
    print("   ✗ Sentinel MCP entry missing.")
    return False

def trigger_test_permission():
    print("\n4️⃣ Triggering Live Notch Permission Card for Antigravity...")
    print("   Look up at your MacBook Camera Notch (or top screen island)!")
    print("   You will see the permission card drop down with Touch ID & buttons.")
    
    approved = ask_permission(
        command="docker compose up -d antigravity-core --build",
        title="Deploy Antigravity App Container?",
        subtitle="Antigravity IDE • Agent Deployer",
        risk="high",
        requested_by="Antigravity App",
        modifies_files="Docker environment & containers",
        tool="Docker"
    )
    
    if approved:
        print("   🎉 SUCCESS: User approved action via Sentinel Notch / Touch ID!")
    else:
        print("   🛡️ User denied or closed the prompt.")
    return approved

if __name__ == "__main__":
    print("=" * 60)
    print("  AGENT SENTINEL — ANTIGRAVITY INTEGRATION DIAGNOSTICS")
    print("=" * 60)
    check_daemon()
    check_ide_hooks()
    check_mcp_config()
    if len(sys.argv) > 1 and sys.argv[1] == "--trigger":
        trigger_test_permission()
    else:
        print("\n💡 Run with --trigger to test live popup: python3 sdk/test_antigravity_integration.py --trigger")
