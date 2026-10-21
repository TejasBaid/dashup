import DashUpKit
import Foundation
import Network

/// The iPad side of the connection: finds the Mac over Bonjour, pairs, connects with the stored
/// secret and reconnects with backoff whenever the link drops.
final class MacLink {
    enum Status: Equatable {
        case unpaired
        case searching
        case connecting
        case connected
    }

    var onStatus: (Status) -> Void = { _ in }
    var onMessage: (ServerMessage) -> Void = { _ in }

    private(set) var status: Status = .unpaired {
        didSet { if status != oldValue { onStatus(status) } }
    }
    private var browser: NWBrowser?
    private var peer: PeerConnection?
    private var retryDelay: TimeInterval = 1
    private var retryWork: DispatchWorkItem?
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<Response, Never>] = [:]
    private var heartbeat: Timer?
    private let deviceName = "iPad"
    private let deviceID: String = {
        if let id = UserDefaults.standard.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "deviceID")
        return id
    }()

    var isPaired: Bool { Keychain.secret != nil }

    // MARK: Connecting

    func start() {
        guard isPaired else { status = .unpaired; return }
        guard status != .connected, status != .connecting, browser == nil else { return }
        status = .searching
        browse(type: DashUpNetwork.serviceType) { [weak self] endpoint in
            self?.connect(to: endpoint)
        }
    }

    func disconnect() {
        retryWork?.cancel()
        browser?.cancel()
        browser = nil
        peer?.cancel()
        peer = nil
    }

    func forget() {
        disconnect()
        Keychain.secret = nil
        UserDefaults.standard.removeObject(forKey: "macName")
        status = .unpaired
    }

    private func browse(type: String, found: @escaping @MainActor (NWEndpoint) -> Void) {
        browser?.cancel()
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: parameters)
        let preferred = UserDefaults.standard.string(forKey: "macName")
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self, self.browser === browser else { return }
                let match = results.first { result in
                    if case .service(let name, _, _, _) = result.endpoint { return name == preferred }
                    return false
                } ?? results.first
                guard let match else { return }
                browser.cancel()
                self.browser = nil
                found(match.endpoint)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                MainActor.assumeIsolated { self?.scheduleRetry() }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func connect(to endpoint: NWEndpoint) {
        guard let secret = Keychain.secret else { status = .unpaired; return }
        status = .connecting
        let peer = PeerConnection(connection: NWConnection(to: endpoint, using: DashUpNetwork.parameters(key: DashUpNetwork.sessionKey(secret: secret))))
        self.peer = peer
        peer.start(queue: .main) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.peer === peer else { return }
                switch event {
                case .ready:
                    self.retryDelay = 1
                    self.status = .connected
                    peer.send(ClientMessage.hello(Hello(deviceName: self.deviceName, deviceID: self.deviceID)))
                    peer.send(ClientMessage.subscribe(Topic.allCases))
                    self.heartbeat?.invalidate()
                    self.heartbeat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self, weak peer] _ in
                        MainActor.assumeIsolated {
                            guard let self, let peer, self.peer === peer else { return }
                            peer.send(ClientMessage.ping)
                        }
                    }
                case .message(let data):
                    guard let message = try? WireCoding.decode(ServerMessage.self, from: data) else { return }
                    if case .response(let id, let response) = message {
                        self.pending.removeValue(forKey: id)?.resume(returning: response)
                    } else {
                        self.onMessage(message)
                    }
                case .closed:
                    self.peer = nil
                    self.failPending()
                    self.scheduleRetry()
                }
            }
        }
    }

    private func scheduleRetry() {
        guard isPaired else { status = .unpaired; return }
        status = .searching
        browser?.cancel()
        browser = nil
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.start() }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: work)
        retryDelay = min(retryDelay * 2, 8)
    }

    /// Reconnect immediately, e.g. when the app returns to the foreground.
    func reconnectNow() {
        // Leave a connection that's already being set up alone; only retry a stalled search.
        guard isPaired, status != .connected, status != .connecting else { return }
        retryWork?.cancel()
        browser?.cancel()
        browser = nil
        peer?.cancel()
        peer = nil
        retryDelay = 1
        status = .searching
        start()
    }

    // MARK: Requests

    func send(_ request: Request) async -> Response {
        guard let peer, status == .connected else { return .failed("Not connected to your Mac") }
        let id = nextRequestID
        nextRequestID += 1
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            peer.send(ClientMessage.request(id: id, request))
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                self?.pending.removeValue(forKey: id)?.resume(returning: .failed("Your Mac didn't respond"))
            }
        }
    }

    private func failPending() {
        let waiting = pending
        pending.removeAll()
        waiting.values.forEach { $0.resume(returning: .failed("Lost the connection to your Mac")) }
    }

    // MARK: Pairing

    enum PairingResult { case paired(String), wrongCode, noMac }

    /// Finds a Mac showing a pairing code and exchanges the code for the long-lived secret.
    func pair(code: String) async -> PairingResult {
        disconnect()
        return await withCheckedContinuation { continuation in
            let done = Flag()
            let finish: @MainActor (PairingResult) -> Void = { result in
                guard !done.value else { return }
                done.value = true
                continuation.resume(returning: result)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                self?.browser?.cancel()
                self?.browser = nil
                finish(.noMac)
            }
            browse(type: DashUpNetwork.pairingServiceType) { endpoint in
                let peer = PeerConnection(connection: NWConnection(to: endpoint, using: DashUpNetwork.parameters(key: DashUpNetwork.pairingKey(code: code))))
                peer.start(queue: .main) { [weak self] event in
                    MainActor.assumeIsolated {
                        switch event {
                        case .ready:
                            peer.send(PairRequest(deviceName: self?.deviceName ?? "iPad"))
                        case .message(let data):
                            guard let response = try? WireCoding.decode(PairResponse.self, from: data) else { return finish(.wrongCode) }
                            Keychain.secret = response.secret
                            UserDefaults.standard.set(response.macName, forKey: "macName")
                            peer.cancel()
                            finish(.paired(response.macName))
                        case .closed:
                            finish(.wrongCode)
                        }
                    }
                }
            }
        }
    }
}

@MainActor
private final class Flag {
    var value = false
}

enum Keychain {
    private static let service = "com.tejasbaid.dashup"
    private static let account = "mac-secret"

    static var secret: Data? {
        get {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecAttrAccount as String: account, kSecReturnData as String: true]
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
            return result as? Data
        }
        set {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecAttrAccount as String: account]
            SecItemDelete(query as CFDictionary)
            guard let newValue else { return }
            var add = query
            add[kSecValueData as String] = newValue
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
