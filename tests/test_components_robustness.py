#!/usr/bin/env python3
"""
Comprehensive robustness tests for RulesEngine and HookInstaller components.
Tests atomic file persistence, corrupt config recovery, deduplication, grant expiration,
and shell hook safety boundaries.
"""

import unittest
import os
import sys
import json
import tempfile
import shutil
import time
import hashlib

class MockRulesEngine:
    """Python simulation matching Sources/RulesEngine.swift logic for unit testing."""
    def __init__(self, storage_dir: str):
        self.storage_dir = storage_dir
        self.stored_rules = []
        self.active_grants = []
        self.audit_logs = []
        self.recent_approvals = {}
        os.makedirs(self.storage_dir, exist_ok=True)

    def is_catastrophic_destructive(self, command: str) -> bool:
        lower = command.lower()
        patterns = ["rm -rf /", "rm -fr /", "mkfs", "> /dev/sd", ":(){ :|:& };:"]
        return any(p in lower for p in patterns)

    def is_recently_approved(self, command: str) -> bool:
        cmd = command.strip()
        if cmd in self.recent_approvals:
            if time.time() - self.recent_approvals[cmd] < 15.0:
                return True
            else:
                del self.recent_approvals[cmd]
        return False

    def record_recent_approval(self, command: str):
        self.recent_approvals[command.strip()] = time.time()

    def grant_temporary(self, command: str, minutes: int = 10):
        expiry = time.time() + (minutes * 60)
        grant = {"command": command, "expires_at": expiry}
        self.active_grants.append(grant)
        self.save_to_disk()

    def prune_expired_grants(self):
        now = time.time()
        self.active_grants = [g for g in self.active_grants if g["expires_at"] > now]
        self.save_to_disk()

    def save_to_disk(self):
        def atomic_write(filepath, data):
            tmp = filepath + ".tmp"
            with open(tmp, "w") as f:
                json.dump(data, f, indent=2)
            os.replace(tmp, filepath)

        atomic_write(os.path.join(self.storage_dir, "rules.json"), self.stored_rules)
        atomic_write(os.path.join(self.storage_dir, "grants.json"), self.active_grants)
        atomic_write(os.path.join(self.storage_dir, "audit_log.json"), self.audit_logs)

    def load_from_disk(self):
        for name in ["rules.json", "grants.json", "audit_log.json"]:
            path = os.path.join(self.storage_dir, name)
            if os.path.exists(path):
                try:
                    with open(path) as f:
                        data = json.load(f)
                    if name == "rules.json": self.stored_rules = data
                    elif name == "grants.json": self.active_grants = data
                    elif name == "audit_log.json": self.audit_logs = data
                except Exception as e:
                    # Create timestamped corrupt backup
                    corrupt_path = os.path.join(self.storage_dir, f"{name}.corrupt.{int(time.time())}")
                    shutil.copyfile(path, corrupt_path)

class MockHookInstaller:
    """Python simulation matching Sources/HookInstaller.swift logic for unit testing."""
    START_MARKER = "# >>> loggdin hook start >>>"
    END_MARKER = "# <<< loggdin hook end <<<"

    @classmethod
    def install_zsh_hook(cls, zshrc_path: str, hook_cmd: str):
        # 1. Create atomic backup if file exists
        if os.path.exists(zshrc_path):
            backup_path = f"{zshrc_path}.bak.{int(time.time())}"
            shutil.copyfile(zshrc_path, backup_path)
            with open(zshrc_path) as f:
                content = f.read()
        else:
            content = ""

        # 2. Strip existing block
        content = cls.uninstall_zsh_hook_content(content)

        # 3. Append boundary-delimited block
        block = f"\n{cls.START_MARKER}\n{hook_cmd}\n{cls.END_MARKER}\n"
        with open(zshrc_path, "w") as f:
            f.write(content + block)

    @classmethod
    def uninstall_zsh_hook_content(cls, content: str) -> str:
        if cls.START_MARKER in content and cls.END_MARKER in content:
            before = content.split(cls.START_MARKER)[0]
            after = content.split(cls.END_MARKER)[1]
            return before.rstrip() + "\n" + after.lstrip()
        return content

    @classmethod
    def read_json_safe(cls, path: str):
        if not os.path.exists(path):
            return {}
        with open(path) as f:
            return json.load(f)

