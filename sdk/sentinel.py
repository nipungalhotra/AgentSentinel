"""
Agent Sentinel Python SDK
Universal Liquid Glass Permission Gate for AI Agents (ChatGPT, Codex, LangChain, CrewAI)
"""

import json
import urllib.request
import urllib.error
import subprocess
import os

SENTINEL_URL = os.environ.get("SENTINEL_URL", "http://127.0.0.1:9191/ask")

def ask_permission(
    command: str,
    title: str = None,
    subtitle: str = None,
    risk: str = "medium",
    requested_by: str = "Antigravity App",
    directory: str = None,
    modifies_files: str = "Unknown",
    tool: str = "Antigravity",
    symbol: str = "sparkles",
    force_prompt: bool = True
) -> bool:
    """
    Triggers the macOS Liquid Glass permission popup anchored beneath the MacBook camera notch.
    Returns True if user approved, False if denied or timed out.
    """
    payload = {
        "command": command,
        "title": title,
        "subtitle": subtitle or f"{requested_by} • {tool}",
        "risk": risk,
        "requestedBy": requested_by,
        "directory": directory or os.getcwd(),
        "modifiesFiles": modifies_files,
        "tool": tool,
        "symbol": symbol,
        "forcePrompt": force_prompt
    }

    try:
        data = json.dumps(payload).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        token_path = os.path.expanduser("~/.loggdin/token")
        if not os.path.exists(token_path):
            token_path = os.path.expanduser("~/Library/Application Support/AgentSentinel/token")
        if os.path.exists(token_path):
            try:
                with open(token_path) as f:
                    headers["X-Loggdin-Token"] = f.read().strip()
            except Exception:
                pass

        req = urllib.request.Request(
            SENTINEL_URL,
            data=data,
            headers=headers
        )
        with urllib.request.urlopen(req, timeout=60) as response:
            res = json.loads(response.read().decode("utf-8"))
            return res.get("allowed", False)
    except urllib.error.URLError:
        # If Sentinel is not running, try to launch the app
        try:
            if os.path.exists("/Applications/AgentSentinel.app"):
                subprocess.run(["open", "/Applications/AgentSentinel.app"], check=False)
            else:
                subprocess.run(["open", "/Users/nipun/.gemini/antigravity-ide/scratch/AgentSentinel/AgentSentinel.app"], check=False)
        except Exception:
            pass
        return False
    except Exception:
        return False

def guard(command: str, requested_by: str = "Agent", directory: str = None) -> subprocess.CompletedProcess:
    """
    Requests permission via Liquid Glass popup and executes the command only if approved.
    Raises PermissionError if denied.
    """
    if not ask_permission(command, requested_by=requested_by, directory=directory):
        raise PermissionError(f"Sentinel: Permission denied by user for command '{command}'")

    return subprocess.run(command, shell=True, cwd=directory or os.getcwd(), capture_output=True, text=True)
