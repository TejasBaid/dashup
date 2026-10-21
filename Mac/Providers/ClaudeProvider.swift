import AppKit
import DashUpKit
import Foundation

/// Tracks running Claude Code sessions.
///
/// Three sources are merged:
/// 1. `~/.claude/sessions/<pid>.json`, which Claude Code keeps for every live process (name, cwd,
///    busy/idle). The `*.key` files next to them are secrets and are never read.
/// 2. The session transcript (`~/.claude/projects/*/<sessionId>.jsonl`) for titles, messages and the
///    tool timeline.
/// 3. HTTP hook events for instant activity updates and permission requests.
@MainActor
final class ClaudeProvider {
    var onChange: (() -> Void)?
    /// Whether any iPad is connected; permission requests fall through to the terminal otherwise.
    var hasListeners: () -> Bool = { false }
    var approvalTimeout: TimeInterval = 45

    private(set) var state = ClaudeState()
    private let claudeDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
    private var timer: Timer?
    private var transcripts: [String: TranscriptCache] = [:]
    private var live: [String: LiveInfo] = [:]
    private var asks: [String: PendingAsk] = [:]
    private var recent: [ClaudeSession] = []
    private var recentScannedAt = Date.distantPast

    private struct LiveInfo {
        var activity: String?
        var waiting: Bool = false
        var turnStartedAt: Date?
    }

    private struct PendingAsk {
        let ask: PermissionAsk
        let continuation: CheckedContinuation<PermissionDecision, Never>
    }

    enum PermissionDecision { case allow, deny(String), passThrough }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: Hook events

    func handleHook(_ payload: [String: Any]) {
        guard let event = payload["hook_event_name"] as? String,
              let sessionID = payload["session_id"] as? String else { return }
        var info = live[sessionID] ?? LiveInfo()
        switch event {
        case "UserPromptSubmit":
            info = LiveInfo(activity: "Thinking", waiting: false, turnStartedAt: .now)
        case "PreToolUse":
            info.activity = Self.activity(tool: payload["tool_name"] as? String ?? "",
                                          input: payload["tool_input"] as? [String: Any] ?? [:],
                                          cwd: payload["cwd"] as? String)
            info.waiting = false
        case "PostToolUse":
            info.activity = "Thinking"
        case "Notification":
            let type = payload["notification_type"] as? String ?? payload["type"] as? String ?? ""
            if ["agent_needs_input", "elicitation_dialog", "permission_prompt", "idle_prompt"].contains(type) {
                // Ignore the permission prompt notification while our own hook is handling it.
                if !(type == "permission_prompt" && asks.values.contains { $0.ask.sessionID == sessionID }) {
                    info.waiting = type != "idle_prompt"
                }
            }
        case "Stop", "StopFailure", "SessionEnd":
            info.activity = nil
            info.waiting = false
        default:
            break
        }
        live[sessionID] = info
        refresh()
    }

