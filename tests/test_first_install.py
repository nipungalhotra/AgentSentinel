#!/usr/bin/env python3
"""
First-install problems found by installing loggdin like a new Mac user (Nov 2026):
- hooks saved Apple's internal Python path (inside Xcode / Command Line Tools), which breaks when
  Xcode is updated or removed;
- `uninstall all` left the zsh terminal gate, loggdin's PATH line and old MCP entries behind;
- the CLI ran a placeholder `python3` on Macs without developer tools instead of saying what to do.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(home):
    os.environ["HOME"] = home
    spec = importlib.util.spec_from_file_location("loggdin_first_install", os.path.join(ROOT, "bin", "loggdin.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class StablePythonTest(unittest.TestCase):
    def setUp(self):
        self.m = load(tempfile.mkdtemp())

    def test_apple_python_inside_xcode_becomes_usr_bin_python3(self):
        for internal in ("/Applications/Xcode.app/Contents/Developer/usr/bin/python3",
                         "/Library/Developer/CommandLineTools/usr/bin/python3"):
            old_exe, old_plat = self.m.sys.executable, self.m.sys.platform
            try:
                self.m.sys.executable, self.m.sys.platform = internal, "darwin"
                if os.name != "nt":
                    self.assertEqual(self.m.stable_python(), ["/usr/bin/python3"], internal)
            finally:
                self.m.sys.executable, self.m.sys.platform = old_exe, old_plat


@unittest.skipIf(os.name == "nt", "shell config cleanup is for macOS/Linux")
class UninstallLeftoversTest(unittest.TestCase):
    def test_uninstall_all_removes_zsh_gate_path_line_and_old_mcp_entries(self):
        home = tempfile.mkdtemp()
        share = os.path.join(home, ".local", "share", "sentinel")
        os.makedirs(share)
        open(os.path.join(share, "sentinel-hook.zsh"), "w").write("x")
        with open(os.path.join(home, ".zshrc"), "w") as f:
            f.write(f'export A=1\n# Agent Sentinel Terminal Gate\n[ -f "{share}/sentinel-hook.zsh" ] && source "{share}/sentinel-hook.zsh"\nalias ll="ls -l"\n')
        with open(os.path.join(home, ".zprofile"), "w") as f:
            f.write('eval "$(brew shellenv)"\n# Added by loggdin: make the loggdin command available in Terminal\nexport PATH="$HOME/.local/bin:$PATH"\n')
        with open(os.path.join(home, ".claude.json"), "w") as f:
            json.dump({"keep": 1, "mcpServers": {"sentinel": {"command": "node", "args": ["/gone/bin/sentinel-mcp.js"]},
                                                  "github": {"command": "gh"}},
                       "projects": {"/p": {"mcpServers": {"loggdin": {"command": "node", "args": ["x/sentinel-mcp.js"]}}}}}, f)
        env = dict(os.environ, HOME=home, LOGGDIN_HOME=os.path.join(home, "state"))
        out = subprocess.run([sys.executable, os.path.join(ROOT, "bin", "loggdin.py"), "uninstall", "all"],
                             env=env, capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(open(os.path.join(home, ".zshrc")).read(), 'export A=1\nalias ll="ls -l"\n')
        self.assertEqual(open(os.path.join(home, ".zprofile")).read(), 'eval "$(brew shellenv)"\n')
        self.assertFalse(os.path.exists(share))
        cfg = json.load(open(os.path.join(home, ".claude.json")))
        self.assertEqual(cfg["mcpServers"], {"github": {"command": "gh"}})
        self.assertEqual(cfg["projects"]["/p"]["mcpServers"], {})
        self.assertEqual(cfg["keep"], 1)


@unittest.skipIf(os.name == "nt", "bash CLI")
class CliWithoutPythonTest(unittest.TestCase):
    def test_cli_explains_how_to_get_python_instead_of_failing_oddly(self):
        env = {"HOME": tempfile.mkdtemp(), "PATH": "/usr/bin:/bin", "LOGGDIN_PYTHON": "none", "LOGGDIN_PORTABLE": "1"}
        out = subprocess.run(["bash", os.path.join(ROOT, "bin", "loggdin"), "status"], env=env, capture_output=True, text=True)
        self.assertEqual(out.returncode, 1)
        self.assertIn("needs Python 3", out.stderr)


class MacInstallerScriptTest(unittest.TestCase):
    """packaging/install-mac.sh runs as `curl ... | bash`, i.e. under macOS's bash 3.2, which reads a
    non-ASCII character right after `$name` (like "…") as part of the variable name."""

    def test_no_unbraced_variable_touches_non_ascii_text(self):
        import re
        text = open(os.path.join(ROOT, "packaging", "install-mac.sh"), encoding="utf-8").read()
        bad = re.findall(r'\$[A-Za-z_][A-Za-z_0-9]*[^\x00-\x7f]', text)
        self.assertEqual(bad, [], "wrap these variables in ${...}")

    @unittest.skipUnless(os.path.exists("/bin/bash"), "needs bash")
    def test_parses_with_system_bash(self):
        out = subprocess.run(["/bin/bash", "-n", os.path.join(ROOT, "packaging", "install-mac.sh")],
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
