import DashUpKit
import Foundation
import Network

/// A minimal HTTP/1.1 server on 127.0.0.1 that receives Claude Code HTTP hooks.
///
/// - `POST /hooks/event`: lifecycle and tool events; answered immediately.
/// - `POST /hooks/permission`: `PermissionRequest`; held open until the iPad decides or the timeout
///   passes. Answering `{}` lets Claude Code fall back to its normal terminal prompt.
@MainActor
final class HookServer {
    private var listener: NWListener?
    private let claude: ClaudeProvider
    private let token: String
    /// Names of connected iPads, reported by /health for scripts and tests.
    var connectedClients: () -> [String] = { [] }
    private(set) var isRunning = false
    var onStateChange: (() -> Void)?

    init(claude: ClaudeProvider, token: String) {
        self.claude = claude
        self.token = token
    }

    func start() {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: NWEndpoint.Port(rawValue: DashUpNetwork.hookPort)!) else {
            NSLog("DashUp: could not create hook listener")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready: self.isRunning = true
                case .failed(let error):
                    NSLog("DashUp: hook listener failed: \(error)")
                    self.isRunning = false
                    // Port busy (another agent instance?) — retry shortly.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.start() }
                default: break
                }
                self.onStateChange?()
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if let request = HTTPRequest(buffer) {
                    self.route(request, on: connection)
                } else if isComplete || error != nil || buffer.count > 4 * 1024 * 1024 {
                    connection.cancel()
                } else {
                    self.read(connection, buffer: buffer)
                }
            }
        }
    }

    private func route(_ request: HTTPRequest, on connection: NWConnection) {
        guard request.headers["authorization"] == "Bearer \(token)" else {
            return respond(connection, status: "401 Unauthorized", body: #"{"error":"bad token"}"#)
        }
        let payload = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        switch (request.method, request.path) {
        case ("POST", "/hooks/event"):
            claude.handleHook(payload)
            respond(connection, body: "{}")
        case ("POST", "/hooks/permission"):
            let sessionID = payload["session_id"] as? String ?? ""
            // If Claude Code gives up on the request (user answered in the terminal, or interrupted),
            // drop the card from the iPad.
            connection.stateUpdateHandler = { [weak self] state in
                if case .cancelled = state { return }
                if case .failed = state { MainActor.assumeIsolated { self?.claude.cancelAsk(matching: sessionID) } }
            }
            Task {
                let decision = await claude.requestPermission(payload)
                respond(connection, body: Self.body(for: decision))
            }
        case ("GET", "/health"):
            let body = (try? JSONSerialization.data(withJSONObject: ["ok": true, "clients": connectedClients()])) ?? Data()
            respond(connection, body: String(decoding: body, as: UTF8.self))
        default:
            respond(connection, status: "404 Not Found", body: "{}")
        }
    }

    static func body(for decision: ClaudeProvider.PermissionDecision) -> String {
        let object: [String: Any]
        switch decision {
        case .passThrough:
            object = [:]
        case .allow:
            object = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow"]]]
        case .deny(let reason):
            object = ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                             "decision": ["behavior": "deny", "message": reason, "reason": reason]]]
        }
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func respond(_ connection: NWConnection, status: String = "200 OK", body: String) {
        let bodyData = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + bodyData, completion: .contentProcessed { _ in connection.cancel() })
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// Parses a complete request from `data`, or returns nil if more bytes are needed.
    init?(_ data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return nil }
        method = String(requestLine[0])
        path = String(requestLine[1].split(separator: "?").first ?? "")
        self.headers = headers
        body = data.subdata(in: bodyStart..<(bodyStart + length))
    }
}
