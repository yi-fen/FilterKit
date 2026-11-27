import Foundation

/// App-side read-only client for Helper identity evidence. This service has no mutation methods.
@MainActor
final class HelperPluginIdentityAttestationService {
    enum ServiceError: Error { case trustNotProvisioned }
    private let coordinatorFactory: () throws -> HelperDeploymentCoordinator

    init(coordinatorFactory: @escaping () throws -> HelperDeploymentCoordinator) {
        self.coordinatorFactory = coordinatorFactory
    }

    static func production(resolvedRootPath: String?) throws -> HelperPluginIdentityAttestationService {
        #if canImport(Darwin)
        guard let trustURL = Bundle.main.url(forResource: "FilterKit-Helper-AppTrust", withExtension: "json"),
              let data = try? Data(contentsOf: trustURL),
              let trust = try? JSONDecoder().decode(HelperAppTrustConfiguration.self, from: data),
              let root = resolvedRootPath, !root.isEmpty else {
            throw ServiceError.trustNotProvisioned
        }
        let socket = root + "/Library/FilterKit/Helper/helper.sock"
        return HelperPluginIdentityAttestationService {
            try HelperProductionTransportFactory.makeCoordinator(socketPath: socket, appTrust: trust)
        }
        #else
        throw ServiceError.trustNotProvisioned
        #endif
    }

    func attest(_ plugin: PluginScanItem) async throws -> HelperPluginIdentityAttestation {
        guard let pluginID = UUID(uuidString: plugin.filterKitPluginID ?? ""),
              let dylib = plugin.dylibFileName, let plist = plugin.plistFileName else {
            throw HelperDeploymentCoordinator.CoordinatorError.mutationRejected
        }
        let coordinator = try coordinatorFactory()
        return try await coordinator.attestPluginIdentity(pluginID: pluginID,
            dylibFileName: dylib, plistFileName: plist)
    }
}
