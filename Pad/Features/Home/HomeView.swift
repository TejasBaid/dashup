import DashUpKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 80
            let columns = Columns(width: width)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HomeHeader()
                        .padding(.bottom, Theme.sectionGap)
                    ClaudeSection(columns: columns)
                        .padding(.bottom, Theme.sectionGap)
                    AppsRow(width: width)
                        .padding(.bottom, Theme.sectionGap)
                    HStack(alignment: .top, spacing: Columns.gap) {
                        RecentTabs(columns: columns)
                            .frame(width: columns.first + Columns.gap + columns.other)
                        QuickOpen()
                            .frame(width: columns.other)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 40)
                .padding(.top, 32)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// The 1.3 : 1 : 1 column system shared by the session row and the bottom row.
struct Columns {
    static let gap: CGFloat = 16
    let first: CGFloat
    let other: CGFloat

    init(width: CGFloat) {
        let unit = (width - Self.gap * 2) / 3.3
        first = unit * 1.3
        other = unit
    }
}

// MARK: - Header

private struct HomeHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Ticking(interval: 60) { now in
                    Text(greeting(now))
                        .font(.ui(30, .semibold))
                        .tracking(-0.66)
                        .foregroundStyle(Theme.text)
                        .frame(height: 36, alignment: .leading)
                }
                summary
                    .font(.ui(14.5))
                    .foregroundStyle(Theme.text2)
            }
            Spacer()
            ConnectionLabel()
                .frame(height: 36)
        }
    }

    private func greeting(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part = hour < 5 ? "Good evening" : hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return model.firstName.isEmpty ? part : "\(part), \(model.firstName)"
    }

    private var summary: Text {
        let sessions = model.claude.sessions
        let working = sessions.filter { $0.phase == .working }.count
        let needs = sessions.filter { $0.phase == .needsApproval || $0.phase == .waiting }.count
        let needsPhrase = needs == 1 ? "one needs you" : "\(Format.spelled(needs).lowercased()) need you"
        let workingPhrase = "\(Format.spelled(working)) \(working == 1 ? "session is" : "sessions are") working"
        switch (working, needs) {
        case (0, 0):
            return Text(sessions.isEmpty ? "Nothing is running in Claude Code." : "Every session is quiet.")
        case (0, _):
            let capitalized = Text(needsPhrase.prefix(1).uppercased() + needsPhrase.dropFirst()).foregroundStyle(Theme.needsText)
            return Text("\(capitalized).")
        case (_, 0):
            return Text("\(workingPhrase).")
        default:
            let needsText = Text(needsPhrase).foregroundStyle(Theme.needsText)
            return Text("\(workingPhrase) and \(needsText).")
        }
    }
}

struct ConnectionLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.status == .connected ? Theme.done : Theme.text3)
                .frame(width: 7, height: 7)
            Text(model.status == .connected ? model.shortMacName : "Connecting to \(model.shortMacName)…")
        }
        .font(.ui(13.5))
        .foregroundStyle(Theme.text2)
    }
}

// MARK: - Claude

private struct ClaudeSection: View {
    @Environment(AppModel.self) private var model
    let columns: Columns

