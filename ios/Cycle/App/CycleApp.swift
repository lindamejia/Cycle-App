import SwiftUI

@main
struct CycleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "dark"
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(appearance == "light" ? .light : .dark)
                .tint(.primary)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.onForeground() }
            case .background:
                Task { await Analytics.shared.flush() }
            default:
                break
            }
        }
    }
}
