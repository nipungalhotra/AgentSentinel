#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
loggdin — cross-platform permission daemon + CLI (Windows, Linux, macOS).

On macOS the native Loggdin.app is the primary daemon (notch popup, Touch ID).
On Windows and Linux this single, dependency-free file provides the same local
API the hook, MCP server and SDKs talk to:

    GET  /status                 health (no auth)
    GET  /pending                current pending request          (token)
    GET  /pending?all=1          every queued request              (token)
    POST /ask  | /hook           block until the user decides      (token)
    POST /decision|/allow|/deny  resolve the pending request       (token)
    POST /event                  non-blocking agent activity       (token)
    GET  /audit/verify           verify the SHA-256 audit chain    (token)
    GET  /audit/export[?format=csv]                                (token)
    POST /shutdown               stop the daemon                   (token)
    GET  /                       browser approval page (token is passed in the
                                 URL fragment by `loggdin ui`, never served)

Usage:
    loggdin daemon                 run in the foreground
    loggdin start | stop | status
    loggdin ui                     open the approval page in the browser
    loggdin pending [--json]
    loggdin allow [once|10m|10m-all|always] | loggdin deny
    loggdin install <claude|codex|antigravity|cursor|cowork|copilot|all|detected>
    loggdin uninstall <same targets>
    loggdin autostart [on|off]
    loggdin run <command...>       ask before running a shell command
    loggdin phone setup | test | on | off | status | delay <s> | details <full|minimal>
                                   approve from your phone's notifications (ntfy)
    loggdin doctor | version
