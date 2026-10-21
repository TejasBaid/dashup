import Foundation
import Network
import Testing
@testable import DashUpKit

@Suite struct WireTests {
    @Test func clientMessagesRoundTrip() throws {
        let messages: [ClientMessage] = [
            .hello(Hello(deviceName: "iPad")),
            .subscribe(Topic.allCases),
            .request(id: 7, .permissionDecision(requestID: "abc", allow: true, reason: nil)),
            .request(id: 8, .media(.seek(42.5))),
            .request(id: 9, .focusTab(windowID: 1, tabID: 22)),
        ]
        for message in messages {
            let data = try WireCoding.encode(message)
            #expect(try WireCoding.decode(ClientMessage.self, from: data) == message)
        }
    }

    @Test func serverStateRoundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_791_899_195)
        let session = ClaudeSession(
            id: "s1", pid: 42, name: "medan-6c", cwd: "/tmp", project: "DashUp / medan", isConductor: true,
            phase: .needsApproval, phaseSince: date, startedAt: date,
            timeline: [TimelineItem(id: "t", kind: .tool, date: date, text: "Ran", detail: "swift test", toolName: "Bash")])
        let ask = PermissionAsk(id: "p", sessionID: "s1", toolName: "Bash", subject: "xcodebuild", cwd: "/tmp",
                                createdAt: date, expiresAt: date.addingTimeInterval(45))
        let message = ServerMessage.claude(ClaudeState(sessions: [session], pending: [ask], hooksInstalled: true))
        let data = try WireCoding.encode(message)
        #expect(try WireCoding.decode(ServerMessage.self, from: data) == message)
    }

    @Test func keysAreDeterministicAndDistinct() {
        #expect(DashUpNetwork.pairingKey(code: "123456") == DashUpNetwork.pairingKey(code: "123456"))
        #expect(DashUpNetwork.pairingKey(code: "123456") != DashUpNetwork.pairingKey(code: "123457"))
        let secret = DashUpNetwork.newSecret()
        #expect(secret.count == 32)
        #expect(DashUpNetwork.sessionKey(secret: secret) != secret)
    }

    @Test func formatting() {
        #expect(Format.clock(42) == "0:42")
        #expect(Format.clock(3789) == "1:03:09")
        #expect(Format.tokens(182_400) == "182k")
        #expect(Format.tokens(1_234_567) == "1.2M")
        #expect(Format.shortDuration(130) == "2m")
    }
}

/// Starts a PSK listener on localhost and connects to it.
@Suite(.serialized) struct TransportTests {
    private func roundTrip(serverKey: Data, clientKey: Data) async throws -> String? {
        let queue = DispatchQueue(label: "test")
        let listener = try NWListener(using: DashUpNetwork.parameters(key: serverKey), on: .any)
        let box = ResultBox()

        listener.newConnectionHandler = { connection in
            let peer = PeerConnection(connection: connection)
            box.retain(peer)
            peer.start(queue: queue) { event in
                if case .message(let data) = event {
                    let text = String(decoding: data, as: UTF8.self)
                    peer.send(Data("echo:\(text)".utf8))
                }
            }
        }
        let port = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume(returning: listener.port!.rawValue)
                case .failed(let error): cont.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        defer { listener.cancel() }

        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!,
                                      using: DashUpNetwork.parameters(key: clientKey))
        let client = PeerConnection(connection: connection)
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let once = Once()
            client.start(queue: queue) { event in
                switch event {
                case .ready: client.send(Data("hi".utf8))
                case .message(let data):
                    once.run { cont.resume(returning: String(decoding: data, as: UTF8.self)) }
                    client.cancel()
                case .closed: once.run { cont.resume(returning: nil) }
                }
            }
            queue.asyncAfter(deadline: .now() + 5) { once.run { cont.resume(returning: nil) }; client.cancel() }
        }
    }

    @Test func pskConnectionEchoes() async throws {
        let key = DashUpNetwork.sessionKey(secret: DashUpNetwork.newSecret())
        #expect(try await roundTrip(serverKey: key, clientKey: key) == "echo:hi")
    }

    @Test func wrongKeyIsRejected() async throws {
        let server = DashUpNetwork.pairingKey(code: "111111")
        let client = DashUpNetwork.pairingKey(code: "222222")
        #expect(try await roundTrip(serverKey: server, clientKey: client) == nil)
    }
}

private final class ResultBox: @unchecked Sendable {
    private var peers: [PeerConnection] = []
    private let lock = NSLock()
    func retain(_ peer: PeerConnection) { lock.withLock { peers.append(peer) } }
}

private final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func run(_ body: () -> Void) {
        let shouldRun = lock.withLock { () -> Bool in
            if done { return false }
            done = true
            return true
        }
        if shouldRun { body() }
    }
}
