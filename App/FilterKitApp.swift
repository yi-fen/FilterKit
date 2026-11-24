import SwiftUI

@main
struct FilterKitApp: App {
    @StateObject private var language = LanguagePreference()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(language)
                .environment(\.locale, language.locale)
        }
    }
}