    /// Called by the hook server for `PermissionRequest`; suspends until the iPad decides or the timeout passes.
    func requestPermission(_ payload: [String: Any]) async -> PermissionDecision {
        guard hasListeners(),
              let sessionID = payload["session_id"] as? String else { return .passThrough }
        let tool = payload["tool_name"] as? String ?? "Tool"
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        let cwd = payload["cwd"] as? String ?? ""
        let id = UUID().uuidString
        let ask = PermissionAsk(id: id, sessionID: sessionID, toolName: tool,
                                subject: Self.subject(tool: tool, input: input, cwd: cwd), cwd: cwd,
                                createdAt: .now, expiresAt: .now.addingTimeInterval(approvalTimeout))

        let decision = await withCheckedContinuation { continuation in
            asks[id] = PendingAsk(ask: ask, continuation: continuation)
            refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + approvalTimeout) { [weak self] in
                MainActor.assumeIsolated { self?.resolve(id, .passThrough) }
            }
        }
        return decision
    }

    func decide(requestID: String, allow: Bool, reason: String?) -> Bool {
        guard asks[requestID] != nil else { return false }
        resolve(requestID, allow ? .allow : .deny(reason ?? "Denied from DashUp on iPad"))
        return true
    }

    /// Drops a pending ask whose HTTP request went away (Claude moved on or was interrupted).
    func cancelAsk(matching sessionID: String) {
        for (id, pending) in asks where pending.ask.sessionID == sessionID { resolve(id, .passThrough) }
    }

    private func resolve(_ id: String, _ decision: PermissionDecision) {
        guard let pending = asks.removeValue(forKey: id) else { return }
        pending.continuation.resume(returning: decision)
        if case .allow = decision { live[pending.ask.sessionID, default: LiveInfo()].activity = "Thinking" }
        refresh()
    }

    // MARK: Focus

    func focus(sessionID: String) -> Bool {
        guard let session = state.sessions.first(where: { $0.id == sessionID }) else { return false }
        if session.isConductor,
           let conductor = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "Conductor" }) {
            return conductor.activate()
        }
        var pid = session.pid
        for _ in 0..<12 {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                return app.activate()
            }
            guard let parent = Self.parentPID(of: pid), parent > 1 else { break }
            pid = parent
        }
        return false
    }

    // MARK: Refresh

    func refresh() {
        let registry = readRegistry()
        var sessions: [ClaudeSession] = []
        for entry in registry {
            let transcript = transcript(for: entry)
            let info = live[entry.sessionId]
            let hasAsk = asks.values.contains { $0.ask.sessionID == entry.sessionId }
            let busy = entry.status == "busy"
            let statusDate = Date(timeIntervalSince1970: (entry.statusUpdatedAt ?? entry.startedAt) / 1000)

            let phase: SessionPhase
            if hasAsk { phase = .needsApproval }
            else if info?.waiting == true { phase = .waiting }
            else if busy { phase = .working }
            else if Date.now.timeIntervalSince(statusDate) < 30 * 60, transcript?.lastAssistantText != nil { phase = .finished }
            else { phase = .idle }

            var activity: String?
            if phase == .working { activity = info?.activity ?? transcript?.lastActivity ?? "Thinking" }

            sessions.append(ClaudeSession(
                id: entry.sessionId, pid: entry.pid, name: entry.name ?? String(entry.sessionId.prefix(8)),
                cwd: entry.cwd, project: Self.projectLabel(entry.cwd),
                isConductor: entry.cwd.contains("/conductor/workspaces/"),
                phase: phase, phaseSince: busy ? (info?.turnStartedAt ?? transcript?.lastPromptAt ?? statusDate) : statusDate,
                startedAt: Date(timeIntervalSince1970: entry.startedAt / 1000),
                title: transcript?.title, lastPrompt: transcript?.lastPrompt,
                lastMessage: transcript?.lastAssistantText, activity: activity,
                model: transcript?.model, branch: transcript?.branch,
                contextTokens: transcript?.contextTokens, timeline: transcript?.timeline ?? [],
                filesChanged: transcript?.filesChanged ?? [], steps: transcript?.steps ?? 0))
        }
        // Needs-you first, then working, then most recent.
        let order: [SessionPhase: Int] = [.needsApproval: 0, .waiting: 1, .working: 2, .finished: 3, .idle: 4]
        sessions.sort { (order[$0.phase]!, -$0.phaseSince.timeIntervalSince1970) < (order[$1.phase]!, -$1.phaseSince.timeIntervalSince1970) }

        let liveIDs = Set(sessions.map(\.id))
        live = live.filter { liveIDs.contains($0.key) }
        transcripts = transcripts.filter { liveIDs.contains($0.key) }

        if Date.now.timeIntervalSince(recentScannedAt) > 60 { scanRecent(excluding: liveIDs) }
        let newState = ClaudeState(sessions: sessions,
                                   pending: asks.values.map(\.ask).sorted { $0.createdAt < $1.createdAt },
                                   hooksInstalled: HookInstaller.isInstalled,
                                   recent: recent.filter { !liveIDs.contains($0.id) })
        if newState != state {
            state = newState
            onChange?()
        }
    }

    // MARK: Registry

    private struct RegistryEntry: Decodable {
        let pid: Int32
        let sessionId: String
        let cwd: String
        let startedAt: Double
        let name: String?
        let status: String?
        let statusUpdatedAt: Double?
    }

    private func readRegistry() -> [RegistryEntry] {
        let dir = claudeDir.appending(path: "sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(RegistryEntry.self, from: Data(contentsOf: $0)) }
            .filter { kill($0.pid, 0) == 0 || errno == EPERM }
    }

    // MARK: Transcripts

    private func transcript(for entry: RegistryEntry) -> TranscriptCache? {
        var cache = transcripts[entry.sessionId] ?? TranscriptCache()
        if cache.url == nil { cache.url = findTranscript(sessionID: entry.sessionId, cwd: entry.cwd) }
        guard let url = cache.url,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let modified = attrs[.modificationDate] as? Date ?? .distantPast
        if size != cache.size || modified != cache.modified {
            cache.size = size
            cache.modified = modified
            cache.parse(url: url, cwd: entry.cwd)
        }
        transcripts[entry.sessionId] = cache
        return cache
    }

    private func findTranscript(sessionID: String, cwd: String) -> URL? {
        let projects = claudeDir.appending(path: "projects")
        let guess = projects.appending(path: cwd.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-"))
            .appending(path: "\(sessionID).jsonl")
        if FileManager.default.fileExists(atPath: guess.path) { return guess }
        let dirs = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return dirs.map { $0.appending(path: "\(sessionID).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Recent sessions

    /// Transcripts touched in the last 12 hours whose process has ended, for the "Earlier today" list.
    private func scanRecent(excluding live: Set<String>) {
        recentScannedAt = .now
        let fm = FileManager.default
        let projects = claudeDir.appending(path: "projects")
        let cutoff = Date.now.addingTimeInterval(-12 * 3600)
        var candidates: [(URL, Date)] = []
        for dir in (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
            for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where file.pathExtension == "jsonl" {
                let id = file.deletingPathExtension().lastPathComponent
                guard !live.contains(id),
                      let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      modified > cutoff else { continue }
                candidates.append((file, modified))
            }
        }
        recent = candidates.sorted { $0.1 > $1.1 }.prefix(12).compactMap { url, modified in
            var cache = TranscriptCache()
            cache.parse(url: url, cwd: "", tailBytes: 160 * 1024)
            // Skip one-off runs that never produced a reply.
            guard cache.lastAssistantText != nil || cache.title != nil else { return nil }
            let cwd = cache.cwd ?? ""
            let id = url.deletingPathExtension().lastPathComponent
            return ClaudeSession(
                id: id, pid: 0, name: cache.title ?? String(id.prefix(8)), cwd: cwd,
                project: Self.projectLabel(cwd), isConductor: cwd.contains("/conductor/workspaces/"),
                phase: .idle, phaseSince: cache.lastDate ?? modified, startedAt: cache.firstDate ?? modified,
                title: cache.title, lastPrompt: cache.lastPrompt, lastMessage: cache.lastAssistantText.map { String($0.prefix(400)) },
                model: cache.model, branch: cache.branch, steps: cache.steps)
        }
    }

    // MARK: Labels

    nonisolated static func projectLabel(_ cwd: String) -> String {
        let parts = cwd.split(separator: "/").map(String.init)
        if let i = parts.firstIndex(of: "workspaces"), i > 0, parts[i - 1] == "conductor", parts.count > i + 2 {
            return "\(parts[i + 1]) / \(parts[i + 2])"
        }
        return parts.last ?? cwd
    }

    nonisolated static func relative(_ path: String, to cwd: String?) -> String {
        if let cwd, path.hasPrefix(cwd + "/") { return String(path.dropFirst(cwd.count + 1)) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    nonisolated static func subject(tool: String, input: [String: Any], cwd: String) -> String {
        if let command = input["command"] as? String { return command }
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String { return relative(path, to: cwd) }
        if let url = input["url"] as? String { return url }
        if let pattern = input["pattern"] as? String { return pattern }
        if let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]) {
            return String(String(decoding: data, as: UTF8.self).prefix(300))
        }
        return tool
    }

    nonisolated static func activity(tool: String, input: [String: Any], cwd: String?) -> String {
        let path = (input["file_path"] as? String).map { relative($0, to: cwd) }
        switch tool {
        case "Bash": return "Running \(firstLine(input["command"] as? String ?? ""))"
        case "Read": return "Reading \(path ?? "a file")"
        case "Edit", "MultiEdit": return "Editing \(path ?? "a file")"
        case "Write": return "Writing \(path ?? "a file")"
        case "NotebookEdit": return "Editing a notebook"
        case "Grep": return "Searching for \(input["pattern"] as? String ?? "text")"
        case "Glob": return "Looking for \(input["pattern"] as? String ?? "files")"
        case "WebFetch": return "Reading \(URL(string: input["url"] as? String ?? "")?.host() ?? "a web page")"
        case "WebSearch": return "Searching the web"
        case "Task", "Agent": return "Running an agent"
        case "TodoWrite": return "Updating its plan"
        default: return tool.hasPrefix("mcp__") ? "Using \(tool.split(separator: "_").dropFirst(2).first ?? "a tool")" : "Using \(tool)"
        }
    }

    nonisolated static func firstLine(_ text: String) -> String {
        String(text.split(separator: "\n", maxSplits: 1).first ?? "").trimmingCharacters(in: .whitespaces)
    }

    nonisolated private static func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
