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

    // MARK: - Helper Script Discovery & Deployment

    private func locateHelperScript(named name: String) -> String? {
        if let resURL = Bundle.main.resourceURL {
            let inBundleBin = resURL.appendingPathComponent("bin").appendingPathComponent(name).path
            if fileManager.fileExists(atPath: inBundleBin) { return inBundleBin }
            let inBundleRoot = resURL.appendingPathComponent(name).path
            if fileManager.fileExists(atPath: inBundleRoot) { return inBundleRoot }
        }

        if let execPath = ProcessInfo.processInfo.arguments.first {
            let execURL = URL(fileURLWithPath: execPath).resolvingSymlinksInPath()
            let execDir = execURL.deletingLastPathComponent()

            let adjacent = execDir.appendingPathComponent(name).path
            if fileManager.fileExists(atPath: adjacent) { return adjacent }

            let inBin = execDir.appendingPathComponent("bin").appendingPathComponent(name).path
            if fileManager.fileExists(atPath: inBin) { return inBin }

            let inResources = execDir.deletingLastPathComponent().appendingPathComponent("Resources/bin").appendingPathComponent(name).path
            if fileManager.fileExists(atPath: inResources) { return inResources }
        }

        let cwdBin = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("bin").appendingPathComponent(name).path
        if fileManager.fileExists(atPath: cwdBin) { return cwdBin }

        let appDefault = "/Applications/Loggdin.app/Contents/Resources/bin/\(name)"
        if fileManager.fileExists(atPath: appDefault) { return appDefault }

        return nil
    }

    private var nodeBinaryPath: String {
        if fileManager.fileExists(atPath: "/opt/homebrew/bin/node") {
            return "/opt/homebrew/bin/node"
        }
        if fileManager.fileExists(atPath: "/usr/local/bin/node") {
            return "/usr/local/bin/node"
        }
        return "node"
    }

    var mcpScriptPath: String {
        return appSupportDir.appendingPathComponent("sentinel-mcp.js").path
    }

    func deployHookScript() {
        let targetDir = appSupportDir
        do {
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
        } catch {
            print("[HookInstaller] Warning: Failed to create app support directory: \(error)")
        }

        let targetScript = targetDir.appendingPathComponent("sentinel-hook")
        let targetMcp = targetDir.appendingPathComponent("sentinel-mcp.js")

        // Deploy sentinel-hook
        if let hookSrc = locateHelperScript(named: "sentinel-hook") {
            do {
                if fileManager.fileExists(atPath: targetScript.path) {
                    try fileManager.removeItem(at: targetScript)
                }
                try fileManager.copyItem(atPath: hookSrc, toPath: targetScript.path)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetScript.path)
                print("[HookInstaller] Deployed sentinel-hook to \(targetScript.path)")
            } catch {
                print("[HookInstaller] Error deploying sentinel-hook: \(error)")
            }
        } else {
            print("[HookInstaller] Warning: Could not locate sentinel-hook source script.")
        }

        // Deploy sentinel-mcp.js
        if let mcpSrc = locateHelperScript(named: "sentinel-mcp.js") {
            do {
                if fileManager.fileExists(atPath: targetMcp.path) {
                    try fileManager.removeItem(at: targetMcp)
                }
                try fileManager.copyItem(atPath: mcpSrc, toPath: targetMcp.path)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetMcp.path)
                print("[HookInstaller] Deployed sentinel-mcp.js to \(targetMcp.path)")
            } catch {
                print("[HookInstaller] Error deploying sentinel-mcp.js: \(error)")
            }
        } else {
            print("[HookInstaller] Warning: Could not locate sentinel-mcp.js source script.")
        }

        // Ensure symlinks in ~/.local/bin
        let localBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
        do {
            try fileManager.createDirectory(at: localBin, withIntermediateDirectories: true)
            let localHook = localBin.appendingPathComponent("sentinel-hook")
            if fileManager.fileExists(atPath: localHook.path) {
                try fileManager.removeItem(at: localHook)
            }
            try fileManager.createSymbolicLink(at: localHook, withDestinationURL: targetScript)

            let localMcp = localBin.appendingPathComponent("sentinel-mcp.js")
            if fileManager.fileExists(atPath: localMcp.path) {
                try fileManager.removeItem(at: localMcp)
            }
            try fileManager.createSymbolicLink(at: localMcp, withDestinationURL: targetMcp)
        } catch {
            print("[HookInstaller] Note: Could not update ~/.local/bin symlinks: \(error)")
        }
    }

    private func quotedHookCmd(agent: String, event: String? = nil, ask: Bool = false) -> String {
        let path = hookScriptPath.replacingOccurrences(of: "\"", with: "\\\"")
        var cmd = "python3 \"\(path)\" --agent \(agent)"
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
            ("PreToolUse", 120),
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
        return json["loggdin"] != nil || json["sentinel"] != nil || json["loggdin-safety-gate"] != nil
    }

    @discardableResult
    func installAntigravityHooks() throws -> Bool {
        deployHookScript()
        var root = (try? readJSON(at: agyHooksURL)) ?? [:]
        let baseCmd = quotedHookCmd(agent: "antigravity")

        var loggdinConfig: [String: Any] = [:]
        loggdinConfig["enabled"] = true

        // PreToolUse
        loggdinConfig["PreToolUse"] = [
            [
                "matcher": "*",
                "hooks": [
                    [
                        "type": "command",
                        "command": "\(baseCmd) PreToolUse",
                        "timeout": 120
                    ]
                ]
            ]
        ]

        // PostToolUse
        loggdinConfig["PostToolUse"] = [
            [
                "matcher": "*",
                "hooks": [
                    [
                        "type": "command",
                        "command": "\(baseCmd) PostToolUse",
                        "timeout": 10
                    ]
                ]
            ]
        ]

        root.removeValue(forKey: "sentinel")
        root.removeValue(forKey: "loggdin-safety-gate")
        root["loggdin"] = loggdinConfig
        try writeJSON(root, to: agyHooksURL)
        return true
    }

    func uninstallAntigravityHooks() throws {
        guard var root = try? readJSON(at: agyHooksURL) else { return }
        root.removeValue(forKey: "loggdin")
        root.removeValue(forKey: "sentinel")
        root.removeValue(forKey: "loggdin-safety-gate")
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
            ("PreToolUse", 120, "Waiting for permission in the notch (Agent Sentinel)"),
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
        deployHookScript()
        var root = (try? readJSON(at: claudeDesktopURL)) ?? [:]
        var mcp = root["mcpServers"] as? [String: Any] ?? [:]

        let currentPort = String(LocalIPCServer.shared.port)
        mcp["sentinel"] = [
            "command": nodeBinaryPath,
            "args": [mcpScriptPath],
            "env": ["SENTINEL_PORT": currentPort, "LOGGDIN_PORT": currentPort]
        ]
        root["mcpServers"] = mcp
        try writeJSON(root, to: claudeDesktopURL)
        return true
    }

    func uninstallCoworkMCP() throws {
        guard var root = try? readJSON(at: claudeDesktopURL),
              var mcp = root["mcpServers"] as? [String: Any] else { return }
        mcp.removeValue(forKey: "sentinel")
        mcp.removeValue(forKey: "loggdin")
        root["mcpServers"] = mcp
        try writeJSON(root, to: claudeDesktopURL)
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
        deployHookScript()
        var root = (try? readJSON(at: cursorMcpURL)) ?? [:]
        var mcp = root["mcpServers"] as? [String: Any] ?? [:]

        let currentPort = String(LocalIPCServer.shared.port)
        mcp["sentinel"] = [
            "command": nodeBinaryPath,
            "args": [mcpScriptPath],
            "env": ["SENTINEL_PORT": currentPort, "LOGGDIN_PORT": currentPort]
        ]
        root["mcpServers"] = mcp
        try writeJSON(root, to: cursorMcpURL)
        return true
    }

    func uninstallCursorMCP() throws {
        guard var root = try? readJSON(at: cursorMcpURL),
              var mcp = root["mcpServers"] as? [String: Any] else { return }
        mcp.removeValue(forKey: "sentinel")
        mcp.removeValue(forKey: "loggdin")
        root["mcpServers"] = mcp
        try writeJSON(root, to: cursorMcpURL)
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
                "preToolUse": [["bash": "\(baseCmd) PreToolUse", "timeoutSec": 120]],
                "postToolUse": [["bash": "\(baseCmd) PostToolUse", "timeoutSec": 10]],
                "sessionStart": [["bash": "\(baseCmd) SessionStart", "timeoutSec": 10]],
                "sessionEnd": [["bash": "\(baseCmd) SessionEnd", "timeoutSec": 10]]
            ]
        ]
        try writeJSON(config, to: copilotHooksURL)
        return true
    }

    func uninstallCopilotHooks() throws {
        if fileManager.fileExists(atPath: copilotHooksURL.path) {
            try? fileManager.removeItem(at: copilotHooksURL)
        }
    }

    // MARK: - Terminal / Zsh

    private var zshrcURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")
    }

    private let zshMarkerBegin = "# >>> loggdin hook start >>>"
    private let zshMarkerEnd   = "# <<< loggdin hook end <<<"

    func isZshInstalled() -> Bool {
        guard let content = try? String(contentsOf: zshrcURL, encoding: .utf8) else { return false }
        return content.contains(zshMarkerBegin) || content.contains("# Agent Sentinel Auto-Gate Hook") || content.contains("sentinel run")
    }

    @discardableResult
    func installZshHook() throws -> Bool {
        deployHookScript()
        let hookBlock = """
        \(zshMarkerBegin)
        # Universal liquid glass gate for shell commands
        if command -v loggdin >/dev/null 2>&1; then
            alias sudo='loggdin run sudo'
            alias rm='loggdin run rm'
        elif command -v sentinel >/dev/null 2>&1; then
            alias sudo='sentinel run sudo'
            alias rm='sentinel run rm'
        fi
        \(zshMarkerEnd)
        """

        let existing = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""

        // Create atomic backup before modifying user configuration
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "")
        let backupURL = zshrcURL.deletingLastPathComponent().appendingPathComponent(".zshrc.bak.\(timestamp)")
        if !existing.isEmpty {
            try? existing.write(to: backupURL, atomically: true, encoding: .utf8)
        }

        var updatedContent: String
        if existing.contains(zshMarkerBegin) && existing.contains(zshMarkerEnd) {
            let pattern = "\(zshMarkerBegin)[\\s\\S]*?\(zshMarkerEnd)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: existing.utf16.count)
                updatedContent = regex.stringByReplacingMatches(in: existing, options: [], range: range, withTemplate: hookBlock)
            } else {
                updatedContent = existing
            }
        } else if existing.contains("# Agent Sentinel Auto-Gate Hook") {
            let legacyPattern = "# Agent Sentinel Auto-Gate Hook[\\s\\S]*?fi"
            if let regex = try? NSRegularExpression(pattern: legacyPattern, options: []) {
                let range = NSRange(location: 0, length: existing.utf16.count)
                updatedContent = regex.stringByReplacingMatches(in: existing, options: [], range: range, withTemplate: hookBlock)
            } else {
                updatedContent = existing + "\n\n" + hookBlock + "\n"
            }
        } else {
            updatedContent = existing
            if !updatedContent.isEmpty && !updatedContent.hasSuffix("\n") {
                updatedContent += "\n"
            }
            updatedContent += "\n" + hookBlock + "\n"
        }

        try updatedContent.write(to: zshrcURL, atomically: true, encoding: .utf8)
        return true
    }

    func uninstallZshHook() throws {
        guard let existing = try? String(contentsOf: zshrcURL, encoding: .utf8) else { return }

        // Create backup
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "")
        let backupURL = zshrcURL.deletingLastPathComponent().appendingPathComponent(".zshrc.bak.\(timestamp)")
        try? existing.write(to: backupURL, atomically: true, encoding: .utf8)

        var cleaned = existing
        if cleaned.contains(zshMarkerBegin) && cleaned.contains(zshMarkerEnd) {
            let pattern = "\\n?\(zshMarkerBegin)[\\s\\S]*?\(zshMarkerEnd)\\n?"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "\n")
            }
        }

        if cleaned.contains("# Agent Sentinel Auto-Gate Hook") {
            let legacyPattern = "\\n?# Agent Sentinel Auto-Gate Hook[\\s\\S]*?fi\\n?"
            if let regex = try? NSRegularExpression(pattern: legacyPattern, options: []) {
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "\n")
            }
        }

        try cleaned.write(to: zshrcURL, atomically: true, encoding: .utf8)
    }

    func uninstall(for agentId: String) throws {
        switch agentId {
        case "claude-code":
            try uninstallClaudeCodeHooks()
        case "antigravity":
            try uninstallAntigravityHooks()
        case "codex", "chatgpt":
            try uninstallCodexHooks()
        case "cowork":
            try uninstallCoworkMCP()
        case "cursor":
            try uninstallCursorMCP()
        case "terminal":
            try uninstallZshHook()
        case "copilot":
            try uninstallCopilotHooks()
        default:
            break
        }
    }

    // MARK: - Install All

    @discardableResult
    func installAll() -> (success: Int, failed: Int) {
        var succ = 0
        var fail = 0

        let installers: [(String, () throws -> Bool)] = [
            ("Claude Code", { try self.installClaudeCodeHooks() }),
            ("Antigravity", { try self.installAntigravityHooks() }),
            ("Codex", { try self.installCodexHooks() }),
            ("Cowork MCP", { try self.installCoworkMCP() }),
            ("Cursor MCP", { try self.installCursorMCP() }),
            ("Copilot CLI", { try self.installCopilotHooks() }),
            ("Zsh Shell Hook", { try self.installZshHook() })
        ]

        for (name, installer) in installers {
            do {
                let ok = try installer()
                if ok {
                    succ += 1
                    print("[HookInstaller] Successfully configured hooks for \(name)")
                } else {
                    fail += 1
                    print("[HookInstaller] Configuration unchanged or skipped for \(name)")
                }
            } catch {
                fail += 1
                print("[HookInstaller] Error installing hooks for \(name): \(error)")
            }
        }

        return (succ, fail)
    }

    // MARK: - Helpers

    private func readJSON(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[HookInstaller] Warning: JSON at \(url.path) is not an object.")
                return [:]
            }
            return obj
        } catch {
            print("[HookInstaller] Error reading JSON from \(url.path): \(error)")
            throw error
        }
    }

    private func writeJSON(_ obj: [String: Any], to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
