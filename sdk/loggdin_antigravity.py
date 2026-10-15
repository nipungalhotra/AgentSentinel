"""
loggdin Google Antigravity SDK Integration
Provides drop-in policies and hooks to intercept Antigravity agent tool calls
and gate them with the native macOS Liquid Glass notch popup.
"""

from typing import Any, Callable, Dict, Optional
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from loggdin import ask_permission

def make_loggdin_approval_handler(agent_name: str = "Antigravity App") -> Callable:
    """
    Creates an asynchronous policy approval handler for Google Antigravity SDK:
    policy.ask_user('run_command', handler=make_loggdin_approval_handler())
    """
    async def handler(tool_call: Any) -> bool:
        cmd = "Unknown Action"
        tool_name = getattr(tool_call, "name", "Tool")
        args = getattr(tool_call, "args", {}) or {}

        if isinstance(args, dict):
            cmd = args.get("CommandLine") or args.get("command") or args.get("file_path") or str(args)
        elif hasattr(tool_call, "command"):
            cmd = tool_call.command

        risk = "high" if any(p in cmd.lower() for p in ["rm ", "sudo", "docker", "drop", "delete", "kill", "git push"]) else "medium"

        return ask_permission(
            command=cmd,
            title=f"Authorize {tool_name}?",
            subtitle=f"{agent_name} • {tool_name}",
            risk=risk,
            requested_by=agent_name,
            tool=tool_name
        )

    return handler

def loggdin_pre_tool_decide_hook(agent_name: str = "Antigravity App") -> Callable:
    """
    Creates a pre_tool_call_decide hook for Google Antigravity SDK.
    """
    approval_handler = make_loggdin_approval_handler(agent_name)

    async def hook(tool_call: Any) -> Any:
        try:
            from google.antigravity import types
            allowed = await approval_handler(tool_call)
            return types.HookResult(allow=allowed)
        except ImportError:
            return await approval_handler(tool_call)

    return hook
