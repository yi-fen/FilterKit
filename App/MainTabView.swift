import SwiftUI

/// Stable identifiers for the four primary areas of FilterKit.
private enum MainTab: Hashable {
    case home
    case apps
    case plugins
    case settings
}

struct MainTabView: View {
    @State private var selection: MainTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("tab.home", systemImage: "house") }
                .tag(MainTab.home)
                .accessibilityIdentifier("tab.home")

            AppsView()
                .tabItem { Label("tab.apps", systemImage: "square.grid.2x2") }
                .tag(MainTab.apps)
                .accessibilityIdentifier("tab.apps")

            PluginsView()
                .tabItem { Label("tab.plugins", systemImage: "puzzlepiece") }
                .tag(MainTab.plugins)
                .accessibilityIdentifier("tab.plugins")

            SettingsView()
                .tabItem { Label("tab.settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
                .accessibilityIdentifier("tab.settings")
        }
        .accentColor(FilterKitTheme.ColorToken.accent)
        .task {
            // Warm the installed-app inventory in the background at launch so the
            // Apps/Plugins screens can read a warm cache instead of blocking on
            // the first LaunchServices enumeration. Non-blocking and failure-tolerant.
            AppDiscoveryProviderRegistry.shared.prewarm()
        }
    }
}
