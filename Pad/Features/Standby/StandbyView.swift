import DashUpKit
import SwiftUI

/// The dimmed desk clock. A coral glow rises from the bottom when a session needs approval,
/// and the request can be answered right here.
struct StandbyView: View {
    @Environment(AppModel.self) private var model

    private let ground = Color(hex: 0x0B0A09)
    private let dim = Color(hex: 0x66615B)
    private let mid = Color(hex: 0xA9A29A)

    var body: some View {
        let ask = model.claude.pending.first
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ground
                glow(alert: ask != nil, size: proxy.size)
                if let ask {
                    alertLayout(ask)
                } else {
                    calmLayout
                }
            }
            .contentShape(.rect)
            .onTapGesture { model.wake() }
        }
        .ignoresSafeArea()
    }

    private func glow(alert: Bool, size: CGSize) -> some View {
        let color = alert ? Color(hex: 0xE07A6B) : Color(hex: 0xC9A27E)
        return EllipticalGradient(
            stops: [
                .init(color: color.opacity(alert ? 0.34 : 0.20), location: 0),
                .init(color: color.opacity(alert ? 0.09 : 0.05), location: 0.55),
                .init(color: color.opacity(0), location: 1),
            ],
            center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: 1600, height: 760)
            .position(x: size.width / 2, y: size.height + (alert ? 40 : 80))
            .animation(.easeInOut(duration: 0.8), value: alert)
            .allowsHitTesting(false)
    }

    /// "8:26" — 12-hour, no leading zero, like a desk clock.
    static func clock(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = (c.hour ?? 0) % 12 == 0 ? 12 : (c.hour ?? 0) % 12
        return String(format: "%d:%02d", hour, c.minute ?? 0)
    }

    // MARK: Calm

    private var calmLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            Ticking { now in
                Text(Self.clock(now))
                    .font(.system(size: 300, weight: .thin).monospacedDigit())
                    .tracking(-14)
                    .fixedSize()
                    .foregroundStyle(Color(hex: 0xE9E3DC))
                    .padding(.top, 70)
            }
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.ui(24))
                .foregroundStyle(Color(hex: 0x77726C))
                .padding(.top, 28)
            Spacer()
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(alignment: .top, spacing: 40) {
                if let title = model.nowPlaying.title, model.nowPlaying.state != .stopped {
                    cell("Playing") {
                        Text("\(Text(title).foregroundStyle(Color(hex: 0xD6CFC7)).fontWeight(.semibold)) · \(model.nowPlaying.artist ?? "")")
                    }
                }
                ForEach(model.claude.sessions.prefix(3)) { session in
                    cell(session.name) {
                        HStack(spacing: 9) {
                            StatusDot(phase: session.phase, size: 6)
                            Ticking(interval: 30) { now in Text(SessionText.state(session, now: now)) }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 92)
        .padding(.top, 64)
        .padding(.bottom, 80)
    }

    private func cell<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.ui(13)).foregroundStyle(Color(hex: 0x57534E))
            content().font(.ui(16)).foregroundStyle(mid).lineLimit(1)
        }
        .frame(maxWidth: 300, alignment: .leading)
    }

    // MARK: Alert

    private func alertLayout(_ ask: PermissionAsk) -> some View {
        let session = model.session(ask.sessionID)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Ticking { now in
                        Text(Self.clock(now))
                            .font(.system(size: 230, weight: .thin).monospacedDigit())
                            .tracking(-10)
                            .fixedSize()
                            .foregroundStyle(Color(hex: 0xE9E3DC))
                    }
                    Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.ui(22))
                        .foregroundStyle(Color(hex: 0x77726C))
                        .padding(.top, 22)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    if let title = model.nowPlaying.title, model.nowPlaying.state != .stopped {
                        HStack(spacing: 14) {
                            Artwork(trackID: model.nowPlaying.trackID, radius: 6).frame(width: 46, height: 46).opacity(0.85)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(.ui(15, .semibold)).foregroundStyle(Color(hex: 0xB9B2AA))
                                Text(model.nowPlaying.artist ?? "").font(.ui(13.5)).foregroundStyle(dim)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                    ForEach(model.claude.sessions.filter { $0.id != ask.sessionID }.prefix(3)) { other in
                        HStack(spacing: 10) {
                            StatusDot(phase: other.phase, size: 6)
                            Text(other.name).font(.ui(15, .semibold)).foregroundStyle(mid)
                            Ticking(interval: 30) { now in
                                Text(SessionText.state(other, now: now)).font(.ui(15)).foregroundStyle(dim)
                            }
                        }
                    }
                }
                .frame(width: 330, alignment: .leading)
                .padding(.top, 18)
            }
            Spacer()
            HStack(spacing: 10) {
                StatusDot(phase: .needsApproval, size: 8)
                Text(session?.name ?? "Claude").font(.ui(16, .semibold)).foregroundStyle(Color(hex: 0xF0D5CE))
                Text(ApprovalPanel.headline(ask).lowercased()).font(.ui(16)).foregroundStyle(Color(hex: 0xB88A80))
            }
            Text(ask.subject)
                .font(.mono(34))
                .tracking(-0.3)
                .lineSpacing(8)
                .foregroundStyle(Color(hex: 0xF3ECE5))
                .lineLimit(3)
                .padding(.top, 16)
            HStack(spacing: 14) {
                Ticking { now in
                    Text("\(ask.toolName) · \(session?.project ?? ClaudePaths.short(ask.cwd)) · back to terminal in \(Format.clock(ask.expiresAt.timeIntervalSince(now)))")
                        .font(.ui(14)).foregroundStyle(Color(hex: 0x9B6E65))
                }
                .padding(.trailing, 26)
                QuietButton(title: "Deny", height: 50, fontSize: 16, color: Color(hex: 0xC9A59D)) { model.decide(ask, allow: false) }
                Button { model.decide(ask, allow: true) } label: {
                    Text("Allow")
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 32)
                        .frame(height: 50)
                        .background(Color(hex: 0xF3ECE5), in: .capsule)
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.top, 30)
        }
        .padding(.horizontal, 92)
        .padding(.top, 64)
        .padding(.bottom, 80)
    }
}
