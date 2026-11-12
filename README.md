<p align="center">
  <img src="assets/logo.png" alt="loggdin Logo" width="130" style="border-radius: 28px; box-shadow: 0 10px 25px rgba(0,0,0,0.3);" />
</p>
<p align="center">
  <img src="assets/demo/loggdin-demo.gif" alt="loggdin demo: Claude Code asks to install a package and is allowed for 10 minutes; Codex tries git push --force and is denied; Cursor runs tests and is allowed once" width="760" />
</p>
<p align="center">
  <a href="https://nipungalhotra.github.io/AgentSentinel/"><b>Website</b></a> ·
  <a href="https://github.com/nipungalhotra/AgentSentinel/releases/latest"><b>Download the Mac beta</b></a> ·
  <a href="assets/demo/loggdin-demo.mp4">Demo video (MP4)</a>
</p>

# 🛡️ loggdin

> **The native macOS Menu Bar security daemon & permission sentinel. Drops down an expressive Liquid Glass permission card centered directly below the MacBook camera notch, featuring Touch ID biometrics, persistent grant caching (10 min / always), and seamless keyboard focus preservation across Claude Code, Antigravity IDE, Cursor, Codex, and terminal shells.**

<p align="center">
  <img src="https://img.shields.io/badge/Architecture-loggdin%20Liquid%20Glass%20%2B%20Hooks-purple" alt="loggdin Architecture" />
  <img src="https://img.shields.io/badge/macOS-14%2B%20%7C%20Sequoia-black?logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-6.0-orange?logo=swift" alt="Swift 6.0" />
  <img src="https://img.shields.io/badge/Biometrics-Touch%20ID%20Native-blue" alt="Touch ID Native" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License" />
</p>

---

## 🌟 Universal AI Agent Compatibility

Engineered for high-assurance developer environments, loggdin implements a dual-transport hook engine (sub-millisecond Unix Domain Socket + HTTP) giving every AI tool its own branded badge, theme colors, and native authorization flow:

| AI Assistant / Tool | Integration Channel | Config Path | What It Guards |
| :--- | :--- | :--- | :--- |
| **🟣 Claude Code** | Native `PermissionRequest` & `PreToolUse` Hooks | `~/.claude/settings.json` | Bash commands, file writes, package installs, `AskUserQuestion` |
| **🔵 Antigravity IDE** | Native Hooks + MCP Schema | `~/.gemini/config/hooks.json` | Terminal executions, file modifications, cloud deployments |
| **🟩 Cursor IDE** | Workspace MCP Server | `~/.cursor/mcp.json` | Autonomous agent execution, background runs, shell tasks |
| **🔷 Codex CLI (OpenAI)** | Native `PermissionRequest` Hook | `~/.codex/hooks.json` | Python runners, dependency installs, shell commands |
| **🟧 Cowork (Claude Desktop)** | Standard MCP Server (`sentinel-mcp`) | `~/Library/Application Support/Claude/claude_desktop_config.json` | Agent file edits, terminal commands, tool executions |
| **🤖 ChatGPT Desktop** | Codex Gateway & Python/Node SDKs | `sdk/sentinel.py` / `sdk/sentinel.js` | Custom LLM function calling, LangChain, OpenAI agent loops |
| **🐙 Copilot CLI** | GitHub Copilot Hook System | `~/.copilot/hooks/sentinel.json` | Pull requests, merges, repository actions, CLI runs |
| **⚡ Terminal Shells (ZSH/Bash)** | Preexec Auto-Gate Hook | `~/.zshrc` | Automatically intercepts `rm -rf`, `sudo`, `git push --force` |

---

## ✨ Key Features & Enhancements

### 🎯 1. Pixel-Perfect Camera Notch Centering
- **Zero Drift**: Calculated from `NSScreen.frame.midX - (width / 2)` and anchored flush beneath the macOS camera housing (`cameraBottomY - 4px`).
- **Multi-Monitor Awareness**: Detects whether the active monitor has a physical camera notch or is an external display, adapting automatically between notch-anchored and floating island styles.

