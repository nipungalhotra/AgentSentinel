import Foundation

// MARK: - Chain Verification Result

struct ChainVerificationResult {
    let isValid: Bool
    let totalEntries: Int
    let brokenIndex: Int?
    let message: String
}

@MainActor @Observable
final class RulesEngine {
    static let shared = RulesEngine()

    private(set) var storedRules: [StoredRule] = []
    private(set) var activeGrants: [ActiveGrant] = []
    private(set) var auditLogs: [AuditLogEntry] = []

    private let storageDir: URL
    private var cleanupTimer: Timer?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("AgentSentinel", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadFromDisk()
        startPeriodicPruning()
    }

    private func startPeriodicPruning() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupExpired()
            }
        }
    }

    // MARK: - Evaluation

    // In-memory deduplication: prevent identical command popups within 15 seconds
    private var recentApprovals: [String: Date] = [:]

    private func isRecentlyApproved(command: String) -> Bool {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timestamp = recentApprovals[cmd] {
            if Date().timeIntervalSince(timestamp) < 15.0 {
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

    private func isCatastrophicDestructive(_ command: String) -> Bool {
        let lower = command.lowercased()
        if lower.contains("rm -rf /") || lower.contains("rm -fr /") || lower.contains("mkfs") || lower.contains("> /dev/sd") || lower.contains(":(){ :|:& };:") {
            return true
        }
        return false
    }

    func toolFamily(for command: String) -> String {
        let clean = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract last significant command in compound shell pipelines (e.g. "cd foo && git diff")
        let subcmds = clean.components(separatedBy: "&&")
            .flatMap { $0.components(separatedBy: ";") }
            .flatMap { $0.components(separatedBy: "||") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let target = subcmds.last ?? clean
        let parts = target.split(separator: " ").map(String.init)
        guard let first = parts.first?.lowercased() else { return clean }

        let effectiveFirst: String
        if (first == "sudo" || first == "env") && parts.count > 1 {
            effectiveFirst = parts[1].lowercased()
        } else {
            effectiveFirst = first
        }

        if effectiveFirst == "write" || effectiveFirst == "edit" || effectiveFirst == "inspect" || effectiveFirst == "modify" {
            return "file_mod"
        }

        let knownTools = [
            "git", "npm", "npx", "yarn", "pnpm", "bun",
            "cargo", "rustc", "swift", "xcodebuild",
            "python", "python3", "pytest", "pip", "pip3", "poetry", "uv",
            "docker", "docker-compose", "podman",
            "brew", "curl", "wget", "gh", "terraform", "go", "make", "cmake", "ctest",
            "node", "deno", "ts-node", "tsc", "eslint", "prettier"
        ]

        if knownTools.contains(effectiveFirst) {
            return effectiveFirst
        }

        return effectiveFirst
    }

    func isFileModification(command: String, category: PermissionCategory) -> Bool {
        if category == .readFile { return false }
        let lower = command.lowercased()
        return lower.hasPrefix("write ") || lower.hasPrefix("edit ") || lower.hasPrefix("modify ") ||
               lower.contains("replace_file_content") || lower.contains("write_to_file")
    }

    private func matchesGrant(grant: ActiveGrant, command: String, family: String, isFileMod: Bool, requestDir: String) -> Bool {
        let cleanCmd = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Direct or prefix command match
        if cleanCmd == grant.commandPrefix || cleanCmd.hasPrefix(grant.commandPrefix) {
            return true
        }

        // 2. Tool family match (e.g. grant for "git" allows "git status", "git diff", "git commit")
        if let gFamily = grant.toolFamily, !gFamily.isEmpty, gFamily == family {
            return true
        }
        if grant.commandPrefix == family {
            return true
        }

        // 3. File modifications across agents (Antigravity "Write", Claude Code "Edit", Codex "Edit")
        if isFileMod && (grant.commandPrefix == "file_mod" || grant.toolFamily == "file_mod" || grant.commandPrefix == "Edit" || grant.commandPrefix == "Write") {
            let reqExp = (requestDir as NSString).expandingTildeInPath
            let grantExp = (grant.directory as NSString).expandingTildeInPath
            if grant.directory == "*" || reqExp.hasPrefix(grantExp) || grantExp.hasPrefix(reqExp) {
                return true
            }
        }

        // 4. Workspace match
        if grant.commandPrefix == "workspace" || grant.toolFamily == "workspace" {
            let reqExp = (requestDir as NSString).expandingTildeInPath
            let grantExp = (grant.directory as NSString).expandingTildeInPath
            if grant.directory == "*" || reqExp.hasPrefix(grantExp) || grantExp.hasPrefix(reqExp) {
                return true
            }
        }

        return false
    }

    private func matchesRule(rule: StoredRule, command: String, family: String, isFileMod: Bool, requestDir: String) -> Bool {
        let cleanCmd = command.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanCmd == rule.pattern || cleanCmd.hasPrefix(rule.pattern) {
            return true
        }

        if let rFamily = rule.toolFamily, !rFamily.isEmpty, rFamily == family {
            return true
        }
        if rule.pattern == family {
            return true
        }

        if isFileMod && (rule.pattern == "file_mod" || rule.toolFamily == "file_mod" || rule.pattern == "Edit" || rule.pattern == "Write") {
            let reqExp = (requestDir as NSString).expandingTildeInPath
            let ruleExp = (rule.directory as NSString).expandingTildeInPath
            if rule.directory == "*" || reqExp.hasPrefix(ruleExp) || ruleExp.hasPrefix(reqExp) {
                return true
            }
        }

        return false
    }

    func evaluate(request: PermissionRequest) -> Decision? {
        cleanupExpired()

        let cmd = request.plainCommand.trimmingCharacters(in: .whitespacesAndNewlines)

        // 0. Deduplicate: if this exact command was approved in the last 15 seconds, auto-allow immediately
        if isRecentlyApproved(command: cmd) {
            recordDecision(request: request, decision: .allow(.once), autoAllowed: true)
            return .allow(.once)
        }

        // Catastrophic root destructive operations cannot be automatically bypassed
        if isCatastrophicDestructive(cmd) {
            return nil
        }

        let family = toolFamily(for: cmd)
        let isFile = isFileModification(command: cmd, category: request.category)

        // 1. Check active temporary grants (10 min)
        if activeGrants.contains(where: { grant in
            guard !grant.isExpired else { return false }
            return matchesGrant(grant: grant, command: cmd, family: family, isFileMod: isFile, requestDir: request.directory)
        }) {
            recordDecision(request: request, decision: .allow(.tenMinutes), autoAllowed: true)
            return .allow(.tenMinutes)
        }

        // 2. Check persistent rules
        if storedRules.contains(where: { rule in
            return matchesRule(rule: rule, command: cmd, family: family, isFileMod: isFile, requestDir: request.directory)
        }) {
            recordDecision(request: request, decision: .allow(.always), autoAllowed: true)
            return .allow(.always)
        }

        return nil
    }

    static let genesisHash = "0000000000000000000000000000000000000000000000000000000000000000"

    // MARK: - Recording

    func recordDecision(request: PermissionRequest, decision: Decision, autoAllowed: Bool = false) {
        if decision.isAllowed {
            recordRecentApproval(command: request.plainCommand)
        }

        let prev = auditLogs.first?.entryHash ?? RulesEngine.genesisHash
        var entry = AuditLogEntry(
            timestamp: Date(),
            request: request,
            decision: decision,
            autoAllowed: autoAllowed,
            prevHash: prev,
            entryHash: nil
        )
        entry.entryHash = entry.computeHash(prev: prev)

        auditLogs.insert(entry, at: 0)
        if auditLogs.count > 500 {
            auditLogs.removeLast()
        }

        if !autoAllowed {
            let family = toolFamily(for: request.plainCommand)
            let isFile = isFileModification(command: request.plainCommand, category: request.category)
            let effectivePrefix = isFile ? "file_mod" : family

            switch decision {
            case .allow(.tenMinutes):
                let grant = ActiveGrant(
                    commandPrefix: effectivePrefix,
                    directory: request.directory,
                    expiresAt: Date().addingTimeInterval(600),
                    agent: request.requestedBy,
                    toolFamily: effectivePrefix
                )
                activeGrants.append(grant)
            case .allow(.always):
                let rule = StoredRule(
                    pattern: effectivePrefix,
                    directory: request.directory,
                    createdAt: Date(),
                    notes: "Saved rule from \(request.requestedBy) for \(effectivePrefix)",
                    toolFamily: effectivePrefix
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
        let initialCount = activeGrants.count
        activeGrants.removeAll { $0.isExpired }
        if activeGrants.count != initialCount {
            saveToDisk()
        }
    }

    // MARK: - Cryptographic Chain Verification

    func verifyChainIntegrity() -> ChainVerificationResult {
        guard !auditLogs.isEmpty else {
            return ChainVerificationResult(isValid: true, totalEntries: 0, brokenIndex: nil, message: "Audit log is empty.")
        }

        // Entries are ordered from newest at index 0 to oldest at index count - 1
        var expectedPrev: String? = nil
        for i in stride(from: auditLogs.count - 1, through: 0, by: -1) {
            let entry = auditLogs[i]
            guard let storedPrev = entry.prevHash, let storedHash = entry.entryHash else {
                return ChainVerificationResult(
                    isValid: false,
                    totalEntries: auditLogs.count,
                    brokenIndex: i,
                    message: "Missing cryptographic hash at entry #\(auditLogs.count - i)."
                )
            }

            // For all entries following the oldest entry in the window, verify chain continuity
            if let expected = expectedPrev, storedPrev != expected {
                return ChainVerificationResult(
                    isValid: false,
                    totalEntries: auditLogs.count,
                    brokenIndex: i,
                    message: "Chain link broken at entry #\(auditLogs.count - i): prevHash altered."
                )
            }

            let computed = entry.computeHash(prev: storedPrev)
            if computed != storedHash {
                return ChainVerificationResult(
                    isValid: false,
                    totalEntries: auditLogs.count,
                    brokenIndex: i,
                    message: "Tamper detected at entry #\(auditLogs.count - i): content digest mismatch."
                )
            }

            expectedPrev = storedHash
        }

        return ChainVerificationResult(
            isValid: true,
            totalEntries: auditLogs.count,
            brokenIndex: nil,
            message: "Cryptographically verified: SHA-256 Merkle chain intact across all \(auditLogs.count) entries."
        )
    }

    // MARK: - Audit Export

    func exportAuditLogCSV() -> String {
        var csv = "Timestamp,ISO8601,Agent,Risk,Command,Directory,ModifiesFiles,Decision,AutoAllowed,PrevHash,EntryHash\n"
        let isoFormatter = ISO8601DateFormatter()
        for entry in auditLogs {
            let cleanCmd = entry.request.plainCommand.replacingOccurrences(of: "\"", with: "\"\"")
            let cleanDir = entry.request.directory.replacingOccurrences(of: "\"", with: "\"\"")
            let cleanMod = entry.request.modifiesFiles.replacingOccurrences(of: "\"", with: "\"\"")
            let cleanAgent = entry.request.requestedBy.replacingOccurrences(of: "\"", with: "\"\"")
            let row = "\"\(entry.dateFormatted)\",\"\(isoFormatter.string(from: entry.timestamp))\",\"\(cleanAgent)\",\"\(entry.request.risk.rawValue)\",\"\(cleanCmd)\",\"\(cleanDir)\",\"\(cleanMod)\",\"\(entry.decision.summary)\",\(entry.autoAllowed),\"\(entry.prevHash ?? "")\",\"\(entry.entryHash ?? "")\"\n"
            csv.append(row)
        }
        return csv
    }

    func exportAuditLogJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(auditLogs), let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    private func backfillHashesIfNeeded() {
        guard !auditLogs.isEmpty else { return }
        var needsSave = false
        var currentPrev = RulesEngine.genesisHash
        for i in stride(from: auditLogs.count - 1, through: 0, by: -1) {
            if auditLogs[i].entryHash == nil || auditLogs[i].prevHash == nil {
                auditLogs[i].prevHash = currentPrev
                auditLogs[i].entryHash = auditLogs[i].computeHash(prev: currentPrev)
                needsSave = true
            }
            currentPrev = auditLogs[i].entryHash ?? currentPrev
        }
        if needsSave {
            saveToDisk()
        }
    }

    private func commandBase(for command: String) -> String {
        let parts = command.split(separator: " ").map(String.init)
        if parts.count >= 2 && (parts[0] == "npm" || parts[0] == "cargo" || parts[0] == "brew" || parts[0] == "git" || parts[0] == "swift" || parts[0] == "docker" || parts[0] == "terraform" || parts[0] == "gh" || parts[0] == "pip" || parts[0] == "pip3") {
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
            self.backfillHashesIfNeeded()
        }
    }
}
