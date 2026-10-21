import DashUpKit
import Foundation

/// Parsed view of the tail of a Claude Code transcript (`<sessionId>.jsonl`).
struct TranscriptCache {
    var url: URL?
    var size = -1
    var modified = Date.distantPast

    var title: String?
    var lastPrompt: String?
    var lastPromptAt: Date?
    var lastAssistantText: String?
    var lastActivity: String?
    var model: String?
    var branch: String?
    var contextTokens: Int?
    var timeline: [TimelineItem] = []
    var filesChanged: [FileChange] = []
    var steps = 0
    var cwd: String?
    var firstDate: Date?
    var lastDate: Date?
    /// Steps and changed files are counted across the whole file, incrementally from here.
    private var statsOffset: UInt64 = 0
    private var changedFiles: [String: Bool] = [:]
    private var changedOrder: [String] = []

    /// Only the end of the file is read; long sessions can be many megabytes.
    static let tailBytes = 768 * 1024
    private static let maxTimeline = 160

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    mutating func parse(url: URL, cwd: String, tailBytes: Int = TranscriptCache.tailBytes) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let start = end > UInt64(tailBytes) ? end - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return }

        var lines = data.split(separator: UInt8(ascii: "\n"))
        if start > 0, !lines.isEmpty { lines.removeFirst() } // partial first line

        var items: [TimelineItem] = []
        var toolIndex: [String: Int] = [:]
        var lastActivity: String?
        title = nil
        lastAssistantText = nil
        firstDate = nil
        countSteps(handle: handle, end: end, cwd: cwd)

        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = object["type"] as? String else { continue }
            let date = (object["timestamp"] as? String).flatMap { Self.isoFormatter.date(from: $0) } ?? .distantPast
            let uuid = object["uuid"] as? String ?? UUID().uuidString
            if date != .distantPast {
                if firstDate == nil { firstDate = date }
                lastDate = date
            }
            if let lineCwd = object["cwd"] as? String { self.cwd = lineCwd }

            switch type {
            case "ai-title":
                title = object["aiTitle"] as? String
            case "last-prompt":
                if let prompt = object["lastPrompt"] as? String { lastPrompt = Self.cleanPrompt(prompt) }
            case "user":
                guard object["isMeta"] as? Bool != true, object["isSidechain"] as? Bool != true,
                      let message = object["message"] as? [String: Any] else { continue }
                if let text = message["content"] as? String {
                    if let prompt = Self.cleanPrompt(text) {
                        items.append(TimelineItem(id: uuid, kind: .prompt, date: date, text: prompt))
                        lastPrompt = prompt
                        lastPromptAt = date
                        lastActivity = nil
                    }
                } else if let blocks = message["content"] as? [[String: Any]] {
                    for (i, block) in blocks.enumerated() {
                        switch block["type"] as? String {
                        case "tool_result":
                            if block["is_error"] as? Bool == true,
                               let id = block["tool_use_id"] as? String, let index = toolIndex[id] {
                                items[index].isError = true
                            }
                        case "text":
                            if let prompt = Self.cleanPrompt(block["text"] as? String ?? "") {
                                items.append(TimelineItem(id: "\(uuid)-\(i)", kind: .prompt, date: date, text: prompt))
                                lastPrompt = prompt
                                lastPromptAt = date
                            }
                        default: break
                        }
                    }
                }
                if let branch = object["gitBranch"] as? String { self.branch = branch }
            case "assistant":
                guard object["isSidechain"] as? Bool != true,
                      let message = object["message"] as? [String: Any] else { continue }
                if let model = message["model"] as? String, model != "<synthetic>" { self.model = model }
                if let usage = message["usage"] as? [String: Any] {
                    let total = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                        .compactMap { (usage[$0] as? NSNumber)?.intValue }.reduce(0, +)
                    if total > 0 { contextTokens = total }
                }
                for (i, block) in ((message["content"] as? [[String: Any]]) ?? []).enumerated() {
                    switch block["type"] as? String {
                    case "text":
                        let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        items.append(TimelineItem(id: "\(uuid)-\(i)", kind: .text, date: date, text: String(text.prefix(6000))))
                        lastAssistantText = text
                    case "tool_use":
                        let name = block["name"] as? String ?? "Tool"
                        let input = block["input"] as? [String: Any] ?? [:]
                        let (verb, detail) = Self.describe(tool: name, input: input, cwd: cwd)
                        if let id = block["id"] as? String { toolIndex[id] = items.count }
                        items.append(TimelineItem(id: "\(uuid)-\(i)", kind: .tool, date: date, text: verb,
                                                  detail: detail.map { String($0.prefix(300)) }, toolName: name))

                        lastActivity = ClaudeProvider.activity(tool: name, input: input, cwd: cwd)
                    default: break
                    }
                }
            default:
                break
            }
        }
        self.lastActivity = lastActivity
        timeline = Array(items.suffix(Self.maxTimeline))
        filesChanged = changedOrder.reversed().map { FileChange(path: $0, written: changedFiles[$0] ?? false) }
    }

    /// Counts tool calls and changed files in bytes not yet seen. Only lines that contain a tool call
    /// are decoded, so even very long transcripts are cheap after the first pass.
    private mutating func countSteps(handle: FileHandle, end: UInt64, cwd: String) {
        guard end > statsOffset else {
            if end < statsOffset { statsOffset = 0; steps = 0; changedFiles = [:]; changedOrder = [] }
            return
        }
        try? handle.seek(toOffset: statsOffset)
        guard let data = try? handle.read(upToCount: Int(end - statsOffset)),
              let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let marker = Data(#""type":"tool_use""#.utf8)
        for line in data[...lastNewline].split(separator: UInt8(ascii: "\n")) where line.range(of: marker) != nil {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "assistant", object["isSidechain"] as? Bool != true,
                  let blocks = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
            for block in blocks where block["type"] as? String == "tool_use" {
                steps += 1
                let name = block["name"] as? String ?? ""
                let input = block["input"] as? [String: Any] ?? [:]
                guard ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(name),
                      let raw = input["file_path"] as? String ?? input["notebook_path"] as? String else { continue }
                let path = ClaudeProvider.relative(raw, to: cwd.isEmpty ? (object["cwd"] as? String) : cwd)
                if changedFiles[path] == nil { changedOrder.append(path) } else if let i = changedOrder.firstIndex(of: path) {
                    changedOrder.remove(at: i)
                    changedOrder.append(path)
                }
                changedFiles[path] = (changedFiles[path] ?? false) || name == "Write"
            }
        }
        statsOffset += UInt64(data.distance(from: data.startIndex, to: lastNewline) + 1)
    }

    static func describe(tool: String, input: [String: Any], cwd: String) -> (String, String?) {
        let path = (input["file_path"] as? String ?? input["notebook_path"] as? String).map { ClaudeProvider.relative($0, to: cwd) }
        switch tool {
        case "Bash": return ("Ran", ClaudeProvider.firstLine(input["command"] as? String ?? ""))
        case "Read": return ("Read", path)
        case "Edit", "MultiEdit", "NotebookEdit": return ("Edited", path)
        case "Write": return ("Wrote", path)
        case "Grep": return ("Searched", input["pattern"] as? String)
        case "Glob": return ("Listed", input["pattern"] as? String)
        case "WebFetch": return ("Fetched", input["url"] as? String)
        case "WebSearch": return ("Searched the web", input["query"] as? String)
        case "Task", "Agent": return ("Agent", input["description"] as? String)
        case "TodoWrite": return ("Updated the plan", nil)
        default:
            if tool.hasPrefix("mcp__") { return ("Used", tool.split(separator: "__").dropFirst().joined(separator: " · ")) }
            return ("Used", tool)
        }
    }

    /// Strips harness wrappers from a user message; returns nil for messages that aren't real prompts.
    static func cleanPrompt(_ raw: String) -> String? {
        var text = raw
        // Remove leading <tag>…</tag> blocks (system instructions, reminders, command echoes).
        while text.hasPrefix("<"), let close = text.range(of: ">"),
              let tag = text[text.index(after: text.startIndex)..<close.lowerBound].split(separator: " ").first,
              let end = text.range(of: "</\(tag)>") {
            text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.hasPrefix("<") || text.hasPrefix("[Request interrupted") || text.hasPrefix("Caveat:") {
            return nil
        }
        return text
    }
}
