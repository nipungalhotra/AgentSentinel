#!/usr/bin/env python3
"""
Phone approvals (ntfy) for bin/loggdin.py, fully offline: a tiny fake ntfy server
stands in for ntfy.sh, and a "phone tap" is the exact HTTP request the ntfy app
sends when an action button is pressed.
"""

import importlib.util
import json
import os
import queue
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DAEMON = os.path.join(ROOT, "bin", "loggdin.py")


def load_module():
    spec = importlib.util.spec_from_file_location("loggdin_phone_under_test", DAEMON)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


class FakeNtfy:
    """Just enough of ntfy: JSON publish, text publish, clear, and /<topic>/json streaming."""

    def __init__(self):
        self.published = []          # JSON publishes (notifications)
        self.cleared = []
        self.subs = {}               # topic -> [queue]
        self.lock = threading.Lock()
        fake = self

        class H(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def _ok(self, body=b"{}"):
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                n = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(n)
                path = self.path.strip("/")
                if not path:
                    fake.published.append(json.loads(raw))
                else:
                    fake.deliver(path, raw.decode())
                self._ok()

            def do_PUT(self):
                fake.cleared.append(self.path)
                self._ok()

            def do_GET(self):
                topic = self.path.split("/")[1]
                q = queue.Queue()
                with fake.lock:
                    fake.subs.setdefault(topic, []).append(q)
                self.send_response(200)
                self.send_header("Content-Type", "application/x-ndjson")
                self.end_headers()
                self.wfile.write(json.dumps({"event": "open"}).encode() + b"\n")
                self.wfile.flush()
                try:
                    while True:
                        try:
                            msg = q.get(timeout=1)
                        except queue.Empty:
                            msg = {"event": "keepalive"}
                        self.wfile.write(json.dumps(msg).encode() + b"\n")
                        self.wfile.flush()
                except OSError:
                    pass

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.httpd.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def deliver(self, topic, text):
        with self.lock:
            qs = list(self.subs.get(topic, []))
        for q in qs:
            q.put({"event": "message", "id": f"m{time.time_ns()}", "message": text})

    def tap(self, notification, label):
        action = next(a for a in notification["actions"] if a["label"] == label)
        req = urllib.request.Request(action["url"], data=action["body"].encode(), method=action.get("method", "POST"))
        urllib.request.urlopen(req, timeout=5).read()

    def wait_published(self, count, timeout=10):
        end = time.time() + timeout
        while time.time() < end and len(self.published) < count:
            time.sleep(0.05)
        return len(self.published) >= count


class PhoneProtocolTest(unittest.TestCase):
    """Pure functions: signing, parsing, message content."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="lgp")
        os.environ["LOGGDIN_HOME"] = cls.tmp
        cls.m = load_module()
        cls.cfg = cls.m.new_phone_config("https://ntfy.example")

    def test_topic_is_long_and_typeable(self):
        t = self.cfg["topic"]
        self.assertTrue(t.startswith("loggdin-"))
        self.assertEqual(len(t), len("loggdin-") + 20)
        self.assertFalse(set(t[8:]) & set("01lo"))

    def test_valid_reply_parses(self):
        sig = self.m.phone_sig(self.cfg["secret"], "REQ-1", "allow-10m")
        rid, d = self.m.phone_parse_reply(self.cfg, f"lg1 REQ-1 allow-10m {sig}")
        self.assertEqual(rid, "REQ-1")
        self.assertEqual(d, {"type": "allow", "scope": "tenMinutes"})

    def test_forged_or_swapped_replies_rejected(self):
        sig = self.m.phone_sig(self.cfg["secret"], "REQ-1", "deny")
        for text in ("lg1 REQ-1 allow-once 0000", f"lg1 REQ-1 allow-once {sig}", f"lg1 REQ-2 deny {sig}",
                     f"lg1 REQ-1 always {sig}", "", "hello", f"lg2 REQ-1 deny {sig}"):
            self.assertIsNone(self.m.phone_parse_reply(self.cfg, text), text)

    def test_signature_matches_swift_vector(self):
        # Same vector is produced by Sources/PhoneRelay.swift (CryptoKit HMAC-SHA256, 32 hex chars).
        self.assertEqual(self.m.phone_sig("abc123secret", "BB3A26FF-8E69", "allow-10m"), "7ca1291cc8499d13512e776bfd55e813")

    def test_message_hides_secrets_and_minimal_mode(self):
        req = {"id": "X", "requestedBy": "Codex", "risk": "high", "command": "export KEY=sk-live-123",
               "directory": "/home/me/shop", "secretWarnings": ["API key"]}
        title, body = self.m.phone_message(self.cfg, req)
        self.assertIn("HIGH RISK", title)
        self.assertNotIn("sk-live", body)
        self.assertIn("shop", body)
        req["secretWarnings"] = []
        title, body = self.m.phone_message(dict(self.cfg, details="minimal"), req)
        self.assertNotIn("sk-live", body)
        _, body = self.m.phone_message(self.cfg, req)
        self.assertIn("sk-live", body)          # full mode, no secret flagged


class PhoneRelayEndToEndTest(unittest.TestCase):
    """Real daemon process + fake ntfy: push, tap, forged tap, clear, high-risk buttons."""

    @classmethod
    def setUpClass(cls):
        cls.ntfy = FakeNtfy()
        cls.tmp = tempfile.mkdtemp(prefix="lgq")
        cls.state = os.path.join(cls.tmp, "s")
        os.makedirs(cls.state)
        cls.port = free_port()
        cls.env = dict(os.environ, LOGGDIN_HOME=cls.state, LOGGDIN_PORT=str(cls.port), LOGGDIN_NO_NOTIFY="1",
                       LOGGDIN_NO_UNIX="1", PYTHONIOENCODING="utf-8")
        cls.env.pop("LOGGDIN_NO_PHONE", None)
        out = subprocess.run([sys.executable, DAEMON, "phone", "setup", "--server", cls.ntfy.url],
                             env=cls.env, capture_output=True, text=True)
        assert out.returncode == 0, out.stderr
        subprocess.run([sys.executable, DAEMON, "phone", "delay", "0"], env=cls.env, capture_output=True)
        with open(os.path.join(cls.state, "phone.json")) as f:
            cls.cfg = json.load(f)
        cls.proc = subprocess.Popen([sys.executable, DAEMON, "daemon"], env=cls.env,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{cls.port}/status", timeout=1).read()
                break
            except Exception:
                time.sleep(0.1)
        with open(os.path.join(cls.state, "token")) as f:
            cls.token = f.read().strip()
        # wait until the daemon's listener is subscribed to the reply topic
        reply = cls.cfg["topic"] + "-reply"
        for _ in range(100):
            if cls.ntfy.subs.get(reply):
                break
            time.sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        cls.proc.kill()
        cls.proc.wait()
        cls.ntfy.httpd.shutdown()

    def ask_async(self, body):
        result = {}

        def run():
            req = urllib.request.Request(f"http://127.0.0.1:{self.port}/ask", data=json.dumps(body).encode(),
                                         headers={"Content-Type": "application/json", "X-Loggdin-Token": self.token})
            with urllib.request.urlopen(req, timeout=60) as r:
                result["r"] = json.loads(r.read())
        t = threading.Thread(target=run)
        t.start()
        return t, result

    def test_tap_allow_10m_resolves_and_clears(self):
        n0 = len(self.ntfy.published)
        t, result = self.ask_async({"requestedBy": "Claude Code", "risk": "medium",
                                    "command": "npm install stripe", "directory": "/tmp/shop", "timeout": 30})
        self.assertTrue(self.ntfy.wait_published(n0 + 1))
        note = self.ntfy.published[n0]
        self.assertEqual(note["topic"], self.cfg["topic"])
        self.assertEqual([a["label"] for a in note["actions"]], ["Allow once", "Allow 10 min", "Deny"])
        self.ntfy.tap(note, "Allow 10 min")
        t.join(10)
        self.assertEqual(result.get("r"), {"allowed": True, "decision": "allow", "scope": "tenMinutes"})
        time.sleep(0.5)
        self.assertTrue(any(note["sequence_id"] in p for p in self.ntfy.cleared))
        with open(os.path.join(self.state, "audit_log.jsonl")) as f:
            last = json.loads(f.read().strip().splitlines()[-1])
        self.assertEqual(last["decision"].get("via"), "phone")

    def test_high_risk_has_no_10_minute_button_and_deny_works(self):
        n0 = len(self.ntfy.published)
        t, result = self.ask_async({"requestedBy": "Codex", "risk": "high",
                                    "command": "git push --force origin main", "directory": "/tmp/repo", "timeout": 30})
        self.assertTrue(self.ntfy.wait_published(n0 + 1))
        note = self.ntfy.published[n0]
        self.assertEqual([a["label"] for a in note["actions"]], ["Allow once", "Deny"])
        self.assertEqual(note["priority"], 5)
        self.ntfy.tap(note, "Deny")
        t.join(10)
        self.assertEqual(result.get("r"), {"allowed": False, "decision": "deny"})

    def test_forged_reply_is_ignored(self):
        n0 = len(self.ntfy.published)
        t, result = self.ask_async({"requestedBy": "Cursor", "risk": "low", "command": "rm -rf build",
                                    "directory": "/tmp/site", "timeout": 4})
        self.assertTrue(self.ntfy.wait_published(n0 + 1))
        note = self.ntfy.published[n0]
        req_id = note["actions"][0]["body"].split()[1]
        self.ntfy.deliver(self.cfg["topic"] + "-reply", f"lg1 {req_id} allow-once {'0' * 32}")
        t.join(10)
        self.assertEqual(result.get("r"), {"allowed": False, "decision": "timeout"})

    def test_phone_off_sends_nothing(self):
        subprocess.run([sys.executable, DAEMON, "phone", "off"], env=self.env, capture_output=True)
        try:
            n0 = len(self.ntfy.published)
            t, result = self.ask_async({"requestedBy": "Cursor", "risk": "low", "command": "ls -la",
                                        "directory": "/tmp/off", "timeout": 2})
            t.join(10)
            self.assertEqual(len(self.ntfy.published), n0)
        finally:
            reply = self.cfg["topic"] + "-reply"
            before = len(self.ntfy.subs.get(reply, []))
            subprocess.run([sys.executable, DAEMON, "phone", "on"], env=self.env, capture_output=True)
            for _ in range(100):                      # listener resubscribes once switched back on
                if len(self.ntfy.subs.get(reply, [])) > before:
                    break
                time.sleep(0.1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
