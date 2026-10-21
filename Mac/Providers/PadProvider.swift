import AppKit
import ApplicationServices
import DashUpKit
import Foundation

/// The Pad: user-defined keys loaded from `~/Library/Application Support/DashUp/pad.json`.
///
/// Each item has one action field: `shell`, `url`, `open`, `launch`, `toggle`, `builtin` or `shortcut`.
/// The file is created with sensible defaults on first run and reloaded whenever it changes.
@MainActor
final class PadProvider {
    var onChange: (() -> Void)?
    var isActive: () -> Bool = { false }
    /// Used for `launch` actions and app icons.
    var launchApp: (String) async -> Response = { _ in .failed("unavailable") }
    var music: NowPlayingProvider?

    private(set) var state = PadState()
    private var config = PadConfig.defaults
    private var configDate = Date.distantPast
    private var runs: [String: RunInfo] = [:]
    private var toggles = ToggleState()
    private var caffeinate: (process: Process, until: Date)?
    private var timer: Timer?
    private var savedInputVolume = 75

    static let configURL = AgentPaths.support.appending(path: "pad.json")

    private struct RunInfo {
        var startedAt: Date?
        var finishedAt: Date?
        var result: String?
        var succeeded: Bool?
    }

    private struct ToggleState: Equatable {
        var darkMode = false
        var micMuted = false
        var soundMuted = false
    }

