# 🛡️ Agent Sentinel

> **A native macOS Menu Bar security daemon & permission sentinel featuring an expressive Liquid Glass permission card that drops down below the MacBook camera notch.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B%20%7C%20Sequoia-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-blue)
![License](https://img.shields.io/badge/License-MIT-green)

---

## ✨ Features

- **Menu Bar Daemon (`🛡️`)**: Lives in your macOS menu bar with real-time status indicators (Guarding, Active Alert, Paused).
- **Liquid Glass Notch Popup**: Drops down directly beneath the MacBook notch / camera with specular rim highlights, frosted glass blur, and fluid animations.
- **Expressive Face Orb**: An animated avatar that blinks, tracks cursor movement, tilts brows in worry, wiggles with sparkles on approval, and sleeps on timeout.
- **Zero-Dependency IPC Server (`127.0.0.1:9191`)**: Built natively with Apple's `Network.framework` (`NWListener`) to synchronously intercept requests from shell scripts, CLI tools, and AI agents.
- **Hold to Delete**: Requires a 1.0-second hold with a filling red progress bar for destructive commands (e.g. `rm -rf`).
- **Flexible Scope Control**: Choose between **Once**, **10 min**, or **Always** (saved to persistent whitelist rules).
- **Dashboard & Rules Manager**: Multi-tab SwiftUI dashboard featuring an interactive simulator, full audit log with risk badges, active temporary grants with countdown timers, and persistent whitelist rule management.
- **Shell Wrapper**: Instant `sentinel <command>` wrapper to guard commands directly in your terminal.

---

## 🚀 Quick Start

### Build and Run

```bash
# Clone the repository
git clone <your-repo-url>
cd AgentSentinel

# Build using Swift Package Manager
swift build

# Package into macOS .app bundle
mkdir -p AgentSentinel.app/Contents/MacOS
cp .build/debug/AgentSentinel AgentSentinel.app/Contents/MacOS/

# Launch the app
open AgentSentinel.app
```

### Command Line Usage

Prefix any terminal command with `sentinel`:

```bash
# Low risk: reads file
sentinel cat ~/Documents/notes.txt

# Medium risk: package manager installation
sentinel npm install express

# High risk: triggers hold-to-confirm
sentinel rm -rf ./old-build
```

### HTTP API Usage (for AI Agents & Scripts)

Any tool (Claude Code, Cursor, Codex, bash scripts) can ask Sentinel for permission via HTTP:

```bash
curl -s -X POST http://localhost:9191/ask \
  -H "Content-Type: application/json" \
  -d '{"command": "git push origin main", "requestedBy": "AI Agent", "directory": "~/code"}'
```

Response:
```json
{"allowed": true, "decision": "allow", "scope": "tenMinutes"}
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
│   └── DashboardView.swift     # Multi-tab SwiftUI management dashboard
└── README.md
```

---

## 📜 License

MIT License. Designed for macOS 14+ on Apple Silicon.
