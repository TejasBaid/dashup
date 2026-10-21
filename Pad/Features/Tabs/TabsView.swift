import DashUpKit
import SwiftUI

struct TabsView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Text("Chrome").font(.ui(30, .semibold)).tracking(-0.66).foregroundStyle(Theme.text)
                if model.chrome.isRunning {
                    Text("\(model.chrome.tabCount) tabs · \(model.chrome.windows.count) \(model.chrome.windows.count == 1 ? "window" : "windows")")
                        .font(.ui(14)).foregroundStyle(Theme.text3)
                }
                Spacer()
                URLField(text: $text, placeholder: "Open a URL on your Mac") {
                    model.open(text)
                    text = ""
                }
                .frame(width: 380)
            }
            .padding(.bottom, 28)

            if let error = model.chrome.error {
                message("DashUp can't see Chrome yet", error)
            } else if !model.chrome.isRunning {
                message("Chrome isn't open", "Open a site above and Chrome will start on your Mac.")
            } else {
                windows
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 32)
    }

    private var windows: some View {
        GeometryReader { proxy in
            let count = max(1, min(3, model.chrome.windows.count))
            let width = (proxy.size.width - CGFloat(count - 1) * 16) / CGFloat(count)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(model.chrome.windows.enumerated()), id: \.element.id) { index, window in
                        WindowColumn(index: index, window: window)
                            .frame(width: width)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(model.chrome.windows.count <= 3)
        }
    }

    private func message(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.ui(17, .semibold)).foregroundStyle(Theme.text)
            Text(body).font(.ui(14)).foregroundStyle(Theme.text2).lineSpacing(4)
        }
        .padding(24)
        .frame(maxWidth: 560, alignment: .leading)
        .card(radius: 18)
    }
}

private struct WindowColumn: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let window: ChromeWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(index == 0 ? "Front window" : "Window \(index + 1)").font(.ui(14.5, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text("\(window.tabs.count) tabs").font(.ui(12.5)).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(window.tabs.enumerated()), id: \.element.id) { i, tab in
                        let active = i == window.activeTabIndex - 1
                        TabRow(window: window.id, tab: tab, isActive: active)
                            .padding(.horizontal, 10)
                            .background(active ? Theme.surface2 : .clear, in: .rect(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .card(radius: Theme.panelRadius)
    }
}
