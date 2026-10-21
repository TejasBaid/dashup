import DashUpKit
import Foundation

/// Adds DashUp's HTTP hooks to `~/.claude/settings.json`, and removes them again.
///
/// Our entries are recognised by their URL, so install/uninstall never touch the user's own hooks.
/// The previous file is backed up next to it before every write.
enum HookInstaller {
    static let settingsURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")
    static let urlPrefix = "http://127.0.0.1:\(DashUpNetwork.hookPort)/hooks/"

    /// Events that only report activity; answered immediately.
    private static let eventHooks: [(event: String, matcher: String?)] = [
        ("SessionStart", nil), ("SessionEnd", nil), ("UserPromptSubmit", nil),
        ("PreToolUse", "*"), ("PostToolUse", "*"), ("Notification", nil),
        ("Stop", nil), ("StopFailure", nil),
    ]

    static var isInstalled: Bool {
        guard let settings = readSettings(), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return containsOurs(hooks["PermissionRequest"])
    }

    static func install(token: String) throws {
        var settings = readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let headers = ["Authorization": "Bearer \(token)"]

        func add(_ event: String, matcher: String?, path: String, timeout: Int) {
            var groups = withoutOurs(hooks[event])
            var group: [String: Any] = ["hooks": [["type": "http", "url": urlPrefix + path, "timeout": timeout, "headers": headers]]]
            if let matcher { group["matcher"] = matcher }
            groups.append(group)
            hooks[event] = groups
        }
        for hook in eventHooks { add(hook.event, matcher: hook.matcher, path: "event", timeout: 3) }
        add("PermissionRequest", matcher: "*", path: "permission", timeout: 120)

        settings["hooks"] = hooks
        try write(settings)
    }

    static func uninstall() throws {
        guard var settings = readSettings(), var hooks = settings["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            let remaining = withoutOurs(value)
            hooks[event] = remaining.isEmpty ? nil : remaining
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try write(settings)
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func write(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.deletingLastPathComponent().appending(path: "settings.json.dashup-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    private static func isOurs(_ group: Any) -> Bool {
        guard let group = group as? [String: Any], let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["url"] as? String)?.hasPrefix(urlPrefix) == true }
    }

    private static func containsOurs(_ value: Any?) -> Bool {
        (value as? [Any])?.contains(where: isOurs) ?? false
    }

    private static func withoutOurs(_ value: Any?) -> [Any] {
        (value as? [Any] ?? []).filter { !isOurs($0) }
    }
}
