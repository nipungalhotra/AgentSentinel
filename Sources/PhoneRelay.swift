import AppKit
import CoreGraphics
import CryptoKit
import Foundation

// MARK: - Phone approvals over ntfy
//
// When you are away from the Mac, a pending request is pushed to your phone as a native notification
// (the free ntfy app, https://ntfy.sh) with Allow / Deny buttons. Outbound only: the Mac publishes to a
// secret topic and listens on a secret reply topic, so nothing on this Mac is exposed to the internet.
// Each button carries a one-time HMAC signature bound to one request id, so forged or replayed replies
// are ignored. "Always" and "all folders" are never offered on the phone.
//
// The config file and wire protocol are shared with bin/loggdin.py (PhoneRelay) — keep them in sync.

struct PhoneConfig: Codable, Equatable {
    var enabled: Bool = true
    var server: String = PhoneRelay.defaultServer
    var topic: String
    var secret: String
    var pushAfter: Double = 15
    var details: String = "full"

    init(topic: String, secret: String) {
        self.topic = topic
        self.secret = secret
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topic = try c.decode(String.self, forKey: .topic)
        secret = try c.decode(String.self, forKey: .secret)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        let s = ((try? c.decodeIfPresent(String.self, forKey: .server)) ?? nil) ?? PhoneRelay.defaultServer
        server = s.isEmpty ? PhoneRelay.defaultServer : s
        pushAfter = min(max(((try? c.decodeIfPresent(Double.self, forKey: .pushAfter)) ?? nil) ?? 15, 0), 100)
        details = ((try? c.decodeIfPresent(String.self, forKey: .details)) ?? nil) == "minimal" ? "minimal" : "full"
    }

    var serverURL: String {
        var s = server
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
    var replyTopic: String { topic + "-reply" }
}

@MainActor
final class PhoneRelay {
    static let shared = PhoneRelay()
    nonisolated static let defaultServer = "https://ntfy.sh"
    /// Seconds of no keyboard/mouse input after which the Mac counts as "away" and pushes at once.
    static let idleAwaySeconds: Double = 60

    private(set) var config: PhoneConfig?
    private(set) var listening = false
    private(set) var lastError: String?