"""

import hashlib
import hmac
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
import uuid
import webbrowser
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
import urllib.request
import urllib.error

VERSION = "1.2.1"
DEFAULT_PORT = 9191
PORT_RANGE = 10                      # 9191..9200 if the default is taken
ASK_TIMEOUT = float(os.environ.get("LOGGDIN_TIMEOUT", "115"))  # agents allow 120s
DEDUP_SECONDS = 15.0
GRANT_SECONDS = 600.0
IS_WINDOWS = os.name == "nt"
IS_MAC = sys.platform == "darwin"


# ---------------------------------------------------------------------------
# Paths (must stay in sync with bin/sentinel-hook, sdk/*, bin/sentinel-mcp.js)
# ---------------------------------------------------------------------------

def state_dir():
    override = os.environ.get("LOGGDIN_HOME")
    if override:
        return override
    home = os.path.expanduser("~")
    if IS_MAC:
        return os.path.join(home, "Library", "Application Support", "AgentSentinel")
    if IS_WINDOWS:
        return os.path.join(os.environ.get("APPDATA") or os.path.join(home, "AppData", "Roaming"), "Loggdin")
    return os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config"), "loggdin")


def mirror_dir():
    """~/.loggdin mirror read first by older clients (skipped when LOGGDIN_HOME is set)."""
    if os.environ.get("LOGGDIN_HOME"):
        return None
    return os.path.join(os.path.expanduser("~"), ".loggdin")


def ensure_private_dir(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    if not IS_WINDOWS:
        try:
            os.chmod(path, 0o700)
        except OSError:
            pass


def write_private(path, text):
    ensure_private_dir(os.path.dirname(path))
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def read_text(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def port_file():
    return os.path.join(state_dir(), "port")


def token_file():
    return os.path.join(state_dir(), "token")


def get_port():
    for env in ("LOGGDIN_PORT", "SENTINEL_PORT"):
        if os.environ.get(env, "").isdigit():
            return int(os.environ[env])
    candidates = [port_file()]
    if mirror_dir():
        candidates.insert(0, os.path.join(mirror_dir(), "port"))
    for p in candidates:
        v = read_text(p)
        if v.isdigit():
            return int(v)
    return DEFAULT_PORT


def get_token():
    if os.environ.get("LOGGDIN_TOKEN"):
        return os.environ["LOGGDIN_TOKEN"]
    candidates = [token_file()]
    if mirror_dir():
        candidates.append(os.path.join(mirror_dir(), "token"))
    for p in candidates:
        v = read_text(p)
        if v:
            return v
    return ""


def status_proof(token, challenge):
    """HMAC proving the daemon knows the token, without revealing it (see verify_daemon)."""
    return hmac.new(token.encode("utf-8"), ("loggdin-status:" + challenge).encode("utf-8"), hashlib.sha256).hexdigest()


def load_or_create_token():
    tok = read_text(token_file())
    if not tok:
        tok = secrets.token_hex(32)
        write_private(token_file(), tok)
    m = mirror_dir()
    if m:
        try:
            write_private(os.path.join(m, "token"), tok)
        except OSError:
            pass
    return tok


def save_port(port):
    write_private(port_file(), str(port))
    m = mirror_dir()
    if m:
        try:
            write_private(os.path.join(m, "port"), str(port))
        except OSError:
            pass


def log(msg):
    line = f"[{datetime.now().strftime('%H:%M:%S')}] {msg}"
    try:
        print(line, flush=True)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Rules, grants, audit
# ---------------------------------------------------------------------------

CATASTROPHIC = (
    "rm -rf /", "rm -rf /*", "rm -rf ~", "rm -rf $home", "rm -fr /", "mkfs", "dd if=",
    ":(){", "format c:", "del /s /q c:\\", "rd /s /q c:\\", "remove-item -recurse c:\\",
    "chmod -r 777 /", "> /dev/sda",
)


def is_catastrophic(cmd):
    c = " ".join(cmd.lower().split())
    return any(p in c for p in CATASTROPHIC)


def norm_dir(d):
    d = (d or "~").strip() or "~"
    return os.path.normcase(os.path.abspath(os.path.expanduser(d)))


def dir_matches(rule_dir, req_dir):
    if (rule_dir or "~").strip() in ("~", "*", ""):
        return True
    r, q = norm_dir(rule_dir), norm_dir(req_dir)
    return q == r or q.startswith(r.rstrip(os.sep) + os.sep)


def is_compound_shell(cmd):
    """Chained, piped, redirected or substituted commands: an approved prefix could smuggle more in."""
    return any(op in cmd for op in ("&&", "||", ";", "|", "`", "$(", ">", "<", "\n", "&"))


HARMLESS_FILTERS = {"head", "tail", "grep", "wc", "cut", "tr", "jq", "nl", "column", "pwd", "echo", "true"}


def chain_segments(cmd):
    """Split `a && b || c ; d | e`, or None if it uses substitution, redirection or background `&`."""
    if any(b in cmd for b in ("`", "$(", ">", "<", "\n")) or "&" in cmd.replace("&&", ""):
        return None
    parts = [cmd]
    for sep in ("&&", "||", ";", "|"):
        parts = [x for part in parts for x in part.split(sep)]
    segments = [x.strip() for x in parts]
    return None if any(not x for x in segments) else segments


def is_harmless_segment(seg):
    """`cd` into a sub-folder, or a read-only text filter."""
    words = seg.split()
    if not words:
        return False
    if words[0] == "cd":
        if len(words) != 2:
            return False
        t = words[1]
        return not t.startswith(("/", "~", "$", "-")) and ".." not in t.split("/")
    return words[0] in HARMLESS_FILTERS


def cmd_matches(pattern, cmd, risk="low"):
    """Exact command always. Otherwise (never for high risk): the same command with extra plain
    arguments, or a chain whose every real command is covered (cd into a sub-folder and read-only
    filters are allowed glue; substitution and redirection never match)."""
    p, c = pattern.strip(), cmd.strip()
    if not p:
        return False
    if c == p:
        return True
    if risk == "high":
        return False
    if is_compound_shell(c):
        segments = chain_segments(c)
        if not segments:
            return False
        real = [x for x in segments if not is_harmless_segment(x)]
        return bool(real) and all(x == p or (x.startswith(p + " ") and not is_compound_shell(x)) for x in real)
    return c.startswith(p + " ")


class Store:
    """rules.json (Mac-app compatible), in-memory grants, hash-chained audit log."""

    def __init__(self):
        self.lock = threading.Lock()
        self.rules_path = os.path.join(state_dir(), "rules.json")
        self.audit_path = os.path.join(state_dir(), "audit_log.jsonl")
        self.grants = []          # [{pattern, directory, expires}]
        self.recent = {}          # command -> approved timestamp
        self.rules = self._load_rules()

    def _load_rules(self):
        try:
            with open(self.rules_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data if isinstance(data, list) else []
        except (OSError, ValueError):
            return []

    def _save_rules(self):
        write_private(self.rules_path, json.dumps(self.rules, indent=2))

    def evaluate(self, req):
        cmd = req["command"]
        now = time.time()
        with self.lock:
            self.grants = [g for g in self.grants if g["expires"] > now]
            if is_catastrophic(cmd):      # always needs a human, even right after an approval
                return None
            if now - self.recent.get((req["directory"], cmd), 0) < DEDUP_SECONDS:
                return {"type": "allow", "scope": "once"}
            for g in self.grants:
                if cmd_matches(g["pattern"], cmd, req["risk"]) and dir_matches(g["directory"], req["directory"]):
                    return {"type": "allow", "scope": "tenMinutes"}
            for r in self.rules:
                if cmd_matches(r.get("pattern", ""), cmd, req["risk"]) and dir_matches(r.get("directory"), req["directory"]):
                    return {"type": "allow", "scope": "always"}
        return None

    def remember(self, req, decision):
        if decision.get("type") != "allow":
            return
        cmd, scope = req["command"], decision.get("scope", "once")
        with self.lock:
            self.recent[(req["directory"], cmd)] = time.time()
            if scope in ("tenMinutes", "tenMinutesAnywhere"):
                # "all folders" is an explicit opt-in; never for high-risk requests.
                anywhere = scope == "tenMinutesAnywhere" and req["risk"] != "high"
                self.grants.append({"pattern": cmd, "directory": "*" if anywhere else req["directory"],
                                    "expires": time.time() + GRANT_SECONDS})
            elif scope == "always" and not is_catastrophic(cmd):
                if not any(r.get("pattern") == cmd and r.get("directory") == req["directory"] for r in self.rules):
                    self.rules.append({
                        "id": str(uuid.uuid4()).upper(), "pattern": cmd,
                        "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "directory": req["directory"], "notes": f"Saved rule from {req['requestedBy']}",
                    })
                    self._save_rules()

    def _entries(self):
        out = []
        try:
            with open(self.audit_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            out.append(json.loads(line))
                        except ValueError:
                            out.append({"corrupt": line})
        except OSError:
            pass
        return out

    @staticmethod
    def _hash(entry):
        body = {k: v for k, v in entry.items() if k != "entryHash"}
        return hashlib.sha256(json.dumps(body, sort_keys=True).encode("utf-8")).hexdigest()

    def audit(self, req, decision, auto):
        with self.lock:
            entries = self._entries()
            prev = entries[-1].get("entryHash", "0" * 64) if entries else "0" * 64
            entry = {
                "id": str(uuid.uuid4()).upper(),
                "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "requestedBy": req["requestedBy"], "command": req["command"],
                "directory": req["directory"], "risk": req["risk"],
                "decision": decision, "autoAllowed": auto, "prevHash": prev,
            }
            entry["entryHash"] = self._hash(entry)
            ensure_private_dir(state_dir())
            fd = os.open(self.audit_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            with os.fdopen(fd, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry) + "\n")

    def verify(self):
        entries = self._entries()
        prev = "0" * 64
        for i, e in enumerate(entries):
            if e.get("prevHash") != prev or e.get("entryHash") != self._hash(e):
                return {"isValid": False, "totalEntries": len(entries), "brokenIndex": i,
                        "algorithm": "SHA-256 Merkle Chain", "message": f"Chain broken at entry {i}"}
            prev = e["entryHash"]
        return {"isValid": True, "totalEntries": len(entries), "brokenIndex": None,
                "algorithm": "SHA-256 Merkle Chain", "message": "Audit chain intact"}

    def export_csv(self):
        rows = ["timestamp,requestedBy,risk,decision,autoAllowed,directory,command"]
        for e in self._entries():
            def q(v):
                return '"' + str(v).replace('"', '""') + '"'
            rows.append(",".join(q(x) for x in (
                e.get("timestamp", ""), e.get("requestedBy", ""), e.get("risk", ""),
                (e.get("decision") or {}).get("type", ""), e.get("autoAllowed", ""),
                e.get("directory", ""), e.get("command", ""))))
        return "\n".join(rows) + "\n"


# ---------------------------------------------------------------------------
# Pending request queue
# ---------------------------------------------------------------------------

def parse_request(body):
    """Mirror of LocalIPCServer.parseRequest in the Mac app."""
    ti = body.get("tool_input") if isinstance(body.get("tool_input"), dict) else {}
    cmd = body.get("command") or ti.get("command") or ti.get("CommandLine") or body.get("tool") or "Execute Tool"
    agent = body.get("requestedBy") or body.get("agent") or "CLI"
    risk = str(body.get("risk") or "low").lower()
    if risk not in ("low", "medium", "high"):
        risk = "low"
    secrets_w = body.get("secretWarnings") if isinstance(body.get("secretWarnings"), list) else []
    return {
        "id": str(uuid.uuid4()).upper(),
        "title": str(body.get("title") or f"{agent} Permission"),
        "subtitle": str(body.get("subtitle") or f"{agent} • {body.get('tool') or 'Tool'}"),
        "command": str(cmd),
        "risk": risk,
        "requestedBy": str(agent),
        "directory": str(body.get("directory") or body.get("cwd") or "~"),
        "modifiesFiles": str(body.get("modifiesFiles") or "Unknown"),
        "secretWarnings": [str(s) for s in secrets_w][:20],
        "diffPreview": (str(body["diffPreview"])[:20000] if body.get("diffPreview") else None),
        "blastRadius": (str(body["blastRadius"]) if body.get("blastRadius") else None),
        "createdAt": time.time(),
    }


class Pending:
    def __init__(self):
        self.lock = threading.Lock()
        self.items = []   # [(req, event, holder)]

    def add(self, req):
        ev, holder = threading.Event(), {}
        with self.lock:
            self.items.append((req, ev, holder))
        return ev, holder

    def remove(self, req_id):
        with self.lock:
            self.items = [it for it in self.items if it[0]["id"] != req_id]

    def first(self):
        with self.lock:
            return self.items[0][0] if self.items else None

    def all(self):
        with self.lock:
            return [it[0] for it in self.items]

    def resolve(self, decision, req_id=None):
        with self.lock:
            for req, ev, holder in self.items:
                if req_id is None or req["id"] == req_id:
                    holder["decision"] = decision
                    ev.set()
                    return True
        return False


def decision_json(decision):
    t = decision.get("type")
    if t == "allow":
        return {"allowed": True, "decision": "allow", "scope": decision.get("scope", "once")}
    return {"allowed": False, "decision": t or "deny"}


def parse_decision(decision_str, scope_str):
    if (decision_str or "").lower() != "allow":
        return {"type": "deny"}
    s = (scope_str or "once").lower()
    if s in ("10m-all", "10m_all", "tenminutesanywhere", "anywhere", "all"):
        return {"type": "allow", "scope": "tenMinutesAnywhere"}
    if s in ("10m", "tenminutes", "10_minutes", "10min"):
        return {"type": "allow", "scope": "tenMinutes"}
    if s in ("always", "all"):
        return {"type": "allow", "scope": "always"}
    return {"type": "allow", "scope": "once"}


# ---------------------------------------------------------------------------
# Desktop notifications (best effort, never blocks)
# ---------------------------------------------------------------------------

def notify(req):
    if os.environ.get("LOGGDIN_NO_NOTIFY"):
        return
    title = f"loggdin: {req['requestedBy']} wants permission"
    body = (req["command"][:180] + ("…" if len(req["command"]) > 180 else "")) + "  —  run `loggdin ui` to decide"
    try:
        if IS_WINDOWS:
            ps = (
                "Add-Type -AssemblyName System.Windows.Forms;"
                "$n=New-Object System.Windows.Forms.NotifyIcon;"
                "$n.Icon=[System.Drawing.SystemIcons]::Shield;$n.Visible=$true;"
                "$n.ShowBalloonTip(8000,$env:LG_T,$env:LG_B,'Warning');Start-Sleep 9;$n.Dispose()"
            )
            env = dict(os.environ, LG_T=title, LG_B=body)
            subprocess.Popen(["powershell", "-NoProfile", "-WindowStyle", "Hidden", "-Command", ps],
                             env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        elif IS_MAC:
            subprocess.Popen(["osascript", "-e", "on run argv\ndisplay notification (item 2 of argv) with title (item 1 of argv)\nend run", title, body],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif shutil.which("notify-send"):
            urgency = "critical" if req["risk"] == "high" else "normal"
            subprocess.Popen(["notify-send", "-a", "loggdin", "-u", urgency, title, body],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    if os.environ.get("LOGGDIN_OPEN_UI") == "1":
        open_ui(quiet=True)


# ---------------------------------------------------------------------------
# HTTP server
# ---------------------------------------------------------------------------

UI_HTML = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>loggdin approvals</title>
<style nonce="__NONCE__">
:root{--bg:#f6f7f9;--card:#fff;--fg:#14161a;--muted:#5d6470;--line:#e2e5ea;--hi:#c62828;--med:#b26a00;--lo:#2e7d32;--btn:#1f6feb}
@media (prefers-color-scheme:dark){:root{--bg:#0f1115;--card:#171a20;--fg:#e8eaee;--muted:#9aa3ad;--line:#2a2f37;--btn:#3b82f6}}
*{box-sizing:border-box}body{margin:0;font:15px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--fg)}
main{max-width:760px;margin:0 auto;padding:24px 16px}h1{font-size:20px;margin:0 0 4px}.sub{color:var(--muted);margin:0 0 20px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:14px}
.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.agent{font-weight:600}.pill{font-size:12px;padding:2px 8px;border-radius:99px;color:#fff}
.high{background:var(--hi)}.medium{background:var(--med)}.low{background:var(--lo)}
pre{background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:10px;white-space:pre-wrap;word-break:break-all;margin:10px 0;font:13px/1.4 ui-monospace,Menlo,Consolas,monospace}
.meta{color:var(--muted);font-size:13px}.warn{color:var(--hi);font-size:13px;margin:4px 0}
button{font:inherit;border-radius:8px;border:1px solid var(--line);background:var(--card);color:var(--fg);padding:8px 14px;cursor:pointer}
button.primary{background:var(--btn);border-color:var(--btn);color:#fff}button.deny{color:var(--hi)}
.empty{color:var(--muted);text-align:center;padding:40px 0}.err{color:var(--hi)}
</style></head><body><main>
<h1>loggdin</h1><p class="sub">Permission requests from your AI agents. Keep this tab open, or run <code>loggdin ui</code> when notified.</p>
<div id="list"><p class="empty">Loading…</p></div>
</main>
<script nonce="__NONCE__">
(function(){
  var h=location.hash.replace(/^#/,''), m=/(?:^|&)token=([0-9a-f]+)/.exec(h);
  if(m){try{sessionStorage.setItem('lgtok',m[1]);}catch(e){} history.replaceState(null,'',location.pathname);}
  var tok=''; try{tok=sessionStorage.getItem('lgtok')||'';}catch(e){}
  var list=document.getElementById('list');
  function el(t,c,x){var e=document.createElement(t);if(c)e.className=c;if(x!=null)e.textContent=x;return e;}
  function decide(id,d,s){fetch('/decision',{method:'POST',headers:{'Content-Type':'application/json','X-Loggdin-Token':tok},
    body:JSON.stringify({requestId:id,decision:d,scope:s})}).then(poll);}
  function render(items){
    list.textContent='';
    if(!items.length){list.appendChild(el('p','empty','No pending requests.'));return;}
    items.forEach(function(r){
      var c=el('div','card'),top=el('div','row');
      top.appendChild(el('span','agent',r.requestedBy));top.appendChild(el('span','pill '+r.risk,r.risk+' risk'));
      c.appendChild(top);c.appendChild(el('div','meta',r.subtitle));
      c.appendChild(el('pre',null,r.command));
      c.appendChild(el('div','meta','Directory: '+r.directory+'  ·  Modifies files: '+r.modifiesFiles));
      (r.secretWarnings||[]).forEach(function(w){c.appendChild(el('div','warn','⚠ '+w));});
      if(r.blastRadius)c.appendChild(el('div','meta','Blast radius: '+r.blastRadius));
      if(r.diffPreview)c.appendChild(el('pre',null,r.diffPreview));
      var b=el('div','row');
      var opts=[['Allow once','allow','once','primary'],['Allow 10 min','allow','10m','']];
      if(r.risk!=='high')opts.push(['10 min, all folders','allow','10m-all','']);
      opts.push(['Always allow','allow','always',''],['Deny','deny','','deny']);
      opts.forEach(function(a){
        var x=el('button',a[3],a[0]);x.onclick=function(){decide(r.id,a[1],a[2]);};b.appendChild(x);});
      c.appendChild(b);list.appendChild(c);
    });
  }
  function poll(){
    if(!tok){list.innerHTML='';list.appendChild(el('p','err','Missing access token. Open this page with the command: loggdin ui'));return;}
    fetch('/pending?all=1',{headers:{'X-Loggdin-Token':tok}}).then(function(r){
      if(r.status===401){throw new Error('Token rejected. Re-open with: loggdin ui');} return r.json();})
    .then(function(j){render(j.requests||[]);}).catch(function(e){list.textContent='';list.appendChild(el('p','err',e.message));});
  }
  poll(); setInterval(poll,1500);
})();
</script></body></html>
"""


