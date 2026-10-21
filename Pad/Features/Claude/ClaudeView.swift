import DashUpKit
import SwiftUI

/// Claude Code: a board of what every session is working on, and a detail view per session.
struct ClaudeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let id = model.claudeDetailID, let session = model.session(id) ?? model.claude.recent.first(where: { $0.id == id }) {
                ClaudeDetail(session: session)
                    .id(session.id)
                    .transition(.opacity)
            } else {
                ClaudeBoard()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.claudeDetailID)
    }
}

// MARK: - Board

private struct ClaudeBoard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let active = model.claude.sessions.filter { $0.phase != .idle }
        let earlier = model.claude.sessions.filter { $0.phase == .idle } + model.claude.recent
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude Code").font(.ui(30, .semibold)).tracking(-0.66).foregroundStyle(Theme.text)
                    summary.font(.ui(14.5)).foregroundStyle(Theme.text2)
                }
                .padding(.bottom, 28)

                ForEach(model.claude.pending) { ask in
                    BoardApproval(ask: ask, session: model.session(ask.sessionID))
                        .padding(.bottom, 16)
                }

                if active.isEmpty && model.claude.pending.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nothing running right now").font(.ui(17, .semibold)).foregroundStyle(Theme.text)
                        Text(model.claude.hooksInstalled
                             ? "Start Claude Code on your Mac and it shows up here."
                             : "Start Claude Code on your Mac and it shows up here. To approve requests from this iPad, choose Connect Claude Code in the DashUp menu on your Mac.")
                            .font(.ui(14)).foregroundStyle(Theme.text2).lineSpacing(4)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(radius: 18)
                    .padding(.bottom, 36)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(active) { session in
                            SessionTile(session: session)
                        }
                    }
                    .padding(.bottom, 36)
                }

                if !earlier.isEmpty {
                    SectionHeading(title: "Earlier today", detail: "\(earlier.count)")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 0) {
                        ForEach(earlier) { session in
                            EarlierRow(session: session)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
        }
        .scrollIndicators(.hidden)
    }

    /// "Two sessions are working, one needs you, and one finished recently."
    private var summary: Text {
        let sessions = model.claude.sessions
        let working = sessions.filter { $0.phase == .working }.count
        let orphanAsks = model.claude.pending.filter { ask in !sessions.contains { $0.id == ask.sessionID } }.count
        let needs = sessions.filter { $0.phase == .needsApproval || $0.phase == .waiting }.count + orphanAsks
        let finished = sessions.filter { $0.phase == .finished }.count
        var phrases: [(text: String, alert: Bool)] = []
        if working > 0 { phrases.append(("\(Format.spelled(working).lowercased()) \(working == 1 ? "session is" : "sessions are") working", false)) }
        if needs > 0 { phrases.append((needs == 1 ? "one needs you" : "\(Format.spelled(needs).lowercased()) need you", true)) }
        if finished > 0 { phrases.append(("\(Format.spelled(finished).lowercased()) finished recently", false)) }
        guard !phrases.isEmpty else { return Text(sessions.isEmpty ? "No sessions are open." : "Every session is quiet.") }

        var sentence = Text("")
        for (i, phrase) in phrases.enumerated() {
            let words = i == 0 ? phrase.text.prefix(1).uppercased() + phrase.text.dropFirst() : phrase.text
            let piece = phrase.alert ? Text(words).foregroundStyle(Theme.needsText) : Text(words)
            let joiner = i == 0 ? "" : (i == phrases.count - 1 ? (phrases.count > 2 ? ", and " : " and ") : ", ")
            sentence = Text("\(sentence)\(joiner)\(piece)")
        }
        return Text("\(sentence).")
    }
}

private struct BoardApproval: View {
    @Environment(AppModel.self) private var model
    let ask: PermissionAsk
    let session: ClaudeSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                StatusDot(phase: .needsApproval)
                Text(session?.name ?? "Claude Code").font(.ui(14, .semibold)).foregroundStyle(Theme.text)
                Text(ApprovalPanel.headline(ask).lowercased()).font(.ui(14)).foregroundStyle(Theme.text2)
                Spacer()
                Text(session?.project ?? ClaudePaths.short(ask.cwd)).font(.ui(12.5)).foregroundStyle(Theme.text3)
            }
            Text(ask.subject)
                .font(.mono(17))
                .lineSpacing(6)
                .foregroundStyle(Theme.text)
                .lineLimit(4)
                .padding(.top, 12)
            HStack(spacing: 8) {
                Ticking { now in
                    Text("\(ask.toolName) · back to terminal in \(Format.clock(ask.expiresAt.timeIntervalSince(now)))")
                        .font(.ui(12.5)).foregroundStyle(Theme.text3)
                }
                Spacer()
                QuietButton(title: "Deny", height: 40, fontSize: 14) { model.decide(ask, allow: false) }
                PillButton(title: "Allow", height: 40, fontSize: 14) { model.decide(ask, allow: true) }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 18)
    }
}

