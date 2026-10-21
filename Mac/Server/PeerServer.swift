import DashUpKit
import Foundation
import Network

/// Advertises `_dashup._tcp` over Bonjour and serves paired iPads.
///
/// Also runs the pairing listener (`_dashup-pair._tcp`) while a pairing code is showing.
@MainActor
final class PeerServer {
    struct Client {
        let peer: PeerConnection
        var name: String?
        var deviceID: String?
        var topics: Set<Topic> = []
        var lastSeen = Date.now
        /// Older iPad builds don't send heartbeats; only hold newer ones to the silence timeout.
        var sendsPings = false
    }

    var onChange: (() -> Void)?
    /// Returns the current state message for a topic.
    var stateFor: (Topic) -> ServerMessage? = { _ in nil }
    var handleRequest: (Request) async -> Response = { _ in .failed("unavailable") }

    private(set) var clients: [ObjectIdentifier: Client] = [:]
    private(set) var pairingCode: String?
    private(set) var pairingExpires: Date?
    private(set) var listenerError: String?
    private var listener: NWListener?
    private var pairingListener: NWListener?
    private let secret: Data
    let macName: String

    init(secret: Data, macName: String) {
        self.secret = secret
        self.macName = macName
    }

    var connectedNames: [String] { clients.values.compactMap(\.name).sorted() }

    func hasSubscribers(_ topic: Topic) -> Bool {
        clients.values.contains { $0.topics.contains(topic) }
    }

    // MARK: Main listener

    private var sweepTimer: Timer?

    /// Drops clients whose connection died without a close event reaching us: failed connections,
    /// and iPads that have stopped sending heartbeats.
    private func sweep() {
        let dead = clients.filter { id, client in
            !client.peer.isAlive || (client.sendsPings && Date.now.timeIntervalSince(client.lastSeen) > 30)
        }.map(\.key)
        guard !dead.isEmpty else { return }
        for id in dead {
            clients[id]?.peer.cancel()
            clients[id] = nil
        }
        onChange?()
    }

    func start() {
        if sweepTimer == nil {
            sweepTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sweep() }
            }
        }
        do {
            let listener = try NWListener(using: DashUpNetwork.parameters(key: DashUpNetwork.sessionKey(secret: secret)))
            listener.service = NWListener.Service(name: macName, type: DashUpNetwork.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if case .failed(let error) = state {
                        self.listenerError = error.debugDescription
                        self.listener?.cancel()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.start() }
                    } else if case .ready = state {
                        self.listenerError = nil
                    }
                    self.onChange?()
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            listenerError = error.localizedDescription
        }
    }

    private func accept(_ connection: NWConnection) {
        let peer = PeerConnection(connection: connection)
        let id = ObjectIdentifier(peer)
        clients[id] = Client(peer: peer)
        peer.start(queue: .main) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch event {
                case .ready:
                    break
                case .message(let data):
                    guard let message = try? WireCoding.decode(ClientMessage.self, from: data) else { return }
                    self.receive(message, from: id)
                case .closed:
                    self.clients[id] = nil
                    self.onChange?()
                }
            }
        }
    }

    private func receive(_ message: ClientMessage, from id: ObjectIdentifier) {
        guard var client = clients[id] else { return }
        client.lastSeen = .now
        clients[id] = client
        switch message {
        case .ping:
            client.sendsPings = true
            clients[id] = client
        case .hello(let hello):
            client.name = hello.deviceName
            client.deviceID = hello.deviceID
            // The same iPad reconnecting: retire its previous connection.
            if let deviceID = hello.deviceID {
                for (other, existing) in clients where other != id && existing.deviceID == deviceID {
                    existing.peer.cancel()
                    clients[other] = nil
                }
            }
            clients[id] = client
            client.peer.send(ServerMessage.welcome(Welcome(macName: macName)))
            onChange?()
        case .subscribe(let topics):
            client.topics = Set(topics)
            clients[id] = client
            onChange?()
            for topic in topics {
                if let state = stateFor(topic) { client.peer.send(state) }
            }
        case .request(let requestID, let request):
            Task {
                let response = await handleRequest(request)
                clients[id]?.peer.send(ServerMessage.response(id: requestID, response))
            }
        }
    }

    func broadcast(_ topic: Topic) {
        guard let message = stateFor(topic), let data = try? WireCoding.encode(message) else { return }
        for client in clients.values where client.topics.contains(topic) {
            client.peer.send(data)
        }
    }

    // MARK: Pairing

    /// Opens a pairing window. `fixedCode` is for automated testing only.
    func startPairing(fixedCode: String? = nil, duration: TimeInterval = 5 * 60) {
        stopPairing()
        let code = fixedCode ?? String(format: "%06d", Int.random(in: 0...999_999))
        do {
            let listener = try NWListener(using: DashUpNetwork.parameters(key: DashUpNetwork.pairingKey(code: code)))
            listener.service = NWListener.Service(name: macName, type: DashUpNetwork.pairingServiceType)
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.acceptPairing(connection) }
            }
            listener.start(queue: .main)
            pairingListener = listener
            pairingCode = code
            pairingExpires = fixedCode == nil ? .now.addingTimeInterval(duration) : nil
            if fixedCode == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                    MainActor.assumeIsolated {
                        if self?.pairingCode == code { self?.stopPairing() }
                    }
                }
            }
        } catch {
            listenerError = error.localizedDescription
        }
        onChange?()
    }

    func stopPairing() {
        pairingListener?.cancel()
        pairingListener = nil
        pairingCode = nil
        pairingExpires = nil
        onChange?()
    }

    private var pairingPeers: [ObjectIdentifier: PeerConnection] = [:]

    private func acceptPairing(_ connection: NWConnection) {
        let peer = PeerConnection(connection: connection)
        let id = ObjectIdentifier(peer)
        pairingPeers[id] = peer
        peer.start(queue: .main) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch event {
                case .message(let data):
                    guard let request = try? WireCoding.decode(PairRequest.self, from: data) else { return }
                    peer.send(PairResponse(macName: self.macName, secret: self.secret))
                    NSLog("DashUp: paired with \(request.deviceName)")
                    // Leave a fixed (test) code open; close a one-time code after use.
                    if self.pairingExpires != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.stopPairing() }
                    }
                case .closed:
                    self.pairingPeers[id] = nil
                case .ready:
                    break
                }
            }
        }
    }
}
