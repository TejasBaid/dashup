import CryptoKit
import Foundation
import Network

/// Network configuration shared by the Mac agent and the iPad app.
///
/// Every connection is TLS with a pre-shared key, so only devices holding the key can connect and
/// all traffic is encrypted. Pairing uses a key derived from a 6-digit code shown on the Mac; the
/// pairing channel hands the iPad the long-lived secret used for normal connections.
public enum DashUpNetwork {
    public static let serviceType = "_dashup._tcp"
    public static let pairingServiceType = "_dashup-pair._tcp"
    public static let hookPort: UInt16 = 47823

    public static func sessionKey(secret: Data) -> Data {
        derive(key: secret, label: "DashUp session v1")
    }

    public static func pairingKey(code: String) -> Data {
        derive(key: Data(code.utf8), label: "DashUp pairing v1")
    }

    public static func newSecret() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func parameters(key: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let identity = Data("dashup".utf8)
        let keyData = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = identity.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(
            tls.securityProtocolOptions, keyData as __DispatchData, identityData as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(
            tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        // Network.framework only negotiates external PSKs up to TLS 1.2.
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        let tcp = NWProtocolTCP.Options()
        // Notice a vanished peer within ~25s so stale iPads don't hold permission requests.
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        tcp.noDelay = true

        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    private static func derive(key: Data, label: String) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(label.utf8), using: SymmetricKey(data: key))
        return Data(mac)
    }
}

/// A message stream over an `NWConnection`: each message is a 4-byte big-endian length followed
/// by a JSON body. All callbacks run on the queue passed to `start`.
public final class PeerConnection: @unchecked Sendable {
    public enum Event: Sendable {
        case ready
        case message(Data)
        case closed(String?)
    }

    public let connection: NWConnection
    private var handler: (@Sendable (Event) -> Void)?
    private var isClosed = false
    private static let maxMessageSize = 32 * 1024 * 1024

    public init(connection: NWConnection) {
        self.connection = connection
    }

    public func start(queue: DispatchQueue, handler: @escaping @Sendable (Event) -> Void) {
        self.handler = handler
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.handler?(.ready)
                self.receiveHeader()
            case .failed(let error):
                self.finish(error.debugDescription)
            case .waiting(let error):
                // A TLS failure (wrong key) surfaces as waiting; treat it as fatal so callers retry.
                self.finish(error.debugDescription)
            case .cancelled:
                self.finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    public func send(_ data: Data) {
        var length = UInt32(data.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(data)
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            if let error { self?.finish(error.debugDescription) }
        })
    }

    public func send<T: Encodable>(_ value: T) {
        guard let data = try? WireCoding.encode(value) else { return }
        send(data)
    }

    public func cancel() {
        connection.cancel()
    }

    /// False once the underlying connection has failed or been cancelled.
    public var isAlive: Bool {
        if isClosed { return false }
        switch connection.state {
        case .failed, .cancelled: return false
        default: return true
        }
    }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error { return self.finish(error.debugDescription) }
            guard let data, data.count == 4 else {
                return isComplete ? self.finish(nil) : self.receiveHeader()
            }
            let length = data.withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
            guard length <= Self.maxMessageSize else { return self.finish("Message too large") }
            if length == 0 { return self.receiveHeader() }
            self.receiveBody(length: length)
        }
    }

    private func receiveBody(length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error { return self.finish(error.debugDescription) }
            guard let data, data.count == length else { return self.finish(isComplete ? nil : "Short read") }
            self.handler?(.message(data))
            self.receiveHeader()
        }
    }

    private func finish(_ reason: String?) {
        guard !isClosed else { return }
        isClosed = true
        handler?(.closed(reason))
        handler = nil
        connection.cancel()
    }
}