# ---------------------------------------------------------------------------
# Phone approvals over ntfy (https://ntfy.sh): a native push notification on
# the phone with Allow / Deny buttons. Outbound only: this computer publishes
# to a secret topic and listens on a secret reply topic, so nothing is exposed
# to the internet. Every button carries a one-time HMAC signature bound to one
# request, so a forged or replayed reply is ignored. "Always" and "all folders"
# are never offered on the phone. Protocol is shared with Sources/PhoneRelay.swift.
# ---------------------------------------------------------------------------

PHONE_DEFAULT_SERVER = "https://ntfy.sh"
PHONE_TOPIC_ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789"   # no 0/o/1/l: easy to type on a phone
PHONE_VERBS = {"allow-once": ("allow", "once"), "allow-10m": ("allow", "10m"), "deny": ("deny", "")}


def phone_path():
    return os.path.join(state_dir(), "phone.json")


def load_phone():
    try:
        with open(phone_path(), "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(cfg, dict) or not cfg.get("topic") or not cfg.get("secret"):
        return None
    cfg.setdefault("enabled", True)
    cfg["server"] = str(cfg.get("server") or PHONE_DEFAULT_SERVER).rstrip("/")
    try:
        cfg["pushAfter"] = max(0.0, min(float(cfg.get("pushAfter", 15)), 100.0))
    except (TypeError, ValueError):
        cfg["pushAfter"] = 15.0
    cfg["details"] = "minimal" if cfg.get("details") == "minimal" else "full"
    # "auto": phone after the delay. "both" / "phone" (set in the Mac dashboard): push at once.
    cfg["mode"] = cfg.get("mode") if cfg.get("mode") in ("both", "phone") else "auto"
    tokens = cfg.get("pushTokens") if isinstance(cfg.get("pushTokens"), list) else []
    cfg["pushTokens"] = [t for t in tokens if phone_is_push_token(t)][-PHONE_MAX_PUSH_TOKENS:]
    return cfg


# The loggdin phone app (mobile/) registers itself by posting "lg1-push <Expo push token>" to the
# reply topic. It then gets a short "request waiting" notification through Expo's push service;
# the command text never goes that way. Shared with Sources/PhoneRelay.swift.
PHONE_EXPO_PUSH_URL = os.environ.get("LOGGDIN_EXPO_PUSH_URL", "https://exp.host/--/api/v2/push/send")
PHONE_MAX_PUSH_TOKENS = 5
PHONE_PUSH_TOKEN_RE = re.compile(r"^Expo(nent)?PushToken\[[A-Za-z0-9_-]{10,100}\]$")


def phone_pair_key(secret):
    """Pairing key derived from the secret; the phone signs its registration with it."""
    return hmac.new(secret.encode("utf-8"), b"loggdin-phone|v1|pair", hashlib.sha256).hexdigest()[:16]


def phone_pairing_code(cfg):
    return f"{cfg['topic']}.{phone_pair_key(cfg['secret'])}"


def phone_is_push_token(value):
    return isinstance(value, str) and bool(PHONE_PUSH_TOKEN_RE.match(value))


def phone_parse_push_registration(text, secret):
    """'lg1-push <token> <sig>': accepted only when signed with the pairing key."""
    parts = str(text or "").split()
    if len(parts) != 3 or parts[0] != "lg1-push" or not phone_is_push_token(parts[1]):
        return None
    key = phone_pair_key(secret).encode("utf-8")
    expected = hmac.new(key, f"loggdin-phone|v1|push|{parts[1]}".encode("utf-8"), hashlib.sha256).hexdigest()[:32]
    return parts[1] if hmac.compare_digest(expected, parts[2]) else None


def phone_register_push_token(token):
    cfg = load_phone()
    if not cfg or token in cfg["pushTokens"]:
        return False
    cfg["pushTokens"] = (cfg["pushTokens"] + [token])[-PHONE_MAX_PUSH_TOKENS:]
    save_phone(cfg)
    return True


def phone_app_notify(cfg, req):
    """Tells phones running the loggdin app that a request is waiting (agent, risk and folder only)."""
    if not cfg.get("pushTokens"):
        return True, None
    title, minimal = phone_message(dict(cfg, details="minimal"), req)
    messages = [{"to": t, "title": title, "body": f"{minimal} Open loggdin to answer.", "sound": "default",
                 "priority": "high", "channelId": "requests", "ttl": 110, "data": {"seq": phone_seq(req["id"])}}
                for t in cfg["pushTokens"]]
    return phone_request("POST", PHONE_EXPO_PUSH_URL, messages)


def new_phone_config(server=None):
    topic = "loggdin-" + "".join(secrets.choice(PHONE_TOPIC_ALPHABET) for _ in range(20))
    return {"enabled": True, "server": (server or PHONE_DEFAULT_SERVER).rstrip("/"), "topic": topic,
            "secret": secrets.token_hex(32), "pushAfter": 15, "details": "full"}


def save_phone(cfg):
    write_private(phone_path(), json.dumps(cfg, indent=2))


def phone_sig(secret, req_id, verb):
    msg = f"loggdin-phone|v1|{req_id}|{verb}".encode("utf-8")
    return hmac.new(secret.encode("utf-8"), msg, hashlib.sha256).hexdigest()[:32]


def phone_reply_topic(cfg):
    return cfg["topic"] + "-reply"


def phone_parse_reply(cfg, text):
    """'lg1 <id> <verb> <sig>' -> (req_id, decision) or None when unsigned/forged."""
    parts = str(text or "").strip().split()
    if len(parts) != 4 or parts[0] != "lg1" or parts[2] not in PHONE_VERBS:
        return None
    req_id, verb, sig = parts[1], parts[2], parts[3]
    if not hmac.compare_digest(sig, phone_sig(cfg["secret"], req_id, verb)):
        return None
    d, scope = PHONE_VERBS[verb]
    return req_id, parse_decision(d, scope)


def phone_message(cfg, req):
    agent = req.get("requestedBy") or "An agent"
    high = req.get("risk") == "high"
    title = f"{agent} needs permission" + (" · HIGH RISK" if high else "")
    folder = os.path.basename(str(req.get("directory") or "").rstrip("/\\")) or str(req.get("directory") or "~")
    if cfg.get("details") == "minimal":
        body = f"{req.get('risk', 'low').capitalize()} risk request in {folder}."
    elif req.get("secretWarnings"):
        body = f"Command hidden: it looks like it contains a secret.\nFolder: {folder}"
    else:
        cmd = str(req.get("command") or "")
        cmd = cmd if len(cmd) <= 300 else cmd[:299] + "…"
        body = f"{cmd}\nFolder: {folder}"
    return title, body


# End-to-end encryption of what goes through the relay. The key comes from the pairing key, which
# only the QR code / pairing code carries, so the relay and anyone who knows the topic see neither the
# request nor its (signed) answer buttons. Encrypt-then-MAC with HMAC-SHA256 as both the keystream PRF
# and the MAC, so loggdin Pocket can do the same in plain TypeScript. Shared with PhoneRelay.swift and
# mobile/src/hmac.ts: "lg1e " + base64(nonce16 || ciphertext || tag16).
def _phone_keys(cfg):
    pk = phone_pair_key(cfg["secret"]).encode("utf-8")
    return (hmac.new(pk, b"loggdin-phone|v1|enc", hashlib.sha256).digest(),
            hmac.new(pk, b"loggdin-phone|v1|mac", hashlib.sha256).digest())


def _phone_stream(enc_key, nonce, n):
    out, i = b"", 0
    while len(out) < n:
        out += hmac.new(enc_key, nonce + i.to_bytes(4, "big"), hashlib.sha256).digest()
        i += 1
    return out[:n]


def phone_seal(cfg, obj):
    import base64
    enc_key, mac_key = _phone_keys(cfg)
    nonce = secrets.token_bytes(16)
    plain = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    ct = bytes(a ^ b for a, b in zip(plain, _phone_stream(enc_key, nonce, len(plain))))
    tag = hmac.new(mac_key, nonce + ct, hashlib.sha256).digest()[:16]
    return "lg1e " + base64.b64encode(nonce + ct + tag).decode("ascii")


def phone_open(cfg, text):
    """Inverse of phone_seal; None when the text is not ours or was tampered with."""
    import base64
    try:
        raw = base64.b64decode(str(text).split(" ", 1)[1], validate=True) if str(text).startswith("lg1e ") else b""
    except (ValueError, IndexError):
        return None
    if len(raw) < 33:
        return None
    enc_key, mac_key = _phone_keys(cfg)
    nonce, ct, tag = raw[:16], raw[16:-16], raw[-16:]
    if not hmac.compare_digest(tag, hmac.new(mac_key, nonce + ct, hashlib.sha256).digest()[:16]):
        return None
    try:
        return json.loads(bytes(a ^ b for a, b in zip(ct, _phone_stream(enc_key, nonce, len(ct)))))
    except ValueError:
        return None


def phone_publish(cfg, req):
    verbs = [("allow-once", "Allow once")]
    if req.get("risk") != "high":
        verbs.append(("allow-10m", "Allow 10 min"))
    verbs.append(("deny", "Deny"))
    title, body = phone_message(cfg, req)
    sealed = phone_seal(cfg, {"t": title, "m": body, "h": req.get("risk") == "high",
                              "a": [[label, f"lg1 {req['id']} {verb} {phone_sig(cfg['secret'], req['id'], verb)}"]
                                    for verb, label in verbs]})
    payload = {"topic": cfg["topic"], "title": "loggdin", "message": sealed,
               "priority": 5 if req.get("risk") == "high" else 4,
               "tags": ["warning"] if req.get("risk") == "high" else ["lock"],
               "sequence_id": phone_seq(req["id"])}
    return phone_request("POST", cfg["server"] + "/", payload)


def phone_seq(req_id):
    return "lg-" + re.sub(r"[^A-Za-z0-9]", "", str(req_id)).lower()[:40]


def phone_clear(cfg, req_id):
    return phone_request("PUT", f"{cfg['server']}/{cfg['topic']}/{phone_seq(req_id)}/clear", None)


def phone_request(method, url, payload, timeout=10):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Content-Type": "application/json", "User-Agent": f"loggdin/{VERSION}"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return 200 <= r.status < 300, ""
    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code}"
    except Exception as e:
        return False, str(e)


