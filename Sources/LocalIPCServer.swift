import Foundation
import Network

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

    func start(port: UInt16 = 9191) {
        guard !isRunning else { return }
        self.port = port
        startHTTPServer(port: port)
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

    private func readData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            Task { @MainActor in
                guard let self, let data = data, !data.isEmpty else {
                    if isComplete { connection.cancel() }
                    return
                }

                guard let requestString = String(data: data, encoding: .utf8) else {
                    self.sendHTTPResponse(connection: connection, status: "400 Bad Request", json: "{\"error\":\"Invalid UTF-8\"}")
                    return
                }

                self.processHTTPRequest(requestString, connection: connection)
            }
        }
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

        if method == "OPTIONS" {
            sendHTTPResponse(connection: connection, status: "204 No Content", json: "")
            return
        }

        if method == "GET" && path == "/status" {
            let grants = RulesEngine.shared.activeGrants.count
            let rules = RulesEngine.shared.storedRules.count
            let statusJSON = """
            {
                "status": "active",
                "port": \(self.port),
                "socket": "\(self.socketPath)",
                "activeGrants": \(grants),
                "savedRules": \(rules)
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
                if path.contains("scope=10m") { scopeStr = "10m" }
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
                let scope: AllowScope
                switch scopeStr {
                case "10m", "tenminutes", "10_minutes":
                    scope = .tenMinutes
                case "always":
                    scope = .always
                default:
                    scope = .once
                }
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
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        response += "Access-Control-Allow-Headers: Content-Type\r\n"
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
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
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

        let thread = Thread { [weak self] in
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

                Task { @MainActor in
                    self?.handleUnixClient(clientFD)
                }
            }
        }
        thread.name = "AgentSentinel.UnixSocket"
        thread.start()
        unixSocketThread = thread
        print("[Sentinel IPC] Unix socket listening on \(path)")
    }

    private func handleUnixClient(_ fd: Int32) {
        var raw = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            for i in 0..<n {
                if buf[i] == UInt8(ascii: "\n") { break }
                raw.append(buf[i])
            }
            if raw.count > 65536 || buf.contains(UInt8(ascii: "\n")) { break }
        }

        guard !raw.isEmpty, let bodyString = String(data: raw, encoding: .utf8) else {
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
