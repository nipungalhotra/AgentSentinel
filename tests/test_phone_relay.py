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
        self.posts = []              # (path, body) of every non-root POST (replies, app notifications)
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
                    fake.posts.append((path, raw.decode()))
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

    def tap(self, opened, label, cfg):
        """What loggdin Pocket sends when a button is tapped: the signed body, to the reply topic."""
        body = next(b for l, b in opened["a"] if l == label)
        req = urllib.request.Request(f"{self.url}/{cfg['topic']}-reply", data=body.encode(), method="POST")
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

    def test_sealed_messages_open_only_with_the_right_key_and_untampered(self):
        sealed = self.m.phone_seal(self.cfg, {"t": "x", "m": "rm -rf build", "a": [["Deny", "lg1 A deny 0"]]})
        self.assertTrue(sealed.startswith("lg1e "))
        self.assertNotIn("rm -rf", sealed)
        self.assertEqual(self.m.phone_open(self.cfg, sealed)["m"], "rm -rf build")
        other = dict(self.cfg, secret="another-secret")
        self.assertIsNone(self.m.phone_open(other, sealed))
        import base64
        raw = bytearray(base64.b64decode(sealed[5:]))
        raw[20] ^= 1
        self.assertIsNone(self.m.phone_open(self.cfg, "lg1e " + base64.b64encode(bytes(raw)).decode()))
        self.assertIsNone(self.m.phone_open(self.cfg, "hello"))
        self.assertNotEqual(sealed, self.m.phone_seal(self.cfg, {"t": "x", "m": "rm -rf build", "a": [["Deny", "lg1 A deny 0"]]}))

    def test_question_option_reply_parses_and_rejects_forgery(self):
        sig = self.m.phone_sig(self.cfg["secret"], "Q-1", "opt-2")
        self.assertEqual(self.m.phone_parse_option(self.cfg, f"lg1 Q-1 opt-2 {sig}"), ("Q-1", 2))
        for text in (f"lg1 Q-1 opt-3 {sig}", f"lg1 Q-2 opt-2 {sig}", "lg1 Q-1 opt-2 0000", f"lg1 Q-1 opt-12 {sig}",
                     f"lg1 Q-1 deny {sig}", ""):
            self.assertIsNone(self.m.phone_parse_option(self.cfg, text), text)
        # an option reply is never mistaken for an allow/deny reply
        self.assertIsNone(self.m.phone_parse_reply(self.cfg, f"lg1 Q-1 opt-2 {sig}"))

    def test_signature_matches_swift_vector(self):
        # Same vector is produced by Sources/PhoneRelay.swift (CryptoKit HMAC-SHA256, 32 hex chars).
        self.assertEqual(self.m.phone_sig("abc123secret", "BB3A26FF-8E69", "allow-10m"), "7ca1291cc8499d13512e776bfd55e813")

    def test_push_registration_needs_the_pairing_key(self):
        ok = "ExponentPushToken[abcdefghijklmnopqrstuv]"
        secret = self.cfg["secret"]
        key = self.m.phone_pair_key(secret)
        self.assertEqual(len(key), 16)
        sig = self.m.hmac.new(key.encode(), ("loggdin-phone|v1|push|" + ok).encode(), self.m.hashlib.sha256).hexdigest()[:32]
        self.assertEqual(self.m.phone_parse_push_registration("lg1-push " + ok + " " + sig, secret), ok)
        for bad in ("lg1-push " + ok, "lg1-push " + ok + " " + "0" * 32, "lg1-push https://evil.example/x " + sig,
                    "lg1 " + ok + " " + sig, "lg1-push " + ok + " " + sig + " extra", None):
            self.assertIsNone(self.m.phone_parse_push_registration(bad, secret))
        self.assertIsNone(self.m.phone_parse_push_registration("lg1-push " + ok + " " + sig, "another-secret"))
        self.assertEqual(self.m.phone_pairing_code(self.cfg), self.cfg["topic"] + "." + key)

    def test_pair_key_matches_swift_and_typescript_vector(self):
        # Same derivation as PhoneRelay.pairKey (Swift) and the phone's signPushRegistration (TypeScript).
        self.assertEqual(self.m.phone_pair_key("s3cret"),
                         self.m.hmac.new(b"s3cret", b"loggdin-phone|v1|pair", self.m.hashlib.sha256).hexdigest()[:16])

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
        cls.m = load_module()
        cls.tmp = tempfile.mkdtemp(prefix="lgq")
        cls.state = os.path.join(cls.tmp, "s")
        os.makedirs(cls.state)
        cls.port = free_port()
        cls.env = dict(os.environ, LOGGDIN_HOME=cls.state, LOGGDIN_PORT=str(cls.port), LOGGDIN_NO_NOTIFY="1",
                       LOGGDIN_NO_UNIX="1", PYTHONIOENCODING="utf-8",
                       LOGGDIN_EXPO_PUSH_URL=cls.ntfy.url + "/expo-push")
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

    def post_async(self, path, body):
        result = {}

        def run():
            req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=json.dumps(body).encode(),
                                         headers={"Content-Type": "application/json", "X-Loggdin-Token": self.token})
            with urllib.request.urlopen(req, timeout=60) as r:
                result["r"] = json.loads(r.read())
        t = threading.Thread(target=run)
        t.start()
        return t, result

    def test_question_tap_option_answers_on_the_computer(self):
        n0 = len(self.ntfy.published)
        q = {"question": "Which database?", "header": "DB", "multiSelect": False,
             "options": [{"label": "Postgres"}, {"label": "SQLite"}]}
        t, result = self.post_async("/question", {"agent": "Claude Code", "directory": "/tmp/api", "questions": [q], "timeout": 30})
        self.assertTrue(self.ntfy.wait_published(n0 + 1))
        opened = self.m.phone_open(self.cfg, self.ntfy.published[n0]["message"])
        self.assertEqual(opened["k"], "q")
        self.assertEqual([a[0] for a in opened["a"]], ["Postgres", "SQLite"])
        self.assertIn("Which database?", opened["m"])
        self.ntfy.tap(opened, "SQLite", self.cfg)
        t.join(20)
        self.assertEqual(result["r"], {"answers": {"Which database?": "SQLite"}})

    def test_multi_question_has_no_buttons_on_the_phone(self):
        n0 = len(self.ntfy.published)
        qs = [{"question": f"Q{i}?", "options": [{"label": "a"}, {"label": "b"}]} for i in range(2)]
        t, result = self.post_async("/question", {"agent": "Claude Code", "questions": qs, "timeout": 3})
        self.assertTrue(self.ntfy.wait_published(n0 + 1))
        opened = self.m.phone_open(self.cfg, self.ntfy.published[n0]["message"])
        self.assertEqual(opened["a"], [])
        self.assertIn("Answer this one on your computer", opened["m"])
        t.join(20)
        self.assertEqual(result["r"], {"answers": {}})

    def test_tap_allow_10m_resolves_and_clears(self):
        n0 = len(self.ntfy.published)
        t, result = self.ask_async({"requestedBy": "Claude Code", "risk": "medium",
                                    "command": "npm install stripe", "directory": "/tmp/shop", "timeout": 30})
        self.assertTrue(self.ntfy.wait_published(n0 + 1))
        note = self.ntfy.published[n0]
        self.assertEqual(note["topic"], self.cfg["topic"])
        # Nothing readable reaches the relay: no command, no folder, no answer buttons.
        raw = json.dumps(note)
        for leak in ("npm install stripe", "shop", "Claude Code", "lg1 ", "actions"):
            self.assertNotIn(leak, raw)
        opened = self.m.phone_open(self.cfg, note["message"])
        self.assertIn("npm install stripe", opened["m"])
        self.assertEqual([l for l, _ in opened["a"]], ["Allow once", "Allow 10 min", "Deny"])
        self.ntfy.tap(opened, "Allow 10 min", self.cfg)
        t.join(10)
        self.assertEqual(result.get("r"), {"allowed": True, "decision": "allow", "scope": "tenMinutes"})
        time.sleep(0.5)
        self.assertTrue(any(note["sequence_id"] in p for p in self.ntfy.cleared))
        with open(os.path.join(self.state, "audit_log.jsonl")) as f:
            last = json.loads(f.read().strip().splitlines()[-1])
        self.assertEqual(last["decision"].get("via"), "phone")

    def test_zz_phone_app_registers_and_gets_a_notification_without_the_command(self):
        token = "ExponentPushToken[abcdefghijklmnopqrstuv]"
        reply = self.cfg["topic"] + "-reply"
        # what the loggdin phone app posts when notifications are switched on (plus one bogus token)
        m = load_module()
        key = m.phone_pair_key(self.cfg["secret"]).encode()
        sig = m.hmac.new(key, ("loggdin-phone|v1|push|" + token).encode(), m.hashlib.sha256).hexdigest()[:32]
        intruder = "ExponentPushToken[intruderintruderintr]"
        self.ntfy.deliver(reply, "lg1-push not-a-token " + sig)
        self.ntfy.deliver(reply, "lg1-push " + intruder)               # no signature: someone who only knows the topic
        self.ntfy.deliver(reply, "lg1-push " + intruder + " " + sig)   # a signature for another token
        self.ntfy.deliver(reply, "lg1-push " + token + " " + sig)
        for _ in range(100):
            with open(os.path.join(self.state, "phone.json")) as f:
                if json.load(f).get("pushTokens") == [token]:
                    break
            time.sleep(0.05)
        else:
            self.fail("push token was not stored")
        n0 = len(self.ntfy.published)
        t, result = self.ask_async({"requestedBy": "Claude Code", "risk": "medium",
                                    "command": "npm install left-pad", "directory": "/tmp/shop", "timeout": 30})
        self.assertTrue(self.ntfy.wait_published(n0 + 1))
        for _ in range(100):
            sent = [json.loads(b) for p, b in self.ntfy.posts if p == "expo-push"]
            if sent:
                break
            time.sleep(0.05)
        else:
            self.fail("no app notification was sent")
        note = sent[-1][0]
        self.assertEqual(note["to"], token)
        self.assertIn("Claude Code needs permission", note["title"])
        self.assertNotIn("left-pad", json.dumps(sent[-1]))      # the command stays off Expo's servers
        self.ntfy.tap(self.m.phone_open(self.cfg, self.ntfy.published[n0]["message"]), "Deny", self.cfg)
        t.join(10)
        self.assertEqual(result.get("r", {}).get("decision"), "deny")

    def test_high_risk_has_no_10_minute_button_and_deny_works(self):
        n0 = len(self.ntfy.published)
        t, result = self.ask_async({"requestedBy": "Codex", "risk": "high",
                                    "command": "git push --force origin main", "directory": "/tmp/repo", "timeout": 30})
        self.assertTrue(self.ntfy.wait_published(n0 + 1))
        note = self.ntfy.published[n0]
        opened = self.m.phone_open(self.cfg, note["message"])
        self.assertEqual([l for l, _ in opened["a"]], ["Allow once", "Deny"])
        self.assertEqual(note["priority"], 5)
        self.ntfy.tap(opened, "Deny", self.cfg)
        t.join(10)
        self.assertEqual(result.get("r"), {"allowed": False, "decision": "deny"})

    def test_forged_reply_is_ignored(self):
        n0 = len(self.ntfy.published)
        t, result = self.ask_async({"requestedBy": "Cursor", "risk": "low", "command": "rm -rf build",
                                    "directory": "/tmp/site", "timeout": 4})
        self.assertTrue(self.ntfy.wait_published(n0 + 1))
        note = self.ntfy.published[n0]
        req_id = self.m.phone_open(self.cfg, note["message"])["a"][0][1].split()[1]
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
