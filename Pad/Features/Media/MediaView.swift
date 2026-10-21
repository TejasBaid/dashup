import DashUpKit
import SwiftUI

struct MediaView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.nowPlaying
        Group {
            if player.isRunning, player.title != nil {
                HStack(alignment: .center, spacing: 56) {
                    Artwork(trackID: player.trackID, fallbackApp: player.bundleID, radius: 14)
                        .frame(width: 420, height: 420)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            if let bundleID = player.bundleID { AppIcon(bundleID: bundleID, size: 20) }
                            Text(player.state == .playing ? "Playing in \(player.app)" : "Paused in \(player.app)")
                                .font(.ui(13.5)).foregroundStyle(Theme.text3)
                        }
                        Text(player.title ?? "")
                            .font(.ui(34, .semibold)).tracking(-0.7)
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .padding(.top, 10)
                        Text([player.artist, player.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.ui(17)).foregroundStyle(Theme.text2)
                            .lineLimit(1)
                            .padding(.top, 6)
                        Scrubber(player: player)
                            .padding(.top, 36)
                        controls(player)
                            .padding(.top, 28)
                        VolumeSlider(volume: player.volume)
                            .padding(.top, 36)
                    }
                    .frame(maxWidth: 460)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    Text("Nothing is playing").font(.ui(20, .semibold)).foregroundStyle(Theme.text)
                    Text("Play something on your Mac — Music, Spotify, a video in Chrome — and it shows up here.").font(.ui(14.5)).foregroundStyle(Theme.text2)
                    OutlineButton(title: "Open Music") { model.run(.launchApp(bundleID: "com.apple.Music")) }
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(40)
    }

    private func controls(_ player: NowPlayingState) -> some View {
        HStack(spacing: 44) {
            Button { model.run(.media(.previous)) } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 26))
            }
            Button { model.run(.media(.playPause)) } label: {
                Image(systemName: player.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 72, height: 72)
                    .background(Theme.text, in: .circle)
            }
            Button { model.run(.media(.next)) } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 26))
            }
        }
        .foregroundStyle(Theme.text2)
        .buttonStyle(PressableStyle())
    }
}

private struct Scrubber: View {
    @Environment(AppModel.self) private var model
    let player: NowPlayingState
    @State private var dragging: Double?

    var body: some View {
        Ticking { now in
            let position = dragging ?? player.position(at: now)
            let fraction = player.duration > 0 ? min(1, position / player.duration) : 0
            VStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface3).frame(height: 4)
                        Capsule().fill(Theme.text2).frame(width: proxy.size.width * fraction, height: 4)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { dragging = max(0, min(1, $0.location.x / proxy.size.width)) * player.duration }
                        .onEnded { _ in
                            if let dragging { model.run(.media(.seek(dragging))) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.dragging = nil }
                        })
                }
                .frame(height: 20)
                HStack {
                    Text(Format.clock(position))
                    Spacer()
                    Text(Format.clock(player.duration))
                }
                .font(.ui(12).monospacedDigit())
                .foregroundStyle(Theme.text3)
            }
        }
    }
}

private struct VolumeSlider: View {
    @Environment(AppModel.self) private var model
    let volume: Int
    @State private var value: Double?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.fill").font(.system(size: 13)).foregroundStyle(Theme.text3)
            Slider(value: Binding(get: { value ?? Double(volume) }, set: { value = $0 }), in: 0...100) { editing in
                if !editing, let value {
                    model.run(.media(.volume(Int(value))))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.value = nil }
                }
            }
            .tint(Theme.text2)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 13)).foregroundStyle(Theme.text3)
        }
    }
}
