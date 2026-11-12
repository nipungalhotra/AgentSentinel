#!/usr/bin/env python3
"""
Live check of agent questions and "waiting for you" alerts against the INSTALLED loggdin Mac app
and the real ntfy.sh relay. Feeds the installed sentinel-hook exactly what each agent sends
(Claude Code, Antigravity, Codex, Cursor, GitHub Copilot), answers the way loggdin Pocket does
(a signed reply on the reply topic) and checks what each agent gets back.

macOS only, needs phone approvals switched on. Restores phone.json when done.
Run:  python3 tests/agent_questions_live.py [--with-timeout]
"""
import importlib.util
import json
import os
import subprocess
import sys
import threading
import time
import urllib.request

HOME = os.path.expanduser("~")
STATE = os.path.join(HOME, "Library", "Application Support", "AgentSentinel")
PHONE = os.path.join(STATE, "phone.json")
HOOK = os.path.join(STATE, "sentinel-hook")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("lg", os.path.join(ROOT, "bin", "loggdin.py"))
lg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lg)

ORIG = json.load(open(PHONE))
CFG = dict(ORIG)
RESULTS = []


def save(cfg):
    tmp = PHONE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, json.dumps(cfg, indent=2, sort_keys=True).encode())
    os.close(fd)
    os.replace(tmp, PHONE)


def mode(m):
    save(dict(ORIG, mode=m, pushTokens=[]))
    time.sleep(1.2)


def hook(args, payload, timeout=140):
    r = subprocess.run([sys.executable, HOOK] + args, input=json.dumps(payload).encode(),
                       capture_output=True, timeout=timeout)
    out = r.stdout.decode().strip()
    return json.loads(out) if out else None


def hook_async(args, payload, timeout=140):
    box = {}
    t = threading.Thread(target=lambda: box.update(out=hook(args, payload, timeout)))
    t.start()
    return t, box


def relay(since):
    url = f"https://ntfy.sh/{CFG['topic']}/json?poll=1&since={since}"
    raw = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "loggdin-check"}), timeout=10).read().decode()
    msgs = []
    for line in raw.splitlines():
        m = json.loads(line) if line.strip() else {}
        if m.get("event") == "message" and m.get("time", 0) >= since:
            o = lg.phone_open(CFG, m["message"])
            if o:
                msgs.append(o)
    return msgs


def wait_relay(since, kind, count=1, secs=12):
    end = time.time() + secs
    while time.time() < end:
        found = [m for m in relay(since) if m.get("k") == kind]
        if len(found) >= count:
            return found
        time.sleep(1)
    return [m for m in relay(since) if m.get("k") == kind]


def tap(body):
    urllib.request.urlopen(urllib.request.Request(f"https://ntfy.sh/{CFG['topic']}-reply", data=body.encode(),
                                                  method="POST", headers={"User-Agent": "loggdin-check"}), timeout=10).read()


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok), detail))
    print(("PASS  " if ok else "FAIL  ") + name + (f"  ({detail})" if detail else ""))


def claude_question(questions):
    return {"hook_event_name": "PreToolUse", "session_id": "live", "cwd": ROOT, "tool_name": "AskUserQuestion",
            "tool_input": {"questions": questions}}


DB_Q = {"question": "Which database should the new service use?", "header": "Database", "multiSelect": False,
        "options": [{"label": "PostgreSQL", "description": "Relational"}, {"label": "SQLite", "description": "Single file"},
                    {"label": "Redis", "description": "In-memory"}]}
ASK = ["--agent", "claude-code", "--ask"]


def answers_of(out):
    try:
        return out["hookSpecificOutput"]["updatedInput"]["answers"]
    except (TypeError, KeyError):
        return None


