import Foundation
import SwiftUI

// MARK: - Pill Category

enum PillCategory: String, CaseIterable, Codable {
    case workspace = "Workspace & IDEs"
    case agent     = "AI Coding Agents"
    case terminal  = "Terminal & Shells"
}

// MARK: - Pill Definition

struct PillDefinition: Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let defaultColorHex: String
    let category: PillCategory
    let iconSystemName: String
    let configPath: String
    let hookType: String

    var color: Color {
        Color(hex: defaultColorHex)
    }

    init(id: String,
         name: String,
         subtitle: String,
         colorHex: String,
         category: PillCategory,
         iconSystemName: String,
         configPath: String,
         hookType: String) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.defaultColorHex = colorHex
        self.category = category
        self.iconSystemName = iconSystemName
        self.configPath = configPath
        self.hookType = hookType
    }
}

// MARK: - Color Hex Helper

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch clean.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Pill Catalog

enum PillCatalog {
    static let all: [PillDefinition] = [
        // Claude Code
        .init(
            id: "claude-code",
            name: "Claude Code",
            subtitle: "Anthropic Next-Gen CLI",
            colorHex: "#D97757",
            category: .agent,
            iconSystemName: "terminal.fill",
            configPath: "~/.claude/settings.json",
            hookType: "Native Hook (PermissionRequest & PreToolUse)"
        ),
        // Cowork (Claude Desktop)
        .init(
            id: "cowork",
            name: "Cowork",
            subtitle: "Claude Desktop Native App",
            colorHex: "#CC785C",
            category: .workspace,
            iconSystemName: "app.badge.checkmark",
            configPath: "~/Library/Application Support/Claude/claude_desktop_config.json",
            hookType: "Model Context Protocol (MCP Server)"
        ),
        // Antigravity & IDE
        .init(
            id: "antigravity",
            name: "Antigravity",
            subtitle: "Google DeepMind Agent & IDE",
            colorHex: "#4285F4",
            category: .agent,
            iconSystemName: "sparkles",
            configPath: "~/.gemini/config/hooks.json",
            hookType: "Native Hook + MCP Tool Registry"
        ),
        // Cursor
        .init(
            id: "cursor",
            name: "Cursor",
            subtitle: "AI-Powered Code Editor",
            colorHex: "#00D2FF",
            category: .workspace,
            iconSystemName: "chevron.left.forwardslash.chevron.right",
            configPath: "~/.cursor/mcp.json",
            hookType: "Cursor MCP Server + Terminal Gate"
        ),
        // Codex
        .init(
            id: "codex",
            name: "Codex",
            subtitle: "OpenAI Developer CLI",
            colorHex: "#2DD4BF",
            category: .agent,
            iconSystemName: "curlybraces",
            configPath: "~/.codex/hooks.json",
            hookType: "Native Hook (PermissionRequest)"
        ),
        // ChatGPT Desktop
        .init(
            id: "chatgpt",
            name: "ChatGPT",
            subtitle: "OpenAI Desktop & Codex Core",
            colorHex: "#10A37F",
            category: .agent,
            iconSystemName: "message.badge.filled.fill",
            configPath: "~/.codex/hooks.json",
            hookType: "MCP + Codex Bridge"
        ),
        // Copilot CLI
        .init(
            id: "copilot",
            name: "Copilot CLI",
            subtitle: "GitHub AI Assistant",
            colorHex: "#818CF8",
            category: .agent,
            iconSystemName: "person.crop.circle.badge.checkmark",
            configPath: "~/.copilot/hooks/sentinel.json",
            hookType: "GitHub Hook System"
        ),
        // Terminal / Shell
        .init(
            id: "terminal",
            name: "Terminal",
            subtitle: "Zsh / Bash / Fish Shells",
            colorHex: "#F59E0B",
            category: .terminal,
            iconSystemName: "terminal",
            configPath: "~/.zshrc",
            hookType: "Preexec Interceptor Hook & CLI Wrapper"
        )
    ]

    static func definition(for identifier: String) -> PillDefinition {
        let lower = identifier.lowercased()
        if lower.contains("claude-code") || (lower.contains("claude") && !lower.contains("desktop")) {
            return all.first { $0.id == "claude-code" }!
        }
        if lower.contains("cowork") || lower.contains("claude-desktop") || lower.contains("desktop") {
            return all.first { $0.id == "cowork" }!
        }
        if lower.contains("antigravity") || lower.contains("gemini") || lower.contains("agy") {
            return all.first { $0.id == "antigravity" }!
        }
        if lower.contains("cursor") {
            return all.first { $0.id == "cursor" }!
        }
        if lower.contains("codex") {
            return all.first { $0.id == "codex" }!
        }
        if lower.contains("chatgpt") || lower.contains("openai") {
            return all.first { $0.id == "chatgpt" }!
        }
        if lower.contains("copilot") {
            return all.first { $0.id == "copilot" }!
        }
        if lower.contains("term") || lower.contains("zsh") || lower.contains("bash") {
            return all.first { $0.id == "terminal" }!
        }

        return all.first { $0.id == lower } ?? PillDefinition(
            id: identifier,
            name: identifier.capitalized,
            subtitle: "External AI Agent",
            colorHex: "#8E939C",
            category: .agent,
            iconSystemName: "cpu",
            configPath: "IPC Hook",
            hookType: "Standard Sentinel IPC"
        )
    }
}
