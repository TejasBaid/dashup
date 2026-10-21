import DashUpKit
import Observation
import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case home, apps, tabs, claude, media, pad, settings
    var id: String { rawValue }
}

/// Everything the iPad shows, plus the actions it can take on the Mac.
@Observable
final class AppModel {
    var status: MacLink.Status = .unpaired
    var macName: String? = UserDefaults.standard.string(forKey: "macName")
    var claude = ClaudeState()
    var apps = AppsState()
    var chrome = ChromeState()
    var nowPlaying = NowPlayingState()
    var pad = PadState()

    var screen: Screen = .home
    /// Session shown in the Claude tab's detail view; nil shows the board.
    var claudeDetailID: String?
    var toast: String?
    var standby = false
    /// Optional photo behind the whole app, chosen in Settings.
    var backgroundImage: UIImage? = BackgroundPhoto.load() {
        didSet { Theme.backdrop = backgroundImage != nil }
    }

    let settings = Settings()
    let images: ImageStore
    let isDemo: Bool
    @ObservationIgnored private let link = MacLink()
    @ObservationIgnored private var toastWork: DispatchWorkItem?

    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("-demo")) {
        isDemo = demo
        Theme.backdrop = BackgroundPhoto.exists
        images = ImageStore(demo: demo)
        images.fetch = { [link] in await link.send($0) }
        // Launch arguments used for screenshots: -screen claude, -standby, -calm (standby without a request).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-screen"), i + 1 < args.count, let screen = Screen(rawValue: args[i + 1]) {
            self.screen = screen
        }
        if args.contains("-standby") { standby = true }
        if let i = args.firstIndex(of: "-claudeDetail"), i + 1 < args.count { claudeDetailID = args[i + 1] }
        if args.contains("-clearBackground") {
            BackgroundPhoto.remove()
            backgroundImage = nil
        }
        if let i = args.firstIndex(of: "-backgroundFile"), i + 1 < args.count,
           let data = try? Data(contentsOf: URL(fileURLWithPath: args[i + 1])) {
            backgroundImage = BackgroundPhoto.save(data)
        }
        if args.contains("-resetPairing") {
            Keychain.secret = nil
            UserDefaults.standard.removeObject(forKey: "macName")
            macName = nil
        }
        if demo {
            DemoData.load(into: self)
            return
        }
        link.onStatus = { [weak self] status in
            withAnimation(.easeOut(duration: 0.2)) { self?.status = status }
            if status == .connected { self?.macName = UserDefaults.standard.string(forKey: "macName") }
        }
        link.onMessage = { [weak self] in self?.apply($0) }
    }

    func start() {
        guard !isDemo else { return }
        link.start()
    }

    func becameActive() {
        guard !isDemo else { return }
        link.reconnectNow()
    }

    private func apply(_ message: ServerMessage) {
        switch message {
        case .welcome(let welcome): macName = welcome.macName
        case .claude(let state):
            let hadAsk = !claude.pending.isEmpty
            withAnimation(.easeOut(duration: 0.2)) { claude = state }
            // A new permission request wakes the screen.
            if !hadAsk, !state.pending.isEmpty { standbyWake(reason: .approval) }
        case .apps(let state): apps = state
        case .chrome(let state): chrome = state
        case .nowPlaying(let state): nowPlaying = state
        case .pad(let state): pad = state
        case .response: break
        }
    }

    // MARK: Derived

    var firstName: String {
        if !settings.name.isEmpty { return settings.name }
        guard let mac = macName else { return "" }
        for separator in ["’s ", "'s "] {
            if let range = mac.range(of: separator) { return String(mac[..<range.lowerBound]) }
        }
        return ""
    }

    /// "Mac mini" from "Tejas’s Mac mini".
    var shortMacName: String {
        guard let mac = macName else { return "Mac" }
        for separator in ["’s ", "'s "] {
            if let range = mac.range(of: separator) { return String(mac[range.upperBound...]) }
        }
        return mac
    }

    func session(_ id: String?) -> ClaudeSession? {
        claude.sessions.first { $0.id == id }
    }

    // MARK: Actions

    /// Sends a request and surfaces failures as a toast.
    @discardableResult
    func perform(_ request: Request) async -> Response {
        if isDemo { return .ok }
        let response = await link.send(request)
        if case .failed(let message) = response { show(message) }
        return response
    }

    func run(_ request: Request) {
        Task { await perform(request) }
    }

    func decide(_ ask: PermissionAsk, allow: Bool) {
        // Optimistically clear the card; the Mac's next state update confirms it.
        withAnimation(.easeOut(duration: 0.2)) {
            claude.pending.removeAll { $0.id == ask.id }
            if let i = claude.sessions.firstIndex(where: { $0.id == ask.sessionID }) {
                claude.sessions[i].phase = allow ? .working : .finished
            }
        }
        run(.permissionDecision(requestID: ask.id, allow: allow, reason: allow ? nil : "Denied from DashUp on iPad"))
    }

    func open(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        run(.openURL(trimmed))
    }

    func show(_ message: String) {
        toastWork?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = message }
        let work = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil } }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    // MARK: Background

    func setBackground(_ data: Data) {
        withAnimation(.easeOut(duration: 0.3)) { backgroundImage = BackgroundPhoto.save(data) }
    }

    func removeBackground() {
        BackgroundPhoto.remove()
        withAnimation(.easeOut(duration: 0.3)) { backgroundImage = nil }
    }

    // MARK: Pairing

    func pair(code: String) async -> MacLink.PairingResult {
        let result = await link.pair(code: code)
        if case .paired(let name) = result {
            macName = name
            link.start()
        }
        return result
    }

    func forgetMac() {
        link.forget()
        claude = ClaudeState()
        apps = AppsState()
        chrome = ChromeState()
        nowPlaying = NowPlayingState()
        pad = PadState()
    }

    // MARK: Standby

    enum WakeReason { case touch, approval }
    var lastInteraction = Date.now

    /// Any touch resets the idle clock. Leaving standby takes a tap on standby itself, so its
    /// Allow / Deny buttons work without waking the screen first.
    func touched() {
        lastInteraction = .now
    }

    func wake() {
        lastInteraction = .now
        withAnimation(.easeOut(duration: 0.35)) { standby = false }
    }

    func enterStandby() {
        withAnimation(.easeInOut(duration: 0.6)) { standby = true }
    }

    private func standbyWake(reason: WakeReason) {
        // Standby itself shows the approval, so only reset the idle clock.
        lastInteraction = .now
    }

    func checkIdle(now: Date) {
        guard settings.standbyMinutes > 0, !standby,
              now.timeIntervalSince(lastInteraction) > Double(settings.standbyMinutes) * 60 else { return }
        withAnimation(.easeInOut(duration: 0.6)) { standby = true }
    }
}

