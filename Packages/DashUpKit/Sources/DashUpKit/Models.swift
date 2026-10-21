import Foundation

// MARK: - Claude Code

public struct ClaudeState: Codable, Sendable, Equatable {
    public var sessions: [ClaudeSession]
    public var pending: [PermissionAsk]
    public var hooksInstalled: Bool
    /// Sessions that ended in the last 12 hours, newest first, without timelines.
    public var recent: [ClaudeSession]

    public init(sessions: [ClaudeSession] = [], pending: [PermissionAsk] = [], hooksInstalled: Bool = false,
                recent: [ClaudeSession] = []) {
        self.sessions = sessions
        self.pending = pending
        self.hooksInstalled = hooksInstalled
        self.recent = recent
    }

    public func pending(for sessionID: String) -> PermissionAsk? {
        pending.first { $0.sessionID == sessionID }
    }
}

public enum SessionPhase: String, Codable, Sendable {
    /// Claude is generating or running tools.
    case working
    /// A permission request is waiting on a decision.
    case needsApproval
    /// Claude asked a question or is idle waiting for input after a notification.
    case waiting
    /// The last turn finished recently.
    case finished
    /// Nothing has happened for a while.
    case idle
}

public struct ClaudeSession: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var pid: Int32
    public var name: String
    public var cwd: String
    /// Human label for where the session runs, e.g. "DashUp / medan".
    public var project: String
    public var isConductor: Bool
    public var phase: SessionPhase
    public var phaseSince: Date
    public var startedAt: Date
    public var title: String?
    public var lastPrompt: String?
    public var lastMessage: String?
    /// What the session is doing right now, e.g. "Editing Link/Bridge.swift".
    public var activity: String?
    public var model: String?
    public var branch: String?
    public var contextTokens: Int?
    public var timeline: [TimelineItem]
    /// Files edited or written, most recent first.
    public var filesChanged: [FileChange]
    /// Tool calls seen in the transcript.
    public var steps: Int

    public init(id: String, pid: Int32, name: String, cwd: String, project: String, isConductor: Bool,
                phase: SessionPhase, phaseSince: Date, startedAt: Date, title: String? = nil,
                lastPrompt: String? = nil, lastMessage: String? = nil, activity: String? = nil,
                model: String? = nil, branch: String? = nil, contextTokens: Int? = nil,
                timeline: [TimelineItem] = [], filesChanged: [FileChange] = [], steps: Int = 0) {
        self.id = id
        self.pid = pid
        self.name = name
        self.cwd = cwd
        self.project = project
        self.isConductor = isConductor
        self.phase = phase
        self.phaseSince = phaseSince
        self.startedAt = startedAt
        self.title = title
        self.lastPrompt = lastPrompt
        self.lastMessage = lastMessage
        self.activity = activity
        self.model = model
        self.branch = branch
        self.contextTokens = contextTokens
        self.timeline = timeline
        self.filesChanged = filesChanged
        self.steps = steps
    }
}

public struct FileChange: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var path: String
    /// Written with the Write tool (usually a new file) rather than edited in place.
    public var written: Bool

    public init(path: String, written: Bool) {
        self.path = path
        self.written = written
    }
}

public struct TimelineItem: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case prompt, text, tool }

    public var id: String
    public var kind: Kind
    public var date: Date
    /// Prompt or assistant text, or the tool verb ("Edited", "Ran", "Read").
    public var text: String
    /// Tool target: a path, command or pattern.
    public var detail: String?
    public var toolName: String?
    public var isError: Bool

    public init(id: String, kind: Kind, date: Date, text: String, detail: String? = nil,
                toolName: String? = nil, isError: Bool = false) {
        self.id = id
        self.kind = kind
        self.date = date
        self.text = text
        self.detail = detail
        self.toolName = toolName
        self.isError = isError
    }
}

public struct PermissionAsk: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionID: String
    public var toolName: String
    /// The thing being approved, shown large: a command, a path, a URL.
    public var subject: String
    public var cwd: String
    public var createdAt: Date
    public var expiresAt: Date

    public init(id: String, sessionID: String, toolName: String, subject: String, cwd: String,
                createdAt: Date, expiresAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.toolName = toolName
        self.subject = subject
        self.cwd = cwd
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

// MARK: - Apps

public struct AppsState: Codable, Sendable, Equatable {
    public var running: [RunningApp]
    public var installed: [InstalledApp]

    public init(running: [RunningApp] = [], installed: [InstalledApp] = []) {
        self.running = running
        self.installed = installed
    }
}

public struct RunningApp: Codable, Sendable, Equatable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    public var pid: Int32
    public var isFront: Bool
    public var isHidden: Bool
    public var windowCount: Int
    /// Live detail shown under the icon, e.g. "23 tabs" or "Playing".
    public var caption: String?
    public var memoryBytes: UInt64?

    public init(bundleID: String, name: String, pid: Int32, isFront: Bool, isHidden: Bool,
                windowCount: Int, caption: String? = nil, memoryBytes: UInt64? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
        self.isFront = isFront
        self.isHidden = isHidden
        self.windowCount = windowCount
        self.caption = caption
        self.memoryBytes = memoryBytes
    }
}