def phone_listen(cfg, on_reply, should_stop, since=None):
    """Stream the reply topic; calls on_reply(req_id, decision) for every validly signed reply.
    Returns the last message id seen so a reconnect resumes without losing replies."""
    url = f"{cfg['server']}/{phone_reply_topic(cfg)}/json?since={since or int(time.time()) - 5}"
    req = urllib.request.Request(url, headers={"User-Agent": f"loggdin/{VERSION}"})
    with urllib.request.urlopen(req, timeout=75) as r:          # ntfy sends a keepalive every ~45s
        for raw in r:
            if should_stop():
                break
            try:
                msg = json.loads(raw.decode("utf-8"))
            except ValueError:
                continue
            if msg.get("event") != "message":
                continue
            since = msg.get("id") or since
            token = phone_parse_push_registration(msg.get("message"), cfg["secret"])
            if token:
                if phone_register_push_token(token):
                    log("phone: registered a phone for notifications")
                continue
            parsed = phone_parse_reply(cfg, msg.get("message"))
            if parsed:
                on_reply(*parsed)
    return since


class PhoneRelay:
    def __init__(self, pending):
        self.pending = pending
        self.pushed = {}            # req_id -> config used to push it
        self.lock = threading.Lock()

    def schedule(self, req):
        cfg = load_phone()
        if not cfg or not cfg.get("enabled") or os.environ.get("LOGGDIN_NO_PHONE"):
            return None
        t = threading.Timer(cfg["pushAfter"] if cfg["mode"] == "auto" else 0, self._push, args=(req["id"],))
        t.daemon = True
        t.start()
        return t

    def _push(self, req_id):
        req = next((r for r in self.pending.all() if r["id"] == req_id), None)
        cfg = load_phone()
        if not req or not cfg or not cfg.get("enabled"):
            return
        ok, err = phone_publish(cfg, req)
        app_ok, app_err = phone_app_notify(cfg, req)
        if not app_ok:
            log(f"phone: app notification failed ({app_err})")
        if ok:
            with self.lock:
                self.pushed[req_id] = cfg
            log(f"phone: pushed {req_id[:8]}")
        else:
            log(f"phone: push failed ({err})")

    def finished(self, req_id, timer):
        if timer:
            timer.cancel()
        with self.lock:
            cfg = self.pushed.pop(req_id, None)
        if cfg:
            threading.Thread(target=phone_clear, args=(cfg, req_id), daemon=True).start()

    def on_reply(self, req_id, decision):
        if self.pending.resolve(dict(decision, via="phone"), req_id):
            log(f"phone: {decision.get('type')} {req_id[:8]}")

    def run(self):
        def loop():
            since, key, delay = None, None, 2
            while True:
                cfg = load_phone()
                if not cfg or not cfg.get("enabled") or os.environ.get("LOGGDIN_NO_PHONE"):
                    since, key = None, None
                    time.sleep(2)
                    continue
                if (cfg["server"], cfg["topic"], cfg["secret"]) != key:
                    since, key = None, (cfg["server"], cfg["topic"], cfg["secret"])
                current = key
                changed = lambda: (lambda c: not c or not c.get("enabled") or
                                   (c["server"], c["topic"], c["secret"]) != current)(load_phone())
                try:
                    since = phone_listen(cfg, self.on_reply, changed, since) or since
                    delay = 2
                except Exception as e:
                    log(f"phone: listener reconnecting ({e})")
                    time.sleep(delay)
                    delay = min(delay * 2, 60)
        threading.Thread(target=loop, daemon=True, name="loggdin-phone").start()