    var body: some View {
        let sessions = Array(Self.displayed(model.claude).prefix(3))
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Claude Code", detail: detail) {
                HeadingLink(title: "All sessions") { model.screen = .claude }
            }
            HStack(alignment: .top, spacing: Columns.gap) {
                if sessions.isEmpty {
                    EmptySessions()
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        SessionCard(session: session, ask: model.claude.pending(for: session.id))
                            .frame(width: index == 0 ? columns.first : columns.other)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Sessions in Mac order, plus a stand-in for any request whose session hasn't been seen yet,
    /// so an approval is never hidden.
    static func displayed(_ state: ClaudeState) -> [ClaudeSession] {
        let known = Set(state.sessions.map(\.id))
        let orphans = state.pending.filter { !known.contains($0.sessionID) }.map { ask in
            ClaudeSession(id: ask.sessionID, pid: 0, name: "Claude Code", cwd: ask.cwd, project: ClaudePaths.short(ask.cwd),
                          isConductor: false, phase: .needsApproval, phaseSince: ask.createdAt, startedAt: ask.createdAt)
        }
        return orphans + state.sessions
    }

    private var detail: String? {
        let live = model.claude.sessions.filter { $0.phase != .idle }.count
        return live == 0 ? nil : "\(live) running"
    }
}

private struct EmptySessions: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No sessions running").font(.ui(15, .semibold)).foregroundStyle(Theme.text)
            Text(model.claude.hooksInstalled
                 ? "Start Claude Code on your Mac and it will show up here."
                 : "Start Claude Code on your Mac and it will show up here. To approve requests from this iPad, choose Connect Claude Code in the DashUp menu on your Mac.")
                .font(.ui(13.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(4)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(height: 200, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct SessionCard: View {
    @Environment(AppModel.self) private var model
    let session: ClaudeSession
    let ask: PermissionAsk?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                StatusDot(phase: session.phase)
                Text(session.name).font(.ui(15, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 8)
                Text(session.project).font(.ui(12.5)).foregroundStyle(Theme.text3).lineLimit(1)
            }
            .frame(height: 20)

            if let ask {
                Text(ask.subject)
                    .font(.mono(15))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .padding(.top, 14)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Ticking { now in
                        Text("\(ask.toolName) · back to terminal in \(Format.clock(ask.expiresAt.timeIntervalSince(now)))")
                            .font(.ui(12.5))
                            .foregroundStyle(Theme.text3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    QuietButton(title: "Deny") { model.decide(ask, allow: false) }
                    PillButton(title: "Allow") { model.decide(ask, allow: true) }
                }
                .frame(height: 36)
            } else {
                Ticking(interval: 30) { now in
                    Text(SessionText.state(session, now: now))
                        .font(.ui(13))
                        .foregroundStyle(Theme.text2)
                }
                .padding(.top, 12)
                if let message = session.lastMessage ?? session.title ?? session.lastPrompt {
                    Text(SessionText.firstParagraph(message))
                        .font(.ui(13.5))
                        .lineSpacing(3.5)
                        .foregroundStyle(Theme.text2)
                        .lineLimit(3)
                        .padding(.top, 8)
                }
                Spacer(minLength: 0)
                SessionFooter(session: session)
                    .frame(height: 36, alignment: .leading)
            }
        }
        .padding(20)
        .frame(height: 200, alignment: .topLeading)
        .card()
        .contentShape(.rect)
        .onTapGesture {
            model.claudeDetailID = session.id
            model.screen = .claude
        }
    }
}

struct SessionFooter: View {
    let session: ClaudeSession

    var body: some View {
        Group {
            switch session.phase {
            case .working:
                if let activity = session.activity {
                    let (verb, target) = SessionText.split(activity)
                    if let target {
                        let mono = Text(target).font(.mono(12)).foregroundStyle(Theme.text2)
                        Text("\(verb) \(mono)").foregroundStyle(Theme.text3)
                    } else {
                        Text(verb).foregroundStyle(Theme.text3)
                    }
                }
            case .waiting:
                Text("Waiting for your reply on the Mac").foregroundStyle(Theme.text3)
            default:
                Text(SessionText.stats(session)).foregroundStyle(Theme.text3)
            }
        }
        .font(.ui(12.5))
        .lineLimit(1)
    }
}

enum SessionText {
    static func state(_ s: ClaudeSession, now: Date) -> String {
        let since = Format.shortDuration(now.timeIntervalSince(s.phaseSince))
        switch s.phase {
        case .working: return "Working · \(since)"
        case .needsApproval: return "Needs approval"
        case .waiting: return "Waiting for you"
        case .finished: return "Finished · \(Format.ago(s.phaseSince, now: now))"
        case .idle: return "Idle · \(since)"
        }
    }

    static func stats(_ s: ClaudeSession) -> String {
        var parts: [String] = []
        if let tokens = s.contextTokens { parts.append("\(Format.tokens(tokens)) tokens") }
        if let model = s.model { parts.append(modelName(model)) }
        if let branch = s.branch, !s.isConductor, branch != "HEAD" { parts.append(branch) }
        return parts.joined(separator: " · ")
    }

    /// "claude-opus-5-5" → "Opus 5.5".
    static func modelName(_ id: String) -> String {
        let parts = id.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().prefix { $0.allSatisfy(\.isNumber) && $0.count <= 2 }.joined(separator: ".")
        return family.capitalized + (version.isEmpty ? "" : " \(version)")
    }

    /// "Editing Link/Bridge.swift" → ("Editing", "Link/Bridge.swift").
    static func split(_ activity: String) -> (String, String?) {
        let verbs = ["Editing", "Reading", "Writing", "Running", "Searching for", "Looking for"]
        for verb in verbs where activity.hasPrefix(verb + " ") {
            return (verb, String(activity.dropFirst(verb.count + 1)))
        }
        return (activity, nil)
    }

    static func firstParagraph(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        let paragraph = cleaned.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? cleaned
        return paragraph.trimmingCharacters(in: CharacterSet(charactersIn: "#- ").union(.whitespaces))
    }
}

// MARK: - Apps

private struct AppsRow: View {
    @Environment(AppModel.self) private var model
    let width: CGFloat

    private let item: CGFloat = 84
    private let spacing: CGFloat = 28

    var body: some View {
        let runningIDs = Set(model.apps.running.map(\.bundleID))
        let installed = Dictionary(model.apps.installed.map { ($0.bundleID, $0.name) }, uniquingKeysWith: { a, _ in a })
        let pinned = model.settings.pinnedApps.filter { !runningIDs.contains($0) && installed[$0] != nil }.prefix(4)
        let pinnedWidth = pinned.isEmpty ? 0 : CGFloat(pinned.count) * (item + spacing) - spacing + 65
        let openSlots = max(1, Int((width - pinnedWidth + spacing) / (item + spacing)))
        let open = Array(model.apps.running.prefix(openSlots))

        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Apps") {
                HeadingLink(title: "All apps") { model.screen = .apps }
            }
            HStack(alignment: .top, spacing: 0) {
                group("Open") {
                    ForEach(open) { app in
                        AppTile(bundleID: app.bundleID, name: app.name, caption: app.caption ?? " ", isFront: app.isFront)
                    }
                }
                if !pinned.isEmpty {
                    Rectangle().fill(Theme.hairline2).frame(width: 1, height: 118).padding(.top, 28).padding(.horizontal, 32)
                    group("Pinned") {
                        ForEach(Array(pinned), id: \.self) { id in
                            AppTile(bundleID: id, name: installed[id] ?? id, caption: " ", isFront: false)
                        }
                    }
                }
            }
        }
    }

    private func group<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.ui(12)).foregroundStyle(Theme.text3).frame(height: 16)
            HStack(alignment: .top, spacing: spacing) { content() }
        }
    }
}

