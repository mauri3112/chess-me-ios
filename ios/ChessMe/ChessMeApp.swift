import SwiftUI
import ChessMeCore

@main
struct ChessMeApp: App {
    @UIApplicationDelegateAdaptor(ChessMeAppDelegate.self) private var appDelegate
    @StateObject private var notifications = GameNotifications.shared
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-evaluation") {
            UserDefaults.standard.removeObject(forKey: "analysis.showEvaluationBar")
        }
        if ProcessInfo.processInfo.arguments.contains("--reset-design") {
            UserDefaults.standard.removeObject(forKey: ChessBoardDesign.preferenceKey)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.authentication)
                .environmentObject(model.subscriptions)
                .environmentObject(notifications)
                .tint(ChessMeStyle.green)
                .preferredColorScheme(.light)
                .task { await model.prepare() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.deviceAnalysis.sceneChanged(active: true) }
                    else if phase == .background { model.deviceAnalysis.sceneChanged(active: false) }
                }
        }
    }
}
