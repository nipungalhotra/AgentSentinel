import Foundation

struct WorkspacePolicy: Codable {
    var enforceJail: Bool? = true
    var allowedPaths: [String]? = []
    var allowedCommands: [String]? = []
    var blockedCommands: [String]? = []
    var requireTouchID: [String]? = []
}

@MainActor
final class PolicyEngine {
    static let shared = PolicyEngine()

    private init() {}

    /// Checks if a path is considered a sensitive system or credential location
    func isSensitivePath(_ path: String) -> Bool {
        let p = (path as NSString).expandingTildeInPath
        let sensitivePrefixes = [
            "/etc/",
            "/private/etc/",
            "/var/root",
            "/Library/Keychains"
        ]
        if p == "/etc" || p == "/private/etc" || sensitivePrefixes.contains(where: { p.hasPrefix($0) }) {
            return true
        }
        let sensitiveContainments = [
            "/.ssh",
            "/.aws",
            "/.gnupg"
        ]
        return sensitiveContainments.contains { p.contains($0) }
    }

    /// Evaluates if targetPath violates the workspace jail boundary
    func checkJailViolation(targetPath: String, workspaceRoot: String?) -> String? {
        let trimmed = targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Only evaluate actual file paths, ignore descriptive status strings
        let nonFileIndicators = ["no", "workspace", "terminal shell", "read only", "n/a", "none"]
        let lower = trimmed.lowercased()
        if nonFileIndicators.contains(where: { lower.contains($0) }) && !trimmed.hasPrefix("/") && !trimmed.hasPrefix("~") {
            return nil
        }
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix("./") || trimmed.hasPrefix("../") else {
            return nil
        }

        let expandedTarget = (trimmed as NSString).expandingTildeInPath

        // 1. Never allow targeting sensitive system/credential directories without biometric escalation
        if isSensitivePath(expandedTarget) {
            return "Sensitive credential path targeted: \(targetPath)"
        }

        // 2. If workspace root is available, check containment
        guard let ws = workspaceRoot, !ws.isEmpty, ws != "~" else { return nil }
        let expandedWS = (ws as NSString).expandingTildeInPath

        // If target doesn't start with workspace root and isn't /tmp or /var/folders
        let isInside = expandedTarget.hasPrefix(expandedWS)
        let isTemp = expandedTarget.hasPrefix("/tmp") || expandedTarget.hasPrefix("/var/folders")
        if !isInside && !isTemp {
            return "Path escapes workspace jail: \(targetPath)"
        }

        return nil
    }

    /// Load workspace policy from .loggdin.json in workspace directory
    func loadPolicy(for workspaceRoot: String?) -> WorkspacePolicy? {
        guard let ws = workspaceRoot, !ws.isEmpty else { return nil }
        let expandedWS = (ws as NSString).expandingTildeInPath
        let policyURL = URL(fileURLWithPath: expandedWS).appendingPathComponent(".loggdin.json")
        guard let data = try? Data(contentsOf: policyURL),
              let policy = try? JSONDecoder().decode(WorkspacePolicy.self, from: data) else {
            return nil
        }
        return policy
    }
}
