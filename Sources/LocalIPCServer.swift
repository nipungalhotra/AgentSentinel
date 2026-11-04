import Foundation
import Network
import CryptoKit

@MainActor
final class LocalIPCServer {
    static let shared = LocalIPCServer()

    private var listener: NWListener?
    private(set) var port: UInt16 = 9191
    private(set) var isRunning: Bool = false
    private var unixSocketFD: Int32 = -1
    private var unixSocketThread: Thread?

    var onRequestReceived: ((PermissionRequest) async -> Decision)?

    var socketPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AgentSentinel", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("sentinel.sock").path
    }

    var tokenPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AgentSentinel", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("token").path
    }

    private(set) var authToken: String = ""

    func initializeAuthToken() {
        let path = tokenPath
        if let existing = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            self.authToken = existing
        } else {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let newToken = bytes.map { String(format: "%02x", $0) }.joined()
            try? newToken.write(toFile: path, atomically: true, encoding: .utf8)
            chmod(path, 0o600)
            self.authToken = newToken
        }

        // Mirror token to ~/.loggdin/token with strict 0600 permissions
        let dotLoggdin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".loggdin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dotLoggdin, withIntermediateDirectories: true)
        let dotToken = dotLoggdin.appendingPathComponent("token").path
        try? self.authToken.write(toFile: dotToken, atomically: true, encoding: .utf8)
        chmod(dotToken, 0o600)
    }

    private func isAuthorized(headers: [String: String], path: String, bodyString: String?) -> Bool {
        guard !authToken.isEmpty else { return true }
        if let headerToken = headers["x-loggdin-token"] ?? headers["x-sentinel-token"], headerToken == authToken {
            return true
        }
        if let authHeader = headers["authorization"], authHeader.hasPrefix("Bearer ") {
            let token = String(authHeader.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            if token == authToken { return true }
        }
        if path.contains("token=\(authToken)") {
            return true
        }
        if let body = bodyString, let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let bodyToken = json["token"] as? String, bodyToken == authToken {
            return true
        }
        return false
    }

    func savePortFile(_ port: UInt16) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AgentSentinel", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let portPath = appSupport.appendingPathComponent("port").path
        try? "\(port)".write(toFile: portPath, atomically: true, encoding: .utf8)
        chmod(portPath, 0o600)

        let dotLoggdin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".loggdin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dotLoggdin, withIntermediateDirectories: true)
        let dotPort = dotLoggdin.appendingPathComponent("port").path
        try? "\(port)".write(toFile: dotPort, atomically: true, encoding: .utf8)
        chmod(dotPort, 0o600)
    }

    func start(port: UInt16? = nil) {
        guard !isRunning else { return }
        
        var selectedPort: UInt16 = 9191
        if let explicit = port {
            selectedPort = explicit
        } else if let envPortStr = ProcessInfo.processInfo.environment["LOGGDIN_PORT"] ?? ProcessInfo.processInfo.environment["SENTINEL_PORT"],
                  let envPort = UInt16(envPortStr), envPort > 0 {
            selectedPort = envPort
        }

        self.port = selectedPort
        initializeAuthToken()
        savePortFile(selectedPort)
        startHTTPServer(port: selectedPort)
        startUnixSocketServer()
        isRunning = true
    }

    func stop() {
        listener?.cancel()
        listener = nil

        if unixSocketFD >= 0 {
            Darwin.close(unixSocketFD)
            unixSocketFD = -1
        }
        unlink(socketPath)
        isRunning = false
    }

    // MARK: - HTTP Server (NWListener)

    private func startHTTPServer(port: UInt16) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // HARDENED SECURITY: Restrict listener strictly to loopback interface (127.0.0.1).
            // Rejects all external incoming connections from Wi-Fi, LAN, Ethernet, or remote scanners at the kernel level.
            params.requiredInterfaceType = .loopback
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener.stateUpdateHandler = { state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        print("[Sentinel IPC] HTTP server listening on http://127.0.0.1:\(port)")
                    case .failed(let err):
                        print("[Sentinel IPC] HTTP server failed: \(err)")
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in
                    self?.handleConnection(conn)
                }
            }

            listener.start(queue: .main)
            self.listener = listener
        } catch {
            print("[Sentinel IPC] Failed to bind port \(port): \(error)")
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        readData(from: connection)
    }

    private func readData(from connection: NWConnection, buffer: Data = Data()) {
        // Accumulate until the headers and the full Content-Length body have arrived (a single
        // receive used to cap requests at 64 KB, truncating large permission requests).
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var buf = buffer
                if let data { buf.append(data) }

                if buf.count > 2_000_000 {
                    self.sendHTTPResponse(connection: connection, status: "413 Payload Too Large", json: "{\"error\":\"Request too large\"}")
                    return
                }
                if !LocalIPCServer.isCompleteHTTPRequest(buf) && !isComplete && error == nil {
                    self.readData(from: connection, buffer: buf)
                    return
                }
                guard !buf.isEmpty else {
                    connection.cancel()
                    return
                }
                guard let requestString = String(data: buf, encoding: .utf8) else {
                    self.sendHTTPResponse(connection: connection, status: "400 Bad Request", json: "{\"error\":\"Invalid UTF-8\"}")
                    return
                }
                self.processHTTPRequest(requestString, connection: connection)
            }
        }
    }

    /// True once `data` holds the complete header block plus `Content-Length` bytes of body.
    nonisolated static func isCompleteHTTPRequest(_ data: Data) -> Bool {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else { return false }
        let headerText = String(decoding: data[data.startIndex..<range.lowerBound], as: UTF8.self)
        var contentLength = 0
        for line in headerText.components(separatedBy: "\r\n") {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return data.count - range.upperBound >= contentLength
    }

    private func processHTTPRequest(_ raw: String, connection: NWConnection) {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", json: "{\"error\":\"Empty request\"}")
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", json: "{\"error\":\"Malformed request\"}")
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let kv = line.split(separator: ":", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                headers[kv[0].trimmingCharacters(in: .whitespaces).lowercased()] = kv[1].trimmingCharacters(in: .whitespaces)
            }
        }

        // 1. HARDENED SECURITY: DNS Rebinding Protection
        // Validate Host header: must strictly resolve to 127.0.0.1 or localhost
        if let hostHeader = headers["host"] {
            let hostPart = hostHeader.split(separator: ":").first.map(String.init)?.lowercased() ?? hostHeader.lowercased()
            if hostPart != "127.0.0.1" && hostPart != "localhost" {
                sendHTTPResponse(connection: connection, status: "403 Forbidden", json: "{\"error\":\"Forbidden: Invalid Host header (DNS rebinding rejected)\"}")
                return
            }
        }

        // 2. HARDENED SECURITY: Web-to-Localhost & Cross-Origin Request Forgery (CSRF) Protection
        // Block any browser-originated requests with external Origin or Referer
        if let origin = headers["origin"], !origin.isEmpty {
            if !origin.hasPrefix("http://127.0.0.1") && !origin.hasPrefix("http://localhost") {
                sendHTTPResponse(connection: connection, status: "403 Forbidden", json: "{\"error\":\"Forbidden: Cross-origin browser request rejected\"}")
                return
            }
        }
        if let referer = headers["referer"], !referer.isEmpty {
            if !referer.hasPrefix("http://127.0.0.1") && !referer.hasPrefix("http://localhost") {
                sendHTTPResponse(connection: connection, status: "403 Forbidden", json: "{\"error\":\"Forbidden: Cross-origin browser referer rejected\"}")
                return
            }
        }

        // Reject all cross-origin preflight requests
        if method == "OPTIONS" {
            sendHTTPResponse(connection: connection, status: "403 Forbidden", json: "{\"error\":\"Preflight rejected\"}")
            return
        }

        let bodyString: String? = {
            if let bodyRange = raw.range(of: "\r\n\r\n") {
                return String(raw[bodyRange.upperBound...])
            }
            return nil
        }()

        // 3. HARDENED SECURITY: Token Authorization for State-Modifying Endpoints
        let requiresAuth = path.hasPrefix("/decision") || path.hasPrefix("/allow") || path.hasPrefix("/deny") ||
                           path.hasPrefix("/sound") || path == "/ask" || path == "/hook"
        if requiresAuth && !isAuthorized(headers: headers, path: path, bodyString: bodyString) {
            sendHTTPResponse(connection: connection, status: "401 Unauthorized", json: "{\"error\":\"Unauthorized: Valid token required in X-Loggdin-Token or Authorization header\"}")
            return
        }

        if method == "GET" && (path == "/status" || path.hasPrefix("/status?")) {
            let grants = RulesEngine.shared.activeGrants.count
            let rules = RulesEngine.shared.storedRules.count
            // Identity proof: clients send a random challenge and only send their token if we can
            // HMAC it with the token, so a process squatting this port cannot harvest tokens.
            var proofField = ""
            if let q = URLComponents(string: "http://localhost" + path)?.queryItems,
               let challenge = q.first(where: { $0.name == "challenge" })?.value,
               (16...128).contains(challenge.count), !authToken.isEmpty {
                let mac = HMAC<SHA256>.authenticationCode(for: Data(("loggdin-status:" + challenge).utf8),
                                                          using: SymmetricKey(data: Data(authToken.utf8)))
                proofField = ",\n    \"proof\": \"" + mac.map { String(format: "%02x", $0) }.joined() + "\""
            }
            let statusJSON = """
            {
                "status": "active",
                "port": \(self.port),
                "socket": "\(self.socketPath)",
                "activeGrants": \(grants),
                "savedRules": \(rules)\(proofField)
            }
            """
            sendHTTPResponse(connection: connection, status: "200 OK", json: statusJSON)
            return
        }

        if method == "GET" && path == "/audit/verify" {
            let res = RulesEngine.shared.verifyChainIntegrity()
            let brokenStr = res.brokenIndex != nil ? "\(res.brokenIndex!)" : "null"
            let json = """
            {
                "isValid": \(res.isValid),
                "totalEntries": \(res.totalEntries),
                "brokenIndex": \(brokenStr),
                "algorithm": "SHA-256 Merkle Chain",
                "message": "\(res.message)"
            }
            """
            sendHTTPResponse(connection: connection, status: "200 OK", json: json)
            return
        }

        if method == "GET" && path.hasPrefix("/audit/export") {
            if path.contains("format=csv") {
                let csv = RulesEngine.shared.exportAuditLogCSV()
                sendRawHTTPResponse(connection: connection, status: "200 OK", contentType: "text/csv; charset=utf-8", body: csv)
            } else {
                let json = RulesEngine.shared.exportAuditLogJSON()
                sendHTTPResponse(connection: connection, status: "200 OK", json: json)
            }
            return
        }

        // Apple Shortcuts & CLI Integration: Check pending permissions (Strictly Loopback 127.0.0.1)
        if method == "GET" && path == "/pending" {
            if let req = PermissionPopupController.shared.currentPendingRequest() {
                let json = """
                {
                    "hasPending": true,
                    "id": "\(req.id.uuidString)",
                    "title": "\(req.title.replacingOccurrences(of: "\"", with: "\\\""))",
                    "subtitle": "\(req.subtitle.replacingOccurrences(of: "\"", with: "\\\""))",
                    "command": "\(req.plainCommand.replacingOccurrences(of: "\"", with: "\\\""))",
                    "risk": "\(req.risk.rawValue)",
                    "requestedBy": "\(req.requestedBy.replacingOccurrences(of: "\"", with: "\\\""))"
                }
                """
                sendHTTPResponse(connection: connection, status: "200 OK", json: json)
            } else {
                sendHTTPResponse(connection: connection, status: "200 OK", json: "{\"hasPending\": false, \"message\": \"No pending permissions\"}")
            }
            return
        }

        // Apple Shortcuts & CLI Integration: Submit decision (Strictly Loopback 127.0.0.1)
        if (method == "POST" || method == "GET") && (path.hasPrefix("/decision") || path.hasPrefix("/allow") || path.hasPrefix("/deny")) {
            var decStr = "allow"
            var scopeStr = "once"
            var reqId: String? = nil

            if path.hasPrefix("/deny") {
                decStr = "deny"
            } else if path.hasPrefix("/allow") {
                decStr = "allow"
                if path.contains("scope=10m-all") { scopeStr = "10m-all" }
                else if path.contains("scope=10m") { scopeStr = "10m" }
                else if path.contains("scope=always") { scopeStr = "always" }
            }

            if let bodyRange = raw.range(of: "\r\n\r\n") {
                let bodyString = String(raw[bodyRange.upperBound...])
                if let data = bodyString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let d = json["decision"] as? String { decStr = d.lowercased() }
                    if let s = json["scope"] as? String { scopeStr = s.lowercased() }
                    if let r = json["requestId"] as? String { reqId = r }
                }
            }

            let decision: Decision
            if decStr == "allow" {
                let scope = AllowScope.parse(scopeStr)
                decision = .allow(scope)
            } else {
                decision = .deny
            }

            let handled = PermissionPopupController.shared.submitExternalDecision(decision, forRequestId: reqId)
            let resp = "{\"success\": \(handled), \"decision\": \"\(decStr)\", \"scope\": \"\(scopeStr)\"}"
            sendHTTPResponse(connection: connection, status: "200 OK", json: resp)
            return
        }

        // Sound Preferences: Query or set notification sound
        if path.hasPrefix("/sound") {
            if method == "POST" {
                if let bodyRange = raw.range(of: "\r\n\r\n") {
                    let bodyString = String(raw[bodyRange.upperBound...])
                    if let data = bodyString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let sound = json["sound"] as? String {
                        SoundEngine.shared.popupSoundName = sound
                        SoundEngine.shared.playPopup()
                    }
                }
            }
            let cur = SoundEngine.shared.popupSoundName
            sendHTTPResponse(connection: connection, status: "200 OK", json: "{\"currentSound\": \"\(cur)\", \"available\": [\"Glass\", \"Ping\", \"Bottle\", \"Pop\", \"Hero\", \"Morse\", \"Purr\"]}")
            return
        }

        if method == "POST" && (path == "/ask" || path == "/hook") {
            if let bodyRange = raw.range(of: "\r\n\r\n") {
                let bodyString = String(raw[bodyRange.upperBound...])
                if let req = parseRequest(from: bodyString) {
                    Task {
                        let decision = await (self.onRequestReceived?(req) ?? .deny)
                        let decisionJSON = self.makeDecisionJSON(decision)
                        self.sendHTTPResponse(connection: connection, status: "200 OK", json: decisionJSON)
                    }
                    return
                }
            }

            sendHTTPResponse(connection: connection, status: "400 Bad Request", json: "{\"error\":\"Missing or invalid JSON body\"}")
            return
        }

        sendHTTPResponse(connection: connection, status: "404 Not Found", json: "{\"error\":\"Unknown route\"}")
    }

    private func sendHTTPResponse(connection: NWConnection, status: String, json: String) {
        let bodyData = json.data(using: .utf8) ?? Data()
        var response = "HTTP/1.1 \(status)\r\n"
        response += "Content-Type: application/json; charset=utf-8\r\n"
        response += "Content-Length: \(bodyData.count)\r\n"
        response += "Content-Security-Policy: default-src 'none'\r\n"
        response += "X-Content-Type-Options: nosniff\r\n"
        response += "X-Frame-Options: DENY\r\n"
        response += "Connection: close\r\n\r\n"

        var responseData = response.data(using: .utf8) ?? Data()
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func sendRawHTTPResponse(connection: NWConnection, status: String, contentType: String, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        var response = "HTTP/1.1 \(status)\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(bodyData.count)\r\n"
        response += "Content-Security-Policy: default-src 'none'\r\n"
        response += "X-Content-Type-Options: nosniff\r\n"
        response += "X-Frame-Options: DENY\r\n"
        response += "Connection: close\r\n\r\n"

        var responseData = response.data(using: .utf8) ?? Data()
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    // MARK: - Unix Socket Server

    private func startUnixSocketServer() {
        let path = socketPath
        unlink(path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        unixSocketFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cpath = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, c) in cpath.enumerated() where i < raw.count {
                raw[i] = UInt8(bitPattern: c)
            }
        }

        let bindRC = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindRC == 0 else {
            Darwin.close(fd)
            return
        }

        chmod(path, 0o600)
        guard Darwin.listen(fd, 32) == 0 else {
            Darwin.close(fd)
            return
        }

        // The accept loop runs off the main actor; hand each client to the main-actor singleton
        // instead of capturing `self` across threads (Swift 6 region isolation rejects that).
        let thread = Thread {
            while true {
                let clientFD = Darwin.accept(fd, nil, nil)
                guard clientFD >= 0 else { break }

                // Same user validation
                var euid: uid_t = 0
                var egid: gid_t = 0
                guard getpeereid(clientFD, &euid, &egid) == 0, euid == getuid() else {
                    Darwin.close(clientFD)
                    continue
                }

                // Read on this background thread (blocking recv must never run on the main actor),
                // then hand the finished line to the main actor.
                let line = LocalIPCServer.readLine(from: clientFD)
                Task { @MainActor in
                    LocalIPCServer.shared.handleUnixClient(clientFD, line: line)
                }
            }
        }
        thread.name = "AgentSentinel.UnixSocket"
        thread.start()
        unixSocketThread = thread
        print("[Sentinel IPC] Unix socket listening on \(path)")
    }

    /// Reads one newline-terminated message (max 2 MB) from a connected client.
    nonisolated private static func readLine(from fd: Int32) -> Data {
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var raw = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while raw.count <= 2_000_000 {
            let n = Darwin.recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            if let nl = buf[0..<n].firstIndex(of: UInt8(ascii: "\n")) {
                raw.append(contentsOf: buf[0..<nl])
                break
            }
            raw.append(contentsOf: buf[0..<n])
        }
        return raw
    }

    private func handleUnixClient(_ fd: Int32, line raw: Data) {
        guard !raw.isEmpty, let bodyString = String(data: raw, encoding: .utf8) else {
            Darwin.close(fd)
            return
        }

        // Activity notifications from sentinel-hook (SessionStart, PostToolUse, Stop, ...) carry an
        // "event" key and no "risk". They are not permission requests: acknowledge immediately
        // instead of queueing a popup and making the agent wait on the hook's socket timeout.
        if let data = bodyString.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           obj["event"] != nil, obj["risk"] == nil {
            let ok = "{\"ok\":true}\n"
            _ = ok.withCString { Darwin.send(fd, $0, strlen($0), 0) }
            Darwin.close(fd)
            return
        }

        Task { @MainActor in
            if let req = self.parseRequest(from: bodyString) {
                let decision = await (self.onRequestReceived?(req) ?? .deny)
                let decisionJSON = self.makeDecisionJSON(decision) + "\n"
                let data = decisionJSON.data(using: .utf8) ?? Data()
                data.withUnsafeBytes { ptr in
                    _ = Darwin.send(fd, ptr.baseAddress, data.count, 0)
                }
            } else {
                let okJSON = "{\"ok\":true}\n"
                let data = okJSON.data(using: .utf8) ?? Data()
                data.withUnsafeBytes { ptr in
                    _ = Darwin.send(fd, ptr.baseAddress, data.count, 0)
                }
            }
            Darwin.close(fd)
        }
    }

    // MARK: - Parsing Helpers

    private func parseRequest(from jsonString: String) -> PermissionRequest? {
        guard let data = jsonString.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let cmd = (json["command"] as? String)
            ?? (json["tool_input"] as? [String: Any])?["command"] as? String
            ?? (json["tool_input"] as? [String: Any])?["CommandLine"] as? String
            ?? json["tool"] as? String
            ?? "Execute Tool"

        let agent = (json["requestedBy"] as? String) ?? (json["agent"] as? String) ?? "CLI"
        let pill = PillCatalog.definition(for: agent)

        let riskStr = (json["risk"] as? String)?.lowercased()
        let risk: Risk = {
            if riskStr == "high" { return .high }
            if riskStr == "medium" { return .medium }
            return .low
        }()

        let title = (json["title"] as? String) ?? "\(pill.name) Permission"
        let subtitle = (json["subtitle"] as? String) ?? "\(pill.name) • \(json["tool"] as? String ?? "Tool")"
        let symbol = (json["symbol"] as? String) ?? pill.iconSystemName
        let dir = (json["directory"] as? String) ?? (json["cwd"] as? String) ?? "~"
        let mod = (json["modifiesFiles"] as? String) ?? "Workspace"
        let secrets = (json["secretWarnings"] as? [String]) ?? []
        let diff = json["diffPreview"] as? String
        let blast = json["blastRadius"] as? String

        return PermissionRequest(
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            command: cmd,
            risk: risk,
            requestedBy: pill.name,
            directory: dir,
            modifiesFiles: mod,
            secretWarnings: secrets.isEmpty ? nil : secrets,
            diffPreview: diff,
            blastRadius: blast
        )
    }

    private func makeDecisionJSON(_ decision: Decision) -> String {
        switch decision {
        case .allow(let scope):
            return "{\"allowed\": true, \"decision\": \"allow\", \"scope\": \"\(scope.rawValue)\"}"
        case .deny:
            return "{\"allowed\": false, \"decision\": \"deny\"}"
        case .timeout:
            return "{\"allowed\": false, \"decision\": \"timeout\"}"
        }
    }
}