struct AppTile: View {
    @Environment(AppModel.self) private var model
    let bundleID: String
    let name: String
    let caption: String
    let isFront: Bool

    var body: some View {
        Button {
            model.run(.launchApp(bundleID: bundleID))
        } label: {
            VStack(spacing: 0) {
                AppIcon(bundleID: bundleID, size: 62)
                    .frame(width: 84, height: 84)
                    .background(isFront ? Theme.surface2 : .clear, in: .rect(cornerRadius: 20, style: .continuous))
                    .padding(.bottom, 8)
                Text(name)
                    .font(.ui(13, isFront ? .medium : .regular))
                    .foregroundStyle(isFront ? Theme.text : Theme.text2)
                    .frame(height: 17)
                Text(caption)
                    .font(.ui(12))
                    .foregroundStyle(Theme.text3)
                    .frame(height: 16)
            }
            .fixedSize()
            .frame(width: 84)
        }
        .buttonStyle(PressableStyle())
        .contextMenu { AppMenu(bundleID: bundleID, isRunning: model.apps.running.contains { $0.bundleID == bundleID }) }
    }
}

struct AppMenu: View {
    @Environment(AppModel.self) private var model
    let bundleID: String
    let isRunning: Bool

    var body: some View {
        Button(isRunning ? "Switch to" : "Open", systemImage: "arrow.up.forward.app") { model.run(.launchApp(bundleID: bundleID)) }
        if isRunning {
            Button("Hide", systemImage: "eye.slash") { model.run(.hideApp(bundleID: bundleID)) }
        }
        Button(model.settings.pinnedApps.contains(bundleID) ? "Unpin" : "Pin to Home", systemImage: "pin") {
            model.settings.togglePin(bundleID)
        }
        if isRunning {
            Divider()
            Button("Quit", systemImage: "xmark", role: .destructive) { model.run(.quitApp(bundleID: bundleID)) }
        }
    }
}

