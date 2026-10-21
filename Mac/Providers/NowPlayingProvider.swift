import AppKit
import DashUpKit
import Foundation

/// System-wide Now Playing: whatever macOS shows in Control Center — Spotify, YouTube in Chrome,
/// Safari, Podcasts, Music.
///
/// MediaRemote only answers Apple-signed processes, so a small bridge library
/// (`Mac/NowPlaying/DashUpMediaRemote.m`) is loaded into `/usr/bin/perl`, which streams one JSON
/// line per change. If the bridge can't run, Apple Music is scripted directly instead.
@MainActor
final class NowPlayingProvider {
    var onChange: (() -> Void)?
    var isActive: () -> Bool = { false }

    private(set) var state = NowPlayingState()
    private var stream: Process?
    private var buffer = Data()
    private var bridgeFailed = false
    private var restartDelay: TimeInterval = 1
    private var artwork: (id: String, data: Data)?
    private var volume = 0
    private var timer: Timer?

    private static var bridge: (script: String, library: String)? {
        guard let script = Bundle.main.path(forResource: "now-playing", ofType: "pl"),
              let library = Bundle.main.path(forResource: "libDashUpMediaRemote", ofType: "dylib") else { return nil }
        return (script, library)
    }

    func start() {
        startStream()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive() else { return }
                self.readVolume()
                if self.bridgeFailed { self.pollMusic() }
            }
        }
    }

    // MARK: Bridge stream

    private func startStream() {
        guard let bridge = Self.bridge else { return fallBack("bridge missing from the app bundle") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [bridge.script, bridge.library]
        process.environment = ["DASHUP_MR_COMMAND": "stream"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        // The bridge exits when this pipe closes, so it never outlives DashUp.
        process.standardInput = Pipe()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.stream = nil
                    // Back off and retry; give up on the bridge after repeated quick failures.
                    if self.restartDelay > 30 { return self.fallBack("bridge keeps exiting") }
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.restartDelay) { self.startStream() }
                    self.restartDelay *= 2
                }
            }
        }
        do {
            try process.run()
            stream = process
        } catch {
            fallBack(error.localizedDescription)
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let dto = try? JSONDecoder().decode(BridgeDTO.self, from: line) else { continue }
            if dto.error != nil { return fallBack(dto.error ?? "") }
            restartDelay = 1
            apply(dto)
        }
    }

    private struct BridgeDTO: Decodable {
        let error: String?
        let playing: Bool?
        let bundleID: String?
        let parentBundleID: String?
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsedtime: Double?
        let playbackrate: Double?
        let timestamp: Double?
        let artworkID: String?
        let artwork: String?
    }

    private func apply(_ dto: BridgeDTO) {
        if let id = dto.artworkID, let encoded = dto.artwork, let data = Data(base64Encoded: encoded) {
            artwork = (id, data)
        }
        guard let title = dto.title, !title.isEmpty else {
            return update(NowPlayingState(app: "", isRunning: false, state: .stopped, volume: volume))
        }
        let bundleID = dto.parentBundleID ?? dto.bundleID
        let playing = dto.playing ?? ((dto.playbackrate ?? 0) > 0)
        // Elapsed time is reported as of `timestamp`; bring it up to now.
        var position = dto.elapsedtime ?? 0
        if playing, let timestamp = dto.timestamp {
            position += Date.now.timeIntervalSince1970 - timestamp
        }
        update(NowPlayingState(
            app: bundleID.flatMap(Self.appName) ?? "Now Playing", bundleID: bundleID, isRunning: true,
            state: playing ? .playing : .paused,
            trackID: dto.artworkID ?? String(title.hashValue),
            title: title, artist: dto.artist.flatMap { $0.isEmpty ? nil : $0 },
            album: dto.album.flatMap { $0.isEmpty ? nil : $0 },
            duration: dto.duration ?? 0, position: max(0, position), positionDate: .now, volume: volume))
    }

    private static func appName(_ bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return name == "Google Chrome" ? "Chrome" : name
    }

    private func update(_ newState: NowPlayingState) {
        var comparable = newState
        comparable.positionDate = state.positionDate
        if abs(newState.position(at: .now) - state.position(at: .now)) < 2 { comparable.position = state.position }
        guard comparable != state else { return }
        state = newState
        onChange?()
    }

    private func readVolume() {
        Task {
            guard let text = try? await Scripting.run("""
                const app = Application.currentApplication(); app.includeStandardAdditions = true; app.getVolumeSettings().outputVolume;
                """), let level = Int(text), level != volume else { return }
            volume = level
            var newState = state
            newState.volume = level
            update(newState)
        }
    }

    // MARK: Captions

    /// "Playing" under the app that's playing (unless it has a better caption already).
    var caption: (bundleID: String, text: String)? {
        guard state.isRunning, let id = state.bundleID else { return nil }
        return (id, state.state == .playing ? "Playing" : "Paused")
    }

    // MARK: Commands

    func perform(_ command: MediaCommand) async -> Response {
        if bridgeFailed { return await performMusic(command) }
        switch command {
        case .playPause: return await bridgeCommand("send toggle")
        case .next: return await bridgeCommand("send next")
        case .previous: return await bridgeCommand("send previous")
        case .seek(let seconds): return await bridgeCommand("seek \(max(0, seconds))")
        case .volume(let level):
            do {
                _ = try await Scripting.run("""
                    const app = Application.currentApplication(); app.includeStandardAdditions = true;
                    app.setVolume(null, {outputVolume: \(min(100, max(0, level)))});
                    """)
                volume = level
                return .ok
            } catch {
                return .failed("\(error)")
            }
        }
    }

    private func bridgeCommand(_ command: String) async -> Response {
        guard let bridge = Self.bridge else { return .failed("Now Playing bridge is missing") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [bridge.script, bridge.library]
        process.environment = ["DASHUP_MR_COMMAND": command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return .ok
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func artwork(trackID: String) async -> Data? {
        if bridgeFailed { return await musicArtwork() }
        guard let artwork, artwork.id == trackID else { return nil }
        return Self.downscale(artwork.data)
    }

    // MARK: Apple Music fallback

    private func fallBack(_ reason: String) {
        guard !bridgeFailed else { return }
        NSLog("DashUp: Now Playing bridge unavailable (\(reason)); using Apple Music only")
        bridgeFailed = true
        stream?.terminate()
        pollMusic()
    }

    private var musicRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty }

    private func pollMusic() {
        guard isActive(), musicRunning else {
            if !musicRunning { update(NowPlayingState(volume: volume)) }
            return
        }
        Task {
            struct DTO: Decodable {
                let state: String, id: String?, name: String?, artist: String?, album: String?, duration: Double?, position: Double?
            }
            guard let dto = try? await Scripting.json(DTO.self, """
                const m = Application('Music');
                const r = {state: m.playerState()};
                if (r.state !== 'stopped') { try { const t = m.currentTrack;
                  r.id = t.persistentID(); r.name = t.name(); r.artist = t.artist(); r.album = t.album();
                  r.duration = t.duration(); r.position = m.playerPosition(); } catch (e) {} }
                JSON.stringify(r);
                """) else { return }
            update(NowPlayingState(app: "Music", bundleID: "com.apple.Music", isRunning: dto.name != nil,
                                   state: dto.state == "playing" ? .playing : (dto.state == "stopped" ? .stopped : .paused),
                                   trackID: dto.id, title: dto.name, artist: dto.artist, album: dto.album,
                                   duration: dto.duration ?? 0, position: dto.position ?? 0, positionDate: .now, volume: volume))
        }
    }

    private func performMusic(_ command: MediaCommand) async -> Response {
        let source: String
        switch command {
        case .playPause: source = "Application('Music').playpause();"
        case .next: source = "Application('Music').nextTrack();"
        case .previous: source = "Application('Music').backTrack();"
        case .seek(let seconds): source = "Application('Music').playerPosition = \(max(0, seconds));"
        case .volume(let level): source = "Application('Music').soundVolume = \(min(100, max(0, level)));"
        }
        do {
            _ = try await Scripting.run(source)
            pollMusic()
            return .ok
        } catch {
            return .failed("\(error)")
        }
    }

    private func musicArtwork() async -> Data? {
        let file = FileManager.default.temporaryDirectory.appending(path: "dashup-artwork")
        try? FileManager.default.removeItem(at: file)
        let result = try? await Scripting.run("""
            tell application "Music"
              if (count of artworks of current track) is 0 then return "none"
              set d to raw data of artwork 1 of current track
            end tell
            set f to open for access (POSIX file "\(file.path)") with write permission
            set eof f to 0
            write d to f
            close access f
            return "ok"
            """, language: .appleScript)
        return result == "ok" ? (try? Data(contentsOf: file)).flatMap(Self.downscale) : nil
    }

    /// Artwork can be several megabytes; send at most a 600px JPEG.
    private static func downscale(_ data: Data) -> Data? {
        guard let image = NSImage(data: data), let rep = image.representations.first else { return data }
        let longest = max(rep.pixelsWide, rep.pixelsHigh)
        guard longest > 600 else { return data }
        let scale = 600 / Double(longest)
        let size = NSSize(width: Double(rep.pixelsWide) * scale, height: Double(rep.pixelsHigh) * scale)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return data }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
