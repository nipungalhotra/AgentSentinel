import Foundation
import SwiftUI

// MARK: - Risk Levels

enum Risk: String, Codable, CaseIterable {
    case low, medium, high

    var label: String {
        switch self {
        case .low: return "Low risk"
        case .medium: return "Medium risk"
        case .high: return "High risk"
        }
    }

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Scopes

enum AllowScope: String, Codable, CaseIterable, Identifiable {
    case once, tenMinutes, always

    var id: String { rawValue }

    var label: String {
        switch self {
        case .once: return "Once"
        case .tenMinutes: return "10 min"
        case .always: return "Always"
        }
    }

    var allowLabel: String {
        switch self {
        case .once: return "Allow once"
        case .tenMinutes: return "Allow 10 min"
        case .always: return "Always allow"
        }
    }

    var resolvedText: String {
        switch self {
        case .once: return "Just this once"
        case .tenMinutes: return "For the next 10 minutes"
        case .always: return "Saved to your rules"
        }
    }
}

// MARK: - Decisions

enum Decision: Codable, Equatable {
    case allow(AllowScope)
    case deny
    case timeout

    var isAllowed: Bool {
        if case .allow = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .allow(let scope): return "Allowed (\(scope.rawValue))"
        case .deny: return "Denied"
        case .timeout: return "Timed out"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, scope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "allow":
            let scope = try container.decodeIfPresent(AllowScope.self, forKey: .scope) ?? .once
            self = .allow(scope)
        case "deny":
            self = .deny
        case "timeout":
            self = .timeout
        default:
            self = .deny
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allow(let scope):
            try container.encode("allow", forKey: .type)
            try container.encode(scope, forKey: .scope)
        case .deny:
            try container.encode("deny", forKey: .type)
        case .timeout:
            try container.encode("timeout", forKey: .type)
        }
    }
}

// MARK: - Command Tokens

struct CommandToken: Hashable, Codable {
    enum Kind: String, Codable { case plain, command, argument, danger }
    let text: String
    let kind: Kind

    init(_ text: String, _ kind: Kind = .plain) {
        self.text = text
        self.kind = kind
    }
}

// MARK: - Permission Request

struct PermissionRequest: Identifiable, Codable {
    var id: UUID = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let tokens: [CommandToken]
    let risk: Risk
    let requestedBy: String
    let directory: String
    let modifiesFiles: String

    var plainCommand: String { tokens.map(\.text).joined(separator: " ") }

    var commandText: AttributedString {
        var out = AttributedString()
        for (i, token) in tokens.enumerated() {
            var piece = AttributedString(token.text + (i < tokens.count - 1 ? " " : ""))
            switch token.kind {
            case .plain: piece.foregroundColor = .primary
            case .command: piece.foregroundColor = .orange
            case .argument: piece.foregroundColor = .blue
            case .danger: piece.foregroundColor = .red
            }
            out += piece
        }
        return out
    }