    func start() {
        loadConfig()
        rebuild()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.loadConfig()
                if self.isActive() { self.readToggles() }
                self.rebuild()
            }
        }
    }

    /// Called when an iPad subscribes, so toggles show real state straight away.
    func activate() {
        readToggles()
    }

    // MARK: Config

    private func loadConfig() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.configURL.path) {
            try? fm.createDirectory(at: Self.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            try? encoder.encode(PadConfig.defaults).write(to: Self.configURL)
        }
        let modified = (try? fm.attributesOfItem(atPath: Self.configURL.path)[.modificationDate] as? Date) ?? .distantPast
        guard modified != configDate else { return }
        configDate = modified
        do {
            config = try JSONDecoder().decode(PadConfig.self, from: Data(contentsOf: Self.configURL))
        } catch {
            NSLog("DashUp: pad.json is invalid, keeping the previous layout: \(error)")
        }
    }

    // MARK: State

    private func rebuild() {
        let pages = config.pages.enumerated().map { pageIndex, page in
            PadPage(id: "p\(pageIndex)", title: page.title, sections: page.sections.enumerated().map { sectionIndex, section in
                PadSection(id: "p\(pageIndex)s\(sectionIndex)", title: section.title, subtitle: section.subtitle,
                           style: PadSection.Style(rawValue: section.style ?? "keys") ?? .keys,
                           items: section.items.map { item(for: $0) })
            })
        }
        let newState = PadState(pages: pages)
        if newState != state {
            state = newState
            onChange?()
        }
    }

    private func item(for config: PadConfig.Item) -> PadItem {
        let run = runs[config.id]
        var item = PadItem(
            id: config.id, title: config.title, subtitle: config.subtitle,
            context: config.context ?? config.shell.map { String($0.prefix(32)) },
            appBundleID: config.app, usesClaudeMark: config.claude ?? false, keycaps: config.keycaps ?? [],
            isRunning: run?.startedAt != nil, runningSince: run?.startedAt, lastRunAt: run?.finishedAt,
            lastResult: run?.result, lastSucceeded: run?.succeeded, needsConfirmation: config.confirm ?? false)
        if let toggle = config.toggle {
            item.isToggle = true
            switch toggle {
            case "stayAwake":
                if let caffeinate, caffeinate.process.isRunning {
                    item.isOn = true
                    let left = caffeinate.until.timeIntervalSinceNow
                    item.stateText = left > 3600 ? "\(Int(left / 3600))h \(Int(left.truncatingRemainder(dividingBy: 3600) / 60))m left" : "\(max(1, Int(left / 60)))m left"
                } else {
                    item.stateText = "Off"
                }
            case "darkMode":
                item.isOn = toggles.darkMode
                item.stateText = toggles.darkMode ? "On" : "Off"
            case "muteMic":
                item.isOn = toggles.micMuted
                item.stateText = toggles.micMuted ? "Muted" : "Live"
            case "muteSound":
                item.isOn = toggles.soundMuted
                item.stateText = toggles.soundMuted ? "Muted" : "On"
            default:
                item.stateText = "Unknown toggle"
            }
        }
        return item
    }

    private func readToggles() {
        Task {
            struct DTO: Decodable { let dark: Bool; let input: Int?; let muted: Bool? }
            guard let dto = try? await Scripting.json(DTO.self, """
                const app = Application.currentApplication(); app.includeStandardAdditions = true;
                const v = app.getVolumeSettings();
                JSON.stringify({dark: Application('System Events').appearancePreferences.darkMode(),
                                input: v.inputVolume, muted: v.outputMuted});
                """) else { return }
            let new = ToggleState(darkMode: dto.dark, micMuted: (dto.input ?? 1) == 0, soundMuted: dto.muted ?? false)
            if new != toggles {
                toggles = new
                rebuild()
            }
        }
    }

    // MARK: Running

    func run(id: String) async -> Response {
        guard let item = config.pages.flatMap(\.sections).flatMap(\.items).first(where: { $0.id == id }),
              let section = config.pages.flatMap(\.sections).first(where: { $0.items.contains { $0.id == id } }) else {
            return .failed("Unknown key")
        }
        let directory = (item.directory ?? section.directory).map { NSString(string: $0).expandingTildeInPath }

        if let command = item.shell { return runShell(id: id, command: command, directory: directory) }
        if let url = item.url {
            guard let target = URL(string: ChromeProvider.normalize(url)) else { return .failed("Bad URL") }
            return await open(target, appBundleID: item.app)
        }
        if let path = item.open {
            let expanded = NSString(string: path).expandingTildeInPath
            let full = expanded.hasPrefix("/") ? expanded : ((directory ?? NSHomeDirectory()) as NSString).appendingPathComponent(expanded)
            return await open(URL(fileURLWithPath: full), appBundleID: item.app)
        }
        if let bundleID = item.launch { return await launchApp(bundleID) }
        if let toggle = item.toggle { return await flip(toggle) }
        if let builtin = item.builtin { return await perform(builtin) }
        if let shortcut = item.shortcut {
            return runShell(id: id, command: "shortcuts run \(shellQuote(shortcut))", directory: nil)
        }
        return .failed("This key has no action")
    }

    private func runShell(id: String, command: String, directory: String?) -> Response {
        guard runs[id]?.startedAt == nil else { return .failed("Already running") }
        runs[id] = RunInfo(startedAt: .now)
        rebuild()
        Task {
            var info = RunInfo(finishedAt: .now)
            do {
                let output = try await Shell.run("/bin/zsh", ["-lc", command], directory: directory, timeout: 30 * 60)
                info.succeeded = true
                info.result = Self.summary(output) ?? "Done"
            } catch {
                info.succeeded = false
                info.result = Self.summary("\(error)") ?? "Failed"
            }
            info.finishedAt = .now
            runs[id] = info
            rebuild()
        }
        return .ok
    }

    /// The last meaningful line of output, shortened for a key.
    private static func summary(_ output: String) -> String? {
        let line = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        guard let line else { return nil }
        return line.count > 60 ? String(line.prefix(57)) + "…" : line
    }

    private func open(_ url: URL, appBundleID: String?) async -> Response {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            if let appBundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) {
                _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
            } else {
                NSWorkspace.shared.open(url)
            }
            return .ok
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func flip(_ toggle: String) async -> Response {
        defer { rebuild() }
        switch toggle {
        case "stayAwake":
            if let caffeinate, caffeinate.process.isRunning {
                caffeinate.process.terminate()
                self.caffeinate = nil
            } else {
                let hours: TimeInterval = 2
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
                process.arguments = ["-di", "-t", "\(Int(hours * 3600))"]
                process.terminationHandler = { [weak self] _ in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.rebuild() } }
                }
                do { try process.run() } catch { return .failed(error.localizedDescription) }
                caffeinate = (process, .now.addingTimeInterval(hours * 3600))
            }
            return .ok
        case "darkMode":
            toggles.darkMode.toggle()
            return await script("Application('System Events').appearancePreferences.darkMode = \(toggles.darkMode);")
        case "muteMic":
            toggles.micMuted.toggle()
            if toggles.micMuted, let current = try? await Scripting.run("""
                const app = Application.currentApplication(); app.includeStandardAdditions = true; app.getVolumeSettings().inputVolume;
                """), let level = Int(current), level > 0 {
                savedInputVolume = level
            }
            return await script("""
                const app = Application.currentApplication(); app.includeStandardAdditions = true;
                app.setVolume(null, {inputVolume: \(toggles.micMuted ? 0 : savedInputVolume)});
                """)
        case "muteSound":
            toggles.soundMuted.toggle()
            return await script("""
                const app = Application.currentApplication(); app.includeStandardAdditions = true;
                app.setVolume(null, {outputMuted: \(toggles.soundMuted)});
                """)
        default:
            return .failed("Unknown toggle \(toggle)")
        }
    }

    private func perform(_ builtin: String) async -> Response {
        switch builtin {
        case "lockScreen": return Self.keystroke(12, flags: [.maskControl, .maskCommand])
        case "screenshot": return Self.keystroke(21, flags: [.maskShift, .maskCommand])
        case "sleepDisplay": return await shell("/usr/bin/pmset", ["displaysleepnow"])
        case "missionControl": return await shell("/usr/bin/open", ["-a", "Mission Control"])
        case "showDesktop": return await shell("/System/Applications/Mission Control.app/Contents/MacOS/Mission Control", ["1"])
        case "emptyTrash": return await script("Application('Finder').empty();")
        case "playPause": return await music?.perform(.playPause) ?? .failed("No player")
        case "nextTrack": return await music?.perform(.next) ?? .failed("No player")
        case "previousTrack": return await music?.perform(.previous) ?? .failed("No player")
        case "volumeUp", "volumeDown":
            let delta = builtin == "volumeUp" ? 10 : -10
            return await script("""
                const app = Application.currentApplication(); app.includeStandardAdditions = true;
                const v = app.getVolumeSettings().outputVolume;
                app.setVolume(null, {outputVolume: Math.max(0, Math.min(100, v + \(delta)))});
                """)
        default: return .failed("Unknown action \(builtin)")
        }
    }

    private func script(_ source: String) async -> Response {
        do {
            _ = try await Scripting.run(source)
            return .ok
        } catch {
            return .failed("\(error)")
        }
    }

    private func shell(_ path: String, _ arguments: [String]) async -> Response {
        do {
            _ = try await Shell.run(path, arguments)
            return .ok
        } catch {
            return .failed("\(error)")
        }
    }

    /// Posts a keyboard shortcut. Needs Accessibility permission, which macOS asks for once.
    static func keystroke(_ key: CGKeyCode, flags: CGEventFlags) -> Response {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return .failed("Allow DashUp in System Settings → Privacy & Security → Accessibility.")
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        return .ok
    }

    private func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

