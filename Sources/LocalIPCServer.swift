import Foundation
import Network

@MainActor
final class LocalIPCServer {
    static let shared = LocalIPCServer()

    private var listener: NWListener?
    private(set) var port: UInt16 = 9191
    private(set) var isRunning: Bool = false

    var onRequestReceived: ((PermissionRequest) async -> Decision)?

    func start(port: UInt16 = 9191) {
        guard !isRunning else { return }
        self.port = port

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("[Sentinel IPC] Server listening on http://127.0.0.1:\(port)")
                    case .failed(let err):
                        print("[Sentinel IPC] Server failed: \(err)")
                        self?.isRunning = false
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

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        readData(from: connection)
    }

    private func readData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
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

        // Handle CORS OPTIONS preflight
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
                "activeGrants": \(grants),
                "savedRules": \(rules)
            }
            """
            sendHTTPResponse(connection: connection, status: "200 OK", json: statusJSON)
            return
        }

        if method == "POST" && path == "/ask" {
            // Find body
            if let bodyRange = raw.range(of: "\r\n\r\n") {
                let bodyString = String(raw[bodyRange.upperBound...])
                guard let bodyData = bodyString.data(using: .utf8) else {
                    sendHTTPResponse(connection: connection, status: "400 Bad Request", json: "{\"error\":\"Invalid body\"}")
                    return
                }

                struct AskPayload: Codable {
                    let title: String?
                    let subtitle: String?
                    let command: String
                    let risk: String?
                    let requestedBy: String?
                    let directory: String?
                    let modifiesFiles: String?
                    let symbol: String?
                    let tool: String?
                }

                if let payload = try? JSONDecoder().decode(AskPayload.self, from: bodyData) {
                    let risk: Risk = {
                        switch payload.risk?.lowercased() {
                        case "high": return .high
                        case "medium": return .medium
                        default: return .low
                        }
                    }()

                    let agentName = payload.requestedBy ?? "CLI"
                    let sub = payload.subtitle ?? (payload.tool != nil ? "\(agentName) • \(payload.tool!)" : nil)
                    let sym = payload.symbol ?? (payload.tool?.contains("File") == true ? "pencil.and.outline" : "terminal")

                    let req = PermissionRequest(
                        title: payload.title,
                        subtitle: sub,
                        symbol: sym,
                        command: payload.command,
                        risk: risk,
                        requestedBy: agentName,
                        directory: payload.directory ?? "~",
                        modifiesFiles: payload.modifiesFiles ?? "Unknown"
                    )

                    Task {
                        let decision = await (self.onRequestReceived?(req) ?? .deny)
                        let decisionJSON: String
                        switch decision {
                        case .allow(let scope):
                            decisionJSON = "{\"allowed\": true, \"decision\": \"allow\", \"scope\": \"\(scope.rawValue)\"}"
                        case .deny:
                            decisionJSON = "{\"allowed\": false, \"decision\": \"deny\"}"
                        case .timeout:
                            decisionJSON = "{\"allowed\": false, \"decision\": \"timeout\"}"
                        }
                        self.sendHTTPResponse(connection: connection, status: "200 OK", json: decisionJSON)
                    }
                    return
                }
            }

            sendHTTPResponse(connection: connection, status: "400 Bad Request", json: "{\"error\":\"Missing or invalid JSON body. Expected {'command': '...'}\"}")
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
}