// MARK: - Tabs

private struct RecentTabs: View {
    @Environment(AppModel.self) private var model
    let columns: Columns

    var body: some View {
        let tabs = Self.recent(model.chrome, limit: 10)
        let half = (tabs.count + 1) / 2
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Chrome", detail: model.chrome.isRunning ? "\(model.chrome.tabCount) tabs" : nil) {
                HeadingLink(title: "All tabs") { model.screen = .tabs }
            }
            if let error = model.chrome.error {
                Text(error).font(.ui(13.5)).foregroundStyle(Theme.text2).padding(.vertical, 12)
            } else if tabs.isEmpty {
                Text(model.chrome.isRunning ? "No tabs open." : "Chrome isn't open.")
                    .font(.ui(13.5)).foregroundStyle(Theme.text3).padding(.vertical, 12)
            } else {
                HStack(alignment: .top, spacing: Columns.gap) {
                    VStack(spacing: 0) { ForEach(tabs.prefix(half), id: \.tab.id) { TabRow(window: $0.window, tab: $0.tab) } }
                        .frame(width: columns.first)
                    VStack(spacing: 0) { ForEach(tabs.dropFirst(half), id: \.tab.id) { TabRow(window: $0.window, tab: $0.tab) } }
                        .frame(width: columns.other)
                }
            }
        }
    }

    /// Each window's active tab first, then the rest in order.
    static func recent(_ chrome: ChromeState, limit: Int) -> [(window: Int, tab: ChromeTab)] {
        var result: [(Int, ChromeTab)] = []
        for window in chrome.windows where window.tabs.indices.contains(window.activeTabIndex - 1) {
            result.append((window.id, window.tabs[window.activeTabIndex - 1]))
        }
        for window in chrome.windows {
            for (i, tab) in window.tabs.enumerated() where i != window.activeTabIndex - 1 {
                result.append((window.id, tab))
            }
        }
        return Array(result.prefix(limit))
    }
}

struct TabRow: View {
    @Environment(AppModel.self) private var model
    let window: Int
    let tab: ChromeTab
    var isActive = false

    var body: some View {
        Button {
            model.run(.focusTab(windowID: window, tabID: tab.id))
        } label: {
            HStack(spacing: 12) {
                Favicon(url: tab.url)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title.isEmpty ? tab.url : tab.title)
                        .font(.ui(13.5, isActive ? .medium : .regular))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(tab.host).font(.ui(12)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 12)
            .frame(height: 60)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button("Show on Mac", systemImage: "macwindow") { model.run(.focusTab(windowID: window, tabID: tab.id)) }
            Button("Close tab", systemImage: "xmark", role: .destructive) { model.run(.closeTab(windowID: window, tabID: tab.id)) }
        }
    }
}

// MARK: - Quick open

private struct QuickOpen: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Open in Chrome")
            VStack(spacing: 0) {
                URLField(text: $text, placeholder: "Type a URL or search") {
                    model.open(text)
                    text = ""
                }
                let sites = Array(model.settings.sites.prefix(6))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
                    ForEach(sites) { site in
                        Button {
                            model.open(site.url)
                        } label: {
                            VStack(spacing: 9) {
                                Favicon(url: site.url, size: 46, radius: 12)
                                Text(site.title).font(.ui(12.5)).foregroundStyle(Theme.text2).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 98)
                            .contentShape(.rect)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.top, 12)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity, alignment: .top)
            .card()
        }
    }
}

struct URLField: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.text3))
            .font(.ui(13.5))
            .foregroundStyle(Theme.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.webSearch)
            .submitLabel(.go)
            .onSubmit(onSubmit)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Theme.well, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
    }
}