// MARK: - Config file

struct PadConfig: Codable {
    var pages: [Page]

    struct Page: Codable {
        var title: String
        var sections: [Section]
    }

    struct Section: Codable {
        var title: String
        var subtitle: String?
        /// "modes", "keys" or "compact".
        var style: String?
        /// Working directory for `shell` and relative `open` items.
        var directory: String?
        var items: [Item]
    }

    struct Item: Codable {
        var id: String
        var title: String
        var subtitle: String?
        var context: String?
        /// Bundle ID whose icon is shown, and the app used for `url`/`open`.
        var app: String?
        var claude: Bool?
        var keycaps: [String]?
        var confirm: Bool?
        var directory: String?
        // Actions — set exactly one.
        var shell: String?
        var url: String?
        var open: String?
        var launch: String?
        var toggle: String?
        var builtin: String?
        var shortcut: String?

        init(id: String, title: String, subtitle: String? = nil, context: String? = nil, app: String? = nil,
             claude: Bool? = nil, keycaps: [String]? = nil, confirm: Bool? = nil, shell: String? = nil,
             url: String? = nil, open: String? = nil, launch: String? = nil, toggle: String? = nil,
             builtin: String? = nil) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.context = context
            self.app = app
            self.claude = claude
            self.keycaps = keycaps
            self.confirm = confirm
            self.shell = shell
            self.url = url
            self.open = open
            self.launch = launch
            self.toggle = toggle
            self.builtin = builtin
        }
    }

    static let modes = Section(title: "Modes", style: "modes", items: [
        Item(id: "stay-awake", title: "Stay awake", toggle: "stayAwake"),
        Item(id: "dark-mode", title: "Dark mode", toggle: "darkMode"),
        Item(id: "mute-mic", title: "Mute mic", toggle: "muteMic"),
        Item(id: "mute-sound", title: "Mute sound", toggle: "muteSound"),
    ])

    static let mac = Section(title: "Mac", style: "compact", items: [
        Item(id: "lock", title: "Lock", keycaps: ["⌃", "⌘", "Q"], builtin: "lockScreen"),
        Item(id: "sleep-display", title: "Sleep display", subtitle: "Wakes on input", builtin: "sleepDisplay"),
        Item(id: "screenshot", title: "Screenshot", keycaps: ["⇧", "⌘", "4"], builtin: "screenshot"),
        Item(id: "mission-control", title: "Mission Control", keycaps: ["⌃", "↑"], builtin: "missionControl"),
        Item(id: "show-desktop", title: "Show desktop", subtitle: "Moves windows aside", builtin: "showDesktop"),
        Item(id: "empty-trash", title: "Empty Trash", subtitle: "Asks first", confirm: true, builtin: "emptyTrash"),
    ])

    static let defaults = PadConfig(pages: [
        Page(title: "Everyday", sections: [
            modes,
            Section(title: "Open", style: "keys", items: [
                Item(id: "gmail", title: "Gmail", subtitle: "Opens in Chrome", app: "com.google.Chrome", url: "https://mail.google.com"),
                Item(id: "calendar", title: "Calendar", subtitle: "Google Calendar", app: "com.google.Chrome", url: "https://calendar.google.com"),
                Item(id: "messages", title: "Messages", app: "com.apple.MobileSMS", launch: "com.apple.MobileSMS"),
                Item(id: "whatsapp", title: "WhatsApp", app: "net.whatsapp.WhatsApp", launch: "net.whatsapp.WhatsApp"),
            ]),
            mac,
        ]),
        Page(title: "Dev", sections: [
            modes,
            Section(title: "DashUp", subtitle: "~/Desktop/Projects/DashUp", style: "keys", directory: "~/Desktop/Projects/DashUp", items: [
                Item(id: "run-tests", title: "Run tests", context: "swift test", shell: "swift test --package-path Packages/DashUpKit"),
                Item(id: "build-ipad", title: "Build iPad app", context: "xcodebuild",
                     shell: "xcodebuild -project DashUp.xcodeproj -scheme DashUpPad -destination 'generic/platform=iOS Simulator' build -quiet"),
                Item(id: "open-pr", title: "Open pull request", context: "gh pr view --web", shell: "gh pr view --web"),
                Item(id: "pull", title: "Pull & rebase", context: "git pull --rebase", shell: "git pull --rebase"),
                Item(id: "conductor", title: "New Claude session", subtitle: "Opens Conductor", claude: true, launch: "com.conductor.app"),
                Item(id: "xcode", title: "Open in Xcode", subtitle: "DashUp.xcodeproj", app: "com.apple.dt.Xcode", open: "DashUp.xcodeproj"),
                Item(id: "localhost", title: "localhost:3000", subtitle: "Opens in Chrome", app: "com.google.Chrome", url: "http://localhost:3000"),
                Item(id: "copy-sha", title: "Copy last commit", context: "git rev-parse", shell: "git rev-parse --short HEAD | tee /dev/stderr | tr -d '\\n' | pbcopy"),
            ]),
            mac,
        ]),
        Page(title: "Media", sections: [
            Section(title: "Music", style: "compact", items: [
                Item(id: "play-pause", title: "Play / Pause", app: "com.apple.Music", builtin: "playPause"),
                Item(id: "previous", title: "Previous", builtin: "previousTrack"),
                Item(id: "next", title: "Next", builtin: "nextTrack"),
                Item(id: "volume-down", title: "Volume down", builtin: "volumeDown"),
                Item(id: "volume-up", title: "Volume up", builtin: "volumeUp"),
                Item(id: "mute", title: "Mute", toggle: "muteSound"),
            ]),
        ]),
    ])
}
