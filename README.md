# 🛡️ Agent Sentinel

> **A native macOS Menu Bar security daemon & permission sentinel featuring an expressive Liquid Glass permission card that drops down below the MacBook camera notch. Replicates the seamless hook, island, and pill architecture of [Coucou](https://github.com/Louis-CFM/coucou) for universal compatibility across Claude Code, Cowork, Antigravity IDE, Cursor, Codex, ChatGPT, Copilot CLI, and your terminal.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B%20%7C%20Sequoia-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![Architecture](https://img.shields.io/badge/Coucou--Parity-Island%20%2B%20Hooks-purple)
![MCP Compatible](https://img.shields.io/badge/MCP-Universal%20Standard-blue)
![License](https://img.shields.io/badge/License-MIT-green)

---

## 🌟 Universal AI Agent Compatibility (Coucou Parity)

Modeled after **[Louis-CFM/coucou](https://github.com/Louis-CFM/coucou)**, Agent Sentinel implements a unified dual-transport hook engine (sub-millisecond Unix Domain Socket + HTTP) and declared Pill Catalog that gives every AI tool its own branded badge, theme colors, and native authorization flow:

| AI Assistant / Tool | Integration Channel | Config Path | What It Guards |
| :--- | :--- | :--- | :--- |
| **🟣 Claude Code** | Native `PermissionRequest` & `PreToolUse` Hooks | `~/.claude/settings.json` | Bash commands, file writes, package installs, `AskUserQuestion` |
| **🟧 Cowork (Claude Desktop)** | Standard MCP Server (`sentinel-mcp`) | `~/Library/Application Support/Claude/claude_desktop_config.json` | Agent file edits, terminal commands, tool executions |
| **🔵 Antigravity & IDE** | Native Hooks + MCP Schema | `~/.gemini/config/hooks.json` | Terminal executions, file modifications, cloud deployments |
| **🟩 Cursor IDE** | Workspace MCP Server | `~/.cursor/mcp.json` | Autonomous agent execution, background runs, shell tasks |
| **🔷 Codex CLI (OpenAI)** | Native `PermissionRequest` Hook | `~/.codex/hooks.json` | Python runners, dependency installs, shell commands |
| **🤖 ChatGPT Desktop** | Codex Gateway & Python/Node SDKs | `sdk/sentinel.py` / `sdk/sentinel.js` | Custom LLM function calling, LangChain, OpenAI agent loops |
| **🐙 Copilot CLI** | GitHub Copilot Hook System | `~/.copilot/hooks/sentinel.json` | Pull requests, merges, repository actions, CLI runs |
| **⚡ Terminal Shells (ZSH/Bash)** | Preexec Auto-Gate Hook | `~/.zshrc` | Automatically intercepts `rm -rf`, `sudo`, `git push --force` |

---

## ✨ Key Features

- **Physical Notch Hugging (`IslandPanel`)**: Anchored flush with the physical camera notch (`CGWindowLevelForKey(.mainMenuWindow) + 3`) using `constrainFrameRect` overrides so macOS never pushes the popup down into window space.
- **Adaptive Island Geometry (`IslandScreenGeometry`)**: Intelligently switches between `.physicalNotch` on MacBooks and `.floatingIsland` on external monitors, Windows, and Linux.
- **Biometric Touch ID Authentication (`BiometricAuthManager`)**: Tap the Touch ID sensor on your MacBook keyboard to authenticate high-risk operations instantly.
- **Auto-Start & Launch at Login (`StartupManager`)**: Native integration with macOS `SMAppService` and user Login Items, keeping Sentinel active in the background on system boot.
- **Dual Transport IPC (`LocalIPCServer`)**:
  - **Unix Domain Socket** (`~/Library/Application Support/AgentSentinel/sentinel.sock`): Sub-millisecond peer-verified IPC for instantaneous hook responses.
  - **Local HTTP Server** (`http://127.0.0.1:9191`): REST endpoints (`/ask`, `/hook`, `/status`) with full CORS support.
- **Universal Hook Script (`sentinel-hook`)**:
  - Python 3 streaming CLI relay matching Coucou's `nb-hook`.
  - Normalizes events across all agents (`BeforeTool` → `PreToolUse`, `permissionRequest` → `PermissionRequest`, `PreInvocation` → `UserPromptSubmit`).
  - Blocks synchronously on `PermissionRequest` up to 120s and streams decision back in canonical JSON.
- **Expressive Character Face & Audio (`SoundEngine`)**:
  - Animated squircle face with dynamic states: idle, thinking, worried (on high-risk), pleased, sleepy.
  - Interactive eye-tracking follows mouse cursor around the screen.
  - Haptic feedback and native system chimes (popup chime, pop on allow, basso on deny).
- **Hold-to-Confirm for High-Risk Actions**:
  - Destructive commands (`rm -rf`, `sudo`, `kill -9`, `drop database`) require a 1.0-second hold with visual red progress or Touch ID tap.
- **Flexible Scope Control**:
  - **Allow Once**: One-time execution permit.
  - **Allow 10 Min**: Temporary grant active across sessions with live countdown in the dashboard.
  - **Always Allow**: Saved to persistent rules ledger (`rules.json`).
- **Comprehensive Management Dashboard**:
  - **Agent Integrations Hub**: 1-click installer and status monitor for all 8 agents.
  - **Live Audit Log**: Searchable trail of every command evaluated, risk level, agent origin, and timestamp.
  - **Rules & Grants Manager**: Delete, edit, or clear temporary permissions and persistent whitelist entries.

---

## 📦 Installation & Packaging

### Method 1: Pre-Built Disk Image (.DMG)
Download the latest `AgentSentinel-v1.2.0.dmg` and drag `AgentSentinel.app` to your `/Applications` folder:
```bash
./bin/package-dmg.sh
open dist/AgentSentinel-v1.2.0.dmg
```

### Method 2: Homebrew Cask
```bash
brew install --cask Casks/agent-sentinel.rb
```

---

## 🚀 1-Click Installation (All AI Tools)

Configure **Claude Code, Cowork, Antigravity, Cursor, Codex, Copilot, and ZSH** in a single command:

```bash
sentinel install all
```

Output:
```
🚀 Setting up Agent Sentinel across all AI agents and environments...
🟣 Configuring Claude Code native hooks & Claude Desktop (Cowork)...
✓ Updated ~/Library/Application Support/Claude/claude_desktop_config.json
✓ Updated ~/.claude.json
✓ Registered Claude Code native hooks in ~/.claude/settings.json
🟩 Configuring Cursor...
✓ Updated ~/.cursor/mcp.json
🟩 Configuring Codex & ChatGPT hooks...
✓ Updated ~/.codex/hooks.json
🔵 Configuring Antigravity & Antigravity IDE...
✓ Registered Antigravity hooks in ~/.gemini/config/hooks.json
✓ Registered MCP schema in ~/.gemini/antigravity-ide/mcp/sentinel
⚡ Installing ZSH Shell Auto-Gate Hook...
✓ Added Sentinel hook to ~/.zshrc
🎉 All integrations installed successfully!
```

---

## 🧪 Testing the Live Notch Popup

Test how different agents trigger the liquid glass popup right beneath your MacBook camera notch:

```bash
# Test Claude Code permission prompt
sentinel test claude

# Test Google Antigravity cloud deployment prompt
sentinel test antigravity

# Test Cursor force push prompt
sentinel test cursor

# Test OpenAI Codex dependency install prompt
sentinel test codex

# Test Cowork private key access prompt
sentinel test cowork
```

---

## 🛠️ CLI Reference

```bash
# Intercept and guard any command in the shell
sentinel run <command...>

# Start the MCP server for Claude, Cursor, Antigravity, Cowork
sentinel mcp

# Inspect daemon health, active grants, and socket status
sentinel status

# Install hooks for a specific assistant
sentinel install [claude|antigravity|codex|cursor|zsh|all]
```

---

## 🧩 SDK Usage (Custom Python & Node.js Agents)

### Python SDK (`sdk/sentinel.py`)
```python
from sentinel import ask_permission, guard

# Ask user authorization before critical action
if ask_permission("rm -rf ./build", requested_by="ChatGPT", risk="high"):
    print("User approved via notch popup! Running cleanup...")

# Or automatically guard command execution
result = guard("git push origin main --force", requested_by="Codex")
```

### Node.js SDK (`sdk/sentinel.js`)
```javascript
const { askPermission } = require('./sentinel');

async function run() {
  const allowed = await askPermission({
    command: 'npm publish --access public',
    requestedBy: 'Claude Code',
    risk: 'medium'
  });
  if (allowed) console.log("Published with user consent!");
}
run();
```

---

## 📜 Credits & Inspiration

- Built natively with **Swift 6, SwiftUI, and AppKit**.
- Inspired by **[Louis-CFM/coucou](https://github.com/Louis-CFM/coucou)** for the notch island architecture, hook lifecycle, and declared pill concepts.
- Licensed under the **MIT License**.