private struct SessionTile: View {
    @Environment(AppModel.self) private var model
    let session: ClaudeSession

    var body: some View {
        let waiting = session.phase == .waiting
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                StatusDot(phase: session.phase)
                // Don't repeat the headline when the session is named after it.
                let named = session.name != ClaudeText.headline(session)
                Text(named ? session.name : session.project).font(.ui(13)).foregroundStyle(Theme.text2).lineLimit(1)
                Spacer(minLength: 8)
                if named { Text(session.project).font(.ui(12.5)).foregroundStyle(Theme.text3).lineLimit(1) }
            }
            Text(ClaudeText.headline(session))
                .font(.ui(20, .semibold)).tracking(-0.3)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .padding(.top, 14)
            Ticking(interval: 30) { now in
                Text(waiting ? "Asked you a question · \(Format.shortDuration(now.timeIntervalSince(session.phaseSince)))" : SessionText.state(session, now: now))
                    .font(.ui(13.5))
                    .foregroundStyle(waiting ? Theme.needsText : Theme.text2)
            }
            .padding(.top, 6)
            if session.phase == .working, let activity = session.activity {
                ActivityLine(activity: activity).padding(.top, 14)
            }
            if let message = session.lastMessage {
                Text(SessionText.firstParagraph(message))
                    .font(.ui(13.5))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.text2)
                    .lineLimit(2)
                    .padding(.top, 14)
            }
            Spacer(minLength: 0)
            HStack {
                Text(ClaudeText.footer(session)).font(.ui(12.5)).foregroundStyle(Theme.text3).lineLimit(1)
                Spacer()
                Button(waiting ? "Answer on Mac" : "Show on Mac") { model.run(.focusSession(sessionID: session.id)) }
                    .font(.ui(13))
                    .foregroundStyle(Theme.text2)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(height: 236, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 16)
        .overlay {
            if waiting { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.needs.opacity(0.35)) }
        }
        .contentShape(.rect)
        .onTapGesture { model.claudeDetailID = session.id }
    }
}

private struct EarlierRow: View {
    @Environment(AppModel.self) private var model
    let session: ClaudeSession