    private let configURL: URL
    private var configStamp: Date?
    private var listener: Task<Void, Never>?
    private var pushed: [String: PhoneConfig] = [:]
    private var screenLocked = false
    private var testWaiter: (id: String, done: (Decision) -> Void)?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AgentSentinel", isDirectory: true)
        configURL = dir.appendingPathComponent("phone.json")
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PhoneRelay.shared.screenLocked = true }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PhoneRelay.shared.screenLocked = false }
        }
        reload()
    }

    /// Phone approvals configured and switched on.
    var isActive: Bool {
        reloadIfChanged()
        return config?.enabled == true
    }

    // MARK: Config

    func reload() {
        configStamp = (try? FileManager.default.attributesOfItem(atPath: configURL.path))?[.modificationDate] as? Date
        if let data = try? Data(contentsOf: configURL), let cfg = try? JSONDecoder().decode(PhoneConfig.self, from: data) {
            config = cfg
        } else {
            config = nil
        }
        restartListener()
    }

    private func reloadIfChanged() {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: configURL.path))?[.modificationDate] as? Date
        if stamp != configStamp { reload() }
    }

    func save(_ cfg: PhoneConfig) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(cfg) else { return }
        try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = configURL.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600])
        _ = try? FileManager.default.replaceItemAt(configURL, withItemAt: tmp)
        reload()
    }

    /// Creates a fresh secret topic (or re-enables the existing one).
    func setUp(newTopic: Bool = false) {
        if var cfg = config, !newTopic {
            cfg.enabled = true
            save(cfg)
            return
        }
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        var rng = SystemRandomNumberGenerator()
        let topic = "loggdin-" + String((0..<20).map { _ in alphabet[Int(rng.next(upperBound: UInt32(alphabet.count)))] })
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255, using: &rng) }
        let secret = bytes.map { String(format: "%02x", $0) }.joined()
        var cfg = PhoneConfig(topic: topic, secret: secret)
        if let old = config { cfg.server = old.server; cfg.pushAfter = old.pushAfter; cfg.details = old.details }
        save(cfg)
    }

    func setEnabled(_ on: Bool) {
        guard var cfg = config else { if on { setUp() }; return }
        cfg.enabled = on
        save(cfg)
    }

    func update(_ change: (inout PhoneConfig) -> Void) {
        guard var cfg = config else { return }
        change(&cfg)
        save(cfg)
    }

    // MARK: Protocol

    nonisolated static func signature(secret: String, requestId: String, verb: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data("loggdin-phone|v1|\(requestId)|\(verb)".utf8), using: key)
        return String(mac.map { String(format: "%02x", $0) }.joined().prefix(32))
    }

    nonisolated static func sequenceId(_ requestId: String) -> String {
        "lg-" + String(requestId.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(40))
    }

    /// Parses "lg1 <id> <verb> <sig>"; returns nil unless the signature is valid.
    nonisolated static func parseReply(_ text: String, secret: String) -> (id: String, decision: Decision)? {
        let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count == 4, parts[0] == "lg1" else { return nil }
        let decision: Decision
        switch parts[2] {
        case "allow-once": decision = .allow(.once)
        case "allow-10m": decision = .allow(.tenMinutes)
        case "deny": decision = .deny
        default: return nil
        }
        let expected = Array(signature(secret: secret, requestId: parts[1], verb: parts[2]).utf8)
        let given = Array(parts[3].utf8)
        guard expected.count == given.count else { return nil }
        var diff: UInt8 = 0
        for i in expected.indices { diff |= expected[i] ^ given[i] }   // constant-time compare
        return diff == 0 ? (parts[1], decision) : nil
    }

    // MARK: Request lifecycle (called by PermissionPopupController)

    /// The Mac counts as away when the screen is locked or there has been no input for a minute.
    var userAway: Bool {
        if screenLocked { return true }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        return idle >= Self.idleAwaySeconds
    }

    func requestPresented(_ request: PermissionRequest, forceNow: Bool = false) {
        guard isActive, let cfg = config else { return }
        let id = request.id.uuidString
        let delay = (forceNow || userAway) ? 0 : cfg.pushAfter
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard PermissionPopupController.shared.isStillAsking(requestId: id), let cfg = self.config, cfg.enabled else { return }
            let ok = await Self.publish(cfg, request: request)
            if ok { self.pushed[id] = cfg }
        }
    }

    func requestFinished(_ request: PermissionRequest) {
        let id = request.id.uuidString
        guard let cfg = pushed.removeValue(forKey: id) else { return }
        Task { await Self.send(method: "PUT", url: "\(cfg.serverURL)/\(cfg.topic)/\(Self.sequenceId(id))/clear", body: nil) }
    }

    /// Sends a test notification; `done` gets the button the user tapped (or .timeout after 90 s).
    func sendTest(done: @escaping (Decision) -> Void) async -> String? {
        guard let cfg = config else { return "Set up phone approvals first." }
        let id = "TEST-" + UUID().uuidString.prefix(8).uppercased()
        let probe = PermissionRequest(title: "Test", subtitle: "loggdin test", symbol: "iphone",
                                      tokens: [CommandToken("echo 'Hello from loggdin'")],
                                      risk: .low, requestedBy: "loggdin test", directory: NSHomeDirectory(),
                                      modifiesFiles: "No", secretWarnings: nil, diffPreview: nil, blastRadius: nil)
        guard await Self.publish(cfg, request: probe, idOverride: id) else { return lastError ?? "Could not reach \(cfg.serverURL)." }
        testWaiter = (id, done)
        restartListener()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            if self.testWaiter?.id == id { self.testWaiter = nil; done(.timeout) }
        }
        return nil
    }

    // MARK: Networking

    nonisolated private static func publish(_ cfg: PhoneConfig, request: PermissionRequest, idOverride: String? = nil) async -> Bool {
        let id = idOverride ?? request.id.uuidString
        let high = request.risk == .high
        var verbs: [(String, String)] = [("allow-once", "Allow once")]
        if !high { verbs.append(("allow-10m", "Allow 10 min")) }
        verbs.append(("deny", "Deny"))
        let replyURL = "\(cfg.serverURL)/\(cfg.replyTopic)"
        let actions: [[String: Any]] = verbs.map { verb, label in
            ["action": "http", "label": label, "url": replyURL, "method": "POST", "clear": true,
             "body": "lg1 \(id) \(verb) \(signature(secret: cfg.secret, requestId: id, verb: verb))"]
        }
        let agent = request.requestedBy.isEmpty ? "An agent" : request.requestedBy
        let title = "\(agent) needs permission" + (high ? " · HIGH RISK" : "")
        let folder = (request.directory as NSString).lastPathComponent.isEmpty ? request.directory : (request.directory as NSString).lastPathComponent
        let body: String
        if cfg.details == "minimal" {
            body = "\(request.risk.rawValue.capitalized) risk request in \(folder)."
        } else if !(request.secretWarnings ?? []).isEmpty {
            body = "Command hidden: it looks like it contains a secret.\nFolder: \(folder)"
        } else {
            var cmd = request.plainCommand
            if cmd.count > 300 { cmd = String(cmd.prefix(299)) + "…" }
            body = "\(cmd)\nFolder: \(folder)"
        }
        let payload: [String: Any] = ["topic": cfg.topic, "title": title, "message": body, "actions": actions,
                                      "priority": high ? 5 : 4, "tags": [high ? "warning" : "lock"],
                                      "sequence_id": sequenceId(id)]
        let ok = await send(method: "POST", url: cfg.serverURL + "/", body: try? JSONSerialization.data(withJSONObject: payload))
        if !ok { NSLog("loggdin phone: push failed") }
        return ok
    }

    @discardableResult
    nonisolated private static func send(method: String, url: String, body: Data?) async -> Bool {
        guard let u = URL(string: url) else { return false }
        var req = URLRequest(url: u, timeoutInterval: 10)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("loggdin-mac", forHTTPHeaderField: "User-Agent")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            await MainActor.run { PhoneRelay.shared.lastError = (200..<300).contains(code) ? nil : "HTTP \(code)" }
            return (200..<300).contains(code)
        } catch {
            await MainActor.run { PhoneRelay.shared.lastError = error.localizedDescription }
            return false
        }
    }

    private func restartListener() {
        listener?.cancel()
        listener = nil
        listening = false
        guard let cfg = config, cfg.enabled || testWaiter != nil else { return }
        listener = Task.detached(priority: .utility) { await Self.listen(cfg) }
    }

    nonisolated private static func listen(_ cfg: PhoneConfig) async {
        var since = String(Int(Date().timeIntervalSince1970) - 5)
        var backoff: UInt64 = 2
        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 75          // ntfy sends a keepalive about every 45 s
            c.timeoutIntervalForResource = 24 * 3600
            return c
        }())
        while !Task.isCancelled {
            guard let url = URL(string: "\(cfg.serverURL)/\(cfg.replyTopic)/json?since=\(since)") else { return }
            var req = URLRequest(url: url)
            req.setValue("loggdin-mac", forHTTPHeaderField: "User-Agent")
            do {
                let (bytes, _) = try await session.bytes(for: req)
                await MainActor.run { PhoneRelay.shared.listening = true }
                backoff = 2
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          obj["event"] as? String == "message" else { continue }
                    if let mid = obj["id"] as? String { since = mid }
                    guard let text = obj["message"] as? String,
                          let reply = parseReply(text, secret: cfg.secret) else { continue }
                    await MainActor.run { PhoneRelay.shared.handle(reply.id, reply.decision) }
                }
            } catch {
                if Task.isCancelled { return }
            }
            await MainActor.run { PhoneRelay.shared.listening = false }
            try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            backoff = min(backoff * 2, 60)
        }
    }

    private func handle(_ id: String, _ decision: Decision) {
        if let waiter = testWaiter, waiter.id == id {
            testWaiter = nil
            waiter.done(decision)
            if config?.enabled != true { restartListener() }
            return
        }
        if PermissionPopupController.shared.submitExternalDecision(decision, forRequestId: id) {
            NSLog("loggdin phone: \(decision.summary) for \(id.prefix(8))")
        }
    }
}