public struct InstalledApp: Codable, Sendable, Equatable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

// MARK: - Chrome

public struct ChromeState: Codable, Sendable, Equatable {
    public var isRunning: Bool
    public var windows: [ChromeWindow]
    /// Set when Chrome could not be scripted, usually a missing Automation permission.
    public var error: String?

    public init(isRunning: Bool = false, windows: [ChromeWindow] = [], error: String? = nil) {
        self.isRunning = isRunning
        self.windows = windows
        self.error = error
    }

    public var tabCount: Int { windows.reduce(0) { $0 + $1.tabs.count } }
}

public struct ChromeWindow: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var tabs: [ChromeTab]
    /// 1-based, as Chrome reports it.
    public var activeTabIndex: Int

    public init(id: Int, tabs: [ChromeTab], activeTabIndex: Int) {
        self.id = id
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
    }
}

public struct ChromeTab: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var title: String
    public var url: String

    public init(id: Int, title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }

    public var host: String {
        guard let host = URL(string: url)?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

// MARK: - Now playing

public struct NowPlayingState: Codable, Sendable, Equatable {
    public enum PlayerState: String, Codable, Sendable { case playing, paused, stopped }

    /// Display name of the app that's playing, e.g. "Chrome" or "Spotify".
    public var app: String
    public var bundleID: String?
    public var isRunning: Bool
    public var state: PlayerState
    public var trackID: String?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var duration: Double
    public var position: Double
    public var positionDate: Date
    public var volume: Int

    public init(app: String = "Music", bundleID: String? = nil, isRunning: Bool = false, state: PlayerState = .stopped,
                trackID: String? = nil, title: String? = nil, artist: String? = nil,
                album: String? = nil, duration: Double = 0, position: Double = 0,
                positionDate: Date = .now, volume: Int = 0) {
        self.app = app
        self.bundleID = bundleID
        self.isRunning = isRunning
        self.state = state
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.positionDate = positionDate
        self.volume = volume
    }

    /// Playback position extrapolated to `date` while playing.
    public func position(at date: Date) -> Double {
        guard state == .playing else { return position }
        return min(duration, position + date.timeIntervalSince(positionDate))
    }
}

// MARK: - Pad

public struct PadState: Codable, Sendable, Equatable {
    public var pages: [PadPage]

    public init(pages: [PadPage] = []) {
        self.pages = pages
    }
}

public struct PadPage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var sections: [PadSection]

    public init(id: String, title: String, sections: [PadSection]) {
        self.id = id
        self.title = title
        self.sections = sections
    }
}

public struct PadSection: Codable, Sendable, Equatable, Identifiable {
    public enum Style: String, Codable, Sendable {
        /// Wide toggles with their state written out.
        case modes
        /// Large keys with a command line on top and status underneath.
        case keys
        /// Short keys, six to a row.
        case compact
    }

    public var id: String
    public var title: String
    public var subtitle: String?
    public var style: Style
    public var items: [PadItem]

    public init(id: String, title: String, subtitle: String? = nil, style: Style, items: [PadItem]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.items = items
    }
}

public struct PadItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    /// Static description shown when there is no live status.
    public var subtitle: String?
    /// Small monospaced line on keys, usually the command.
    public var context: String?
    public var appBundleID: String?
    public var usesClaudeMark: Bool
    public var keycaps: [String]
    public var isToggle: Bool
    public var isOn: Bool
    /// Live state text for toggles, e.g. "2h left".
    public var stateText: String?
    public var isRunning: Bool
    public var runningSince: Date?
    public var lastRunAt: Date?
    public var lastResult: String?
    public var lastSucceeded: Bool?
    public var needsConfirmation: Bool

    public init(id: String, title: String, subtitle: String? = nil, context: String? = nil,
                appBundleID: String? = nil, usesClaudeMark: Bool = false, keycaps: [String] = [],
                isToggle: Bool = false, isOn: Bool = false, stateText: String? = nil,
                isRunning: Bool = false, runningSince: Date? = nil, lastRunAt: Date? = nil,
                lastResult: String? = nil, lastSucceeded: Bool? = nil, needsConfirmation: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.context = context
        self.appBundleID = appBundleID
        self.usesClaudeMark = usesClaudeMark
        self.keycaps = keycaps
        self.isToggle = isToggle
        self.isOn = isOn
        self.stateText = stateText
        self.isRunning = isRunning
        self.runningSince = runningSince
        self.lastRunAt = lastRunAt
        self.lastResult = lastResult
        self.lastSucceeded = lastSucceeded
        self.needsConfirmation = needsConfirmation
    }
}
