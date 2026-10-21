import AppKit
import DashUpKit
import Foundation

/// Running and installed apps, with launch/switch/hide/quit.
@MainActor
final class AppsProvider {
    var onChange: (() -> Void)?
    /// Supplies live captions (e.g. "23 tabs") from other providers, keyed by bundle ID.
    var captions: () -> [String: String] = { [:] }

    private(set) var state = AppsState()
    private var installed: [InstalledApp] = []
    private var iconCache: [String: Data] = [:]
    private var timer: Timer?

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        scanInstalled()
        refresh()
        // Window counts and memory change without notifications.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let windowCounts = Self.windowCounts()
        let captions = captions()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app -> RunningApp? in
                guard let bundleID = app.bundleIdentifier else { return nil }
                let windows = windowCounts[app.processIdentifier] ?? 0
                return RunningApp(
                    bundleID: bundleID, name: app.localizedName ?? bundleID, pid: app.processIdentifier,
                    isFront: app.processIdentifier == front, isHidden: app.isHidden, windowCount: windows,
                    caption: captions[bundleID] ?? (windows > 1 ? "\(windows) windows" : nil),
                    memoryBytes: Self.memory(of: app.processIdentifier))
            }
            .sorted { lhs, rhs in
                // Frontmost first, then by launch order (most recent last on macOS, so reverse).
                if lhs.isFront != rhs.isFront { return lhs.isFront }
                return lhs.pid > rhs.pid
            }
        let newState = AppsState(running: running, installed: installed)
        if newState != state {
            state = newState
            onChange?()
        }
    }

    // MARK: Actions

    func launch(bundleID: String) async -> Response {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.unhide()
            return app.activate() ? .ok : .failed("Could not switch to \(app.localizedName ?? bundleID)")
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return .failed("App not found")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return .ok
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func hide(bundleID: String) -> Response {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.hide() }
        return .ok
    }

    func quit(bundleID: String) -> Response {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
        return .ok
    }

    func icon(bundleID: String) -> Data? {
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let data = NSWorkspace.shared.icon(forFile: url.path).pngData(side: 128)
        iconCache[bundleID] = data
        return data
    }

    // MARK: Installed apps

    private func scanInstalled() {
        let fm = FileManager.default
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                     fm.homeDirectoryForCurrentUser.appending(path: "Applications").path]
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for root in roots {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".app") {
                guard let bundle = Bundle(path: "\(root)/\(name)"), let id = bundle.bundleIdentifier,
                      !seen.contains(id) else { continue }
                seen.insert(id)
                let display = fm.displayName(atPath: "\(root)/\(name)").replacingOccurrences(of: ".app", with: "")
                apps.append(InstalledApp(bundleID: id, name: display.trimmingCharacters(in: .controlCharacters)))
            }
        }
        installed = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: System info

    /// On-screen, normal-layer window counts per process. Needs no Screen Recording permission.
    private static func windowCounts() -> [Int32: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var counts: [Int32: Int] = [:]
        for window in list where (window[kCGWindowLayer as String] as? Int) == 0 {
            if let pid = window[kCGWindowOwnerPID as String] as? Int32 { counts[pid, default: 0] += 1 }
        }
        return counts
    }

    private static func memory(of pid: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }
}

extension NSImage {
    /// Renders the image into a square PNG of `side` pixels.
    func pngData(side: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
