#!/usr/bin/env python3
"""
Unit and integration tests for bin/sentinel-mcp.js Model Context Protocol (MCP) server.
Verifies JSON-RPC 2.0 handshake, tools/list registration, and tools/call execution.
"""

import unittest
import subprocess
import json
import os
import sys
import threading
import http.server

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MCP_SCRIPT = os.path.join(REPO_ROOT, "bin/sentinel-mcp.js")

class MockSentinelServer(http.server.HTTPServer):
    def __init__(self, server_address, RequestHandlerClass):
        super().__init__(server_address, RequestHandlerClass)
        self.last_payload = None

class MockHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length)
        self.server.last_payload = json.loads(body.decode('utf-8'))

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        resp = {"allowed": True, "grantId": "mcp-test-grant"}
        self.wfile.write(json.dumps(resp).encode('utf-8'))

    def log_message(self, format, *args):
        pass

class TestMCPServer(unittest.TestCase):
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

    def test_mcp_handshake_and_tools(self):
        env = os.environ.copy()
        env["LOGGDIN_PORT"] = str(self.port)

        proc = subprocess.Popen(
            ["node", MCP_SCRIPT],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env
        )

        try:
            # 1. Send initialize request
            init_req = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "test-client", "version": "1.0.0"}
                }
            }
            proc.stdin.write(json.dumps(init_req) + "\n")
            proc.stdin.flush()

            init_resp_line = proc.stdout.readline()
            init_resp = json.loads(init_resp_line)
            self.assertEqual(init_resp.get("id"), 1)
            self.assertIn("capabilities", init_resp.get("result", {}))
            self.assertEqual(init_resp["result"]["serverInfo"]["name"], "agent-sentinel")

            # 2. Request tools list
            tools_req = {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/list",
                "params": {}
            }
            proc.stdin.write(json.dumps(tools_req) + "\n")
            proc.stdin.flush()

            tools_resp_line = proc.stdout.readline()
            tools_resp = json.loads(tools_resp_line)
            self.assertEqual(tools_resp.get("id"), 2)
            tools = tools_resp.get("result", {}).get("tools", [])
            tool_names = [t["name"] for t in tools]

            self.assertIn("sentinel_request_permission", tool_names)
            self.assertIn("sentinel_guard_command", tool_names)

            # 3. Call sentinel_request_permission tool
            call_req = {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "sentinel_request_permission",
                    "arguments": {
                        "command": "git push origin main",
                        "title": "Push to main branch",
                        "risk": "high",
                        "requested_by": "Claude Code"
                    }
                }
            }
            proc.stdin.write(json.dumps(call_req) + "\n")
            proc.stdin.flush()

            call_resp_line = proc.stdout.readline()
            call_resp = json.loads(call_resp_line)
            self.assertEqual(call_resp.get("id"), 3)
            content = call_resp.get("result", {}).get("content", [])
            self.assertTrue(len(content) > 0)
            text_data = json.loads(content[0]["text"])
            self.assertTrue(text_data.get("allowed"))

            # Verify mock server received the payload
            self.assertEqual(self.server.last_payload.get("command"), "git push origin main")
            self.assertEqual(self.server.last_payload.get("requestedBy"), "Claude Code")

        finally:
            proc.terminate()
            proc.wait(timeout=2)

if __name__ == "__main__":
    unittest.main(verbosity=2)