class Daemon:
    def __init__(self, port):
        self.port = port
        self.token = load_or_create_token()
        self.store = Store()
        self.pending = Pending()
        self.phone = PhoneRelay(self.pending)
        self.started = time.time()
        self.last_event = None
        self.httpd = None
        self.unix_path = os.path.join(state_dir(), "sentinel.sock")

    # -- core decision flow (shared by HTTP and unix socket) --
    def ask(self, body):
        req = parse_request(body)
        auto = self.store.evaluate(req)
        if auto:
            self.store.remember(req, auto)
            self.store.audit(req, auto, True)
            return decision_json(auto)
        ev, holder = self.pending.add(req)
        log(f"ASK [{req['risk']}] {req['requestedBy']}: {req['command'][:120]}")
        notify(req)
        push_timer = self.phone.schedule(req)
        timeout = float(body.get("timeout") or ASK_TIMEOUT)
        ev.wait(timeout=max(1.0, min(timeout, 3600.0)))
        self.pending.remove(req["id"])
        self.phone.finished(req["id"], push_timer)
        decision = holder.get("decision") or {"type": "timeout"}
        self.store.remember(req, decision)
        self.store.audit(req, decision, False)
        log(f"  -> {decision}")
        return decision_json(decision)

    def status(self):
        return {"status": "active", "port": self.port, "socket": self.unix_path if self._unix_ok() else None,
                "activeGrants": len(self.store.grants), "savedRules": len(self.store.rules),
                "pending": len(self.pending.all()), "daemon": "loggdin.py", "version": VERSION,
                "platform": sys.platform, "uptime": int(time.time() - self.started)}

    def _unix_ok(self):
        return hasattr(socket, "AF_UNIX") and not IS_WINDOWS and os.path.exists(self.unix_path)

    # -- unix socket (Linux/macOS): newline-delimited JSON, same as the Mac app --
    def serve_unix(self):
        if IS_WINDOWS or not hasattr(socket, "AF_UNIX") or os.environ.get("LOGGDIN_NO_UNIX"):
            return
        try:
            if os.path.exists(self.unix_path):
                os.unlink(self.unix_path)
            srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            old = os.umask(0o177)
            try:
                srv.bind(self.unix_path)
            finally:
                os.umask(old)
            os.chmod(self.unix_path, 0o600)
            srv.listen(32)
        except OSError as e:
            log(f"unix socket unavailable: {e}")
            return

        def client(conn):
            try:
                conn.settimeout(5)
                buf = b""
                while b"\n" not in buf and len(buf) < 1_000_000:
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    buf += chunk
                conn.settimeout(None)
                body = json.loads(buf.split(b"\n", 1)[0].decode("utf-8") or "{}")
                if isinstance(body, dict) and body.get("event") and not body.get("risk"):
                    self.last_event = body
                    resp = {"ok": True}
                else:
                    resp = self.ask(body if isinstance(body, dict) else {})
                conn.sendall((json.dumps(resp) + "\n").encode("utf-8"))
            except Exception:
                pass
            finally:
                conn.close()

        def loop():
            while True:
                try:
                    conn, _ = srv.accept()
                except OSError:
                    break
                threading.Thread(target=client, args=(conn,), daemon=True).start()

        threading.Thread(target=loop, daemon=True, name="loggdin-unix").start()
        log(f"unix socket listening on {self.unix_path}")

    def serve(self):
        daemon = self

        class Handler(BaseHTTPRequestHandler):
            server_version = "loggdin"
            sys_version = ""
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def _send(self, code, payload, ctype="application/json; charset=utf-8", csp="default-src 'none'"):
                data = payload if isinstance(payload, bytes) else (
                    payload.encode("utf-8") if isinstance(payload, str) else json.dumps(payload).encode("utf-8"))
                self.send_response(code)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Content-Security-Policy", csp)
                self.send_header("X-Content-Type-Options", "nosniff")
                self.send_header("X-Frame-Options", "DENY")
                self.send_header("Referrer-Policy", "no-referrer")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def _guard(self):
                host = (self.headers.get("Host") or "").lower()
                hostname = host.rsplit(":", 1)[0] if not host.startswith("[") else host.split("]")[0] + "]"
                if host and hostname not in ("127.0.0.1", "localhost"):
                    self._send(403, {"error": "Forbidden: Invalid Host header (DNS rebinding rejected)"})
                    return False
                for h in ("Origin", "Referer"):
                    v = self.headers.get(h)
                    # Any loopback port is fine (SSH/Docker port forwards land on a different port);
                    # cross-site writes are already impossible because they need the token header.
                    loopback = urlparse(v).hostname in ("127.0.0.1", "localhost") if v else False
                    if v and v != "null" and not (loopback and v.startswith("http://")):
                        self._send(403, {"error": f"Forbidden: cross-origin {h.lower()} rejected"})
                        return False
                return True

            def _authorized(self, body=None):
                cand = self.headers.get("X-Loggdin-Token") or self.headers.get("X-Sentinel-Token") or ""
                auth = self.headers.get("Authorization") or ""
                if auth.startswith("Bearer "):
                    cand = cand or auth[7:].strip()
                if not cand and isinstance(body, dict):
                    cand = str(body.get("token") or "")
                if not cand:
                    cand = (parse_qs(urlparse(self.path).query).get("token") or [""])[0]
                return bool(cand) and hmac.compare_digest(cand, daemon.token)

            def _body(self):
                try:
                    n = int(self.headers.get("Content-Length") or 0)
                except ValueError:
                    n = 0
                if n > 2_000_000:
                    return None
                raw = self.rfile.read(n) if n > 0 else b""
                if not raw:
                    return {}
                try:
                    v = json.loads(raw.decode("utf-8"))
                    return v if isinstance(v, dict) else None
                except ValueError:
                    return None

            def do_OPTIONS(self):
                self._send(403, {"error": "Preflight rejected"})

            def do_GET(self):
                if not self._guard():
                    return
                u = urlparse(self.path)
                qs = parse_qs(u.query)
                if u.path == "/status":
                    st = daemon.status()
                    challenge = (qs.get("challenge") or [""])[0]
                    if 16 <= len(challenge) <= 128:
                        st["proof"] = status_proof(daemon.token, challenge)
                    return self._send(200, st)
                if u.path in ("/", "/ui"):
                    nonce = secrets.token_urlsafe(16)
                    csp = (f"default-src 'none'; script-src 'nonce-{nonce}'; style-src 'nonce-{nonce}'; "
                           "connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
                    return self._send(200, UI_HTML.replace("__NONCE__", nonce), "text/html; charset=utf-8", csp)
                if not self._authorized():
                    return self._send(401, {"error": "Unauthorized: Valid token required in X-Loggdin-Token or Authorization header"})
                if u.path == "/pending":
                    reqs = daemon.pending.all()
                    if qs.get("all"):
                        return self._send(200, {"hasPending": bool(reqs), "requests": reqs})
                    if not reqs:
                        return self._send(200, {"hasPending": False, "message": "No pending permissions"})
                    r = reqs[0]
                    return self._send(200, dict(hasPending=True, **{k: r[k] for k in ("id", "title", "subtitle", "command", "risk", "requestedBy")}))
                if u.path == "/audit/verify":
                    return self._send(200, daemon.store.verify())
                if u.path == "/audit/export":
                    if (qs.get("format") or [""])[0] == "csv":
                        return self._send(200, daemon.store.export_csv(), "text/csv; charset=utf-8")
                    return self._send(200, daemon.store._entries())
                if u.path in ("/allow", "/deny", "/decision"):
                    return self._decide(u.path, qs, {})
                return self._send(404, {"error": "Unknown route"})

            def do_POST(self):
                if not self._guard():
                    return
                u = urlparse(self.path)
                body = self._body()
                if body is None:
                    return self._send(400, {"error": "Missing or invalid JSON body"})
                if not self._authorized(body):
                    return self._send(401, {"error": "Unauthorized: Valid token required in X-Loggdin-Token or Authorization header"})
                if u.path in ("/ask", "/hook"):
                    return self._send(200, daemon.ask(body))
                if u.path in ("/allow", "/deny", "/decision"):
                    return self._decide(u.path, parse_qs(u.query), body)
                if u.path == "/event":
                    daemon.last_event = body
                    return self._send(200, {"ok": True})
                if u.path == "/shutdown":
                    self._send(200, {"ok": True})
                    threading.Thread(target=daemon.httpd.shutdown, daemon=True).start()
                    return
                return self._send(404, {"error": "Unknown route"})

            def _decide(self, path, qs, body):
                if not self._authorized(body):
                    return self._send(401, {"error": "Unauthorized"})
                if path == "/deny":
                    d_str, s_str = "deny", None
                elif path == "/allow":
                    d_str, s_str = "allow", (qs.get("scope") or ["once"])[0]
                else:
                    d_str, s_str = body.get("decision", "allow"), body.get("scope")
                decision = parse_decision(d_str, s_str)
                handled = daemon.pending.resolve(decision, body.get("requestId"))
                out = {"success": handled, "decision": decision["type"]}
                if decision["type"] == "allow":
                    out["scope"] = decision["scope"]
                return self._send(200, out)

        class Server(ThreadingHTTPServer):
            daemon_threads = True
            allow_reuse_address = not IS_WINDOWS   # SO_REUSEADDR on Windows allows port hijacking

            def server_bind(self):
                if IS_WINDOWS and hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
                    # Stop another process from binding the same port and intercepting requests.
                    self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
                super().server_bind()

        last_err = None
        for p in range(self.port, self.port + PORT_RANGE):
            try:
                self.httpd = Server(("127.0.0.1", p), Handler)
                self.port = p
                break
            except OSError as e:
                last_err = e
                # Only treat the port as ours if the listener proves it knows our token; another
                # program (or another user) on the port must not stop us from starting.
                if verify_daemon(p, self.token):
                    log(f"loggdin is already running on port {p}.")
                    return 0
                log(f"port {p} is in use by another program; trying {p + 1}")
        if not self.httpd:
            log(f"could not bind 127.0.0.1:{self.port}-{self.port + PORT_RANGE - 1}: {last_err}")
            return 1
        save_port(self.port)
        self.serve_unix()
        self.phone.run()
        log(f"loggdin {VERSION} listening on http://127.0.0.1:{self.port}  (state: {state_dir()})")
        try:
            self.httpd.serve_forever(poll_interval=0.5)
        except KeyboardInterrupt:
            pass
        finally:
            for _, ev, holder in list(self.pending.items):
                holder["decision"] = {"type": "timeout"}
                ev.set()
            try:
                if os.path.exists(self.unix_path):
                    os.unlink(self.unix_path)
            except OSError:
                pass
            log("loggdin stopped.")
        return 0


# ---------------------------------------------------------------------------
# Client helpers
# ---------------------------------------------------------------------------

def verify_daemon(port, token):
    """True if whatever listens on `port` knows our token. Another local user could otherwise
    squat the port while loggdin is down, collect the token and answer "allow"."""
    challenge = secrets.token_hex(16)
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/status?challenge={challenge}", timeout=2) as r:
            proof = json.loads(r.read().decode("utf-8")).get("proof", "")
    except Exception:
        return False
    return hmac.compare_digest(str(proof), status_proof(token, challenge))


def http(method, path, body=None, timeout=5.0, port=None):
    port = port or get_port()
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=data, method=method)
    req.add_header("Content-Type", "application/json")
    tok = get_token()
    if tok and path != "/status":
        if not verify_daemon(port, tok):
            return None, None
        req.add_header("X-Loggdin-Token", tok)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8")
            try:
                return r.status, json.loads(raw)
            except ValueError:
                return r.status, raw
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode("utf-8"))
        except Exception:
            return e.code, {}
    except Exception:
        return None, None


