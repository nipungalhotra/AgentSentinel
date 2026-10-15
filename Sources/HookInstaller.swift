import Foundation

@MainActor
final class HookInstaller {
    static let shared = HookInstaller()

    private let fileManager = FileManager.default

    var hookScriptPath: String {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AgentSentinel", isDirectory: true)
        return appSupport.appendingPathComponent("sentinel-hook").path
    }

    var appSupportDir: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AgentSentinel", isDirectory: true)
    }

    private init() {
        deployHookScript()
    }

    // MARK: - Deploy Hook Script

    func deployHookScript() {
        let targetDir = appSupportDir
        try? fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let targetScript = targetDir.appendingPathComponent("sentinel-hook")

        // Try source repository bin/sentinel-hook or bundle resource
        let repoScriptPath = "/Users/nipun/.gemini/antigravity-ide/scratch/AgentSentinel/bin/sentinel-hook"
        if fileManager.fileExists(atPath: repoScriptPath) {
            try? fileManager.removeItem(at: targetScript)
            try? fileManager.copyItem(atPath: repoScriptPath, toPath: targetScript.path)
            // Make executable
            var attrs = (try? fileManager.attributesOfItem(atPath: targetScript.path)) ?? [:]
            attrs[.posixPermissions] = 0o755
            try? fileManager.setAttributes(attrs, ofItemAtPath: targetScript.path)
        }

        // Also ensure symlink in ~/.local/bin/sentinel-hook
        let localBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
        try? fileManager.createDirectory(at: localBin, withIntermediateDirectories: true)
        let localSymlink = localBin.appendingPathComponent("sentinel-hook")
        try? fileManager.removeItem(at: localSymlink)
        try? fileManager.createSymbolicLink(at: localSymlink, withDestinationURL: targetScript)
    }

    private func quotedHookCmd(agent: String, event: String? = nil, ask: Bool = false) -> String {
        let path = hookScriptPath.replacingOccurrences(of: "\"", with: "\\\"")
        var cmd = "/bin/sh \"\(path)\" --agent \(agent)"
        if ask {
            cmd += " --ask"
        }
        if let event = event {
            cmd += " \(event)"
        }
        return cmd
    }

    // MARK: - Status Checking

    func isInstalled(for agentId: String) -> Bool {
        switch agentId {
        case "claude-code":
            return isClaudeCodeInstalled()
        case "antigravity":
            return isAntigravityInstalled()
        case "codex", "chatgpt":
            return isCodexInstalled()
        case "cowork":
            return isCoworkInstalled()
        case "cursor":
            return isCursorInstalled()
        case "terminal":
            return isZshInstalled()
        case "copilot":
            return isCopilotInstalled()
        default:
            return false
        }
    }

    // MARK: - Claude Code

    private var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    func isClaudeCodeInstalled() -> Bool {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }

        if let perm = hooks["PermissionRequest"] as? [[String: Any]] {
            for entry in perm {
                if let inner = entry["hooks"] as? [[String: Any]] {
                    for h in inner {
                        if let cmd = h["command"] as? String, cmd.contains("sentinel-hook") {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    @discardableResult
    func installClaudeCodeHooks() throws -> Bool {
        deployHookScript()
        var root = (try? readJSON(at: claudeSettingsURL)) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        let events: [(String, Int)] = [
            ("SessionStart", 10),
            ("SessionEnd", 10),
            ("UserPromptSubmit", 10),
            ("PreToolUse", 10),
            ("PostToolUse", 10),
            ("PostToolUseFailure", 10),
            ("PermissionRequest", 120),
            ("Notification", 10),
            ("Stop", 10),
            ("SubagentStart", 10),
            ("SubagentStop", 10)
        ]

        let baseCmd = quotedHookCmd(agent: "claude-code")

        for (event, timeout) in events {
            var existing = hooks[event] as? [[String: Any]] ?? []
            existing.removeAll { group in
                let inner = group["hooks"] as? [[String: Any]] ?? []
                return inner.contains { ($0["command"] as? String)?.contains("sentinel-hook") == true }
            }
            let newGroup: [String: Any] = [
                "hooks": [
                    [
                        "type": "command",
                        "command": "\(baseCmd) \(event)",
                        "timeout": timeout
                    ]
                ]
            ]
            existing.append(newGroup)
            hooks[event] = existing
        }

        // AskUserQuestion hook
        var preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []
        preToolUse.removeAll { ($0["matcher"] as? String) == "AskUserQuestion" }
        preToolUse.append([
            "matcher": "AskUserQuestion",
            "hooks": [
                [
                    "type": "command",
                    "command": "\(baseCmd) --ask",
                    "timeout": 130
                ]
            ]
        ])
        hooks["PreToolUse"] = preToolUse

        root["hooks"] = hooks
        try writeJSON(root, to: claudeSettingsURL)
        return true
    }

    func uninstallClaudeCodeHooks() throws {
        guard var root = try? readJSON(at: claudeSettingsURL),
              var hooks = root["hooks"] as? [String: Any] else { return }

        for (k, v) in hooks {
            if var groups = v as? [[String: Any]] {
                groups.removeAll { group in
                    let inner = group["hooks"] as? [[String: Any]] ?? []
                    return inner.contains { ($0["command"] as? String)?.contains("sentinel-hook") == true }
                }
                hooks[k] = groups
            }
        }
        root["hooks"] = hooks
        try writeJSON(root, to: claudeSettingsURL)
    }

    // MARK: - Antigravity

    private var agyHooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/config/hooks.json")
    }

    func isAntigravityInstalled() -> Bool {
        guard let data = try? Data(contentsOf: agyHooksURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return json["sentinel"] != nil
    }

    @discardableResult
    func installAntigravityHooks() throws -> Bool {
        deployHookScript()
        var root = (try? readJSON(at: agyHooksURL)) ?? [:]
        let baseCmd = quotedHookCmd(agent: "antigravity")

        var sentinelConfig: [String: Any] = [:]

        // PreToolUse & PostToolUse
        for event in ["PreToolUse", "PostToolUse"] {
            sentinelConfig[event] = [
                [
                    "matcher": "*",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(baseCmd) \(event)",
                            "timeout": event == "PreToolUse" ? 120 : 10
                        ]
                    ]
                ]
            ]
        }

        // PreInvocation & Stop
        for event in ["PreInvocation", "PostInvocation", "Stop"] {
            sentinelConfig[event] = [
                [
                    "type": "command",
                    "command": "\(baseCmd) \(event)",
                    "timeout": 10
                ]
            ]
        }

        root["sentinel"] = sentinelConfig
        try writeJSON(root, to: agyHooksURL)
        return true
    }

    func uninstallAntigravityHooks() throws {
        guard var root = try? readJSON(at: agyHooksURL) else { return }
        root.removeValue(forKey: "sentinel")
        try writeJSON(root, to: agyHooksURL)
    }

    // MARK: - Codex & ChatGPT

    private var codexHooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
    }

    func isCodexInstalled() -> Bool {
        guard let data = try? Data(contentsOf: codexHooksURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }

        if let perm = hooks["PermissionRequest"] as? [[String: Any]] {
            for entry in perm {
                if let inner = entry["hooks"] as? [[String: Any]] {
                    for h in inner {
                        if let cmd = h["command"] as? String, cmd.contains("sentinel-hook") {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    @discardableResult
    func installCodexHooks() throws -> Bool {
        deployHookScript()
        var root = (try? readJSON(at: codexHooksURL)) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        let baseCmd = quotedHookCmd(agent: "codex")

        let events: [(String, Int, String?)] = [
            ("SessionStart", 10, nil),
            ("UserPromptSubmit", 10, nil),
            ("PreToolUse", 10, nil),
            ("PermissionRequest", 120, "Waiting for permission in the notch (Agent Sentinel)"),
            ("PostToolUse", 10, nil),
            ("Stop", 10, nil),
            ("SessionEnd", 10, nil)
        ]

        for (event, timeout, statusMsg) in events {
            var existing = hooks[event] as? [[String: Any]] ?? []
            existing.removeAll { group in
                let inner = group["hooks"] as? [[String: Any]] ?? []
                return inner.contains { ($0["command"] as? String)?.contains("sentinel-hook") == true }
            }
            var hookEntry: [String: Any] = [
                "type": "command",
                "command": "\(baseCmd) \(event)",
                "timeout": timeout
            ]
            if let msg = statusMsg {
                hookEntry["statusMessage"] = msg
            }
            existing.append(["hooks": [hookEntry]])
            hooks[event] = existing
        }

        root["hooks"] = hooks
        try writeJSON(root, to: codexHooksURL)
        return true
    }

    func uninstallCodexHooks() throws {
        guard var root = try? readJSON(at: codexHooksURL),
              var hooks = root["hooks"] as? [String: Any] else { return }

        for (k, v) in hooks {
            if var groups = v as? [[String: Any]] {
                groups.removeAll { group in
                    let inner = group["hooks"] as? [[String: Any]] ?? []
                    return inner.contains { ($0["command"] as? String)?.contains("sentinel-hook") == true }
                }
                hooks[k] = groups
            }
        }
        root["hooks"] = hooks
        try writeJSON(root, to: codexHooksURL)
    }

    // MARK: - Cowork (Claude Desktop)

    private var claudeDesktopURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    func isCoworkInstalled() -> Bool {
        guard let data = try? Data(contentsOf: claudeDesktopURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let mcp = json["mcpServers"] as? [String: Any] else { return false }
        return mcp["sentinel"] != nil
    }

    @discardableResult
    func installCoworkMCP() throws -> Bool {
        var root = (try? readJSON(at: claudeDesktopURL)) ?? [:]
        var mcp = root["mcpServers"] as? [String: Any] ?? [:]

        let mcpScript = "/Users/nipun/.gemini/antigravity-ide/scratch/AgentSentinel/bin/sentinel-mcp.js"
        mcp["sentinel"] = [
            "command": "/usr/local/bin/node",
            "args": [mcpScript],
            "env": ["SENTINEL_PORT": "9191"]
        ]
        root["mcpServers"] = mcp
        try writeJSON(root, to: claudeDesktopURL)
        return true
    }

    // MARK: - Cursor

    private var cursorMcpURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor/mcp.json")
    }

    func isCursorInstalled() -> Bool {
        guard let data = try? Data(contentsOf: cursorMcpURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let mcp = json["mcpServers"] as? [String: Any] else { return false }
        return mcp["sentinel"] != nil
    }

    @discardableResult
    func installCursorMCP() throws -> Bool {
        var root = (try? readJSON(at: cursorMcpURL)) ?? [:]
        var mcp = root["mcpServers"] as? [String: Any] ?? [:]

        let mcpScript = "/Users/nipun/.gemini/antigravity-ide/scratch/AgentSentinel/bin/sentinel-mcp.js"
        mcp["sentinel"] = [
            "command": "/usr/local/bin/node",
            "args": [mcpScript],
            "env": ["SENTINEL_PORT": "9191"]
        ]
        root["mcpServers"] = mcp
        try writeJSON(root, to: cursorMcpURL)
        return true
    }

    // MARK: - Copilot CLI

    private var copilotHooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot/hooks/sentinel.json")
    }

    func isCopilotInstalled() -> Bool {
        fileManager.fileExists(atPath: copilotHooksURL.path)
    }

    @discardableResult
    func installCopilotHooks() throws -> Bool {
        deployHookScript()
        let baseCmd = quotedHookCmd(agent: "copilot")
        let config: [String: Any] = [
            "hooks": [
                "permissionRequest": [["bash": "\(baseCmd) PermissionRequest", "timeoutSec": 120]],
                "preToolUse": [["bash": "\(baseCmd) PreToolUse", "timeoutSec": 10]],
                "postToolUse": [["bash": "\(baseCmd) PostToolUse", "timeoutSec": 10]],
                "sessionStart": [["bash": "\(baseCmd) SessionStart", "timeoutSec": 10]],
                "sessionEnd": [["bash": "\(baseCmd) SessionEnd", "timeoutSec": 10]]
            ]
        ]
        try writeJSON(config, to: copilotHooksURL)
        return true
    }

    // MARK: - Terminal / Zsh

    private var zshrcURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")
    }

    func isZshInstalled() -> Bool {
        guard let content = try? String(contentsOf: zshrcURL, encoding: .utf8) else { return false }
        return content.contains("sentinel-hook.zsh") || content.contains("sentinel run")
    }

    @discardableResult
    func installZshHook() throws -> Bool {
        let hookContent = """
        # Agent Sentinel Auto-Gate Hook
        if command -v sentinel >/dev/null 2>&1; then
            alias sudo='sentinel run sudo'
            alias rm='sentinel run rm'
        fi
        """
        if let existing = try? String(contentsOf: zshrcURL, encoding: .utf8), !existing.contains("Agent Sentinel") {
            let updated = existing + "\n\n" + hookContent + "\n"
            try updated.write(to: zshrcURL, atomically: true, encoding: .utf8)
        }
        return true
    }

    // MARK: - Install All

    @discardableResult
    func installAll() -> (success: Int, failed: Int) {
        var succ = 0
        var fail = 0

        do { try installClaudeCodeHooks(); succ += 1 } catch { fail += 1 }
        do { try installAntigravityHooks(); succ += 1 } catch { fail += 1 }
        do { try installCodexHooks(); succ += 1 } catch { fail += 1 }
        do { try installCoworkMCP(); succ += 1 } catch { fail += 1 }
        do { try installCursorMCP(); succ += 1 } catch { fail += 1 }
        do { try installCopilotHooks(); succ += 1 } catch { fail += 1 }
        do { try installZshHook(); succ += 1 } catch { fail += 1 }

        return (succ, fail)
    }

    // MARK: - Helpers

    private func readJSON(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func writeJSON(_ obj: [String: Any], to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
