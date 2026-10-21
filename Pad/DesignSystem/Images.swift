import DashUpKit
import SwiftUI

/// A Mac app icon fetched from the Mac.
struct AppIcon: View {
    @Environment(AppModel.self) private var model
    let bundleID: String
    var size: CGFloat = 62

    var body: some View {
        if let image = model.images.image(.app(bundleID)) {
            Image(uiImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Theme.surface2)
                .frame(width: size * 0.82, height: size * 0.82)
                .frame(width: size, height: size)
        }
    }
}

/// A site's favicon from Chrome's cache on the Mac, or a quiet monogram.
struct Favicon: View {
    @Environment(AppModel.self) private var model
    let url: String
    var size: CGFloat = 28
    var radius: CGFloat = 8

    var body: some View {
        let host = Self.host(url)
        ZStack {
            if let image = model.images.image(.favicon(url)) {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.surface2)
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit().padding(size * 0.2)
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Self.tint(host))
                Text(Self.monogram(host))
                    .font(.ui(size * 0.42, .semibold))
                    .foregroundStyle(Theme.text.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline2, lineWidth: 1))
    }

    static func host(_ url: String) -> String {
        guard let host = URL(string: url)?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func monogram(_ host: String) -> String {
        if host.hasPrefix("localhost") || host.hasPrefix("127.") { return "L" }
        let parts = host.split(separator: ".")
        let name = parts.count >= 2 ? parts[parts.count - 2] : parts.first ?? "?"
        return name.prefix(1).uppercased()
    }

    /// A muted warm tone chosen from the host, so monograms are stable but not loud.
    static func tint(_ host: String) -> Color {
        let tones: [UInt32] = [0x3A332C, 0x2E3530, 0x2F3240, 0x3B2F33, 0x34302A, 0x2C3437]
        let hash = host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFFFFFF }
        return Color(hex: tones[hash % tones.count])
    }
}

/// Album artwork from Music, with a flat placeholder.
struct Artwork: View {
    @Environment(AppModel.self) private var model
    let trackID: String?
    /// Shown when there's no artwork: the icon of the app that's playing.
    var fallbackApp: String?
    var radius: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.surface2)
                if let trackID, let image = model.images.image(.artwork(trackID)) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else if let fallbackApp {
                    AppIcon(bundleID: fallbackApp, size: min(proxy.size.width, proxy.size.height) * 0.36)
                } else {
                    Image(systemName: "music.note").font(.system(size: 28, weight: .light)).foregroundStyle(Theme.text3)
                }
            }
        }
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
    }
}