def is_running(port=None):
    """True if OUR loggdin answers on the port (verified with the token once one exists)."""
    port = port or get_port()
    tok = get_token()
    if tok:
        return verify_daemon(port, tok)
    code, body = http("GET", "/status", timeout=1.0, port=port)
    return code == 200 and isinstance(body, dict) and body.get("status") == "active"


def python_exe(windowed=False):
    exe = sys.executable or ("python" if IS_WINDOWS else "python3")
    if windowed and IS_WINDOWS:
        w = os.path.join(os.path.dirname(exe), "pythonw.exe")
        if os.path.exists(w):
            return w
    return exe


def spawn_daemon():
    ensure_private_dir(state_dir())
    logf = open(os.path.join(state_dir(), "daemon.log"), "ab")
    args = [python_exe(windowed=True), os.path.abspath(__file__), "daemon"]
    kw = dict(stdin=subprocess.DEVNULL, stdout=logf, stderr=logf, close_fds=True)
    if IS_WINDOWS:
        kw["creationflags"] = (getattr(subprocess, "DETACHED_PROCESS", 0x8) |
                               getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0x200) |
                               getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000))
    else:
        kw["start_new_session"] = True
    subprocess.Popen(args, **kw)
    for _ in range(40):
        time.sleep(0.15)
        if is_running():
            return True
    return False


def ensure_daemon():
    if is_running():
        return True
    if IS_MAC and os.path.isdir("/Applications/Loggdin.app") and not os.environ.get("LOGGDIN_HOME"):
        subprocess.run(["open", "-g", "-j", "-a", "/Applications/Loggdin.app"], check=False)
        for _ in range(20):
            time.sleep(0.2)
            if is_running():
                return True
    return spawn_daemon()


def open_ui(quiet=False):
    url = f"http://127.0.0.1:{get_port()}/#token={get_token()}"
    ok = False
    try:
        ok = webbrowser.open(url, new=2)
    except Exception:
        pass
    if not quiet:
        print("Opened the approval page in your browser." if ok else
              "Open this URL in your browser (keep it private — it contains your access token):\n" + url)


# ---------------------------------------------------------------------------
# Agent integrations
# ---------------------------------------------------------------------------

HOOK_MARK = "sentinel-hook"


def install_dir():
    """Where the hook / MCP helper are deployed for agents to call."""
    return state_dir()


def deploy_helpers():
    """Copy sentinel-hook, sentinel-mcp.js and this file into the state dir."""
    here = os.path.dirname(os.path.abspath(__file__))
    dest = install_dir()
    ensure_private_dir(dest)
    copied = {}
    for name in ("sentinel-hook", "sentinel-mcp.js", "loggdin.py"):
        src = os.path.join(here, name)
        if not os.path.exists(src):
            continue
        dst = os.path.join(dest, name)
        if os.path.abspath(src) != os.path.abspath(dst):
            shutil.copyfile(src, dst)
        if not IS_WINDOWS:
            os.chmod(dst, 0o755)
        copied[name] = dst
    return copied


def fwd(p):
    return p.replace("\\", "/") if IS_WINDOWS else p


def stable_python():
    """Interpreter command for hooks that survives upgrades.

    sys.executable is often a versioned path (Homebrew's .../python@3.14/bin/python3.14) that
    disappears on the next upgrade, so prefer a stable launcher that points at a working Python:
    the Windows `py` launcher, or a python3 symlink on PATH / in a standard location.
    """
    if IS_WINDOWS:
        launcher = shutil.which("py")
        if launcher:
            return [launcher, "-3"]
        return [python_exe()]
    current = os.path.realpath(sys.executable or "")
    candidates = [shutil.which("python3"), "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
    for c in candidates:
        if c and os.path.exists(c) and os.path.realpath(c) == current:
            return [c]
    return [python_exe()]


def hook_cmd(agent, event=None, ask=False):
    hook = fwd(os.path.join(install_dir(), "sentinel-hook"))
    # Absolute interpreter: agents run hooks with a minimal PATH (and macOS's /usr/bin/python3
    # may be a stub that only offers to install developer tools).
    py = stable_python()
    exe = " ".join([f'"{fwd(py[0])}"'] + py[1:])
    cmd = f'{exe} "{hook}" --agent {agent}'
    if ask:
        cmd += " --ask"
    if event:
        cmd += f" {event}"
    return cmd


def read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            v = json.load(f)
            return v if isinstance(v, dict) else {}
    except (OSError, ValueError):
        return {}


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        shutil.copyfile(path, path + ".loggdin.bak")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2)
    os.replace(tmp, path)


def _strip_hook_groups(groups):
    return [g for g in (groups or []) if not any(HOOK_MARK in str(h.get("command", "")) for h in g.get("hooks", []))]


def home(*p):
    return os.path.join(os.path.expanduser("~"), *p)


def claude_desktop_config():
    if IS_MAC:
        return home("Library", "Application Support", "Claude", "claude_desktop_config.json")
    if IS_WINDOWS:
        return os.path.join(os.environ.get("APPDATA") or home("AppData", "Roaming"), "Claude", "claude_desktop_config.json")
    return os.path.join(os.environ.get("XDG_CONFIG_HOME") or home(".config"), "Claude", "claude_desktop_config.json")


def install_hook_events(path, agent, events, extra=None):
    root = read_json(path)
    hooks = root.get("hooks") if isinstance(root.get("hooks"), dict) else {}
    for event, timeout, msg in events:
        groups = _strip_hook_groups(hooks.get(event))
        entry = {"type": "command", "command": hook_cmd(agent, event), "timeout": timeout}
        if msg:
            entry["statusMessage"] = msg
        groups.append({"hooks": [entry]})
        hooks[event] = groups
    if extra:
        extra(hooks)
    root["hooks"] = hooks
    write_json(path, root)


def uninstall_hook_events(path):
    root = read_json(path)
    hooks = root.get("hooks") if isinstance(root.get("hooks"), dict) else None
    if not hooks:
        return
    for event in list(hooks):
        kept = _strip_hook_groups(hooks[event])
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    write_json(path, root)


def mcp_entry():
    node = shutil.which("node") or "node"
    port = str(get_port())
    return {"command": fwd(node), "args": [fwd(os.path.join(install_dir(), "sentinel-mcp.js"))],
            "env": {"SENTINEL_PORT": port, "LOGGDIN_PORT": port}}