### ⏱️ 2. Smart Scope Selection ("Allow once", "for 10 min", "Always allow")
- **Allow Once (`Space` / Touch ID)**: Permits the single immediate action.
- **Allow for 10 Min (`Tab` to toggle)**: Caches command approval for 10 minutes with auto-expiration, eliminating annoying repetitive prompts during active agent workflows.
- **Allow 10 Min, All Folders ("10 min · all")**: An explicit opt-in for when you are working across several projects or tools at once. The approval covers every folder for 10 minutes. It is not offered for high-risk requests, and chained or unrelated commands still prompt. From the CLI: `loggdin allow 10m-all`.
- **Always Allow**: Persists command rules to encrypted local storage (`~/.loggdin/rules.json`).
- **Safety Boundary**: Catastrophic root commands (`rm -rf /`, `mkfs`) always require explicit verification and cannot be blindly whitelisted.

### 🔄 3. Simultaneous Multi-Agent Focus Preservation
- When running Claude Code, Antigravity IDE, or Cursor concurrently, loggdin captures the active application state before presenting the card.
- Upon user approval or denial, loggdin automatically activates and returns focus to the calling IDE/terminal without dropping keystrokes or requiring manual mouse clicks.

### 🔒 4. Biometric Touch ID & Hold-to-Confirm
- High-risk operations (e.g., modifying files outside the workspace or executing destructive commands) highlight the card in warm amber/red.
- Complete the action seamlessly by touching the Touch ID sensor or holding the confirm button for 1 second.

