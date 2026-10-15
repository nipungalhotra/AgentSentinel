#!/usr/bin/env python3
"""
Agent Sentinel Background Simulation Test
Simulates an Antigravity background process requesting user permission
while the user is working in another app (Chrome, Slack, etc.).
"""

import time
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sentinel import ask_permission

def main():
    print("=" * 64)
    print("  AGENT SENTINEL — BACKGROUND PERMISSION TEST")
    print("=" * 64)
    print("\n👉 STEP 1: In 5 seconds, this background agent will trigger a permission prompt.")
    print("👉 STEP 2: SWITCH TO ANOTHER APP NOW (e.g. Chrome, Safari, Slack, or Notes).")
    print("           Minimize or hide this window so you are working elsewhere.\n")
    
    for i in range(5, 0, -1):
        print(f"⏳ Switch away... triggering in {i} seconds...", flush=True)
        time.sleep(1)
        
    print("\n🚨 [BACKGROUND TASK]: Antigravity reached a high-risk operation!")
    print("   Look up at your camera notch over whatever app you are using...\n")
    
    # Simulate a background Antigravity task that pauses and requests permission:
    approved = ask_permission(
        command="docker compose up -d production_db && git push origin main",
        title="Background Agent: Deploy Production Container?",
        subtitle="Antigravity Background Worker • AutoDeploy",
        risk="high",
        requested_by="Antigravity Background Agent",
        modifies_files="Production Database & Git Remote",
        tool="Docker/Git",
        symbol="sparkles"
    )
    
    if approved:
        print("🎉 [APPROVED]: You authorized the action from outside Antigravity!")
        print("   The background task received permission and resumed execution.")
    else:
        print("🛡️ [DENIED]: You denied the action or timed out.")
        print("   The background task stopped safely without executing the command.")

if __name__ == "__main__":
    main()
