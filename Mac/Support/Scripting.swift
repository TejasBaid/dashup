import Foundation

/// Runs AppleScript / JavaScript for Automation off the main thread via `osascript`, with a timeout
/// so a busy app can never stall the agent. Automation prompts are attributed to DashUp.
enum Scripting {
    enum Language: String { case appleScript = "AppleScript", javaScript = "JavaScript" }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        var isPermissionDenied: Bool { description.contains("-1743") || description.localizedCaseInsensitiveContains("not allowed") }
    }

    static func run(_ source: String, language: Language = .javaScript, timeout: TimeInterval = 6) async throws -> String {
        try await Shell.run("/usr/bin/osascript", ["-l", language.rawValue, "-e", source], timeout: timeout)
    }

    /// Runs JXA that ends in `JSON.stringify(...)` and decodes the result.
    static func json<T: Decodable>(_ type: T.Type, _ source: String, timeout: TimeInterval = 6) async throws -> T {
        let output = try await run(source, timeout: timeout)
        do {
            return try JSONDecoder().decode(T.self, from: Data(output.utf8))
        } catch {
            NSLog("DashUp: couldn't decode script output (\(error)): \(output.prefix(400))")
            throw error
        }
    }

    /// Escapes a Swift string for use inside a JavaScript string literal.
    static func literal(_ string: String) -> String {
        let data = try? JSONEncoder().encode(string)
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }
}

enum Shell {
    /// Runs an executable and returns trimmed stdout, throwing with stderr on a non-zero exit.
    static func run(_ path: String, _ arguments: [String], directory: String? = nil, timeout: TimeInterval = 10) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            // Drain both pipes while the process runs so large output can't fill the pipe buffer.
            let output = OutputBuffer()
            out.fileHandleForReading.readabilityHandler = { output.append($0.availableData, error: false) }
            err.fileHandleForReading.readabilityHandler = { output.append($0.availableData, error: true) }

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { if process.isRunning { process.terminate() } }

            process.terminationHandler = { process in
                timer.cancel()
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                output.append(out.fileHandleForReading.readDataToEndOfFile(), error: false)
                output.append(err.fileHandleForReading.readDataToEndOfFile(), error: true)
                let (stdout, stderr) = output.strings
                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let message = stderr.isEmpty ? "exit \(process.terminationStatus)" : stderr
                    continuation.resume(throwing: Scripting.Failure(description: message.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
                timer.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private var out = Data()
    private var err = Data()
    private let lock = NSLock()

    func append(_ data: Data, error: Bool) {
        guard !data.isEmpty else { return }
        lock.withLock { error ? err.append(data) : out.append(data) }
    }

    var strings: (String, String) {
        lock.withLock { (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self)) }
    }
}
