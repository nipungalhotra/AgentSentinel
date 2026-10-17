import Foundation

// MARK: - Webhook Configuration

struct WebhookConfig: Codable {
    var url: String = ""
    var enabled: Bool = false
    var notifyHighRiskOnly: Bool = true
    var name: String = "loggdin-guard"
}

// MARK: - Webhook Manager

@MainActor
final class WebhookManager {
    static let shared = WebhookManager()

    private let configURL: URL
    private(set) var config: WebhookConfig = WebhookConfig()

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AgentSentinel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("webhook.json")
        loadConfig()
    }

    func loadConfig() {
        // Priority 1: Environment variable
        if let envUrl = ProcessInfo.processInfo.environment["LOGGDIN_WEBHOOK_URL"], !envUrl.isEmpty {
            config = WebhookConfig(url: envUrl, enabled: true, notifyHighRiskOnly: false, name: "loggdin-env")
            return
        }

        // Priority 2: JSON file
        if FileManager.default.fileExists(atPath: configURL.path) {
            if let data = try? Data(contentsOf: configURL),
               let loaded = try? JSONDecoder().decode(WebhookConfig.self, from: data) {
                config = loaded
                return
            }
        } else {
            // Write default template for user reference
            let sample = WebhookConfig(
                url: "",
                enabled: false,
                notifyHighRiskOnly: true,
                name: "loggdin-guard"
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(sample) {
                try? data.write(to: configURL)
            }
        }
    }

    func saveConfig(_ newConfig: WebhookConfig) {
        config = newConfig
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL)
        }
    }

    var isConfigured: Bool {
        return config.enabled && !config.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Notifications

    func notifyPending(_ request: PermissionRequest) {
        guard isConfigured else { return }
        if config.notifyHighRiskOnly && request.risk != .high {
            return
        }

        let payload = buildPendingPayload(for: request)
        dispatch(payload: payload, to: config.url)
    }

    func notifyDecision(_ request: PermissionRequest, decision: Decision) {
        guard isConfigured else { return }
        if config.notifyHighRiskOnly && request.risk != .high {
            return
        }

        let payload = buildDecisionPayload(for: request, decision: decision)
        dispatch(payload: payload, to: config.url)
    }

    func testWebhook() async -> (success: Bool, message: String) {
        guard isConfigured, let endpoint = URL(string: config.url) else {
            return (false, "Webhook URL is not configured or disabled.")
        }

        let testPayload: [String: Any]
        if config.url.contains("discord.com") {
            testPayload = [
                "content": "🛡️ **loggdin Webhook Test**\nConnection successful! Autonomous agent security alerts are active."
            ]
        } else if config.url.contains("slack.com") {
            testPayload = [
                "text": "🛡️ *[loggdin]* Webhook Test: Connection successful! Autonomous agent security alerts are active."
            ]
        } else {
            testPayload = [
                "event": "test",
                "message": "loggdin security gate webhook operational.",
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        }

        do {
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: testPayload)
            req.timeoutInterval = 5.0

            let (_, response) = try await URLSession.shared.data(for: req)
            if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                return (true, "HTTP \(httpRes.statusCode): Webhook delivered successfully.")
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return (false, "Webhook responded with HTTP status \(code).")
            }
        } catch {
            return (false, "Webhook error: \(error.localizedDescription)")
        }
    }

    // MARK: - Payload Builders

    private func buildPendingPayload(for req: PermissionRequest) -> [String: Any] {
        let urlStr = config.url.lowercased()

        if urlStr.contains("discord.com") {
            let color = req.risk == .high ? 15158332 : (req.risk == .medium ? 15105570 : 3066993)
            return [
                "content": "🛡️ **Action Requires Review**",
                "embeds": [
                    [
                        "title": "\(req.title) (\(req.risk.label))",
                        "description": "```bash\n\(req.plainCommand)\n```",
                        "color": color,
                        "fields": [
                            ["name": "Agent", "value": req.requestedBy, "inline": true],
                            ["name": "Directory", "value": "`\(req.directory)`", "inline": true],
                            ["name": "Modifies", "value": req.modifiesFiles, "inline": true],
                            ["name": "Blast Radius", "value": req.blastRadius ?? "Unknown", "inline": true]
                        ],
                        "footer": ["text": "loggdin • autonomous AI agent security gate"]
                    ]
                ]
            ]
        }

        if urlStr.contains("slack.com") {
            return [
                "text": "🚨 [loggdin] \(req.risk.label.uppercased()): \(req.plainCommand)",
                "blocks": [
                    [
                        "type": "header",
                        "text": ["type": "plain_text", "text": "🛡️ loggdin Security Alert"]
                    ],
                    [
                        "type": "section",
                        "fields": [
                            ["type": "mrkdwn", "text": "*Agent:*\n\(req.requestedBy)"],
                            ["type": "mrkdwn", "text": "*Risk:*\n\(req.risk.label)"],
                            ["type": "mrkdwn", "text": "*Directory:*\n`\(req.directory)`"],
                            ["type": "mrkdwn", "text": "*Modifies:*\n`\(req.modifiesFiles)`"]
                        ]
                    ],
                    [
                        "type": "section",
                        "text": ["type": "mrkdwn", "text": "*Command:*\n```\(req.plainCommand)```"]
                    ]
                ]
            ]
        }

        // Generic webhook payload
        return [
            "event": "permission_requested",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "agent": req.requestedBy,
            "title": req.title,
            "risk": req.risk.rawValue,
            "command": req.plainCommand,
            "directory": req.directory,
            "modifies_files": req.modifiesFiles,
            "blast_radius": req.blastRadius ?? "n/a",
            "secrets_detected": req.secretWarnings ?? []
        ]
    }

    private func buildDecisionPayload(for req: PermissionRequest, decision: Decision) -> [String: Any] {
        let urlStr = config.url.lowercased()

        if urlStr.contains("discord.com") {
            let color = decision.isAllowed ? 3066993 : 15158332
            return [
                "embeds": [
                    [
                        "title": "Decision: \(decision.summary)",
                        "description": "Command: `\(req.plainCommand)`",
                        "color": color,
                        "fields": [
                            ["name": "Agent", "value": req.requestedBy, "inline": true],
                            ["name": "Status", "value": decision.isAllowed ? "APPROVED" : "BLOCKED", "inline": true]
                        ],
                        "footer": ["text": "loggdin • autonomous AI agent security gate"]
                    ]
                ]
            ]
        }

        if urlStr.contains("slack.com") {
            let status = decision.isAllowed ? "✅ Approved" : "🛑 Denied"
            return [
                "text": "\(status) [\(decision.summary)] for \(req.requestedBy): `\(req.plainCommand)`"
            ]
        }

        return [
            "event": "permission_decided",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "decision": decision.summary,
            "is_allowed": decision.isAllowed,
            "command": req.plainCommand,
            "agent": req.requestedBy
        ]
    }

    private func dispatch(payload: [String: Any], to urlString: String) {
        guard let url = URL(string: urlString),
              let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        Task.detached(priority: .utility) {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData
                request.timeoutInterval = 5.0

                let _ = try await URLSession.shared.data(for: request)
            } catch {
                // Non-blocking: background notification failure does not hinder UI or execution
                print("[loggdin-webhook] dispatch failed: \(error.localizedDescription)")
            }
        }
    }
}
