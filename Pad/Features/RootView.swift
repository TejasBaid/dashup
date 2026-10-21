import DashUpKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let image = model.backgroundImage {
                BackdropView(image: image)
                    .transition(.opacity)
            }
            if model.status == .unpaired && !model.isDemo {
                PairingView()
                    .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    Rail()
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea(edges: .bottom)
                // Rebuild when the photo comes or goes so every text colour updates.
                .id(model.backgroundImage != nil)
            }
            if model.standby {
                StandbyView()
                    .transition(.opacity)
                    .zIndex(2)
            }
            if let toast = model.toast {
                ToastView(text: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .environment(\.hasBackdrop, model.backgroundImage != nil)
        .background(TouchObserver { model.touched() })
        .statusBarHidden(model.standby)
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { now in
            model.checkIdle(now: now)
        }
        .onChange(of: model.status, initial: true) { _, status in
            // The iPad lives on the desk; keep it awake while it's showing the Mac.
            UIApplication.shared.isIdleTimerDisabled = status == .connected
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .home: HomeView()
        case .apps: AppsView()
        case .tabs: TabsView()
        case .claude: ClaudeView()
        case .media: MediaView()
        case .pad: PadView()
        case .settings: SettingsView()
        }
    }
}

/// The background photo, darkened and optionally blurred so content stays readable.
struct BackdropView: View {
    @Environment(AppModel.self) private var model
    let image: UIImage

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .blur(radius: model.settings.backgroundBlur, opaque: true)
                .overlay(Theme.background.opacity(model.settings.backgroundDim))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct Rail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.hasBackdrop) private var hasBackdrop

    var body: some View {
        VStack(spacing: 4) {
            item(.home, "Home", symbol: "house")
            item(.apps, "Apps", symbol: "square.grid.2x2")
            item(.tabs, "Tabs", symbol: "macwindow")
            item(.claude, "Claude", symbol: nil)
            item(.media, "Media", symbol: "music.note")
            item(.pad, "Pad", symbol: "square.grid.3x3")
            Spacer()
            item(.settings, "Settings", symbol: "gearshape")
        }
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: 88)
        .frame(maxHeight: .infinity)
        .background {
            if hasBackdrop {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Theme.rail.opacity(0.6)
                }
                .ignoresSafeArea()
            } else {
                Theme.rail.ignoresSafeArea()
            }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }

    private func item(_ screen: Screen, _ label: String, symbol: String?) -> some View {
        let selected = model.screen == screen
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { model.screen = screen }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Theme.surface3 : .clear)
                        .frame(width: 44, height: 36)
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 19, weight: .regular))
                    } else {
                        ClaudeMark(size: 20, color: selected ? Color(hex: 0xE8896A) : Color(hex: 0x8A857F))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if screen == .claude, !model.claude.pending.isEmpty {
                        Text("\(model.claude.pending.count)")
                            .font(.ui(10, .bold))
                            .foregroundStyle(Color(hex: 0x241310))
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Theme.needs, in: .circle)
                            .overlay(Circle().strokeBorder(Theme.rail, lineWidth: 2))
                            .offset(x: 2, y: -4)
                    }
                }
                Text(label).font(.ui(11, .medium))
            }
            .foregroundStyle(selected ? Theme.text : Theme.text2)
            .frame(width: 72)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.ui(14))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Theme.surface3, in: .capsule)
                .overlay(Capsule().strokeBorder(Theme.hairline2))
                .padding(.bottom, 30)
        }
        .allowsHitTesting(false)
    }
}

/// Reports every touch in the window without interfering with it, for the standby idle timer.
struct TouchObserver: UIViewRepresentable {
    let onTouch: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let recognizer = TouchRecognizer(target: context.coordinator, action: #selector(Coordinator.touched))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delegate = context.coordinator
            window.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTouch = onTouch
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTouch: onTouch) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTouch: () -> Void
        init(onTouch: @escaping () -> Void) { self.onTouch = onTouch }
        @objc func touched() { onTouch() }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    final class TouchRecognizer: UIGestureRecognizer {
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            state = .recognized
        }
    }
}
