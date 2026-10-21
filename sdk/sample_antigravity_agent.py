#!/usr/bin/env python3
"""
Complete Antigravity Agent Demo with loggdin Permission Gating
Demonstrates how an Antigravity agent asks permission via the Liquid Glass notch card.
"""

import asyncio
import os
import sys

# Add loggdin SDK to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from loggdin_antigravity import make_loggdin_approval_handler

# Mock ToolCall structure matching google-antigravity SDK
class MockToolCall:
    def __init__(self, name: str, args: dict):
        self.name = name
        self.args = args

async def run_antigravity_agent():
    print("=" * 64)
    print("  ANTIGRAVITY AGENT — LIVE PERMISSION DEMO")
    print("=" * 64)
    print("\n🤖 [Antigravity Agent]: Starting autonomous maintenance task...")
    await asyncio.sleep(1)

    print("🤖 [Antigravity Agent]: Step 1: Inspecting configuration... (Safe, allowed)")
    await asyncio.sleep(1)

    print("🤖 [Antigravity Agent]: Step 2: Requesting high-risk action...")
    print("   Action: Restart production database & prune volumes")
    print("\n🚨 [loggdin Gate]: Pausing Antigravity agent...")
    print("   Look up at your camera notch / screen top to approve with Touch ID!\n")

    # The approval handler that connects Antigravity to loggdin:
    handler = make_loggdin_approval_handler(agent_name="Antigravity Core Agent")
    tool_call = MockToolCall(
        name="run_command",
        args={
            "CommandLine": "docker compose down -v && docker compose up -d",
            "cwd": os.path.expanduser("~")
        }
    )

    allowed = await handler(tool_call)

    if allowed:
        print("\n🎉 [Antigravity Agent]: Permission GRANTED via loggdin notch card / Touch ID!")
        print("   Proceeding with execution...")
    else:
        print("\n🛡️ [Antigravity Agent]: Permission DENIED by user.")
        print("   Action safely cancelled. Agent remains in secure state.")

if __name__ == "__main__":
    asyncio.run(run_antigravity_agent())