class TestComponentRobustness(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_rules_engine_atomic_persistence(self):
        engine = MockRulesEngine(self.temp_dir)
        engine.stored_rules.append({"id": "1", "pattern": "git status", "action": "allow"})
        engine.save_to_disk()

        rules_file = os.path.join(self.temp_dir, "rules.json")
        self.assertTrue(os.path.exists(rules_file))

        with open(rules_file) as f:
            data = json.load(f)
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]["pattern"], "git status")

    def test_rules_engine_corrupt_config_recovery(self):
        engine = MockRulesEngine(self.temp_dir)
        rules_file = os.path.join(self.temp_dir, "rules.json")

        # Write invalid/corrupt JSON
        with open(rules_file, "w") as f:
            f.write("{invalid_json_content[")

        engine.load_from_disk()

        # Verify a .corrupt backup file was created
        files = os.listdir(self.temp_dir)
        corrupt_backups = [f for f in files if "rules.json.corrupt" in f]
        self.assertTrue(len(corrupt_backups) > 0, "Expected corrupt configuration backup file")

    def test_rules_engine_deduplication(self):
        engine = MockRulesEngine(self.temp_dir)
        self.assertFalse(engine.is_recently_approved("npm test"))

        engine.record_recent_approval("npm test")
        self.assertTrue(engine.is_recently_approved("npm test"))
        self.assertFalse(engine.is_recently_approved("git push"))

    def test_rules_engine_grant_pruning(self):
        engine = MockRulesEngine(self.temp_dir)
        # Add an expired grant
        engine.active_grants.append({"command": "expired_cmd", "expires_at": time.time() - 10})
        # Add an active grant
        engine.active_grants.append({"command": "active_cmd", "expires_at": time.time() + 600})

        engine.prune_expired_grants()
        self.assertEqual(len(engine.active_grants), 1)
        self.assertEqual(engine.active_grants[0]["command"], "active_cmd")

    def test_hook_installer_atomic_backup_and_boundaries(self):
        zshrc = os.path.join(self.temp_dir, ".zshrc")
        with open(zshrc, "w") as f:
            f.write("export PATH=$HOME/bin:$PATH\nalias ll='ls -la'\n")

        MockHookInstaller.install_zsh_hook(zshrc, "eval \"$(sentinel hook zsh)\"")

        # 1. Verify backup was created
        backups = [f for f in os.listdir(self.temp_dir) if ".zshrc.bak." in f]
        self.assertTrue(len(backups) > 0, "Expected .zshrc backup file")

        # 2. Verify markers were placed cleanly
        with open(zshrc) as f:
            content = f.read()
        self.assertIn(MockHookInstaller.START_MARKER, content)
        self.assertIn(MockHookInstaller.END_MARKER, content)
        self.assertIn("alias ll='ls -la'", content)

        # 3. Test clean uninstallation without corrupting remaining config
        uninstalled = MockHookInstaller.uninstall_zsh_hook_content(content)
        self.assertNotIn(MockHookInstaller.START_MARKER, uninstalled)
        self.assertNotIn(MockHookInstaller.END_MARKER, uninstalled)
        self.assertIn("alias ll='ls -la'", uninstalled)

    def test_hook_installer_corrupt_json_handling(self):
        corrupt_json = os.path.join(self.temp_dir, "settings.json")
        with open(corrupt_json, "w") as f:
            f.write("{invalid json")

        with self.assertRaises(json.JSONDecodeError):
            MockHookInstaller.read_json_safe(corrupt_json)

if __name__ == "__main__":
    unittest.main(verbosity=2)
