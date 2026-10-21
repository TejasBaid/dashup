import DashUpKit
import SwiftUI

/// "Claude Code  3 running ........ All sessions"
struct SectionHeading<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.ui(14, .semibold)).foregroundStyle(Theme.text)
            if let detail { Text(detail).font(.ui(13)).foregroundStyle(Theme.text3) }
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: 20)
        .padding(.bottom, 14)
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

/// Quiet trailing link used in section headings.
struct HeadingLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.ui(13)).foregroundStyle(Theme.text3)
        }
        .buttonStyle(.plain)
    }
}

struct StatusDot: View {
    let phase: SessionPhase
    var size: CGFloat = 7

    var body: some View {
        Circle().fill(Self.color(phase)).frame(width: size, height: size)
    }

    static func color(_ phase: SessionPhase) -> Color {
        switch phase {
        case .needsApproval, .waiting: Theme.needs
        case .working: Theme.busy
        case .finished: Theme.done
        case .idle: Theme.text3
        }
    }
}

/// White pill, used for the one primary action on a surface (Allow).
struct PillButton: View {
    let title: String
    var height: CGFloat = 36
    var fontSize: CGFloat = 13.5
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(fontSize, .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, height / 2)
                .frame(height: height)
                .background(Theme.text, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Plain text button (Deny).
struct QuietButton: View {
    let title: String
    var height: CGFloat = 36
    var fontSize: CGFloat = 13.5
    var color: Color = Theme.text2
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(fontSize))
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .frame(height: height)
                .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Bordered secondary button.
struct OutlineButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(13.5, .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Theme.surface2, in: .rect(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline2))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Slight dim and shrink on press; no bounce.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Claude's mark: twelve rays of alternating length.
struct ClaudeMark: View {
    var size: CGFloat = 18
    var color: Color = Theme.claude

    var body: some View {
        Canvas { context, canvasSize in
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let scale = canvasSize.width / 24
            var path = Path()
            for k in 0..<12 {
                let a = Double(k) / 12 * .pi * 2
                let r1 = 2.2 * scale, r2 = (k % 2 == 1 ? 9 : 11) * scale
                path.move(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                path.addLine(to: CGPoint(x: c.x + cos(a) * r2, y: c.y + sin(a) * r2))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

/// A keyboard key outline, e.g. ⌘.
struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.ui(12))
            .foregroundStyle(Theme.text2)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, label.count > 1 ? 6 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.hairline2, lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1).fill(Theme.hairline2).frame(height: 1).padding(.horizontal, 3)
            }
    }
}

/// Live text that ticks every second (countdowns, "Working · 12m").
struct Ticking<Content: View>: View {
    var interval: TimeInterval = 1
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { context in
            content(context.date)
        }
    }
}