/// Preferences kept on the iPad.
@Observable
final class Settings {
    struct Site: Codable, Hashable, Identifiable {
        var title: String
        var url: String
        var id: String { url }
    }

    var name: String { didSet { save() } }
    var pinnedApps: [String] { didSet { save() } }
    var sites: [Site] { didSet { save() } }
    var standbyMinutes: Int { didSet { save() } }
    /// How much the background photo is darkened, 0…1.
    var backgroundDim: Double { didSet { save() } }
    /// Blur radius applied to the background photo.
    var backgroundBlur: Double { didSet { save() } }
    var padPage: String? { didSet { save() } }

    static let defaultSites = [
        Site(title: "GitHub", url: "https://github.com"),
        Site(title: "Linear", url: "https://linear.app"),
        Site(title: "Vercel", url: "https://vercel.com"),
        Site(title: "Claude", url: "https://claude.ai"),
        Site(title: "Gmail", url: "https://mail.google.com"),
        Site(title: "localhost", url: "http://localhost:3000"),
    ]

    init() {
        let d = UserDefaults.standard
        name = d.string(forKey: "name") ?? ""
        pinnedApps = d.stringArray(forKey: "pinnedApps") ?? ["net.whatsapp.WhatsApp", "com.apple.Notes", "com.apple.iCal"]
        sites = (d.data(forKey: "sites")).flatMap { try? JSONDecoder().decode([Site].self, from: $0) } ?? Self.defaultSites
        standbyMinutes = d.object(forKey: "standbyMinutes") as? Int ?? 5
        backgroundDim = d.object(forKey: "backgroundDim") as? Double ?? 0.6
        backgroundBlur = d.object(forKey: "backgroundBlur") as? Double ?? 0
        padPage = d.string(forKey: "padPage")
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(name, forKey: "name")
        d.set(pinnedApps, forKey: "pinnedApps")
        d.set(try? JSONEncoder().encode(sites), forKey: "sites")
        d.set(standbyMinutes, forKey: "standbyMinutes")
        d.set(backgroundDim, forKey: "backgroundDim")
        d.set(backgroundBlur, forKey: "backgroundBlur")
        d.set(padPage, forKey: "padPage")
    }

    func togglePin(_ bundleID: String) {
        if let i = pinnedApps.firstIndex(of: bundleID) { pinnedApps.remove(at: i) } else { pinnedApps.append(bundleID) }
    }
}

/// The background photo, stored downscaled in Application Support.
enum BackgroundPhoto {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "background.jpg")
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func load() -> UIImage? {
        (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
    }

    /// Scales the photo to fit a 13" iPad at 2x and saves it as JPEG.
    static func save(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let longest: CGFloat = 2752
        let scale = min(1, longest / max(image.size.width * image.scale, image.size.height * image.scale))
        let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        try? jpeg.write(to: url)
        return resized
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
