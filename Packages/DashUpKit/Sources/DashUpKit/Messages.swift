import Foundation

public enum DashUpProtocol {
    public static let version = 1
}

public enum Topic: String, Codable, Sendable, CaseIterable {
    case claude, apps, chrome, nowPlaying, pad
}

public struct Hello: Codable, Sendable, Equatable {
    public var deviceName: String
    /// Stable per install; a new connection from the same device replaces the old one.
    public var deviceID: String?
    public var protocolVersion: Int

    public init(deviceName: String, deviceID: String? = nil, protocolVersion: Int = DashUpProtocol.version) {
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.protocolVersion = protocolVersion
    }
}

public struct Welcome: Codable, Sendable, Equatable {
    public var macName: String
    public var protocolVersion: Int

    public init(macName: String, protocolVersion: Int = DashUpProtocol.version) {
        self.macName = macName
        self.protocolVersion = protocolVersion
    }
}

public enum MediaCommand: Codable, Sendable, Equatable {
    case playPause
    case next
    case previous
    case seek(Double)
    case volume(Int)
}

public enum Request: Codable, Sendable, Equatable {
    case launchApp(bundleID: String)
    case activateApp(bundleID: String)
    case hideApp(bundleID: String)
    case quitApp(bundleID: String)
    case focusTab(windowID: Int, tabID: Int)
    case closeTab(windowID: Int, tabID: Int)
    case openURL(String)
    case permissionDecision(requestID: String, allow: Bool, reason: String?)
    case focusSession(sessionID: String)
    case media(MediaCommand)
    case runPadItem(id: String)
    case appIcon(bundleID: String)
    case favicon(url: String)
    case artwork(trackID: String)
}

public enum Response: Codable, Sendable, Equatable {
    case ok
    case failed(String)
    case image(Data?)
}

/// Messages from the iPad to the Mac.
public enum ClientMessage: Codable, Sendable, Equatable {
    case hello(Hello)
    case subscribe([Topic])
    case request(id: Int, Request)
    /// Sent every few seconds so the Mac can drop connections that died silently.
    case ping
}

/// Messages from the Mac to the iPad. State topics always carry the full state.
public enum ServerMessage: Codable, Sendable, Equatable {
    case welcome(Welcome)
    case claude(ClaudeState)
    case apps(AppsState)
    case chrome(ChromeState)
    case nowPlaying(NowPlayingState)
    case pad(PadState)
    case response(id: Int, Response)
}

// MARK: - Pairing

/// Sent by the iPad over the code-protected pairing channel.
public struct PairRequest: Codable, Sendable, Equatable {
    public var deviceName: String

    public init(deviceName: String) {
        self.deviceName = deviceName
    }
}

/// The Mac's reply: the long-lived secret used for every later connection.
public struct PairResponse: Codable, Sendable, Equatable {
    public var macName: String
    public var secret: Data

    public init(macName: String, secret: Data) {
        self.macName = macName
        self.secret = secret
    }
}

// MARK: - Coding

public enum WireCoding {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}
