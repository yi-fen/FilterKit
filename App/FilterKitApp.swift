import SwiftUI

@main
struct FilterKitApp: App {
    @StateObject private var language = LanguagePreference()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        RuntimeEventLogger.startSession()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(language)
                .environment(\.locale, language.locale)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: RuntimeEventLogger.recordScenePhase("active")
            case .inactive: RuntimeEventLogger.recordScenePhase("inactive")
            case .background: RuntimeEventLogger.recordScenePhase("background")
            @unknown default: RuntimeEventLogger.recordScenePhase("unknown")
            }
        }
    }
}