def main():
    with_timeout = "--with-timeout" in sys.argv
    try:
        # 1. Claude Code, phone only: question reaches loggdin Pocket encrypted, answer goes back.
        mode("phone")
        start = int(time.time())
        t, box = hook_async(ASK, claude_question([DB_Q]))
        qs = wait_relay(start, "q")
        q = qs[-1] if qs else None
        check("Claude Code: question reaches the phone with one button per option",
              q and [l for l, _ in q["a"]] == ["PostgreSQL", "SQLite", "Redis"], q and q["t"])
        if q:
            tap(q["a"][0][1])
        t.join(20)
        out = box.get("out")
        check("Claude Code: phone answer returned as AskUserQuestion answers",
              answers_of(out) == {DB_Q["question"]: "PostgreSQL"}, answers_of(out))
        check("Claude Code: reply uses PreToolUse allow + updatedInput",
              out and out["hookSpecificOutput"].get("permissionDecision") == "allow"
              and out["hookSpecificOutput"]["updatedInput"].get("questions"), "")
        time.sleep(1.5)

        # 2. Forged answer ignored, real one accepted.
        start = int(time.time())
        t, box = hook_async(ASK, claude_question([DB_Q]))
        qs = wait_relay(start, "q")
        q = qs[-1] if qs else None
        if q:
            req_id = q["a"][1][1].split()[1]
            tap(f"lg1 {req_id} opt-2 {'0' * 32}")      # forged: wrong signature
            time.sleep(2)
            tap(q["a"][1][1])                           # real: SQLite
        t.join(20)
        check("Forged phone answer ignored, signed one accepted",
              answers_of(box.get("out")) == {DB_Q["question"]: "SQLite"}, answers_of(box.get("out")))
        time.sleep(1.5)

        # 3. Mac and phone together: card on the Mac, answered from the phone.
        mode("both")
        start = int(time.time())
        t, box = hook_async(ASK, claude_question([DB_Q]))
        qs = wait_relay(start, "q")
        subprocess.run(["screencapture", "-x", "/tmp/loggdin_live_card.png"])
        q = qs[-1] if qs else None
        if q:
            tap(q["a"][2][1])
        t.join(20)
        check("Mac + phone: answer from the phone closes the Mac card",
              answers_of(box.get("out")) == {DB_Q["question"]: "Redis"}, answers_of(box.get("out")))
        time.sleep(1.5)

        # 4. Claude Code's other hook paths stay out of the way.
        out = hook(["--agent", "claude-code", "PermissionRequest"],
                   dict(claude_question([DB_Q]), hook_event_name="PermissionRequest"), timeout=20)
        check("Claude Code: PermissionRequest for a question lets its own box through",
              out and out.get("hookSpecificOutput", {}).get("decision", {}).get("behavior") == "allow", out)
        out = hook(["--agent", "claude-code", "PreToolUse"], claude_question([DB_Q]), timeout=20)
        check("Claude Code: the general PreToolUse hook stays silent for questions", out is None, out)

        # 5. "Waiting for you" alerts: shown for input-related types only, repeats grouped.
        mode("phone")
        start = int(time.time())
        for ntype, msg in (("idle_prompt", "Claude is waiting for your input"),
                           ("agent_needs_input", "Background agent needs your input"),
                           ("elicitation_dialog", "An MCP server needs details"),
                           ("idle_prompt", "Claude is waiting for your input"),        # repeat: grouped
                           ("permission_prompt", "Claude needs your permission"),       # handled as a permission card
                           ("auth_success", "Signed in")):                              # not about input
            hook(["--agent", "claude-code", "Notification"],
                 {"hook_event_name": "Notification", "cwd": ROOT, "notification_type": ntype, "message": msg}, timeout=20)
            time.sleep(0.4)
        notes = wait_relay(start, "n", count=3, secs=10)
        time.sleep(3)
        notes = [m for m in relay(start) if m.get("k") == "n"]
        texts = sorted(m["m"].split("\n")[0] for m in notes)
        check("Claude Code alerts: idle, background agent and MCP form each shown once",
              texts == sorted(["Claude is waiting for your input", "Background agent needs your input",
                               "An MCP server needs details"]), texts)
        check("Claude Code alerts: permission prompts and sign-in messages not shown as alerts",
              not any("permission" in t or "Signed in" in t for t in texts), "")

        # 6. Other agents: their own question UI runs, loggdin shows a notice, reply in their format.
        cases = [
            ("antigravity", "Antigravity", ["--agent", "antigravity", "PreToolUse"],
             {"hook_event_name": "PreToolUse", "cwd": ROOT, "tool_name": "ask_question",
              "tool_input": {"question": "Deploy to staging or production?"}}, {"decision": "allow"}),
            ("codex", "Codex", ["--agent", "codex", "PermissionRequest"],
             {"hook_event_name": "PermissionRequest", "cwd": ROOT, "tool_name": "ask_user",
              "tool_input": {"question": "Run the full test suite first?"}},
             {"decision": "allow", "behavior": "allow", "status": "approved"}),
            ("cursor", "Cursor", ["--agent", "cursor", "PreToolUse"],
             {"hook_event_name": "PreToolUse", "cwd": ROOT, "tool_name": "ask_question",
              "tool_input": {"question": "Which file should I refactor first?"}}, None),
            ("copilot", "GitHub Copilot", ["--agent", "copilot", "PermissionRequest"],
             {"hook_event_name": "PermissionRequest", "cwd": ROOT, "tool_name": "ask_user",
              "tool_input": {"prompt": "Should I open a pull request?"}}, {"permissionDecision": "allow", "decision": "allow"}),
        ]
        for agent, name, args, payload, expected in cases:
            start = int(time.time())
            out = hook(args, payload, timeout=20)
            if expected is None:
                ok = out and out.get("hookSpecificOutput", {}).get("decision", {}).get("behavior") == "allow"
            else:
                ok = out == expected
            check(f"{name}: its own question UI is allowed, in its reply format", ok, out)
            notes = wait_relay(start, "n", secs=10)
            text = (payload["tool_input"].get("question") or payload["tool_input"].get("prompt"))
            check(f"{name}: question shown in loggdin as a notice",
                  any(m["t"] == f"{name} has a question" and m["m"].startswith(text) for m in notes),
                  [m["t"] for m in notes])
            time.sleep(1.2)

        # 7. Several questions at once, phone only: the phone can't answer it, so the Mac card shows.
        mode("phone")
        start = int(time.time())
        two = [DB_Q, {"question": "Which test runner?", "header": "Tests", "multiSelect": True,
                      "options": [{"label": "pytest", "description": ""}, {"label": "unittest", "description": ""}]}]
        t, box = hook_async(ASK, claude_question(two))
        qs = wait_relay(start, "q")
        time.sleep(2)
        subprocess.run(["screencapture", "-x", "/tmp/loggdin_live_multi.png"])
        check("Several questions: phone shows it without buttons and says to answer on the computer",
              qs and qs[-1]["a"] == [] and "Answer this one on your computer" in qs[-1]["m"], qs and qs[-1]["m"])
        if with_timeout:
            t.join(140)
            check("No answer in time: Claude Code falls back to its own question box (empty reply)",
                  not t.is_alive() and box.get("out") is None, box.get("out"))
        else:
            print("…  leaving the multi-question card to time out on its own (run with --with-timeout to check the fallback)")
    finally:
        save(ORIG)
        print("phone.json restored")

    passed = sum(ok for _, ok, _ in RESULTS)
    print(f"\n{passed}/{len(RESULTS)} checks passed")
    return 0 if passed == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
