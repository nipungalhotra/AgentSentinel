# 🛡️ Agent Sentinel

> **A native macOS Menu Bar security daemon & permission sentinel featuring an expressive Liquid Glass permission card that drops down below the MacBook camera notch. Seamlessly integrates with Claude Code, Cowork, Antigravity IDE, Cursor, Codex, ChatGPT, and your terminal.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B%20%7C%20Sequoia-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![MCP Compatible](https://img.shields.io/badge/MCP-Universal%20Standard-purple)
![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-blue)
![License](https://img.shields.io/badge/License-MIT-green)

---

## 🌟 Universal AI Agent & Tool Support

Agent Sentinel is designed from the ground up to protect your Mac across **all modern AI coding assistants and development workflows**:

| Environment | Integration Mechanism | What it Guards |
| :--- | :--- | :--- |
| **🟣 Claude Code** | MCP Server (`sentinel-mcp`) / CLI wrapper | Bash tool commands, file writes, package installs |
| **🟧 Cowork (Claude Desktop)** | Standard MCP (`claude_desktop_config.json`) | Agent file edits, terminal commands, tool executions |
| **🔵 Antigravity & Antigravity IDE** | Native Antigravity MCP Server | Terminal actions, code generation, cloud deploys |
| **🟩 Cursor & OpenAI Codex** | Cursor MCP (`~/.cursor/mcp.json`) / Python SDK | Agent execution, terminal runs, shell scripts |
| **🤖 ChatGPT & Custom Agents** | Python (`sentinel.py`) & Node (`sentinel.js`) SDKs | Any custom agent tool loop or LLM chain |
| **⚡ Terminal Shells (ZSH / Bash)** | Automatic `preexec` shell hook | Intercepts `rm -rf`, `sudo`, `git push --force` in any terminal |

---

## ✨ Features

- **Liquid Glass Notch Popup**: Drops down directly beneath the MacBook notch / camera with specular rim highlights, frosted glass blur, and fluid Apple spring animations.
- **Expressive Face Orb**: An animated avatar that blinks, tracks cursor movement with spring physics, tilts brows in worry, wiggles with sparkle bursts on approval, and sleeps on timeout.
- **Model Context Protocol (MCP)**: Native zero-dependency `sentinel-mcp` server supporting standard JSON-RPC 2.0 stdio communication.
- **Hold to Confirm**: High-risk actions (`rm -rf`, `sudo`, irreversible file modifications) enforce a 1.0-second hold with a filling red progress bar.
- **Flexible Scope Control**: Grant permission **Once**, for **10 minutes** (temporary grant with remaining countdown timer), or **Always** (saved to persistent whitelist rules).
- **Comprehensive Dashboard**: Multi-tab SwiftUI dashboard with real-time status, test simulator, audit log with search & risk filters, active grants manager, and 1-click agent installer.

---

## 🚀 1-Click Setup for All AI Tools

Run this single command to automatically configure **Claude Code, Cowork, Antigravity, Cursor, and ZSH**:

```bash
sentinel install all
```

Output:
```
🚀 Setting up Agent Sentinel across all AI agents and environments...
🟣 Configuring Claude Code & Claude Desktop (Cowork)...
✓ Updated ~/Library/Application Support/Claude/claude_desktop_config.json
✓ Updated ~/.claude.json
🟩 Configuring Cursor & Codex...
✓ Updated ~/.cursor/mcp.json
🔵 Configuring Antigravity & Antigravity IDE...
✓ Registered in ~/.gemini/antigravity-ide/mcp/sentinel
⚡ Installing ZSH Shell Auto-Gate Hook...
✓ Added Sentinel hook to ~/.zshrc
🎉 All integrations installed successfully!
```

---

## 💻 Manual Setup & Agent Integrations

### 1. Claude Code
Add the Sentinel MCP server to Claude Code:
```bash
claude mcp add sentinel -- sentinel mcp
```

### 2. Cowork (Claude Desktop)
Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "sentinel": {
      "command": "node",
      "args": ["/Users/nipun/.gemini/antigravity-ide/scratch/AgentSentinel/bin/sentinel-mcp.js"],
      "env": { "SENTINEL_PORT": "9191" }
    }
  }
}
```

### 3. Cursor & Codex
Add to `~/.cursor/mcp.json`:
```json
{
  "mcpServers": {
    "sentinel": {
      "command": "node",
      "args": ["/Users/nipun/.gemini/antigravity-ide/scratch/AgentSentinel/bin/sentinel-mcp.js"],
      "env": { "SENTINEL_PORT": "9191" }
    }
  }
}
```

### 4. Custom Python Agents (ChatGPT, LangChain, Codex)
```python
from sentinel import ask_permission, guard

# Ask user permission before performing a sensitive task
if ask_permission("rm -rf ./build-cache", requested_by="ChatGPT", risk="high"):
    print("User approved via Liquid Glass popup!")

# Or guard execution automatically
result = guard("npm run deploy", requested_by="Codex")
print(result.stdout)
```

### 5. Custom Node.js / TypeScript Agents
```javascript
const { askPermission } = require('./sentinel');

async function execute() {
  const allowed = await askPermission({
    command: 'git push origin main --force',
    requestedBy: 'Claude Code',
    risk: 'high'
  });

  if (allowed) {
    console.log("Permission granted!");
  }
}
```

---

## 🛠️ Build and Run from Source

```bash
# Clone the repository
git clone https://github.com/nipungalhotra/AgentSentinel.git
cd AgentSentinel

# Build using Swift Package Manager
swift build

# Package into macOS .app bundle
mkdir -p AgentSentinel.app/Contents/MacOS
cp .build/debug/AgentSentinel AgentSentinel.app/Contents/MacOS/

# Launch the app
open AgentSentinel.app
```

---

## 📂 Project Structure

```
AgentSentinel/
├── Package.swift               # Swift 6 Package definition
├── Sources/
│   ├── Main.swift              # App entry point & NSApplicationDelegate
│   ├── Models.swift            # Risk, Scope, Decision, PermissionRequest, AuditLog
│   ├── RulesEngine.swift       # Whitelist rules, 10-minute grants & persistence
│   ├── LocalIPCServer.swift    # Network.framework HTTP daemon on port 9191
│   ├── FaceAndCardViews.swift  # Liquid glass card, FaceView & notch window controller
│   ├── SentinelManager.swift   # MenuBar coordinator & status item controller
│   └── DashboardView.swift     # Multi-tab SwiftUI management & integrations hub
├── bin/
│   ├── sentinel                # Universal CLI router & 1-click installer
│   └── sentinel-mcp.js         # Model Context Protocol (MCP) server
├── sdk/
│   ├── sentinel.py             # Python SDK for ChatGPT / Codex / LangChain
│   └── sentinel.js             # Node.js SDK
└── README.md
```

---

## 📜 License

MIT License. Designed for macOS 14+ on Apple Silicon.