    /// Convenience initializer that auto-tokenizes a shell command
    init(
        title: String? = nil,
        subtitle: String? = nil,
        symbol: String = "terminal",
        command: String,
        risk: Risk? = nil,
        requestedBy: String = "CLI",
        directory: String = "~",
        modifiesFiles: String = "Unknown"
    ) {
        let parts = command.split(separator: " ").map(String.init)
        var parsedTokens: [CommandToken] = []
        var detectedRisk: Risk = .low

        for (i, part) in parts.enumerated() {
            if i == 0 {
                parsedTokens.append(CommandToken(part, .command))
            } else if part == "-rf" || part == "--force" || part.contains("rm") || part.contains("drop") {
                parsedTokens.append(CommandToken(part, .danger))
                detectedRisk = .high
            } else if part.hasPrefix("-") || part.contains("/") || part.contains(".") {
                parsedTokens.append(CommandToken(part, .argument))
            } else {
                parsedTokens.append(CommandToken(part, .plain))
            }
        }

        if command.contains("rm -rf") || command.contains("sudo") || command.contains("dd ") {
            detectedRisk = .high
        } else if command.contains("npm i") || command.contains("install") || command.contains("pip") || command.contains("git push") {
            detectedRisk = .medium
        }

        let smartSymbol: String = {
            if symbol != "terminal" { return symbol }
            if command.contains("rm") || command.contains("delete") || command.contains("drop") { return "trash" }
            if command.contains("git") { return "arrow.triangle.branch" }
            if command.contains("npm") || command.contains("cargo") || command.contains("pip") || command.contains("brew") { return "shippingbox" }
            if command.contains("curl") || command.contains("wget") || command.contains("http") { return "globe" }
            if requestedBy != "CLI" && requestedBy != "user" { return "sparkles" }
            return "terminal"
        }()

        self.id = UUID()
        self.title = title ?? (detectedRisk == .high ? "Delete files or execute dangerous command?" : "Run this command?")
        self.subtitle = subtitle ?? "\(requestedBy) • \(detectedRisk == .high ? "File System" : "Terminal")"
        self.symbol = smartSymbol
        self.tokens = parsedTokens.isEmpty ? [CommandToken(command, .command)] : parsedTokens
        self.risk = risk ?? detectedRisk
        self.requestedBy = requestedBy
        self.directory = directory
        self.modifiesFiles = modifiesFiles
    }

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        symbol: String,
        tokens: [CommandToken],
        risk: Risk,
        requestedBy: String,
        directory: String,
        modifiesFiles: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tokens = tokens
        self.risk = risk
        self.requestedBy = requestedBy
        self.directory = directory
        self.modifiesFiles = modifiesFiles
    }

    var category: PermissionCategory {
        let cmd = plainCommand.lowercased()
        if cmd.contains("rm ") || cmd.contains("delete") || cmd.contains("drop") || risk == .high {
            return .delete
        }
        if cmd.contains("cat ") || cmd.contains("read") || cmd.contains("head ") || symbol == "doc" {
            return .readFile
        }
        if cmd.contains("curl") || cmd.contains("http") || cmd.contains("fetch") || cmd.contains("wget") || symbol == "globe" {
            return .network
        }
        if cmd.contains("choose") || cmd.contains("confirm") || cmd.contains("ask") {
            return .question
        }
        return .command
    }

    static let samples: [PermissionRequest] = [
        PermissionRequest(
            title: "Read this file?", subtitle: "File access", symbol: "doc",
            tokens: [CommandToken("read", .command), CommandToken("~/Documents/financial_summary.pdf", .argument)],
            risk: .low, requestedBy: "Claude Code", directory: "~/Documents", modifiesFiles: "No"),
        PermissionRequest(
            title: "Connect to this host?", subtitle: "Network access", symbol: "globe",
            tokens: [CommandToken("GET", .command), CommandToken("api.example.com/v1/users", .argument)],
            risk: .low, requestedBy: "Antigravity", directory: "~/Projects/my-app", modifiesFiles: "No"),
        PermissionRequest(
            title: "Run this command?", subtitle: "Terminal access", symbol: "terminal",
            tokens: [CommandToken("npm", .command), CommandToken("install"), CommandToken("express", .argument)],
            risk: .medium, requestedBy: "Claude Code", directory: "~/Projects/my-app", modifiesFiles: "Yes"),
        PermissionRequest(
            title: "Delete these files?", subtitle: "File system", symbol: "trash",
            tokens: [CommandToken("rm", .command), CommandToken("-rf", .danger), CommandToken("~/Projects/old-build", .argument)],
            risk: .high, requestedBy: "Claude Code", directory: "~/Projects", modifiesFiles: "Yes, permanently"),
        PermissionRequest(
            title: "Clarify architectural choice?", subtitle: "Interactive prompt", symbol: "sparkles",
            tokens: [CommandToken("choose", .command), CommandToken("--database"), CommandToken("PostgreSQL", .argument)],
            risk: .low, requestedBy: "Antigravity", directory: "~/workspace", modifiesFiles: "No")
    ]
}

enum PermissionCategory: String, Codable, CaseIterable {
    case readFile = "read"
    case network = "network"
    case command = "command"
    case delete = "delete"
    case question = "question"

    var label: String {
        switch self {
        case .readFile: return "Read file"
        case .network: return "Network"
        case .command: return "Command"
        case .delete: return "Delete"
        case .question: return "Question"
        }
    }
}

// MARK: - Stored Rules & Grants

struct ActiveGrant: Identifiable, Codable {
    var id: UUID = UUID()
    let commandPrefix: String
    let directory: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }

    var remainingSeconds: Int {
        max(0, Int(expiresAt.timeIntervalSince(Date())))
    }

    var remainingFormatted: String {
        let sec = remainingSeconds
        let m = sec / 60
        let s = sec % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct StoredRule: Identifiable, Codable {
    var id: UUID = UUID()
    let pattern: String
    let directory: String
    let createdAt: Date
    let notes: String
}

// MARK: - Audit Log Entry

struct AuditLogEntry: Identifiable, Codable {
    var id: UUID = UUID()
    let timestamp: Date
    let request: PermissionRequest
    let decision: Decision
    let autoAllowed: Bool

    var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: timestamp)
    }

    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
