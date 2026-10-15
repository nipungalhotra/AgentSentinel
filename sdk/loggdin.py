"""
loggdin Python SDK
Universal Liquid Glass Permission Gate for AI Agents (Antigravity, ChatGPT, Codex, LangChain, CrewAI)
"""

import json
import urllib.request
import urllib.error
import subprocess
import os

LOGGDIN_URL = os.environ.get("LOGGDIN_URL", os.environ.get("SENTINEL_URL", "http://127.0.0.1:9191/ask"))

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
        req = urllib.request.Request(
            LOGGDIN_URL,
            data=data,
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=60) as response:
            res = json.loads(response.read().decode("utf-8"))
            return res.get("allowed", False)
    except urllib.error.URLError:
        # If loggdin is not running, try to launch the app
        try:
            for app_candidate in [
                "/Applications/Loggdin.app",
                "/Applications/AgentSentinel.app",
                "/Users/nipun/.gemini/antigravity-ide/scratch/AgentSentinel/Loggdin.app",
                "/Users/nipun/.gemini/antigravity-ide/scratch/AgentSentinel/AgentSentinel.app"
            ]:
                if os.path.exists(app_candidate):
                    subprocess.run(["open", app_candidate], check=False)
                    break
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
        raise PermissionError(f"loggdin: Permission denied by user for command '{command}'")

    return subprocess.run(command, shell=True, cwd=directory or os.getcwd(), capture_output=True, text=True)
