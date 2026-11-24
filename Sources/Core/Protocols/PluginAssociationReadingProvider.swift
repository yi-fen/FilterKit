import Foundation

protocol PluginAssociationReadingProvider {
    func readAssociations(from scanResult: PluginScanResult) async throws -> PluginAssociationReadResult
}
