import DashUpKit
import SwiftUI

struct PadView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming: PadItem?

    var body: some View {
        let pages = model.pad.pages
        let page = pages.first { $0.title == model.settings.padPage } ?? pages.first(where: { $0.title == "Dev" }) ?? pages.first
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 26) {
                    Text("Pad").font(.ui(30, .semibold)).tracking(-0.66).foregroundStyle(Theme.text)
                        .padding(.trailing, 6)
                    ForEach(pages) { p in
                        Button {
                            model.settings.padPage = p.title
                        } label: {
                            Text(p.title).font(.ui(15)).foregroundStyle(p.id == page?.id ? Theme.text : Theme.text3)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text("Edit on Mac").font(.ui(14)).foregroundStyle(Theme.text3)
                }
                .padding(.bottom, 30)

                if let page {
                    ForEach(page.sections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            SectionHeading(title: section.title, detail: section.subtitle)
                            grid(section)
                        }
                        .padding(.bottom, 36)
                    }
                } else {
                    Text(model.status == .connected ? "No keys yet. Choose Edit Pad… in the DashUp menu on your Mac." : "Connecting to your Mac…")
                        .font(.ui(14.5)).foregroundStyle(Theme.text2)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .alert(confirming.map { "\($0.title)?" } ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Cancel", role: .cancel) { confirming = nil }
            Button(confirming?.title ?? "Run", role: .destructive) {
                if let item = confirming { model.run(.runPadItem(id: item.id)) }
                confirming = nil
            }
        } message: {
            Text("This runs on your Mac.")
        }
    }

    @ViewBuilder
    private func grid(_ section: PadSection) -> some View {
        let count: Int = switch section.style {
        case .modes: 4
        case .keys: 4
        case .compact: 6
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: count), spacing: 12) {
            ForEach(section.items) { item in
                Button {
                    if item.needsConfirmation { confirming = item } else { model.run(.runPadItem(id: item.id)) }
                } label: {
                    switch section.style {
                    case .modes: ModeKey(item: item)
                    case .keys: ActionKey(item: item)
                    case .compact: CompactKey(item: item)
                    }
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

/// Wide toggle; turns solid light when on, with its state written out.
private struct ModeKey: View {
    let item: PadItem

    var body: some View {
        VStack(alignment: .leading) {
            Text(item.title).font(.ui(15, .semibold)).foregroundStyle(item.isOn ? Theme.ink : Theme.text2)
            Spacer()
            Text(item.stateText ?? (item.isOn ? "On" : "Off"))
                .font(.ui(13))
                .foregroundStyle(item.isOn ? Color(hex: 0x6B6560) : Theme.text3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100, alignment: .leading)
        .card(radius: 16, fill: item.isOn ? Theme.text : Theme.surface, translucent: !item.isOn)
    }
}

/// Large key: command or app on top, name and live status at the bottom.
private struct ActionKey: View {
    let item: PadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if item.usesClaudeMark {
                    ClaudeMark(size: 22)
                } else if let app = item.appBundleID {
                    AppIcon(bundleID: app, size: 26)
                } else if let context = item.context {
                    Text(context).font(.mono(12)).foregroundStyle(Theme.text3).lineLimit(1)
                }
            }
            .frame(height: 26, alignment: .leading)
            Spacer()
            Text(item.title).font(.ui(17, .semibold)).tracking(-0.17).foregroundStyle(Theme.text).lineLimit(1)
            KeyStatus(item: item)
                .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 206, maxHeight: 206, alignment: .leading)
        .card(radius: 18)
        .overlay {
            if item.isRunning {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.busy.opacity(0.35))
            }
        }
    }
}

private struct KeyStatus: View {
    let item: PadItem

    var body: some View {
        Ticking { now in
            Group {
                if item.isRunning {
                    HStack(spacing: 7) {
                        Circle().fill(Theme.busy).frame(width: 6, height: 6)
                        Text("Running · \(Format.clock(now.timeIntervalSince(item.runningSince ?? now)))")
                    }
                    .foregroundStyle(Theme.busy)
                } else if let date = item.lastRunAt {
                    Text("\(item.lastResult ?? "Done") · \(Format.ago(date, now: now))")
                        .foregroundStyle(item.lastSucceeded == false ? Theme.needsText : Theme.text3)
                } else {
                    Text(item.subtitle ?? " ").foregroundStyle(Theme.text3)
                }
            }
            .font(.ui(13))
            .lineLimit(1)
        }
    }
}

/// Short key: name on top, shortcut or note at the bottom.
private struct CompactKey: View {
    let item: PadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title).font(.ui(14.5, .semibold)).foregroundStyle(item.isToggle && item.isOn ? Theme.ink : Theme.text).lineLimit(1)
            Spacer()
            if !item.keycaps.isEmpty {
                HStack(spacing: 4) { ForEach(item.keycaps, id: \.self) { Keycap(label: $0) } }
            } else if item.isToggle {
                Text(item.stateText ?? "").font(.ui(12.5)).foregroundStyle(item.isOn ? Color(hex: 0x6B6560) : Theme.text3)
            } else if item.isRunning || item.lastRunAt != nil {
                KeyStatus(item: item)
            } else {
                Text(item.subtitle ?? " ").font(.ui(12.5)).foregroundStyle(Theme.text3).lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 136, maxHeight: 136, alignment: .leading)
        .card(radius: 16, fill: item.isToggle && item.isOn ? Theme.text : Theme.surface, translucent: !(item.isToggle && item.isOn))
    }
}
