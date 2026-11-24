import Foundation

/// Persistence abstraction only. A concrete database/schema is selected in a later
/// implementation stage; this prevents feature code from depending on storage details.
protocol PluginRepository {
    func allPlugins() async throws -> [PluginRecord]
    func plugin(id: UUID) async throws -> PluginRecord?
    func save(_ plugin: PluginRecord) async throws
    func delete(pluginID: UUID) async throws
}

protocol AppRepository {
    func allApps() async throws -> [InstalledApp]
    func save(_ apps: [InstalledApp]) async throws
}