    var body: some View {
        Button {
            model.claudeDetailID = session.id
        } label: {
            HStack(spacing: 12) {
                Circle().fill(Theme.text3).frame(width: 7, height: 7)
                Text(ClaudeText.headline(session)).font(.ui(13.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                if session.title != nil, session.name != session.title {
                    Text(session.name).font(.ui(12.5)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer(minLength: 8)
                Ticking(interval: 60) { now in
                    Text(Format.ago(session.phaseSince, now: now)).font(.ui(12.5)).foregroundStyle(Theme.text3)
                }
            }
            .frame(height: 56)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
    }
}

struct ActivityLine: View {
    let activity: String

    var body: some View {
        let (verb, target) = SessionText.split(activity)
        if let target {
            let mono = Text(target).font(.mono(12.5)).foregroundStyle(Theme.text2)
            Text("\(verb) \(mono)").font(.ui(13.5)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
        } else {
            Text(verb).font(.ui(13.5)).foregroundStyle(Theme.text3).lineLimit(1)
        }
    }
}

enum ClaudeText {
    /// What the session is about: Claude Code's own title, else the latest prompt.
    static func headline(_ s: ClaudeSession) -> String {
        if let title = s.title, !title.isEmpty { return title }
        if let prompt = s.lastPrompt { return SessionText.firstParagraph(prompt) }
        if let message = s.lastMessage { return SessionText.firstParagraph(message) }
        // Unnamed sessions fall back to an ID prefix; say where it is instead.
        let looksLikeID = s.name.count == 8 && s.name.allSatisfy(\.isHexDigit)
        return looksLikeID ? "Session in \(s.project)" : s.name
    }

    static func footer(_ s: ClaudeSession) -> String {
        var parts: [String] = []
        if let model = s.model { parts.append(SessionText.modelName(model)) }
        if s.steps > 0 { parts.append("\(s.steps) \(s.steps == 1 ? "step" : "steps")") }
        if !s.filesChanged.isEmpty { parts.append("\(s.filesChanged.count) \(s.filesChanged.count == 1 ? "file" : "files") changed") }
        else if let tokens = s.contextTokens { parts.append("\(Format.tokens(tokens)) tokens") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Detail

private struct ClaudeDetail: View {
    @Environment(AppModel.self) private var model
    let session: ClaudeSession
    @State private var showAllFiles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                model.claudeDetailID = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text("All sessions").font(.ui(14))
                }
                .foregroundStyle(Theme.text3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 18)

            HStack(alignment: .top, spacing: 40) {
                ScrollView { sidebar }
                    .scrollIndicators(.hidden)
                    .frame(width: 360)
                story
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                StatusDot(phase: session.phase)
                Text(session.name == ClaudeText.headline(session) ? session.project : "\(session.name) · \(session.project)")
                    .font(.ui(13)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Text(ClaudeText.headline(session))
                .font(.ui(26, .semibold)).tracking(-0.5)
                .lineSpacing(2)
                .foregroundStyle(Theme.text)
                .padding(.top, 12)
            Ticking(interval: 30) { now in
                Text(session.phase == .waiting ? "Asked you a question" : SessionText.state(session, now: now))
                    .font(.ui(14))
                    .foregroundStyle(session.phase == .waiting ? Theme.needsText : Theme.text2)
            }
            .padding(.top, 10)
            if session.phase == .working, let activity = session.activity {
                ActivityLine(activity: activity).padding(.top, 6)
            }
            if session.pid != 0 {
                Group {
                    if session.phase == .waiting {
                        PillButton(title: "Answer on Mac", height: 40, fontSize: 14) { model.run(.focusSession(sessionID: session.id)) }
                    } else {
                        OutlineButton(title: "Show on Mac") { model.run(.focusSession(sessionID: session.id)) }
                    }
                }
                .padding(.top, 22)
            }

            VStack(spacing: 0) {
                if let model = session.model { fact("Model", SessionText.modelName(model)) }
                if let branch = session.branch, branch != "HEAD" { fact("Branch", branch) }
                if let tokens = session.contextTokens { fact("Context", "\(Format.tokens(tokens)) tokens") }
                fact("Started", session.startedAt.formatted(date: Calendar.current.isDateInToday(session.startedAt) ? .omitted : .abbreviated, time: .shortened))
            }
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .padding(.top, 30)

            if !session.filesChanged.isEmpty {
                HStack(spacing: 8) {
                    Text("Files changed").font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                    Text("\(session.filesChanged.count)").font(.ui(13)).foregroundStyle(Theme.text3)
                }
                .padding(.top, 26)
                .padding(.bottom, 8)
                let files = showAllFiles ? session.filesChanged : Array(session.filesChanged.prefix(5))
                ForEach(files) { file in
                    HStack {
                        Text(file.path).font(.mono(12.5)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.head)
                        Spacer(minLength: 12)
                        Text(file.written ? "written" : "edited").font(.ui(12)).foregroundStyle(Theme.text3)
                    }
                    .frame(height: 30)
                }
                if session.filesChanged.count > 5 {
                    Button(showAllFiles ? "Show fewer" : "\(session.filesChanged.count - 5) more") { showAllFiles.toggle() }
                        .font(.ui(13)).foregroundStyle(Theme.text3).buttonStyle(.plain)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.bottom, 32)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.text3)
            Spacer(minLength: 16)
            Text(value).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
        }
        .font(.ui(13.5))
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    // MARK: Story

    private var story: some View {
        let turns = Turn.build(from: session.timeline, latestPrompt: session.lastPrompt)
        let reply = session.timeline.last { $0.kind == .text }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let ask = model.claude.pending(for: session.id) {
                    ApprovalPanel(ask: ask).padding(.bottom, 26)
                }
                if let reply {
                    Text("\(session.phase == .waiting ? "Question" : "Latest reply") · \(Format.ago(reply.date))")
                        .font(.ui(12.5)).foregroundStyle(Theme.text3)
                        .padding(.bottom, 10)
                    MarkdownView(text: reply.text)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(radius: 16)
                } else if let message = session.lastMessage {
                    MarkdownView(text: message)
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(radius: 16)
                }
                if !turns.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(turns.reversed().enumerated()), id: \.element.id) { index, turn in
                            TurnRow(turn: turn, startsOpen: index == 0)
                        }
                    }
                    .padding(.top, 28)
                }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }
}

/// One prompt and everything Claude did for it.
struct Turn: Identifiable {
    let id: String
    let prompt: String?
    let date: Date
    var tools: [TimelineItem] = []

    /// `latestPrompt` labels the steps when the prompt itself is older than the timeline.
    static func build(from timeline: [TimelineItem], latestPrompt: String? = nil) -> [Turn] {
        var turns: [Turn] = []
        for item in timeline {
            if item.kind == .prompt {
                turns.append(Turn(id: item.id, prompt: item.text, date: item.date))
            } else if item.kind == .tool {
                if turns.isEmpty { turns.append(Turn(id: "start", prompt: nil, date: item.date)) }
                turns[turns.count - 1].tools.append(item)
            }
        }
        if turns.count == 1, turns[0].prompt == nil, let latestPrompt {
            turns[0] = Turn(id: turns[0].id, prompt: latestPrompt, date: turns[0].date, tools: turns[0].tools)
        }
        return turns
    }

    var summary: String {
        var counts: [(String, Int)] = []
        func add(_ label: String) {
            if let i = counts.firstIndex(where: { $0.0 == label }) { counts[i].1 += 1 } else { counts.append((label, 1)) }
        }
        for tool in tools {
            switch tool.toolName ?? "" {
            case "Read": add("read")
            case "Edit", "MultiEdit", "NotebookEdit": add("edit")
            case "Write": add("write")
            case "Bash": add("bash")
            case "Grep", "Glob": add("search")
            case "WebFetch", "WebSearch": add("web")
            case "Task", "Agent": add("agent")
            default: add("other")
            }
        }
        guard !counts.isEmpty else { return "No tool calls" }
        let order = ["read", "edit", "write", "bash", "search", "web", "agent", "other"]
        return counts.sorted { order.firstIndex(of: $0.0)! < order.firstIndex(of: $1.0)! }.map { label, n in
            switch label {
            case "read": "Read \(n) \(n == 1 ? "file" : "files")"
            case "edit": "Edited \(n)"
            case "write": "Wrote \(n)"
            case "bash": "Ran \(n) \(n == 1 ? "command" : "commands")"
            case "search": "Searched \(n) \(n == 1 ? "time" : "times")"
            case "web": "Looked up \(n) \(n == 1 ? "page" : "pages")"
            case "agent": "\(n) \(n == 1 ? "agent" : "agents")"
            default: "Used \(n) \(n == 1 ? "tool" : "tools")"
            }
        }.joined(separator: " · ")
    }
}

private struct TurnRow: View {
    let turn: Turn
    let startsOpen: Bool
    @State private var open: Bool?
    @State private var showAll = false

    var body: some View {
        let isOpen = open ?? startsOpen
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { open = !isOpen }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(turn.prompt.map(SessionText.firstParagraph) ?? "Earlier in the session")
                            .font(.ui(14))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text(Format.ago(turn.date)).font(.ui(12.5)).foregroundStyle(Theme.text3).fixedSize()
                    }
                    Text(turn.summary).font(.ui(13)).foregroundStyle(Theme.text3)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isOpen, !turn.tools.isEmpty {
                let steps = showAll ? turn.tools : Array(turn.tools.suffix(6))
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(steps) { step in
                        HStack(spacing: 12) {
                            Text(step.text).font(.ui(13)).foregroundStyle(step.isError ? Theme.needsText : Theme.text3)
                                .frame(width: 72, alignment: .leading)
                            Text(step.detail ?? step.toolName ?? "")
                                .font(.mono(12.5)).foregroundStyle(Theme.text2)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .frame(height: 28)
                    }
                }
                .padding(.top, 12)
                if turn.tools.count > 6 {
                    Button(showAll ? "Show fewer" : "\(turn.tools.count - 6) more \(turn.tools.count - 6 == 1 ? "step" : "steps")") { showAll.toggle() }
                        .font(.ui(13)).foregroundStyle(Theme.text3).buttonStyle(.plain)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

// MARK: - Shared with Home

/// The approval treatment from Home, given more room: the command is the hero.
struct ApprovalPanel: View {
    @Environment(AppModel.self) private var model
    let ask: PermissionAsk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.headline(ask)).font(.ui(13.5)).foregroundStyle(Theme.text2)
            Text(ask.subject)
                .font(.mono(17))
                .lineSpacing(6)
                .foregroundStyle(Theme.text)
                .lineLimit(8)
                .textSelection(.enabled)
                .padding(.top, 12)
            HStack(spacing: 10) {
                Ticking { now in
                    Text("\(ask.toolName) · back to terminal in \(Format.clock(ask.expiresAt.timeIntervalSince(now)))")
                        .font(.ui(12.5))
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                QuietButton(title: "Deny", height: 44, fontSize: 14.5) { model.decide(ask, allow: false) }
                PillButton(title: "Allow", height: 44, fontSize: 14.5) { model.decide(ask, allow: true) }
            }
            .padding(.top, 20)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 18)
    }

    static func headline(_ ask: PermissionAsk) -> String {
        switch ask.toolName {
        case "Bash": "Wants to run"
        case "Edit", "MultiEdit", "NotebookEdit": "Wants to edit"
        case "Write": "Wants to write"
        case "Read": "Wants to read"
        case "WebFetch": "Wants to open"
        default: "Wants to use \(ask.toolName)"
        }
    }
}

enum ClaudePaths {
    /// "/Users/me/conductor/workspaces/DashUp/medan" → "DashUp/medan".
    static func short(_ path: String) -> String {
        path.split(separator: "/").suffix(2).joined(separator: "/")
    }
}
