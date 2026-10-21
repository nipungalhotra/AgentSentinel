#!/usr/bin/env python3
"""
Unit tests validating command parsing, tool family classification, destructive command checks,
and cryptographic Merkle audit chain logic matching Sources/RulesEngine.swift.
"""

import unittest
import hashlib
import json

def is_catastrophic_destructive(command: str) -> bool:
    lower = command.lower()
    patterns = ["rm -rf /", "rm -fr /", "mkfs", "> /dev/sd", ":(){ :|:& };:"]
    return any(p in lower for p in patterns)

def tool_family(command: str) -> str:
    clean = command.strip()
    subcmds = [s.strip() for s in clean.split("&&")]
    subcmds = [p.strip() for s in subcmds for p in s.split(";")]
    subcmds = [p.strip() for s in subcmds for p in s.split("||")]
    subcmds = [s for s in subcmds if s]
    target = subcmds[-1] if subcmds else clean

    parts = target.split()
    if not parts:
        return clean
    first = parts[0].lower()

    if first in ("sudo", "env") and len(parts) > 1:
        first = parts[1].lower()

    if first in ("write", "edit", "inspect", "modify"):
        return "file_mod"

    known_tools = {
        "git", "npm", "npx", "yarn", "pnpm", "bun",
        "cargo", "rustc", "swift", "xcodebuild",
        "python", "python3", "pytest", "pip", "pip3", "poetry", "uv",
        "docker", "docker-compose", "podman",
        "brew", "curl", "wget", "gh", "terraform", "go", "make", "cmake", "ctest",
        "node", "deno", "ts-node", "tsc", "eslint", "prettier"
    }

    if first in known_tools:
        return first
    return "other"

class AuditChain:
    def __init__(self):
        self.entries = []

    def log(self, command: str, agent: str, decision: str) -> str:
        prev_hash = self.entries[-1]["hash"] if self.entries else "GENESIS"
        record = f"{prev_hash}:{command}:{agent}:{decision}"
        entry_hash = hashlib.sha256(record.encode("utf-8")).hexdigest()
        entry = {
            "index": len(self.entries),
            "command": command,
            "agent": agent,
            "decision": decision,
            "prev_hash": prev_hash,
            "hash": entry_hash
        }
        self.entries.append(entry)
        return entry_hash

    def verify(self) -> bool:
        for i, entry in enumerate(self.entries):
            expected_prev = "GENESIS" if i == 0 else self.entries[i - 1]["hash"]
            if entry["prev_hash"] != expected_prev:
                return False
            expected_hash = hashlib.sha256(
                f"{expected_prev}:{entry['command']}:{entry['agent']}:{entry['decision']}".encode("utf-8")
            ).hexdigest()
            if entry["hash"] != expected_hash:
                return False
        return True

class TestRulesEngineLogic(unittest.TestCase):
    def test_destructive_commands_detected(self):
        self.assertTrue(is_catastrophic_destructive("rm -rf /"))
        self.assertTrue(is_catastrophic_destructive("sudo rm -fr / --no-preserve-root"))
        self.assertTrue(is_catastrophic_destructive("mkfs.ext4 /dev/sda1"))
        self.assertTrue(is_catastrophic_destructive(":(){ :|:& };:"))
        self.assertFalse(is_catastrophic_destructive("rm -rf ./build"))
        self.assertFalse(is_catastrophic_destructive("git status"))

    def test_tool_family_extraction(self):
        self.assertEqual(tool_family("git status"), "git")
        self.assertEqual(tool_family("cd /tmp && npm test"), "npm")
        self.assertEqual(tool_family("sudo docker compose up -d"), "docker")
        self.assertEqual(tool_family("export FOO=1; python3 main.py"), "python3")
        self.assertEqual(tool_family("write /path/to/file.txt"), "file_mod")
        self.assertEqual(tool_family("unknown_tool_xyz --flag"), "other")

    def test_merkle_audit_chain_validity(self):
        chain = AuditChain()
        chain.log("git status", "Claude Code", "allow")
        chain.log("npm test", "Antigravity", "allow")
        chain.log("rm -rf /", "Malicious Agent", "deny")

        self.assertEqual(len(chain.entries), 3)
        self.assertTrue(chain.verify())

    def test_merkle_audit_chain_tamper_detection(self):
        chain = AuditChain()
        chain.log("git status", "Claude Code", "allow")
        chain.log("npm test", "Antigravity", "allow")

        # Tamper with entry 0
        chain.entries[0]["command"] = "git push --force"
        self.assertFalse(chain.verify())

if __name__ == "__main__":
    unittest.main(verbosity=2)