### 📱 5. Approve From Your Phone
- Away from your desk? Pending requests show up in **loggdin Pocket** on your iPhone or Android phone (or at app.loggdin.com; source in `mobile/`), with **Allow once**, **Allow 10 min** and **Deny**. No account to create.
- **Mac:** Dashboard → *Rules & Grants* → *Approve from your phone* (or open `loggdin://dashboard?section=phone`) → switch it on and scan the QR code with your phone's camera. It opens loggdin Pocket already paired. Can't scan? Type the pairing code shown under the QR code. The Mac pushes right away when the screen is locked or you have been idle for a minute. Otherwise it pushes when the card goes unanswered for the delay you pick (15 s by default). While phone approvals are on, the card waits up to 110 s so you have time to answer from the phone. *Ask on* picks where a request appears: **Mac first, then phone** (the default), **Mac and phone together**, or **Phone only** (no card on the Mac; high-risk requests and any request that can't reach the phone still show the card).
- **Windows / Linux:** `loggdin phone setup` prints a pairing code and link for loggdin Pocket; then `loggdin phone test`.
- **Security:** outbound only: your computer publishes to a secret, random topic and listens on a matching reply topic, so no port is opened to the internet. Requests and their answer buttons are **encrypted end to end** with the pairing key, which only the QR code or pairing code carries, so the relay and anyone who learns the topic see only ciphertext. Only a phone holding the pairing key can register for notifications. Every answer carries a one-time HMAC-SHA256 signature tied to that single request, so a forged or replayed answer is ignored. "Always allow" and "all folders" are never offered on the phone, and high-risk requests get only Allow once / Deny. Commands flagged as containing a secret are never sent. Choose *Hide commands on the phone* (`loggdin phone details minimal`) to send only the agent, risk and folder. The audit log marks phone decisions with `"via": "phone"` (Mac: a Phone badge and a Via column in the CSV export).
- **Relay:** messages pass through ntfy.sh by default, as ciphertext only. Lock-screen notifications from the installed app go through Expo's push service and carry only the agent, risk and folder. To use your own relay: `loggdin phone setup --server https://ntfy.example.com`, or edit `server` in `phone.json`. ntfy.sh allows about 250 messages a day per IP on the free tier.

---

## 📦 Installation & Packaging

### Option 1: Install Pre-Built DMG
Download the latest `Loggdin.dmg` and drag `Loggdin.app` to `/Applications`:
```bash
./packaging/create_dmg.sh
open dist/Loggdin.dmg
```

### Option 2: Build from Source
```bash
git clone https://github.com/nipungalhotra/AgentSentinel.git
cd AgentSentinel
swift build -c release
cp .build/release/loggdin /Applications/Loggdin.app/Contents/MacOS/loggdin
```

### Option 3: Windows & Linux (portable daemon)
The notch app is macOS-only. On Windows and Linux, loggdin runs as a small background
daemon (`bin/loggdin.py`, Python 3.9+ standard library only) that serves the same local API,
so the hooks, MCP server and SDKs work unchanged. You approve requests on a local web page,
or from the CLI, and get a desktop notification when an agent asks.

Download `loggdin-portable-v<version>.zip` from the release (or run `./packaging/create_portable.sh`), unzip it, then:

```bash
./install.sh                                            # Linux
```
```powershell
powershell -ExecutionPolicy Bypass -File install.ps1    # Windows
```

The installer copies loggdin into your user profile, adds a `loggdin` command, starts it at login,
and hooks every agent it finds (Claude Code, Codex, Antigravity, Cursor, Claude Desktop, Copilot).
Use `--no-agents` / `-NoAgents` to skip that step, and `--uninstall` / `-Uninstall` to remove it.

| | macOS app | Windows / Linux daemon |
|---|---|---|
| Approve requests | Notch popup, Touch ID | `loggdin ui` web page, `loggdin allow` / `deny` |
| Notifications | Built in | Windows balloon, Linux `notify-send` |
| Start at login | Login item | Startup folder / XDG autostart |
| State folder | `~/Library/Application Support/AgentSentinel` | `%APPDATA%\Loggdin` / `~/.config/loggdin` |
| Rules, 10-min grants, audit chain | Yes | Yes |

Set `LOGGDIN_HOME` to use a different state folder. Node.js is only needed for the MCP integration.



Configure all supported AI agents in one command:

```bash
loggdin install all
```

Output:
```
🚀 Setting up loggdin across all AI agents and environments...
🟣 Configuring Claude Code native hooks & Claude Desktop (Cowork)...
✓ Registered Claude Code native hooks in ~/.claude/settings.json
🔵 Configuring Antigravity & Antigravity IDE...
✓ Registered Antigravity hooks in ~/.gemini/config/hooks.json
🟩 Configuring Cursor...
✓ Updated ~/.cursor/mcp.json
🔷 Configuring Codex & ChatGPT hooks...
✓ Updated ~/.codex/hooks.json
⚡ Installing ZSH Shell Auto-Gate Hook...
✓ Added hook to ~/.zshrc
🎉 All integrations installed successfully!
```

---

## 🧪 Testing the Live Notch Popup

Trigger test prompts for different AI assistants:

```bash
# Test Claude Code permission prompt
loggdin test claude

# Test Google Antigravity cloud deployment prompt
loggdin test antigravity

# Test Cursor force push prompt
loggdin test cursor

# Test OpenAI Codex dependency install prompt
loggdin test codex
```

---

## 💡 Real-World Use Cases

### 1. Autonomous Agent Terminal Gating (LangChain, AutoGPT & CrewAI)
Autonomous agents frequently iterate through shell commands (`git commit`, `npm install`, `pip install`). When an agent attempts an unexpected high-risk command (e.g. `docker compose down -v` or `rm -rf`), loggdin immediately pauses execution and drops down the notch permission card.
- **Operator Advantage**: You can grant **10 minutes** of authorization for iterative steps or reject suspicious actions with zero context switching.

### 2. Workspace Jail & Out-of-Tree File Protection
Agents occasionally hallucinate paths or try writing files to parent directories (`/etc`, `~/.ssh`, `~/.aws/credentials`). loggdin detects out-of-workspace file writes, triggers a warning state on the notch card, and requires Touch ID before any file outside the active project can be modified.

### 3. Focus-Preserving Multi-Agent Development
When running multiple coding assistants simultaneously (e.g., Claude Code in iTerm and Antigravity IDE on an external monitor), approving an action in loggdin instantly restores keyboard focus back to the exact window and cursor location where you were typing, avoiding focus loss.

### 4. Time Machine Rollbacks for Dangerous Edits
Before approving any file modification tool call, loggdin captures a localized file state snapshot. If an agent ruins your file, open the loggdin dashboard and click **Undo** to instantly restore the original file contents.

### 5. Centralized Compliance & Merkle Audit Trail
All security decisions are permanently logged to `~/.loggdin/audit_log.json` and chained together using cryptographic SHA-256 hashes. You can mathematically verify whether any audit entry has been altered, deleted, or tampered with:
```bash
curl http://localhost:9191/audit/verify
# {"isValid": true, "totalEntries": 42, "message": "Audit chain intact"}
```

---

## 🛠️ CLI Reference

| Command | Description |
| :--- | :--- |
| `loggdin status` | Inspect daemon health, active port, socket path, and running grants. |
| `loggdin run <cmd>` | Execute a command protected by the notch permission gate. |
| `loggdin mcp` | Launch the Model Context Protocol stdio server for AI agents. |
| `loggdin dashboard` | Open the native SwiftUI monitoring and rules dashboard. |
| `loggdin rules list` | Display all persistent whitelist and blacklist rules. |
| `loggdin rules add <pattern>` | Add a command pattern to the permanent whitelist. |
| `loggdin grants list` | List active 10-minute temporary authorizations with time remaining. |
| `loggdin grants revoke <id>` | Immediately revoke an active grant. |
| `loggdin install <agent\|all>` | Install native hooks across Claude Code, Antigravity, Cursor, Codex, or all. |
| `loggdin uninstall <agent\|all>` | Cleanly remove hooks and restore original configuration files. |
| `loggdin test <agent>` | Trigger a live demo permission prompt on your screen. |
| `loggdin phone setup\|test\|on\|off\|status` | Pair loggdin Pocket and answer from your phone (end-to-end encrypted). `delay <s>` and `details <full\|minimal>` tune it. |

---

## 🧩 SDK Documentation & Examples

Comprehensive SDK documentation, quickstarts, and integration guides are available in **[`sdk/README.md`](sdk/README.md)**.

### Python Quickstart (`sdk/sentinel.py` / `sdk/loggdin.py`)
```python
from sentinel import ask_permission, guard

# Safe list-based execution prevents command injection
result = guard(["git", "push", "origin", "main", "--force"], requested_by="Release Bot")
print(result.stdout)
```

### Node.js Quickstart (`sdk/sentinel.js`)
```javascript
const { askPermission, guard } = require('./sentinel');

async function run() {
  const allowed = await askPermission({
    command: 'docker compose down -v',
    requestedBy: 'Antigravity Agent',
    risk: 'high'
  });
  if (allowed) console.log("Authorized by operator!");
}
run();
```

---

## ❓ Troubleshooting & FAQs

### Q: Port 9191 is already in use by another service
**A**: loggdin dynamically detects port conflicts. You can customize the port via environment variables or auto-discovery:
```bash
export LOGGDIN_PORT=9292
loggdin status
```
The active port is automatically written to `~/.loggdin/port` and read by all SDKs.

### Q: How do I test the permission card without running an agent?
**A**: Run the built-in test trigger:
```bash
loggdin test antigravity
```
Look up at your MacBook camera notch — the Liquid Glass card will drop down immediately!

### Q: macOS Gatekeeper reports the app is untrusted
**A**: `packaging/create_dmg.sh` includes automatic ad-hoc or Developer ID code signing:
```bash
./packaging/create_dmg.sh
```

---

## 🧪 Automated Testing & CI/CD

loggdin includes an automated test suite across 6 test suites covering security, persistence, packaging, and protocols:

```bash
# Run all automated tests
./tests/run_all.sh
```

| Test Suite | File | What It Validates |
| :--- | :--- | :--- |
| **Packaging & Portability** | `tests/test_packaging_integrity.sh` | Zero hardcoded user paths, shell & Node script syntax, Homebrew Cask supply chain |
| **RulesEngine & Merkle Chain** | `tests/test_rules_engine_logic.py` | Pipeline command splitting (`&&`, `;`, `||`), destructive command traps, Merkle chain tampering |
| **Component Robustness** | `tests/test_components_robustness.py` | Atomic persistence, corrupt config recovery (`.corrupt.<ts>.json`), deduplication, grant expiration, ZSH marker boundaries |
| **Python SDK** | `tests/test_sdk_python.py` | `ask_permission()`, safe `guard()` (list arguments & `shell=False`), dynamic port discovery |
| **Node.js SDK** | `tests/test_sdk_node.js` | `askPermission()`, `guard()` (execFile array execution), dynamic port discovery |
| **MCP Server Protocol** | `tests/test_mcp_server.py` | JSON-RPC 2.0 handshake (`initialize`, `tools/list`, and `tools/call`) |

---

## 🚢 Releasing

Pushing a tag such as `v1.2.1` runs `.github/workflows/release.yml`. It builds a Developer ID-signed,
notarized and stapled DMG, plus the Windows/Linux portable zip, checks that Gatekeeper accepts the
DMG, and publishes a GitHub release. It refuses to publish an unsigned build.

One-time setup: add these repository secrets: `MACOS_CERTIFICATE` (base64 of your
"Developer ID Application" .p12), `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`,
`APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD` (an app-specific password).

Per release: bump the version in `packaging/Info.plist`, `bin/loggdin.py` and the casks, push the tag,
then copy the SHA-256 shown in the workflow summary into the casks' `sha256`.

## 🌐 Website

The marketing site lives in `website/`: plain HTML, CSS and JS with no build step and self-hosted fonts.

- **Preview locally:** `python3 -m http.server 4173 --directory website`, then open http://localhost:4173
- **Connect the waitlist:** sign up for a form backend that accepts a POST with an `email` field (for example Buttondown, Formspree or Tally), then set `data-endpoint="…"` on the `<form id="waitlist">` in `website/index.html`. Until then, the form politely points visitors to the GitHub repo instead of pretending to sign them up.
- **Deploy:** in the repository's Settings → Pages, set Source to "GitHub Actions". Every push to `main` that changes `website/` then publishes the site via `.github/workflows/pages.yml`. Add a custom domain in the same screen.

## 🛡️ Production Error Handling & Logging

### Atomic Persistence & Crash Recovery
- **Atomic File Writes**: Configuration files (`rules.json`, `grants.json`, `audit_log.json`) are written using `.atomic` mode to prevent corruption during unexpected shutdowns.
- **Corrupt File Defense**: If a configuration file is corrupted, `RulesEngine` automatically preserves a timestamped copy (`rules.corrupt.<timestamp>.json`) and logs diagnostics rather than silently discarding user policies.
- **Atomic Shell Backups**: Modifying `~/.zshrc` creates an atomic timestamped backup (`~/.zshrc.bak.<timestamp>`) and wraps injections in strict boundary markers (`# >>> loggdin hook start >>>`).

### Structured Logging
All background operations emit structured diagnostic logs with clear subsystem prefixes:
- `[loggdin]`: Single-instance mutex, URL scheme dispatch, socket binding.
- `[HookInstaller]`: Per-agent hook deployment, configuration parsing, symlink status.
- `[RulesEngine]`: Rule evaluation, active grant caching, Merkle chain computation.

### SDK Injection Defense
- Both Python (`sdk/sentinel.py`) and Node.js (`sdk/sentinel.js`) SDKs support argument lists (`["git", "push"]`) to execute commands with `shell=False` or `execFile`, eliminating shell injection risks.

---

## 📜 Credits & License

**loggdin** (Agent Sentinel) is created and maintained by **Nipun Galhotra** ([@nipungalhotra](https://github.com/nipungalhotra)).

- **Native macOS Daemon & UI**: Built natively in Swift 6, SwiftUI, and AppKit for macOS (14+ Sonoma & 15+ Sequoia).
- **Cross-Platform Security Core**: Portable background daemon engineered for Linux and Windows developer environments.
- **Agent Integrations**: Universal hooks and SDKs for Claude Code, Antigravity, Cursor, Windsurf, Codex, and custom agent runtimes.
- **License**: Released under the **MIT License** — free and open source for developers and teams.
