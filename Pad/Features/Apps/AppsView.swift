import DashUpKit
import SwiftUI

struct AppsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        let running = model.apps.running.filter(matches)
        let installed = model.apps.installed.filter { matches(name: $0.name) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("Apps").font(.ui(30, .semibold)).tracking(-0.66).foregroundStyle(Theme.text)
                    Spacer()
                    URLField(text: $query, placeholder: "Search \(model.apps.installed.count) apps") {}
                        .frame(width: 320)
                }
                .padding(.bottom, Theme.sectionGap)

                SectionHeading(title: "Open", detail: "\(running.count)")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 128), spacing: 0, alignment: .top)], alignment: .leading, spacing: 22) {
                    ForEach(running) { app in
                        AppTile(bundleID: app.bundleID, name: app.name,
                                caption: app.caption ?? app.memoryBytes.map(Self.memory) ?? " ", isFront: app.isFront)
                    }
                }
                .padding(.bottom, Theme.sectionGap)

                SectionHeading(title: "All apps", detail: "\(installed.count)")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 120), spacing: 0, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(installed) { app in
                        Button {
                            model.run(.launchApp(bundleID: app.bundleID))
                        } label: {
                            VStack(spacing: 8) {
                                AppIcon(bundleID: app.bundleID, size: 60)
                                Text(app.name)
                                    .font(.ui(12.5))
                                    .foregroundStyle(Theme.text2)
                                    .lineLimit(1)
                                    .frame(width: 100)
                            }
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            AppMenu(bundleID: app.bundleID, isRunning: model.apps.running.contains { $0.bundleID == app.bundleID })
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func matches(_ app: RunningApp) -> Bool { matches(name: app.name) }

    private func matches(name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    static func memory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return gb >= 1 ? String(format: "%.1f GB", gb) : "\(Int(Double(bytes) / 1_000_000)) MB"
    }
}
