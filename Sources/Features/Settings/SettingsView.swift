import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var language: LanguagePreference
    @AppStorage("filterkit.showSystemApps") private var showingSystemApps = false
    @ObservedObject private var pluginRegistry = PluginScanRegistry.shared
    @State private var appBinaryIdentity: AppBinaryIdentitySnapshot?
    @State private var elleKitProfileStatusKey = "settings.filter.not_checked"
    @State private var elleKitVersion = "—"
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

                Section(header: Text("settings.filter")) {
                    HStack {
                        Text("settings.filter.ellekit_profile")
                        Spacer()
                        Text(LocalizedStringKey(elleKitProfileStatusKey)).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("settings.filter.ellekit_version")
                        Spacer()
                        Text(elleKitVersion).foregroundColor(.secondary)
                    }
                    Text("settings.filter.read_only_note")
                        .font(.footnote).foregroundColor(.secondary)
                    Button("settings.filter.refresh") {
                        pluginRegistry.refresh()
                        Task { await refreshFilterAndIdentityStatus() }
                    }
                }

                Section(header: Text("settings.identity")) {
                    if let identity = appBinaryIdentity {
                        HStack { Text("settings.identity.bundle"); Spacer(); Text(identity.bundleIdentifier).foregroundColor(.secondary).textSelection(.enabled) }
                        HStack { Text("settings.identity.architectures"); Spacer(); Text(identity.slices.compactMap(\.architecture).joined(separator: ", ")).foregroundColor(.secondary) }
                        HStack { Text("settings.identity.cdhash"); Spacer(); Text(identity.slices.compactMap(\.cdHash).joined(separator: ", ").isEmpty ? "—" : identity.slices.compactMap(\.cdHash).joined(separator: ", ")).foregroundColor(.secondary).textSelection(.enabled) }
                        HStack { Text("settings.identity.signature"); Spacer(); Text(identity.slices.map(\.codeSignatureState).joined(separator: ", ")).foregroundColor(.secondary) }
                        HStack { Text("settings.identity.team"); Spacer(); Text(identity.slices.compactMap(\.codeSignatureTeamIdentifier).joined(separator: ", ").isEmpty ? "—" : identity.slices.compactMap(\.codeSignatureTeamIdentifier).joined(separator: ", ")).foregroundColor(.secondary) }
                        HStack { Text("settings.identity.sha256"); Spacer(); Text(identity.sha256).foregroundColor(.secondary).textSelection(.enabled) }
                    } else {
                        Text("settings.identity.unavailable").foregroundColor(.secondary)
                    }
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
        .task {
            await refreshHelperStatus()
            await refreshFilterAndIdentityStatus()
            pluginRegistry.loadIfNeeded()
        }
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
    private func refreshFilterAndIdentityStatus() async {
        appBinaryIdentity = AppBinaryIdentityInspector.inspectMainBundle()
        let provider = ReadOnlyEnvironmentProvider()
        let report = await Task.detached(priority: .utility) { provider.makeDiagnosticReport() }.value
        if let assessment = report.elleKitAssessment {
            elleKitProfileStatusKey = "settings.filter.profile.\(assessment.profileMatch.rawValue)"
            elleKitVersion = assessment.packageMetadata?.version ?? "—"
        } else {
            elleKitProfileStatusKey = "settings.filter.not_checked"
            elleKitVersion = "—"
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