def install_target(target):
    deploy_helpers()
    if target == "claude":
        def ask_hook(hooks):
            pre = [g for g in hooks.get("PreToolUse", []) if g.get("matcher") != "AskUserQuestion"]
            pre.append({"matcher": "AskUserQuestion", "hooks": [
                {"type": "command", "command": hook_cmd("claude-code", ask=True), "timeout": 130}]})
            hooks["PreToolUse"] = pre
        events = [(e, 120 if e in ("PreToolUse", "PermissionRequest") else 10, None) for e in (
            "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
            "PermissionRequest", "Notification", "Stop", "SubagentStart", "SubagentStop")]
        install_hook_events(home(".claude", "settings.json"), "claude-code", events, ask_hook)
    elif target == "codex":
        msg = "Waiting for permission in loggdin"
        install_hook_events(home(".codex", "hooks.json"), "codex", [
            ("SessionStart", 10, None), ("UserPromptSubmit", 10, None), ("PreToolUse", 120, msg),
            ("PermissionRequest", 120, msg), ("PostToolUse", 10, None), ("Stop", 10, None), ("SessionEnd", 10, None)])
    elif target == "antigravity":
        path = home(".gemini", "config", "hooks.json")
        root = read_json(path)
        root.pop("sentinel", None)
        root.pop("loggdin-safety-gate", None)
        root["loggdin"] = {
            "enabled": True,
            "PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": hook_cmd("antigravity", "PreToolUse"), "timeout": 120}]}],
            "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": hook_cmd("antigravity", "PostToolUse"), "timeout": 10}]}],
        }
        write_json(path, root)
    elif target in ("cursor", "cowork"):
        path = home(".cursor", "mcp.json") if target == "cursor" else claude_desktop_config()
        root = read_json(path)
        mcp = root.get("mcpServers") if isinstance(root.get("mcpServers"), dict) else {}
        mcp["sentinel"] = mcp_entry()
        root["mcpServers"] = mcp
        write_json(path, root)
    elif target == "copilot":
        key = "powershell" if IS_WINDOWS else "bash"
        def h(ev, t):
            return [{key: hook_cmd("copilot", ev), "timeoutSec": t}]
        write_json(home(".copilot", "hooks", "sentinel.json"), {"hooks": {
            "permissionRequest": h("PermissionRequest", 120), "preToolUse": h("PreToolUse", 120),
            "postToolUse": h("PostToolUse", 10), "sessionStart": h("SessionStart", 10), "sessionEnd": h("SessionEnd", 10)}})
    else:
        raise ValueError(f"unknown target '{target}'")


def uninstall_target(target):
    if target == "claude":
        uninstall_hook_events(home(".claude", "settings.json"))
    elif target == "codex":
        uninstall_hook_events(home(".codex", "hooks.json"))
    elif target == "antigravity":
        path = home(".gemini", "config", "hooks.json")
        root = read_json(path)
        if root.pop("loggdin", None) is not None:
            write_json(path, root)
    elif target in ("cursor", "cowork"):
        path = home(".cursor", "mcp.json") if target == "cursor" else claude_desktop_config()
        root = read_json(path)
        if isinstance(root.get("mcpServers"), dict) and root["mcpServers"].pop("sentinel", None) is not None:
            write_json(path, root)
    elif target == "copilot":
        p = home(".copilot", "hooks", "sentinel.json")
        if os.path.exists(p):
            os.remove(p)
    else:
        raise ValueError(f"unknown target '{target}'")


TARGETS = ("claude", "codex", "antigravity", "cursor", "cowork", "copilot")


def is_target_installed(t):
    paths = {"claude": home(".claude", "settings.json"), "codex": home(".codex", "hooks.json"),
             "antigravity": home(".gemini", "config", "hooks.json"), "cursor": home(".cursor", "mcp.json"),
             "cowork": claude_desktop_config(), "copilot": home(".copilot", "hooks", "sentinel.json")}
    text = read_text(paths[t])
    return t == "copilot" and bool(text) or "sentinel-hook" in text or '"sentinel"' in text or '"loggdin"' in text


def detected_targets():
    """Agents whose config folder already exists on this machine."""
    found = []
    for t, p in (("claude", home(".claude")), ("codex", home(".codex")), ("antigravity", home(".gemini")),
                 ("cursor", home(".cursor")), ("cowork", os.path.dirname(claude_desktop_config())),
                 ("copilot", home(".copilot"))):
        if os.path.isdir(p):
            found.append(t)
    return found


# ---------------------------------------------------------------------------
# Autostart
# ---------------------------------------------------------------------------

WIN_RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"


def _win_run_name():
    return os.environ.get("LOGGDIN_AUTOSTART_NAME", "loggdin")


def autostart_path():
    if IS_WINDOWS:
        return "HKCU\\" + WIN_RUN_KEY + "\\" + _win_run_name()
    if IS_MAC:
        return home("Library", "LaunchAgents", "dev.loggdin.daemon.plist")
    return os.path.join(os.environ.get("XDG_CONFIG_HOME") or home(".config"), "autostart", "loggdin.desktop")


def _legacy_win_startup_cmd():
    return os.path.join(os.environ.get("APPDATA") or home("AppData", "Roaming"),
                        "Microsoft", "Windows", "Start Menu", "Programs", "Startup", "loggdin.cmd")


def autostart_enabled():
    if IS_WINDOWS:
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, WIN_RUN_KEY) as k:
                winreg.QueryValueEx(k, _win_run_name())
            return True
        except OSError:
            return False
    return os.path.exists(autostart_path())


def set_autostart(on):
    path = autostart_path()
    script = os.path.join(install_dir(), "loggdin.py")
    if not os.path.exists(script):
        script = os.path.abspath(__file__)
    if IS_WINDOWS:
        # Per-user Run key with pythonw: starts at login without a console window flashing up
        # (unlike a .cmd in the Startup folder, which older versions used and we clean up).
        import winreg
        legacy = _legacy_win_startup_cmd()
        if os.path.exists(legacy):
            os.remove(legacy)
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, WIN_RUN_KEY) as k:
            if on:
                pyw = shutil.which("pyw")   # version-independent launcher survives Python upgrades
                runner = f'"{pyw}" -3' if pyw else f'"{python_exe(windowed=True)}"'
                winreg.SetValueEx(k, _win_run_name(), 0, winreg.REG_SZ, f'{runner} "{script}" daemon')
            else:
                try:
                    winreg.DeleteValue(k, _win_run_name())
                except OSError:
                    pass
        return path
    if not on:
        if os.path.exists(path):
            os.remove(path)
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if IS_MAC:
        content = (f'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                   f'"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>'
                   f'<key>Label</key><string>dev.loggdin.daemon</string><key>ProgramArguments</key><array>'
                   f'<string>{python_exe()}</string><string>{script}</string><string>daemon</string></array>'
                   f'<key>RunAtLoad</key><true/></dict></plist>\n')
    else:
        content = ("[Desktop Entry]\nType=Application\nName=loggdin\nComment=Permission gate for AI coding agents\n"
                   f"Exec=\"{python_exe()}\" \"{script}\" daemon\nX-GNOME-Autostart-enabled=true\nNoDisplay=true\nTerminal=false\n")
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(content)
    return path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def report_decision(code, body, ok_msg):
    if code is None:
        print("⚠️  No response from loggdin daemon.", file=sys.stderr)
        return 1
    if isinstance(body, dict) and body.get("success"):
        print(ok_msg)
        return 0
    print("ℹ️  No permission request is pending — nothing was changed.")
    return 1


def cmd_run(argv):
    command = " ".join(argv)
    if not command:
        print("usage: loggdin run <command...>", file=sys.stderr)
        return 2
    if not ensure_daemon():
        print("❌ loggdin daemon is not running.", file=sys.stderr)
        return 1
    print("⏳ Waiting for approval (loggdin ui)...", file=sys.stderr)
    code, resp = http("POST", "/ask", {"command": command, "requestedBy": "Terminal", "cwd": os.getcwd(),
                                       "title": "Run terminal command?"}, timeout=ASK_TIMEOUT + 10)
    if not (isinstance(resp, dict) and resp.get("allowed")):
        print(f"❌ Not approved ({(resp or {}).get('decision', 'no response') if isinstance(resp, dict) else 'no response'}).", file=sys.stderr)
        return 1
    return subprocess.call(command, shell=True)


def doctor():
    ok = True
    print(f"loggdin {VERSION} on {sys.platform} (Python {sys.version.split()[0]})")
    print(f"  state dir : {state_dir()}")
    print(f"  port/token: {get_port()} / {'present' if get_token() else 'missing'}")
    running = is_running()
    print(f"  daemon    : {'running' if running else 'not running'}")
    ok &= running
    node = shutil.which("node")
    print(f"  node      : {node or 'not found (needed for MCP server: cursor/cowork)'}")
    for t, p in (("claude", home(".claude", "settings.json")), ("codex", home(".codex", "hooks.json")),
                 ("antigravity", home(".gemini", "config", "hooks.json")), ("cursor", home(".cursor", "mcp.json"))):
        installed = os.path.exists(p) and ("sentinel-hook" in read_text(p) or '"sentinel"' in read_text(p))
        print(f"  {t:<10}: {'installed' if installed else '-'}")
    print(f"  autostart : {'on' if autostart_enabled() else 'off'}  ({autostart_path()})")
    return 0 if ok else 1


