import Foundation

/// App-facing integration for the association confirmation surface.
/// The production factory is intentionally unavailable until the signed trust resource is provisioned.
@MainActor
final class HelperPluginAssociationCommitService {
    enum ServiceError: Error, Equatable {
        case invalidPluginIdentity, missingSourceEvidence, invalidManifest, trustNotProvisioned
    }

    private let coordinatorFactory: () throws -> HelperDeploymentCoordinator

    init(coordinatorFactory: @escaping () throws -> HelperDeploymentCoordinator) {
        self.coordinatorFactory = coordinatorFactory
    }

    static func production() throws -> HelperPluginAssociationCommitService {
        #if canImport(Darwin)
        guard let trustURL = Bundle.main.url(forResource: "FilterKit-Helper-AppTrust", withExtension: "json"),
              let data = try? Data(contentsOf: trustURL),
              let trust = try? JSONDecoder().decode(HelperAppTrustConfiguration.self, from: data),
              let root = ReadOnlyEnvironmentProvider().makeDiagnosticReport().resolvedRootPath else {
            throw ServiceError.trustNotProvisioned
        }
        let socket = root + "/Library/FilterKit/Helper/helper.sock"
        return HelperPluginAssociationCommitService {
            try HelperProductionTransportFactory.makeCoordinator(socketPath: socket, appTrust: trust)
        }
        #else
        throw ServiceError.trustNotProvisioned
        #endif
    }

    func commit(plugin: PluginScanItem, action: HelperPluginFilterMutationAction,
                targetBundleIdentifier: String, userConfirmed: Bool) async throws -> HelperPluginFilterMutationCommitReceipt {
        guard userConfirmed else { throw HelperDeploymentCoordinator.CoordinatorError.confirmationRequired }
        guard let pluginIDString = plugin.filterKitPluginID, let pluginID = UUID(uuidString: pluginIDString),
              let dylib = plugin.dylibFileName, let plist = plugin.plistFileName,
              let plistPath = plugin.plistPath, let manifestPath = plugin.manifestPath,
              let plistBytes = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let manifestBytes = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)) else {
            throw ServiceError.missingSourceEvidence
        }
        guard plugin.ownership == .filterKit, plugin.pairingState == .paired,
              plugin.managementPermission?.canModify == true,
              plist.hasSuffix(".plist"), dylib.hasSuffix(".dylib") else {
            throw ServiceError.invalidPluginIdentity
        }
        // Parse the manifest before using its current digest as optimistic concurrency evidence.
        guard (try? JSONSerialization.jsonObject(with: manifestBytes)) != nil else {
            throw ServiceError.invalidManifest
        }
        let request = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: pluginID,
            action: action, dylibFileName: dylib, plistFileName: plist,
            targetBundleIdentifier: targetBundleIdentifier,
            expectedPlistSHA256: SHA256Digest.hex(plistBytes),
            expectedManifestSHA256: SHA256Digest.hex(manifestBytes), createdAt: Date())
        guard request.validateShape() else { throw ServiceError.invalidPluginIdentity }
        let coordinator = try coordinatorFactory()
        return try await coordinator.commitPluginAssociation(request, userConfirmed: userConfirmed)
    }
}
