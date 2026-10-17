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
        let sensitiveSubstrings = [
            "/etc",
            "/private/etc",
            "/var/root",
            "/.ssh",
            "/.aws",
            "/.gnupg",
            "/Library/Keychains"
        ]
        return sensitiveSubstrings.contains { p.contains($0) }
    }

    /// Evaluates if targetPath violates the workspace jail boundary
    func checkJailViolation(targetPath: String, workspaceRoot: String?) -> String? {
        guard !targetPath.isEmpty else { return nil }
        let expandedTarget = (targetPath as NSString).expandingTildeInPath

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
