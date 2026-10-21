import AppKit
import DashUpKit
import Foundation
import SQLite3

/// Chrome windows and tabs via JavaScript for Automation. Polls only while someone is subscribed
/// and Chrome is running, so Chrome is never launched or prodded otherwise.
@MainActor
final class ChromeProvider {
    static let bundleID = "com.google.Chrome"

    var onChange: (() -> Void)?
    var isActive: () -> Bool = { false }

    private(set) var state = ChromeState()
    private var timer: Timer?
    private var inFlight = false
    private let favicons = FaviconStore()

    func start() {
        // Avoid briefly reporting "not running" before the first poll.
        state = ChromeState(isRunning: isRunning)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty }

    func poll() {
        guard isActive(), !inFlight else { return }
        guard isRunning else { return update(ChromeState(isRunning: false)) }
        inFlight = true
        Task {
            defer { inFlight = false }
            do {
                let windows = try await Scripting.json([WindowDTO].self, """
                    const chrome = Application('Google Chrome');
                    JSON.stringify(chrome.windows().filter(w => w.mode() !== 'incognito').map(w => ({
                      id: Number(w.id()), active: w.activeTabIndex(),
                      ids: w.tabs.id().map(Number), titles: w.tabs.title(), urls: w.tabs.url()
                    })));
                    """)
                update(ChromeState(isRunning: true, windows: windows.map { w in
                    ChromeWindow(id: w.id, tabs: zip(w.ids, zip(w.titles, w.urls)).map { ChromeTab(id: $0.0, title: $0.1.0, url: $0.1.1) },
                                 activeTabIndex: w.active)
                }))
            } catch let failure as Scripting.Failure {
                update(ChromeState(isRunning: true, error: failure.isPermissionDenied
                    ? "Allow DashUp to control Google Chrome in System Settings → Privacy & Security → Automation."
                    : failure.description))
            } catch {
                update(ChromeState(isRunning: true, error: error.localizedDescription))
            }
        }
    }

    private struct WindowDTO: Decodable {
        let id: Int
        let active: Int
        let ids: [Int]
        let titles: [String]
        let urls: [String]
    }

    private func update(_ newState: ChromeState) {
        guard newState != state else { return }
        state = newState
        onChange?()
    }

    // MARK: Actions

    func focus(windowID: Int, tabID: Int) async -> Response {
        await run("""
            const chrome = Application('Google Chrome');
            const w = chrome.windows.byId('\(windowID)');
            const ids = w.tabs.id().map(String);
            w.activeTabIndex = ids.indexOf('\(tabID)') + 1;
            w.index = 1;
            chrome.activate();
            """)
    }

    func close(windowID: Int, tabID: Int) async -> Response {
        await run("Application('Google Chrome').windows.byId('\(windowID)').tabs.byId('\(tabID)').close();")
    }

    func open(_ text: String) async -> Response {
        let url = Self.normalize(text)
        if !isRunning {
            // Launch Chrome straight onto the URL.
            guard let target = URL(string: url),
                  let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return .failed("Chrome isn't installed") }
            _ = try? await NSWorkspace.shared.open([target], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            return .ok
        }
        return await run("""
            const chrome = Application('Google Chrome');
            if (chrome.windows.length === 0) { chrome.Window().make(); }
            const w = chrome.windows[0];
            w.tabs.push(chrome.Tab({url: \(Scripting.literal(url))}));
            w.activeTabIndex = w.tabs.length;
            chrome.activate();
            """)
    }

    private func run(_ source: String) async -> Response {
        do {
            _ = try await Scripting.run(source)
            poll()
            return .ok
        } catch {
            return .failed("\(error)")
        }
    }

    /// Turns "github.com" into a URL and anything that isn't URL-like into a Google search.
    nonisolated static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") { return trimmed }
        if trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1") { return "http://\(trimmed)" }
        if !trimmed.contains(" "), trimmed.contains(".") { return "https://\(trimmed)" }
        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return "https://www.google.com/search?q=\(query)"
    }

    // MARK: Favicons

    func favicon(for url: String) async -> Data? {
        await favicons.icon(for: url)
    }

    var tabCaption: String? {
        guard state.isRunning, state.error == nil, state.tabCount > 0 else { return nil }
        return "\(state.tabCount) tabs"
    }
}

/// Reads favicons from Chrome's own `Favicons` database (copied first, since Chrome holds a lock),
/// so no network requests are made.
actor FaviconStore {
    private var cache: [String: Data?] = [:]
    private var snapshotDate = Date.distantPast
    private var snapshots: [URL] = []

    func icon(for url: String) -> Data? {
        let host = URL(string: ChromeProvider.normalize(url))?.host() ?? url
        if let cached = cache[host] { return cached }
        refreshSnapshots()
        var result: Data?
        for db in snapshots {
            if let data = query(db: db, url: url, host: host) { result = data; break }
        }
        cache[host] = result
        return result
    }

    private func refreshSnapshots() {
        guard Date.now.timeIntervalSince(snapshotDate) > 300 else { return }
        snapshotDate = .now
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Google/Chrome")
        let profiles = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted { $0 == "Default" ? true : ($1 == "Default" ? false : $0 < $1) }
        let tmp = fm.temporaryDirectory.appending(path: "dashup-favicons")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        snapshots = profiles.compactMap { profile in
            let source = root.appending(path: "\(profile)/Favicons")
            let copy = tmp.appending(path: profile.replacingOccurrences(of: " ", with: "_"))
            try? fm.removeItem(at: copy)
            return (try? fm.copyItem(at: source, to: copy)) != nil ? copy : nil
        }
        cache.removeAll()
    }

    private func query(db path: URL, url: String, host: String) -> Data? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        // Exact page first, then any page on the same host; prefer bitmaps near 64px.
        let sql = """
            SELECT b.image_data FROM icon_mapping m JOIN favicon_bitmaps b ON b.icon_id = m.icon_id
            WHERE m.page_url = ?1 OR m.page_url LIKE ?2 OR m.page_url LIKE ?3
            ORDER BY (m.page_url = ?1) DESC, ABS(b.width - 64) ASC LIMIT 1
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, url, -1, transient)
        sqlite3_bind_text(statement, 2, "https://\(host)/%", -1, transient)
        sqlite3_bind_text(statement, 3, "https://www.\(host)/%", -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 0) else { return nil }
        return Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))
    }
}
