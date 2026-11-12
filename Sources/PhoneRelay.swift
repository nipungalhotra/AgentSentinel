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
    /// Where a request is asked: "auto" (Mac first, phone when away or after the delay),
    /// "both" (Mac and phone at once) or "phone" (phone only, no card on the Mac).
    var mode: String = "auto"
    /// Expo push tokens of phones running the loggdin app (mobile/). They get a short
    /// "request waiting" notification through Expo's push service; the command is never in it.
    var pushTokens: [String] = []

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
        let m = ((try? c.decodeIfPresent(String.self, forKey: .mode)) ?? nil) ?? "auto"
        mode = ["both", "phone"].contains(m) ? m : "auto"
        let tokens = ((try? c.decodeIfPresent([String].self, forKey: .pushTokens)) ?? nil) ?? []
        pushTokens = Array(tokens.filter(PhoneRelay.isPushToken).suffix(PhoneRelay.maxPushTokens))
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
    /// The loggdin phone app on the web (mobile/). A pairing link puts the topic after "#",
    /// which browsers never send to the server.
    nonisolated static let phoneAppURL = "https://app.loggdin.com"

    nonisolated static let expoPushURL = "https://exp.host/--/api/v2/push/send"
    nonisolated static let maxPushTokens = 5

    nonisolated static func isPushToken(_ s: String) -> Bool {
        s.range(of: #"^Expo(nent)?PushToken\[[A-Za-z0-9_-]{10,100}\]$"#, options: .regularExpression) != nil
    }

    /// Parses "lg1-push <token> <sig>", the message loggdin Pocket posts to register itself; the
    /// signature must come from the pairing key, so only a phone that was given the code can register.
    nonisolated static func parsePushRegistration(_ text: String, secret: String) -> String? {
        let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count == 3, parts[0] == "lg1-push", isPushToken(parts[1]) else { return nil }
        let key = SymmetricKey(data: Data(pairKey(secret: secret).utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data("loggdin-phone|v1|push|\(parts[1])".utf8), using: key)
        let expected = Array(String(mac.map { String(format: "%02x", $0) }.joined().prefix(32)).utf8)
        let given = Array(parts[2].utf8)
        guard expected.count == given.count else { return nil }
        var diff: UInt8 = 0
        for i in expected.indices { diff |= expected[i] ^ given[i] }
        return diff == 0 ? parts[1] : nil
    }

    /// Pairing key, derived from the secret: the phone signs its notification registration with it, so
    /// knowing the topic alone is not enough to get a phone registered. Never sent over the network.
    nonisolated static func pairKey(secret: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("loggdin-phone|v1|pair".utf8), using: SymmetricKey(data: Data(secret.utf8)))
        return String(mac.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    // MARK: End-to-end encryption
    // What goes through the relay is sealed with keys derived from the pairing key, which only the QR
    // code / pairing code carries: the relay and anyone who knows the topic see neither the request nor
    // its signed answer buttons. Encrypt-then-MAC with HMAC-SHA256 (keystream PRF and MAC), the same
    // construction as bin/loggdin.py and mobile/src/hmac.ts: "lg1e " + base64(nonce16 || ct || tag16).

    nonisolated private static func hmac(_ key: Data, _ message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    nonisolated static func seal(_ object: [String: Any], secret: String) -> String? {
        guard let plain = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        let pk = Data(pairKey(secret: secret).utf8)
        let encKey = hmac(pk, Data("loggdin-phone|v1|enc".utf8))
        let macKey = hmac(pk, Data("loggdin-phone|v1|mac".utf8))
        var nonce = Data(count: 16)
        guard nonce.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }) == errSecSuccess else { return nil }
        var stream = Data()
        var counter: UInt32 = 0
        while stream.count < plain.count {
            var be = counter.bigEndian
            stream += hmac(encKey, nonce + Data(bytes: &be, count: 4))
            counter += 1
        }
        let cipher = Data(zip(plain, stream).map { $0 ^ $1 })
        let tag = hmac(macKey, nonce + cipher).prefix(16)
        return "lg1e " + (nonce + cipher + tag).base64EncodedString()
    }

    /// What a person types into loggdin Pocket when they can't scan: "<topic>.<pairing key>".
    nonisolated static func pairingCode(_ cfg: PhoneConfig) -> String {
        "\(cfg.topic).\(pairKey(secret: cfg.secret))"
    }

    /// Link the dashboard QR code opens: loggdin Pocket, already paired with this computer.
    /// Everything after "#" stays in the phone; browsers never send it to a server.
    nonisolated static func pairingLink(_ cfg: PhoneConfig) -> String {
        let code = pairingCode(cfg)
        let target = cfg.serverURL == defaultServer ? code : "\(cfg.serverURL)/\(code)"
        return "\(phoneAppURL)/#\(target)"
    }
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
    private var answeredByPhone: Set<String> = []

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

    /// "Phone only" mode: the request is asked on the phone and no card is shown on the Mac.
    var isPhoneOnly: Bool { isActive && config?.mode == "phone" }

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
        if let old = config { cfg.server = old.server; cfg.pushAfter = old.pushAfter; cfg.details = old.details; cfg.mode = old.mode }
        save(cfg)
    }

    func setEnabled(_ on: Bool) {
        guard var cfg = config else { if on { setUp() }; return }
        cfg.enabled = on
        save(cfg)
    }

    /// Remembers a phone that asked for notifications (newest last, at most `maxPushTokens`).
    func registerPushToken(_ token: String) {
        guard var cfg = config, !cfg.pushTokens.contains(token) else { return }
        cfg.pushTokens = Array((cfg.pushTokens + [token]).suffix(Self.maxPushTokens))
        save(cfg)
        NSLog("loggdin phone: registered a phone for notifications")
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

    /// "lg1 <id> opt-<n> <sig>": an option tapped for an agent question.
    nonisolated static func parseOptionReply(_ text: String, secret: String) -> (id: String, option: Int)? {
        let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count == 4, parts[0] == "lg1", parts[2].hasPrefix("opt-"),
              let n = Int(parts[2].dropFirst(4)), (0..<10).contains(n) else { return nil }
        let expected = Array(signature(secret: secret, requestId: parts[1], verb: parts[2]).utf8)
        let given = Array(parts[3].utf8)
        guard expected.count == given.count else { return nil }
        var diff: UInt8 = 0
        for i in expected.indices { diff |= expected[i] ^ given[i] }
        return diff == 0 ? (parts[1], n) : nil
    }

    // MARK: Agent questions and notices (called by QuestionController / NoticeController)

    private var pushedQuestions: [String: PhoneConfig] = [:]

    func questionPresented(_ q: AgentQuestion, forceNow: Bool = false) {
        guard isActive, let cfg = config else { return }
        let delay = (forceNow || userAway || cfg.mode != "auto") ? 0 : cfg.pushAfter
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard QuestionController.shared.isAsking(id: q.id), let cfg = self.config, cfg.enabled else { return }
            if await Self.publishQuestion(cfg, q) { self.pushedQuestions[q.id] = cfg }
        }
    }

    func questionFinished(_ q: AgentQuestion) {
        guard let cfg = pushedQuestions.removeValue(forKey: q.id) else { return }
        Task { await Self.send(method: "PUT", url: "\(cfg.serverURL)/\(cfg.topic)/\(Self.sequenceId(q.id))/clear", body: nil) }
    }

    func noticePresented(agent: String, title: String, message: String, directory: String) {
        guard isActive, let cfg = config, cfg.mode != "auto" || userAway else { return }
        Task { await Self.publishNotice(cfg, agent: agent, title: title, message: message, directory: directory) }
    }

    nonisolated private static func folderName(_ directory: String) -> String {
        let last = (directory as NSString).lastPathComponent
        return last.isEmpty || directory == "~" ? "your home folder" : last
    }

    /// Single-question requests carry one signed button per option; longer ones say to answer on the computer.
    nonisolated private static func publishQuestion(_ cfg: PhoneConfig, _ q: AgentQuestion) async -> Bool {
        let item = q.items[0]
        let actions: [[String]] = q.items.count == 1 && !item.multiSelect
            ? item.options.prefix(6).enumerated().map { i, o in
                [o.label, "lg1 \(q.id) opt-\(i) \(signature(secret: cfg.secret, requestId: q.id, verb: "opt-\(i)"))"]
            }
            : []
        let folder = folderName(q.directory)
        let more = actions.isEmpty ? "\nAnswer this one on your computer." : ""
        guard let sealed = seal(["k": "q", "t": "\(q.agent) asks", "m": "\(item.question)\nFolder: \(folder)\(more)",
                                 "h": false, "a": actions], secret: cfg.secret) else { return false }
        return await deliver(cfg, sealed: sealed, seq: sequenceId(q.id), priority: 4,
                             expoTitle: "\(q.agent) has a question", expoBody: "In \(folder). Open loggdin to answer.")
    }

    nonisolated private static func publishNotice(_ cfg: PhoneConfig, agent: String, title: String, message: String, directory: String) async {
        let folder = folderName(directory)
        guard let sealed = seal(["k": "n", "t": "\(agent) \(title)", "m": "\(message)\nFolder: \(folder)", "a": [[String]]()],
                                secret: cfg.secret) else { return }
        _ = await deliver(cfg, sealed: sealed, seq: "lg-n" + String(UUID().uuidString.lowercased().filter { $0.isHexDigit }.prefix(20)),
                          priority: 3, expoTitle: "\(agent) \(title)", expoBody: "In \(folder).")
    }

    nonisolated private static func deliver(_ cfg: PhoneConfig, sealed: String, seq: String, priority: Int,
                                            expoTitle: String, expoBody: String) async -> Bool {
        let payload: [String: Any] = ["topic": cfg.topic, "title": "loggdin", "message": sealed,
                                      "priority": priority, "tags": ["speech_balloon"], "sequence_id": seq]
        let ok = await send(method: "POST", url: cfg.serverURL + "/", body: try? JSONSerialization.data(withJSONObject: payload))
        guard !cfg.pushTokens.isEmpty else { return ok }
        let messages: [[String: Any]] = cfg.pushTokens.map {
            ["to": $0, "title": expoTitle, "body": expoBody, "sound": "default", "priority": "high",
             "channelId": "requests", "ttl": 110, "data": ["seq": seq]]
        }
        let delivered = await send(method: "POST", url: expoPushURL, body: try? JSONSerialization.data(withJSONObject: messages))
        return ok || delivered
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
        let delay = (forceNow || userAway || cfg.mode != "auto") ? 0 : cfg.pushAfter
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard PermissionPopupController.shared.isStillAsking(requestId: id), let cfg = self.config, cfg.enabled else { return }
            let ok = await Self.publish(cfg, request: request)
            if ok { self.pushed[id] = cfg }
        }
    }

    /// Pushes a request at once and reports whether the phone service accepted it.
    /// Used by "phone only" mode, which falls back to the Mac card when this fails.
    func pushNow(_ request: PermissionRequest) async -> Bool {
        guard isActive, let cfg = config else { return false }
        let id = request.id.uuidString
        guard await Self.publish(cfg, request: request) else { return false }
        if PermissionPopupController.shared.isStillAsking(requestId: id) {
            pushed[id] = cfg
        } else {
            // Answered while the push was in flight: take the notification back.
            await Self.send(method: "PUT", url: "\(cfg.serverURL)/\(cfg.topic)/\(Self.sequenceId(id))/clear", body: nil)
        }
        return true
    }

    /// True once if the phone answered this request (for the audit log's "via": "phone").
    func takeAnsweredByPhone(_ requestId: String) -> Bool {
        answeredByPhone.remove(requestId.uppercased()) != nil
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
        let actions: [[String]] = verbs.map { verb, label in
            [label, "lg1 \(id) \(verb) \(signature(secret: cfg.secret, requestId: id, verb: verb))"]
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
        guard let sealed = seal(["t": title, "m": body, "h": high, "a": actions], secret: cfg.secret) else { return false }
        let payload: [String: Any] = ["topic": cfg.topic, "title": "loggdin", "message": sealed,
                                      "priority": high ? 5 : 4, "tags": [high ? "warning" : "lock"],
                                      "sequence_id": sequenceId(id)]
        let ok = await send(method: "POST", url: cfg.serverURL + "/", body: try? JSONSerialization.data(withJSONObject: payload))
        if !ok { NSLog("loggdin phone: push failed") }
        if !cfg.pushTokens.isEmpty {
            // The loggdin phone app: only the agent, risk and folder go through Expo's servers.
            let note = "\(request.risk.rawValue.capitalized) risk request in \(folder). Open loggdin to answer."
            let messages: [[String: Any]] = cfg.pushTokens.map {
                ["to": $0, "title": title, "body": note, "sound": "default", "priority": "high",
                 "channelId": "requests", "ttl": 110, "data": ["seq": sequenceId(id)]]
            }
            let delivered = await send(method: "POST", url: expoPushURL, body: try? JSONSerialization.data(withJSONObject: messages))
            if !delivered { NSLog("loggdin phone: app notification failed") }
            return ok || delivered
        }
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
                    guard let text = obj["message"] as? String else { continue }
                    if let token = parsePushRegistration(text, secret: cfg.secret) {
                        await MainActor.run { PhoneRelay.shared.registerPushToken(token) }
                        continue
                    }
                    if let pick = parseOptionReply(text, secret: cfg.secret) {
                        await MainActor.run { _ = QuestionController.shared.submitFromPhone(id: pick.id, option: pick.option) }
                        continue
                    }
                    guard let reply = parseReply(text, secret: cfg.secret) else { continue }
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
            answeredByPhone.insert(id.uppercased())
            NSLog("loggdin phone: \(decision.summary) for \(id.prefix(8))")
        }
    }
}
