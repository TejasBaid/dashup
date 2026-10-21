import SwiftUI

@main
struct DashUpPadApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.becameActive() }
                }
        }
    }
}
