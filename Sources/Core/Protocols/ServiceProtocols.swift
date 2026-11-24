import Foundation

protocol EnvironmentProvider {
    func detectEnvironment() async throws -> JailbreakEnvironment
    func resolvePaths() async throws -> EnvironmentPaths
    func inspectElleKit() async throws -> ElleKitInstallation
    func validateCapabilities() async throws -> EnvironmentCapabilities
}

protocol AppDiscoveryProvider {
    func scanInstalledApps() async throws -> [InstalledApp]
    func findApp(bundleIdentifier: String) async throws -> InstalledApp?
}

protocol AppDiscoveryRefreshing {
    func refreshInstalledApps() async throws -> [InstalledApp]
    func invalidateCache() async
}

protocol PluginDiscoveryProvider {
    func scanPlugins() async throws -> PluginScanResult
}

protocol PluginImportProvider {
    func inspect(sourceURL: URL, targetApp: InstalledApp) async throws -> PluginImportPreview
    func prepare(preview: PluginImportPreview) async throws -> PluginImportPlan
    func execute(plan: PluginImportPlan) async throws -> OperationReceipt
}

protocol PluginConfigurationProvider {
    func makeEffectiveConfiguration(originalPlist: Data?, associations: PluginAssociations,
                                    profileIdentifier: String) throws -> PluginConfigurationSnapshot
}

protocol PluginAssociationProvider {
    func associations(for pluginID: UUID) async throws -> PluginAssociations
    func addSoftAssociation(pluginID: UUID, bundleIdentifier: String) async throws
    func removeSoftAssociation(pluginID: UUID, bundleIdentifier: String) async throws
}

/// Any future mutating implementation must resolve a verified environment strategy and
/// pass PluginToggleAuthorization before staging a Helper operation. No implementation
/// may infer runtime load success from a successful file/configuration write.
protocol PluginDeploymentProvider {
    func setEnabled(pluginID: UUID, bundleIdentifier: String, enabled: Bool) async throws -> OperationReceipt
    func uninstall(pluginID: UUID) async throws -> OperationReceipt
    func verify(pluginID: UUID) async throws -> OperationReceipt
}

protocol PluginBackupProvider {
    func export(pluginIDs: [UUID]) async throws -> Data
    func inspectBackup(at url: URL) async throws -> FilterKitBackupDocument
    func restoreBackup(at url: URL) async throws -> OperationReceipt
}

protocol StorageManagementProvider {
    func measureStorage() async throws -> StorageUsage
    func clean(_ categories: Set<StorageCategory>) async throws -> StorageCleanupReceipt
}
