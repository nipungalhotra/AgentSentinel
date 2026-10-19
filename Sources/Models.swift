import Foundation
import SwiftUI
import CryptoKit

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
    let secretWarnings: [String]?
    let diffPreview: String?
    let blastRadius: String?

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
        modifiesFiles: String = "Unknown",
        secretWarnings: [String]? = nil,
        diffPreview: String? = nil,
        blastRadius: String? = nil
    ) {
        let parts = command.split(separator: " ").map(String.init)
        var parsedTokens: [CommandToken] = []
        var detectedRisk: Risk = .low

        let lower = command.lowercased()
        let isRm = parts.contains("rm") || parts.contains("rmdir") || parts.contains("unlink")
        let isRmRf = isRm && (parts.contains("-rf") || parts.contains("-fr") || parts.contains("-r") || parts.contains("-f"))
        let isSudo = parts.first == "sudo" || lower.contains(" sudo ") || lower.contains("; sudo ") || lower.contains("&& sudo ") || lower.contains("| sudo ")
        let isDd = (parts.first == "dd" || lower.contains(" dd if=")) && (lower.contains("of=/dev/") || lower.contains("bs="))
        let isDrop = lower.contains("drop table") || lower.contains("drop database") || lower.contains("truncate table")
        let isDiskDestructive = lower.contains("mkfs") || lower.contains("> /dev/sd") || lower.contains("chmod -r 777") || lower.contains("chown -r")

        if isRmRf || isSudo || isDd || isDrop || isDiskDestructive {
            detectedRisk = .high
        } else if lower.contains("npm install") || lower.contains("npm i ") || lower.contains("pip install") || lower.contains("brew install") || lower.contains("git push") || lower.contains("git reset") {
            detectedRisk = .medium
        }

        // Elevate risk if secrets are detected
        if let warnings = secretWarnings, !warnings.isEmpty {
            detectedRisk = .high
        }

        for (i, part) in parts.enumerated() {
            if i == 0 {
                parsedTokens.append(CommandToken(part, .command))
            } else if part == "-rf" || part == "-fr" || (isRm && (part == "-r" || part == "-f")) {
                parsedTokens.append(CommandToken(part, .danger))
            } else if isRm && part == "rm" {
                parsedTokens.append(CommandToken(part, .danger))
            } else if part.hasPrefix("-") || part.contains("/") || part.contains(".") {
                parsedTokens.append(CommandToken(part, .argument))
            } else {
                parsedTokens.append(CommandToken(part, .plain))
            }
        }

        let smartSymbol: String = {
            if symbol != "terminal" { return symbol }
            if isRm || lower.contains("delete") || isDrop { return "trash" }
            if command.contains("git") { return "arrow.triangle.branch" }
            if command.contains("npm") || command.contains("cargo") || command.contains("pip") || command.contains("brew") { return "shippingbox" }
            if command.contains("curl") || command.contains("wget") || command.contains("http") { return "globe" }
            if requestedBy != "CLI" && requestedBy != "user" { return "sparkles" }
            return "terminal"
        }()

        self.id = UUID()
        let resolvedRisk = risk ?? detectedRisk
        self.title = title ?? (resolvedRisk == .high ? "Delete files or execute dangerous command?" : "Run this command?")
        self.subtitle = subtitle ?? "\(requestedBy) • \(resolvedRisk == .high ? "File System" : "Terminal")"
        self.symbol = smartSymbol
        self.tokens = parsedTokens.isEmpty ? [CommandToken(command, .command)] : parsedTokens
        self.risk = resolvedRisk
        self.requestedBy = requestedBy
        self.directory = directory
        self.modifiesFiles = modifiesFiles
        self.secretWarnings = secretWarnings
        self.diffPreview = diffPreview
        self.blastRadius = blastRadius
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
        modifiesFiles: String,
        secretWarnings: [String]? = nil,
        diffPreview: String? = nil,
        blastRadius: String? = nil
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
        self.secretWarnings = secretWarnings
        self.diffPreview = diffPreview
        self.blastRadius = blastRadius
    }

    var category: PermissionCategory {
        let cmd = plainCommand.lowercased()
        let parts = cmd.split(separator: " ").map(String.init)

        let isRm = parts.contains("rm") || parts.contains("rmdir") || parts.contains("unlink")
        let isDrop = cmd.contains("drop table") || cmd.contains("drop database") || cmd.contains("truncate table")
        if isRm || isDrop || (risk == .high && !cmd.contains("sudo")) {
            return .delete
        }

        let isReadCmd = parts.first == "cat" || parts.first == "head" || parts.first == "tail" || parts.first == "less" || parts.first == "more" || parts.first == "grep"
        let isReadTool = cmd.contains("view_file") || cmd.contains("read_file") || symbol == "doc" || symbol == "doc.text"
        if isReadCmd || isReadTool {
            return .readFile
        }

        let isNetCmd = parts.first == "curl" || parts.first == "wget" || parts.first == "ping" || parts.first == "ssh"
        let isNetTool = cmd.contains("http://") || cmd.contains("https://") || cmd.contains("read_url_content") || symbol == "globe"
        if isNetCmd || isNetTool {
            return .network
        }

        if parts.first == "choose" || parts.first == "prompt" || cmd.contains("ask_question") || symbol == "sparkles" || symbol == "questionmark" {
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
    var agent: String? = nil
    var toolFamily: String? = nil

    init(
        id: UUID = UUID(),
        commandPrefix: String,
        directory: String,
        expiresAt: Date,
        agent: String? = nil,
        toolFamily: String? = nil
    ) {
        self.id = id
        self.commandPrefix = commandPrefix
        self.directory = directory
        self.expiresAt = expiresAt
        self.agent = agent
        self.toolFamily = toolFamily
    }

    enum CodingKeys: String, CodingKey {
        case id, commandPrefix, directory, expiresAt, agent, toolFamily
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.commandPrefix = try c.decode(String.self, forKey: .commandPrefix)
        self.directory = try c.decode(String.self, forKey: .directory)
        self.expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        self.agent = try c.decodeIfPresent(String.self, forKey: .agent)
        self.toolFamily = try c.decodeIfPresent(String.self, forKey: .toolFamily)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(commandPrefix, forKey: .commandPrefix)
        try c.encode(directory, forKey: .directory)
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encodeIfPresent(agent, forKey: .agent)
        try c.encodeIfPresent(toolFamily, forKey: .toolFamily)
    }

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
    var toolFamily: String? = nil

    init(
        id: UUID = UUID(),
        pattern: String,
        directory: String,
        createdAt: Date = Date(),
        notes: String = "",
        toolFamily: String? = nil
    ) {
        self.id = id
        self.pattern = pattern
        self.directory = directory
        self.createdAt = createdAt
        self.notes = notes
        self.toolFamily = toolFamily
    }

    enum CodingKeys: String, CodingKey {
        case id, pattern, directory, createdAt, notes, toolFamily
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.pattern = try c.decode(String.self, forKey: .pattern)
        self.directory = try c.decode(String.self, forKey: .directory)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.notes = try c.decode(String.self, forKey: .notes)
        self.toolFamily = try c.decodeIfPresent(String.self, forKey: .toolFamily)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(pattern, forKey: .pattern)
        try c.encode(directory, forKey: .directory)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(toolFamily, forKey: .toolFamily)
    }
}

// MARK: - Audit Log Entry

struct AuditLogEntry: Identifiable, Codable {
    var id: UUID = UUID()
    let timestamp: Date
    let request: PermissionRequest
    let decision: Decision
    let autoAllowed: Bool
    var prevHash: String? = nil
    var entryHash: String? = nil

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        request: PermissionRequest,
        decision: Decision,
        autoAllowed: Bool,
        prevHash: String? = nil,
        entryHash: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.request = request
        self.decision = decision
        self.autoAllowed = autoAllowed
        self.prevHash = prevHash
        self.entryHash = entryHash
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, request, decision, autoAllowed, prevHash, entryHash
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        self.request = try c.decode(PermissionRequest.self, forKey: .request)
        self.decision = try c.decode(Decision.self, forKey: .decision)
        self.autoAllowed = try c.decodeIfPresent(Bool.self, forKey: .autoAllowed) ?? false
        self.prevHash = try c.decodeIfPresent(String.self, forKey: .prevHash)
        self.entryHash = try c.decodeIfPresent(String.self, forKey: .entryHash)
    }

    func computeHash(prev: String) -> String {
        let payload = "\(prev)|\(Int(timestamp.timeIntervalSince1970))|\(request.plainCommand)|\(request.requestedBy)|\(request.directory)|\(request.risk.rawValue)|\(decision.summary)|\(autoAllowed)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

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
