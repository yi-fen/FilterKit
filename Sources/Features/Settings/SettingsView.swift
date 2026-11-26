import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var language: LanguagePreference
    @AppStorage("filterkit.showSystemApps") private var showingSystemApps = false
    var helperCoordinator: HelperDeploymentCoordinator? = nil
    @State private var helperStatus: HelperStatusResponse?
    @State private var helperStatusUnavailable = false
    @State private var helperStatusNotConfigured = false
    @State private var isRefreshingHelper = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("settings.general")) {
                    Picker(selection: $language.selection, label: Text("settings.language")) {
                        ForEach(LanguageSelection.allCases) { option in
                            Text(option.localizationKey).tag(option)
                        }
                    }
                    .accessibilityIdentifier("settings.language.picker")
                }

                Section(header: Text("settings.apps")) {
                    Toggle("settings.show_system_apps", isOn: $showingSystemApps)
                        .accessibilityIdentifier("settings.showSystemApps.toggle")
                }

                Section(header: Text("settings.helper")) {
                    HStack {
                        Text("settings.helper.connection")
                        Spacer()
                        Text(LocalizedStringKey(helperStatus == nil ? (helperStatusNotConfigured ? "settings.helper.not_configured" : (helperStatusUnavailable ? "settings.helper.unavailable" : "settings.helper.not_checked")) : "settings.helper.connected"))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("settings.helper.recovery")
                        Spacer()
                        Text(LocalizedStringKey(recoveryStatusKey))
                            .foregroundColor(.secondary)
                    }
                    Button {
                        Task { await refreshHelperStatus() }
                    } label: {
                        HStack {
                            Text("settings.helper.refresh")
                            Spacer()
                            if isRefreshingHelper { ProgressView() }
                        }
                    }
                    .disabled(helperCoordinator == nil || isRefreshingHelper)
                }

                Section(header: Text("settings.storage")) {
                    Text("settings.storage.placeholder")
                        .foregroundColor(.secondary)
                }

                Section(header: Text("settings.about")) {
                    HStack {
                        Text("settings.version")
                        Spacer()
                        Text("1.0.0 (Development)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("tab.settings")
            .navigationBarTitleDisplayMode(.large)
            .tint(FilterKitTheme.ColorToken.accent)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .task { await refreshHelperStatus() }
    }

    private var recoveryStatusKey: String {
        guard let status = helperStatus else { return "settings.helper.status_unknown" }
        switch status.recoveryStatus {
        case .clean: return "settings.helper.recovery_clean"
        case .legacyRecoveryRequired, .threeFileRecoveryRequired, .bothRecoveryRequired, .associationTransactionRecoveryRequired:
            return "settings.helper.recovery_pending"
        case .invalidJournal: return "settings.helper.recovery_invalid"
        case .unavailable: return "settings.helper.status_unknown"
        }
    }

    @MainActor
    private func refreshHelperStatus() async {
        guard let helperCoordinator else {
            helperStatusNotConfigured = true
            helperStatusUnavailable = false
            return
        }
        helperStatusNotConfigured = false
        isRefreshingHelper = true
        defer { isRefreshingHelper = false }
        do {
            helperStatus = try await helperCoordinator.fetchStatus()
            helperStatusUnavailable = false
        } catch {
            helperStatus = nil
            helperStatusUnavailable = true
        }
    }
}
