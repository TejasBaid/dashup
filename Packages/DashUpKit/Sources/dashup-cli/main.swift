import DashUpKit
import Foundation
import Network

// A headless DashUp client for testing the Mac agent without an iPad.
//
//   dashup-cli pair <code>          pair with the agent and store the secret in ~/.dashup-cli-secret
//   dashup-cli watch [topic...]     print state updates as they arrive
//   dashup-cli allow|deny <id>      answer a pending permission request
//   dashup-cli request <json>       send a raw Request, e.g. '{"openURL":{"_0":"https://github.com"}}'

let args = Array(CommandLine.arguments.dropFirst())
let secretURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".dashup-cli-secret")
let queue = DispatchQueue(label: "dashup-cli")
nonisolated(unsafe) var heartbeats: [DispatchSourceTimer] = []

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

/// Resolves the first Bonjour service of `type` on the local machine.
func browse(type: String, handler: @escaping @Sendable (NWEndpoint) -> Void) {
    let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
    browser.browseResultsChangedHandler = { results, _ in
        if let first = results.first {
            browser.cancel()
            handler(first.endpoint)
        }
    }
    browser.start(queue: queue)
}

func pair(code: String) {
    browse(type: DashUpNetwork.pairingServiceType) { endpoint in
        let peer = PeerConnection(connection: NWConnection(to: endpoint, using: DashUpNetwork.parameters(key: DashUpNetwork.pairingKey(code: code))))
        peer.start(queue: queue) { event in
            switch event {
            case .ready:
                peer.send(PairRequest(deviceName: "dashup-cli"))
            case .message(let data):
                guard let response = try? WireCoding.decode(PairResponse.self, from: data) else { fail("bad pairing reply") }
                try? response.secret.base64EncodedString().write(to: secretURL, atomically: true, encoding: .utf8)
                print("Paired with \(response.macName)")
                exit(0)
            case .closed(let reason):
                fail("pairing failed: \(reason ?? "closed")")
            }
        }
    }
}

func connect(onReady: @escaping @Sendable (PeerConnection) -> Void, onMessage: @escaping @Sendable (PeerConnection, ServerMessage) -> Void) {
    guard let text = try? String(contentsOf: secretURL, encoding: .utf8), let secret = Data(base64Encoded: text) else {
        fail("not paired; run `dashup-cli pair <code>` first")
    }
    browse(type: DashUpNetwork.serviceType) { endpoint in
        let peer = PeerConnection(connection: NWConnection(to: endpoint, using: DashUpNetwork.parameters(key: DashUpNetwork.sessionKey(secret: secret))))
        peer.start(queue: queue) { event in
            switch event {
            case .ready:
                peer.send(ClientMessage.hello(Hello(deviceName: "dashup-cli")))
                // Heartbeat, or the Mac drops the connection after 30 seconds.
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + 10, repeating: 10)
                timer.setEventHandler { peer.send(ClientMessage.ping) }
                timer.resume()
                heartbeats.append(timer)
                onReady(peer)
            case .message(let data):
                guard let message = try? WireCoding.decode(ServerMessage.self, from: data) else { return }
                onMessage(peer, message)
            case .closed(let reason):
                fail("disconnected: \(reason ?? "closed")")
            }
        }
    }
}

func summary(_ message: ServerMessage) -> String {
    switch message {
    case .welcome(let w): return "welcome from \(w.macName)"
    case .claude(let s):
        let sessions = s.sessions.map { "  \($0.name) [\($0.phase.rawValue)] \($0.project) — \($0.activity ?? $0.lastMessage?.prefix(60).description ?? "")" }
        let pending = s.pending.map { "  ASK \($0.id) \($0.toolName): \($0.subject)" }
        return (["claude: \(s.sessions.count) sessions, hooks \(s.hooksInstalled ? "on" : "off")"] + sessions + pending).joined(separator: "\n")
    case .apps(let s): return "apps: \(s.running.count) running, \(s.installed.count) installed — " + s.running.map { "\($0.name)\($0.isFront ? "*" : "")\($0.caption.map { " (\($0))" } ?? "")" }.joined(separator: ", ")
    case .chrome(let s): return "chrome: running=\(s.isRunning) tabs=\(s.tabCount) \(s.error ?? "")"
    case .nowPlaying(let s): return "nowPlaying: \(s.state.rawValue) \(s.title ?? "-") — \(s.artist ?? "-")"
    case .pad(let s): return "pad: " + s.pages.map { "\($0.title)(\($0.sections.flatMap(\.items).count))" }.joined(separator: " ")
    case .response(let id, let r): return "response \(id): \(r)"
    }
}

switch args.first {
case "pair":
    guard args.count == 2 else { fail("usage: dashup-cli pair <code>") }
    pair(code: args[1])
case "watch":
    let topics = args.dropFirst().compactMap(Topic.init(rawValue:))
    connect(onReady: { peer in
        peer.send(ClientMessage.subscribe(topics.isEmpty ? Topic.allCases : topics))
    }, onMessage: { _, message in
        print(summary(message))
        fflush(stdout)
    })
case "allow", "deny":
    guard args.count == 2 else { fail("usage: dashup-cli allow|deny <request-id>") }
    let allow = args[0] == "allow"
    connect(onReady: { peer in
        peer.send(ClientMessage.request(id: 1, .permissionDecision(requestID: args[1], allow: allow, reason: allow ? nil : "Denied from dashup-cli")))
    }, onMessage: { _, message in
        if case .response(1, let result) = message { print(result); exit(0) }
    })
case "request":
    guard args.count == 2, let request = try? JSONDecoder().decode(Request.self, from: Data(args[1].utf8)) else { fail("usage: dashup-cli request <json>") }
    connect(onReady: { peer in
        peer.send(ClientMessage.request(id: 1, request))
    }, onMessage: { _, message in
        if case .response(1, let result) = message {
            if case .image(let data) = result { print("image: \(data?.count ?? 0) bytes") } else { print(result) }
            exit(0)
        }
    })
default:
    fail("usage: dashup-cli pair <code> | watch [topics] | allow <id> | deny <id> | request <json>")
}

dispatchMain()
