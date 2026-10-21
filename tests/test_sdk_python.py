#!/usr/bin/env python3
"""
Unit tests for loggdin / Agent Sentinel Python SDK (sdk/sentinel.py and sdk/loggdin.py)
"""

import unittest
import os
import sys
import json
import http.server
import threading
import tempfile
import shutil

# Ensure sdk is in import path
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO_ROOT, "sdk"))

import sentinel
import loggdin

class MockSentinelServer(http.server.HTTPServer):
    def __init__(self, server_address, RequestHandlerClass):
        super().__init__(server_address, RequestHandlerClass)
        self.last_request_headers = {}
        self.last_payload = {}
        self.response_allowed = True

class MockHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length)
        self.server.last_payload = json.loads(body.decode('utf-8'))
        self.server.last_request_headers = dict(self.headers)

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        resp = {"allowed": self.server.response_allowed, "grantId": "test-grant-123"}
        self.wfile.write(json.dumps(resp).encode('utf-8'))

    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        resp = {"status": "running", "port": self.server.server_port, "socket": "/tmp/test.sock"}
        self.wfile.write(json.dumps(resp).encode('utf-8'))

    def log_message(self, format, *args):
        pass  # Suppress server access logs during tests

class TestPythonSDK(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = MockSentinelServer(('127.0.0.1', 0), MockHandler)
        cls.port = cls.server.server_port
        cls.server_thread = threading.Thread(target=cls.server.serve_forever)
        cls.server_thread.daemon = True
        cls.server_thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.original_env = os.environ.copy()

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)
        os.environ.clear()
        os.environ.update(self.original_env)

    def test_port_discovery_from_environment(self):
        os.environ["LOGGDIN_PORT"] = str(self.port)
        url = sentinel.get_sentinel_url("status")
        self.assertEqual(url, f"http://127.0.0.1:{self.port}/status")

        url_loggdin = loggdin.get_loggdin_url("ask")
        self.assertEqual(url_loggdin, f"http://127.0.0.1:{self.port}/ask")

    def test_port_discovery_from_file(self):
        port_file = os.path.join(self.temp_dir, "port")
        with open(port_file, "w") as f:
            f.write(f"{self.port}\n")

        # Mock the path in os.path.expanduser
        original_expanduser = os.path.expanduser
        try:
            os.path.expanduser = lambda path: port_file if "port" in path else original_expanduser(path)
            os.environ.pop("LOGGDIN_PORT", None)
            os.environ.pop("SENTINEL_PORT", None)
            os.environ.pop("SENTINEL_URL", None)
            os.environ.pop("LOGGDIN_URL", None)

            url = sentinel.get_sentinel_url("ask")
            self.assertEqual(url, f"http://127.0.0.1:{self.port}/ask")
        finally:
            os.path.expanduser = original_expanduser

    def test_ask_permission_approved(self):
        os.environ["SENTINEL_URL"] = f"http://127.0.0.1:{self.port}/ask"
        self.server.response_allowed = True

        result = sentinel.ask_permission(
            command="npm run build",
            title="Compile project",
            risk="low",
            requested_by="Antigravity Test Agent"
        )
        self.assertTrue(result)
        self.assertEqual(self.server.last_payload.get("command"), "npm run build")
        self.assertEqual(self.server.last_payload.get("requestedBy"), "Antigravity Test Agent")
        self.assertEqual(self.server.last_payload.get("risk"), "low")

    def test_ask_permission_denied(self):
        os.environ["SENTINEL_URL"] = f"http://127.0.0.1:{self.port}/ask"
        self.server.response_allowed = False

        result = sentinel.ask_permission(
            command="rm -rf /test",
            risk="high"
        )
        self.assertFalse(result)

    def test_guard_execution_success(self):
        os.environ["SENTINEL_URL"] = f"http://127.0.0.1:{self.port}/ask"
        self.server.response_allowed = True

        proc = sentinel.guard("echo 'sentinel-test-ok'", requested_by="Tester")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("sentinel-test-ok", proc.stdout)

    def test_guard_execution_with_list_args(self):
        os.environ["SENTINEL_URL"] = f"http://127.0.0.1:{self.port}/ask"
        self.server.response_allowed = True

        proc = sentinel.guard(["echo", "list-mode-ok"], requested_by="Tester")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("list-mode-ok", proc.stdout)

    def test_guard_execution_shell_false(self):
        os.environ["SENTINEL_URL"] = f"http://127.0.0.1:{self.port}/ask"
        self.server.response_allowed = True

        proc = sentinel.guard("echo 'safe-shlex-ok'", requested_by="Tester", shell=False)
        self.assertEqual(proc.returncode, 0)
        self.assertIn("safe-shlex-ok", proc.stdout)

    def test_guard_execution_denied_raises_exception(self):
        os.environ["SENTINEL_URL"] = f"http://127.0.0.1:{self.port}/ask"
        self.server.response_allowed = False

        with self.assertRaises(PermissionError) as ctx:
            sentinel.guard("echo 'should not run'", requested_by="Tester")
        self.assertIn("Permission denied", str(ctx.exception))

if __name__ == "__main__":
    unittest.main(verbosity=2)