def cmd_phone(argv):
    sub = (argv[:1] or ["status"])[0]
    cfg = load_phone()
    if sub == "setup":
        server = argv[argv.index("--server") + 1] if "--server" in argv else None
        if cfg and "--new" not in argv:
            cfg["enabled"] = True
            if server:
                cfg["server"] = server.rstrip("/")
        else:
            cfg = new_phone_config(server)
        save_phone(cfg)
        print("📱 Phone approvals are ON.\n")
        code = phone_pairing_code(cfg)
        target = code if cfg["server"] == PHONE_DEFAULT_SERVER else f"{cfg['server']}/{code}"
        print("1. Install loggdin Pocket on your phone, or open https://app.loggdin.com")
        print("2. Type this pairing code in it (or open the link on your phone):")
        print(f"\n       {code}\n       https://app.loggdin.com/#{target}\n")
        print("   Treat the code like a password. Requests are encrypted with it end to end,")
        print("   so the relay and anyone who only knows the topic can't read or answer them.")
        print("3. Run 'loggdin phone test' and answer on your phone.\n")
        print(f"Requests left unanswered at the computer for {int(cfg['pushAfter'])} s are sent to your phone.")
        print("The phone offers Allow once, Allow 10 min (not for high risk) and Deny. 'Always' stays on the computer.")
        return 0
    if not cfg:
        print("Phone approvals are not set up. Run: loggdin phone setup")
        return 1 if sub != "status" else 0
    if sub in ("on", "off"):
        cfg["enabled"] = sub == "on"
        save_phone(cfg)
        print(f"📱 Phone approvals {'ON' if cfg['enabled'] else 'OFF'}.")
        return 0
    if sub == "delay":
        try:
            cfg["pushAfter"] = max(0, min(int(argv[1]), 100))
        except (IndexError, ValueError):
            print("usage: loggdin phone delay <seconds 0-100>", file=sys.stderr)
            return 2
        save_phone(cfg)
        print(f"Unanswered requests go to your phone after {cfg['pushAfter']} s.")
        return 0
    if sub == "details":
        level = (argv[1:2] or [""])[0]
        if level not in ("full", "minimal"):
            print("usage: loggdin phone details <full|minimal>", file=sys.stderr)
            return 2
        cfg["details"] = level
        save_phone(cfg)
        print("The phone shows " + ("the command and folder." if level == "full" else "only the agent, risk and folder."))
        return 0
    if sub == "test":
        req = {"id": "TEST-" + secrets.token_hex(4).upper(), "requestedBy": "loggdin test", "risk": "low",
               "command": "echo 'Hello from loggdin'", "directory": os.getcwd(), "secretWarnings": []}
        ok, err = phone_publish(cfg, req)
        if not ok:
            print(f"❌ Could not reach {cfg['server']}: {err}")
            return 1
        print("📨 Sent a test notification. Tap a button on your phone (waiting 90 s)…")
        got, deadline = {}, time.time() + 90

        def on_reply(req_id, decision):
            if req_id == req["id"]:
                got["d"] = decision

        since = int(time.time()) - 5
        while not got and time.time() < deadline:
            try:
                since = phone_listen(cfg, on_reply, lambda: bool(got) or time.time() > deadline, since)
            except Exception:
                time.sleep(1)
        phone_clear(cfg, req["id"])
        if not got:
            print("⌛ No answer. Check that loggdin Pocket is open and paired with the code from 'loggdin phone setup'.")
            return 1
        d = got["d"]
        print("✓ Phone works: you tapped " + ("Allow." if d.get("type") == "allow" else "Deny."))
        return 0
    if sub == "status":
        print(f"📱 Phone approvals: {'ON' if cfg.get('enabled') else 'OFF'}")
        print(f"   server:  {cfg['server']}\n   topic:   {cfg['topic']}")
        print(f"   delay:   {int(cfg['pushAfter'])} s\n   details: {cfg['details']}")
        return 0
    print("usage: loggdin phone <setup [--new] [--server URL]|test|on|off|status|delay N|details full|minimal>",
          file=sys.stderr)
    return 2


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    cmd = argv.pop(0) if argv else "help"

    if cmd == "daemon":
        port = int(argv[argv.index("--port") + 1]) if "--port" in argv else get_port() if os.environ.get("LOGGDIN_PORT") else DEFAULT_PORT
        return Daemon(port).serve()
    if cmd == "start":
        if is_running():
            print(f"🛡️ loggdin is already running on port {get_port()}.")
            return 0
        ok = spawn_daemon()
        print(f"🛡️ loggdin started on port {get_port()}." if ok else
              f"❌ loggdin failed to start; see {os.path.join(state_dir(), 'daemon.log')}")
        return 0 if ok else 1
    if cmd == "stop":
        code, _ = http("POST", "/shutdown", {})
        print("loggdin stopped." if code == 200 else "loggdin was not running.")
        return 0
    if cmd == "status":
        code, body = http("GET", "/status", timeout=2)
        if code == 200 and get_token() and not verify_daemon(get_port(), get_token()):
            print(f"⚠️  Port {get_port()} is answered by another program, not your loggdin.\n"
                  "Run 'loggdin start' to start loggdin on a free port.")
            return 7
        if code == 200:
            print("🛡️ loggdin Status: ONLINE")
            print(json.dumps(body, indent=4))
            return 0
        print("❌ loggdin Status: OFFLINE\nRun 'loggdin start' to start it.")
        return 7
    if cmd == "ui":
        if not ensure_daemon():
            print("❌ loggdin daemon is not running.", file=sys.stderr)
            return 1
        open_ui()
        return 0
    if cmd == "pending":
        code, body = http("GET", "/pending")
        if code is None:
            print("❌ loggdin daemon is not running.", file=sys.stderr)
            return 1
        if argv[:1] in (["--json"], ["-j"]):
            print(json.dumps(body))
        elif isinstance(body, dict) and body.get("hasPending"):
            print("⚠️  Pending Permission Request")
            print(f"🤖 Agent:   {body.get('requestedBy')}")
            print(f"⚠️  Risk:    {str(body.get('risk')).upper()}")
            print(f"💻 Action:  {body.get('command')}")
        else:
            print("✓ No permissions currently pending.")
        return 0
    if cmd == "allow":
        scope = (argv[:1] or ["once"])[0]
        code, body = http("POST", "/decision", {"decision": "allow", "scope": scope})
        return report_decision(code, body, f"✓ Approved permission (Scope: {scope})")
    if cmd == "deny":
        code, body = http("POST", "/decision", {"decision": "deny"})
        return report_decision(code, body, "❌ Denied permission.")
    if cmd in ("install", "uninstall"):
        target = (argv[:1] or [""])[0]
        targets = TARGETS if target == "all" else detected_targets() if target == "detected" else (target,)
        if target not in TARGETS and target not in ("all", "detected"):
            print(f"usage: loggdin {cmd} <{'|'.join(TARGETS)}|all|detected>", file=sys.stderr)
            return 2
        if not targets:
            print("No supported agents detected (Claude Code, Codex, Antigravity, Cursor, Claude Desktop, Copilot).")
        failed = 0
        for t in targets:
            if cmd == "uninstall" and target == "all" and not is_target_installed(t):
                continue
            try:
                (install_target if cmd == "install" else uninstall_target)(t)
                print(f"✓ {cmd}ed {t}")
            except Exception as e:
                failed += 1
                print(f"❌ {t}: {e}", file=sys.stderr)
        if cmd == "install":
            ensure_daemon()
        return 1 if failed else 0
    if cmd == "autostart":
        on = (argv[:1] or ["on"])[0] != "off"
        p = set_autostart(on)
        print(f"✓ autostart {'enabled' if on else 'disabled'} ({p})")
        return 0
    if cmd == "deploy":
        for k, v in deploy_helpers().items():
            print(f"✓ {k} -> {v}")
        return 0
    if cmd == "run":
        return cmd_run(argv)
    if cmd == "phone":
        return cmd_phone(argv)
    if cmd == "doctor":
        return doctor()
    if cmd in ("version", "--version", "-V"):
        print(VERSION)
        return 0
    print(__doc__.split("Usage:", 1)[1].rstrip() if cmd in ("help", "--help", "-h") else f"unknown command '{cmd}'\n")
    return 0 if cmd in ("help", "--help", "-h") else 2


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(errors="replace")   # Windows consoles without UTF-8
        sys.stderr.reconfigure(errors="replace")
    except Exception:
        pass
    sys.exit(main())
