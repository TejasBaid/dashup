import AppKit
import DashUpKit
import Foundation
import Observation
import ServiceManagement

enum AgentPaths {
    static let support: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "DashUp")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Reads a secret file, creating it with `make()` (mode 0600) on first use.
    static func secret(_ name: String, make: () -> Data) -> Data {
        let url = support.appending(path: name)
        if let data = try? Data(contentsOf: url), !data.isEmpty { return data }
        let data = make()
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        return data
    }
}

/// Wires the providers to the iPad server and the Claude Code hook server.
@MainActor
@Observable
final class Agent {
    let claude = ClaudeProvider()
    let apps = AppsProvider()
    let chrome = ChromeProvider()
    let music = NowPlayingProvider()
    let pad = PadProvider()
    @ObservationIgnored let server: PeerServer
    @ObservationIgnored let hooks: HookServer
    let hookToken: String

    // Mirrored for the menu UI.
    private(set) var connectedDevices: [String] = []
    private(set) var pairingCode: String?
    private(set) var pairingExpires: Date?
    private(set) var hooksInstalled = HookInstaller.isInstalled
    private(set) var hookServerRunning = false
    private(set) var sessionCount = 0
    private(set) var pendingCount = 0
    var lastError: String?

    init() {
        let secret = AgentPaths.secret("secret") { DashUpNetwork.newSecret() }
        hookToken = String(decoding: AgentPaths.secret("hook-token") {
            Data(DashUpNetwork.newSecret().map { String(format: "%02x", $0) }.joined().utf8)
        }, as: UTF8.self)
        server = PeerServer(secret: secret, macName: Host.current().localizedName ?? "Mac")
        hooks = HookServer(claude: claude, token: hookToken)
    }

    func start() {
        server.stateFor = { [unowned self] in self.message(for: $0) }
        server.handleRequest = { [unowned self] in await self.handle($0) }
        server.onChange = { [unowned self] in self.syncServer() }

        claude.hasListeners = { [unowned self] in self.server.hasSubscribers(.claude) }
        claude.onChange = { [unowned self] in
            self.server.broadcast(.claude)
            self.sessionCount = self.claude.state.sessions.count
            self.pendingCount = self.claude.state.pending.count
            self.hooksInstalled = self.claude.state.hooksInstalled
            self.apps.refresh()
        }
        apps.captions = { [unowned self] in self.captions() }
        apps.onChange = { [unowned self] in self.server.broadcast(.apps) }
        chrome.isActive = { [unowned self] in self.server.hasSubscribers(.chrome) || self.server.hasSubscribers(.apps) }
        chrome.onChange = { [unowned self] in
            self.server.broadcast(.chrome)
            self.apps.refresh()
        }
        music.isActive = { [unowned self] in self.server.hasSubscribers(.nowPlaying) || self.server.hasSubscribers(.apps) }
        music.onChange = { [unowned self] in
            self.server.broadcast(.nowPlaying)
            self.apps.refresh()
        }
        pad.isActive = { [unowned self] in self.server.hasSubscribers(.pad) }
        pad.launchApp = { [unowned self] in await self.apps.launch(bundleID: $0) }
        pad.music = music
        pad.onChange = { [unowned self] in self.server.broadcast(.pad) }
        hooks.onStateChange = { [unowned self] in self.hookServerRunning = self.hooks.isRunning }
        hooks.connectedClients = { [unowned self] in self.server.connectedNames }

        server.start()
        hooks.start()
        claude.start()
        apps.start()
        chrome.start()
        music.start()
        pad.start()

        if let code = ProcessInfo.processInfo.environment["DASHUP_PAIR_CODE"] {
            server.startPairing(fixedCode: code)
        }
    }

    private func syncServer() {
        connectedDevices = server.connectedNames
        pairingCode = server.pairingCode
        pairingExpires = server.pairingExpires
        // A new subscriber may need data a provider only fetches while someone is watching.
        chrome.poll()
        claude.refresh()
        if server.hasSubscribers(.pad) { pad.activate() }
    }

    private func captions() -> [String: String] {
        var captions: [String: String] = [:]
        if let tabs = chrome.tabCaption { captions[ChromeProvider.bundleID] = tabs }
        if let playing = music.caption, captions[playing.bundleID] == nil { captions[playing.bundleID] = playing.text }
        let conductorSessions = claude.state.sessions.filter(\.isConductor).count
        if conductorSessions > 0 { captions["com.conductor.app"] = conductorSessions == 1 ? "1 session" : "\(conductorSessions) sessions" }
        return captions
    }

    private func message(for topic: Topic) -> ServerMessage? {
        switch topic {
        case .claude: .claude(claude.state)
        case .apps: .apps(apps.state)
        case .chrome: .chrome(chrome.state)
        case .nowPlaying: .nowPlaying(music.state)
        case .pad: .pad(pad.state)
        }
    }

    private func handle(_ request: Request) async -> Response {
        switch request {
        case .launchApp(let id), .activateApp(let id): return await apps.launch(bundleID: id)
        case .hideApp(let id): return apps.hide(bundleID: id)
        case .quitApp(let id): return apps.quit(bundleID: id)
        case .focusTab(let window, let tab): return await chrome.focus(windowID: window, tabID: tab)
        case .closeTab(let window, let tab): return await chrome.close(windowID: window, tabID: tab)
        case .openURL(let url): return await chrome.open(url)
        case .permissionDecision(let id, let allow, let reason):
            return claude.decide(requestID: id, allow: allow, reason: reason) ? .ok : .failed("That request already timed out")
        case .focusSession(let id): return claude.focus(sessionID: id) ? .ok : .failed("Couldn't find that session's window")
        case .media(let command): return await music.perform(command)
        case .runPadItem(let id): return await pad.run(id: id)
        case .appIcon(let id): return .image(apps.icon(bundleID: id))
        case .favicon(let url): return .image(await chrome.favicon(for: url))
        case .artwork(let id): return .image(await music.artwork(trackID: id))
        }
    }

    // MARK: Menu actions

    func startPairing() { server.startPairing() }
    func stopPairing() { server.stopPairing() }

    func installHooks() {
        do {
            try HookInstaller.install(token: hookToken)
            lastError = nil
        } catch {
            lastError = "Couldn't update ~/.claude/settings.json: \(error.localizedDescription)"
        }
        claude.refresh()
        hooksInstalled = HookInstaller.isInstalled
    }

    func uninstallHooks() {
        try? HookInstaller.uninstall()
        claude.refresh()
        hooksInstalled = HookInstaller.isInstalled
    }

    func editPad() {
        NSWorkspace.shared.open(PadProvider.configURL)
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
