import Foundation

@MainActor @Observable
final class RulesEngine {
    static let shared = RulesEngine()

    private(set) var storedRules: [StoredRule] = []
    private(set) var activeGrants: [ActiveGrant] = []
    private(set) var auditLogs: [AuditLogEntry] = []

    private let storageDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("AgentSentinel", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadFromDisk()
    }

    // MARK: - Evaluation

    // In-memory deduplication: prevent identical command popups within 5 seconds
    private var recentApprovals: [String: Date] = [:]

    private func isRecentlyApproved(command: String) -> Bool {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timestamp = recentApprovals[cmd] {
            if Date().timeIntervalSince(timestamp) < 5.0 {
                return true
            } else {
                recentApprovals.removeValue(forKey: cmd)
            }
        }
        return false
    }

    private func recordRecentApproval(command: String) {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        recentApprovals[cmd] = Date()
    }

    func evaluate(request: PermissionRequest) -> Decision? {
        cleanupExpired()

        let cmd = request.plainCommand.trimmingCharacters(in: .whitespacesAndNewlines)

        // 0. Deduplicate: if this exact command was approved in the last 5 seconds, auto-allow immediately
        if isRecentlyApproved(command: cmd) {
            recordDecision(request: request, decision: .allow(.once), autoAllowed: true)
            return .allow(.once)
        }

        // High risk operations cannot be automatically bypassed by persistent rules
        if request.risk == .high {
            return nil
        }

        // 1. Check active temporary grants (10 min)
        if activeGrants.contains(where: {
            !$0.isExpired && (cmd.hasPrefix($0.commandPrefix) || cmd == $0.commandPrefix)
        }) {
            recordDecision(request: request, decision: .allow(.tenMinutes), autoAllowed: true)
            return .allow(.tenMinutes)
        }

        // 2. Check persistent rules
        if storedRules.contains(where: {
            cmd.hasPrefix($0.pattern) || cmd == $0.pattern
        }) {
            recordDecision(request: request, decision: .allow(.always), autoAllowed: true)
            return .allow(.always)
        }

        return nil
    }

    // MARK: - Recording

    func recordDecision(request: PermissionRequest, decision: Decision, autoAllowed: Bool = false) {
        if decision.isAllowed {
            recordRecentApproval(command: request.plainCommand)
        }
        let entry = AuditLogEntry(
            timestamp: Date(),
            request: request,
            decision: decision,
            autoAllowed: autoAllowed
        )
        auditLogs.insert(entry, at: 0)
        if auditLogs.count > 500 {
            auditLogs.removeLast()
        }

        if !autoAllowed {
            switch decision {
            case .allow(.tenMinutes):
                let prefix = commandBase(for: request.plainCommand)
                let grant = ActiveGrant(
                    commandPrefix: prefix,
                    directory: request.directory,
                    expiresAt: Date().addingTimeInterval(600)
                )
                activeGrants.append(grant)
            case .allow(.always):
                let prefix = commandBase(for: request.plainCommand)
                let rule = StoredRule(
                    pattern: prefix,
                    directory: request.directory,
                    createdAt: Date(),
                    notes: "Saved rule from \(request.requestedBy)"
                )
                storedRules.append(rule)
            default:
                break
            }
        }

        saveToDisk()
    }

    func addManualRule(pattern: String, notes: String = "Manually configured") {
        let clean = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let rule = StoredRule(
            pattern: clean,
            directory: "*",
            createdAt: Date(),
            notes: notes
        )
        storedRules.append(rule)
        saveToDisk()
    }

    func revokeRule(id: UUID) {
        storedRules.removeAll { $0.id == id }
        saveToDisk()
    }

    func revokeGrant(id: UUID) {
        activeGrants.removeAll { $0.id == id }
        saveToDisk()
    }

    func clearAuditLogs() {
        auditLogs.removeAll()
        saveToDisk()
    }

    func cleanupExpired() {
        activeGrants.removeAll { $0.isExpired }
    }

    private func commandBase(for command: String) -> String {
        let parts = command.split(separator: " ").map(String.init)
        if parts.count >= 2 && (parts[0] == "npm" || parts[0] == "cargo" || parts[0] == "brew" || parts[0] == "git" || parts[0] == "swift") {
            return "\(parts[0]) \(parts[1])"
        }
        return parts.first ?? command
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(storedRules) {
            try? data.write(to: storageDir.appendingPathComponent("rules.json"))
        }
        if let data = try? encoder.encode(activeGrants) {
            try? data.write(to: storageDir.appendingPathComponent("grants.json"))
        }
        if let data = try? encoder.encode(auditLogs) {
            try? data.write(to: storageDir.appendingPathComponent("audit_log.json"))
        }
    }

    private func loadFromDisk() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let rulesURL = storageDir.appendingPathComponent("rules.json")
        if let data = try? Data(contentsOf: rulesURL),
           let rules = try? decoder.decode([StoredRule].self, from: data) {
            self.storedRules = rules
        }

        let grantsURL = storageDir.appendingPathComponent("grants.json")
        if let data = try? Data(contentsOf: grantsURL),
           let grants = try? decoder.decode([ActiveGrant].self, from: data) {
            self.activeGrants = grants.filter { !$0.isExpired }
        }

        let auditURL = storageDir.appendingPathComponent("audit_log.json")
        if let data = try? Data(contentsOf: auditURL),
           let logs = try? decoder.decode([AuditLogEntry].self, from: data) {
            self.auditLogs = logs
        }
    }
}
