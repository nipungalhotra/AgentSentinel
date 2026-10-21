"""
loggdin Python SDK
Universal Liquid Glass Permission Gate for AI Agents (Antigravity, ChatGPT, Codex, LangChain, CrewAI)
"""

import json
import urllib.request
import urllib.error
import subprocess
import os

def get_loggdin_url(endpoint: str = "ask") -> str:
    if "LOGGDIN_URL" in os.environ:
        return os.environ["LOGGDIN_URL"]
    if "SENTINEL_URL" in os.environ:
        return os.environ["SENTINEL_URL"]
    port = os.environ.get("LOGGDIN_PORT") or os.environ.get("SENTINEL_PORT")
    if not port:
        for p in [os.path.expanduser("~/.loggdin/port"), os.path.expanduser("~/Library/Application Support/AgentSentinel/port")]:
            if os.path.exists(p):
                try:
                    with open(p) as f:
                        val = f.read().strip()
                        if val:
                            port = val
                            break
                except Exception:
                    pass
    port = port or "9191"
    return f"http://127.0.0.1:{port}/{endpoint}"

LOGGDIN_URL = get_loggdin_url()

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

        target_url = get_loggdin_url("ask")
        req = urllib.request.Request(
            target_url,
            data=data,
            headers=headers
        )
        with urllib.request.urlopen(req, timeout=60) as response:
            res = json.loads(response.read().decode("utf-8"))
            return res.get("allowed", False)
    except urllib.error.URLError:
        # If loggdin is not running, try to launch the app
        try:
            for app_candidate in [
                "/Applications/Loggdin.app",
                "/Applications/AgentSentinel.app"
            ]:
                if os.path.exists(app_candidate):
                    subprocess.run(["open", "-g", "-j", app_candidate], check=False)
                    break
        except Exception:
            pass
        return False
    except Exception:
        return False

import shlex
from typing import Union, List

def guard(
    command: Union[str, List[str]],
    requested_by: str = "Agent",
    directory: str = None,
    shell: bool = None,
    **kwargs
) -> subprocess.CompletedProcess:
    """
    Requests permission via Liquid Glass popup and executes the command only if approved.
    Supports either string commands or argument lists to prevent shell injection.
    Raises PermissionError if denied.
    """
    if isinstance(command, (list, tuple)):
        cmd_str = " ".join(command)
    else:
        cmd_str = str(command)

    if not ask_permission(cmd_str, requested_by=requested_by, directory=directory):
        raise PermissionError(f"loggdin: Permission denied by user for command '{cmd_str}'")

    cwd = directory or os.getcwd()

    if isinstance(command, (list, tuple)):
        return subprocess.run(command, shell=False, cwd=cwd, capture_output=True, text=True, **kwargs)

    if shell is None:
        has_metachars = any(c in cmd_str for c in ["|", "&", ";", ">", "<", "`", "$"])
        shell = has_metachars

    if shell:
        return subprocess.run(cmd_str, shell=True, cwd=cwd, capture_output=True, text=True, **kwargs)
    else:
        args = shlex.split(cmd_str)
        return subprocess.run(args, shell=False, cwd=cwd, capture_output=True, text=True, **kwargs)
