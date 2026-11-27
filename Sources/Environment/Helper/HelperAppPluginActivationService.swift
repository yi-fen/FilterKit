import Foundation

/// App-side adapter for the APP-detail single-plugin/single-App activation protocol.
/// Prepare is read-only; Commit is independently fail-closed by the coordinator release gate.
@MainActor
final class HelperAppPluginActivationService {
    enum ServiceError: Error, Equatable {
        case invalidPluginIdentity, missingSourceEvidence, invalidCurrentState, trustNotProvisioned
    }

    private let coordinatorFactory: () throws -> HelperDeploymentCoordinator

    init(coordinatorFactory: @escaping () throws -> HelperDeploymentCoordinator) {
        self.coordinatorFactory = coordinatorFactory
    }

    static func production() throws -> HelperAppPluginActivationService {
        // Reuse the same signed trust provisioning and socket path as other Helper operations.
        #if canImport(Darwin)
        guard let trustURL = Bundle.main.url(forResource: "FilterKit-Helper-AppTrust", withExtension: "json"),
              let data = try? Data(contentsOf: trustURL),
              let trust = try? JSONDecoder().decode(HelperAppTrustConfiguration.self, from: data),
              let root = ReadOnlyEnvironmentProvider().makeDiagnosticReport().resolvedRootPath else {
            throw ServiceError.trustNotProvisioned
        }
        let socket = root + "/Library/FilterKit/Helper/helper.sock"
        return HelperAppPluginActivationService {
            try HelperProductionTransportFactory.makeCoordinator(socketPath: socket, appTrust: trust)
        }
        #else
        throw ServiceError.trustNotProvisioned
        #endif
    }

    func makeCommand(plugin: PluginScanItem, activation: AppPluginActivationState,
                     desiredEnabled: Bool, snapshotRevision: UInt64) throws -> HelperAppPluginActivationCommand {
        guard activation.pluginID == plugin.id,
              activation.targetBundleIdentifier.count > 0,
              let pluginID = UUID(uuidString: plugin.filterKitPluginID ?? ""),
              let dylib = plugin.dylibFileName, let plist = plugin.plistFileName,
              let plistPath = plugin.plistPath, let manifestPath = plugin.manifestPath,
              plugin.ownership == .filterKit, plugin.pairingState == .paired,
              plugin.managementPermission?.canModify == true else {
            throw ServiceError.invalidPluginIdentity
        }
        guard let filterBytes = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let manifestBytes = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)) else {
            throw ServiceError.missingSourceEvidence
        }
        guard (try? JSONSerialization.jsonObject(with: manifestBytes)) != nil else {
            throw ServiceError.missingSourceEvidence
        }
        guard let current = activation.isEnabled, snapshotRevision > 0 else {
            throw ServiceError.invalidCurrentState
        }
        return HelperAppPluginActivationCommand(requestID: UUID(), pluginID: pluginID,
            targetBundleIdentifier: activation.targetBundleIdentifier,
            desiredEnabled: desiredEnabled, expectedEnabled: current,
            dylibFileName: dylib, plistFileName: plist,
            expectedFilterSHA256: SHA256Digest.hex(filterBytes),
            expectedManifestSHA256: SHA256Digest.hex(manifestBytes),
            snapshotRevision: snapshotRevision, createdAt: Date())
    }

    func prepare(plugin: PluginScanItem, activation: AppPluginActivationState,
                 desiredEnabled: Bool, snapshotRevision: UInt64) async throws
        -> (HelperAppPluginActivationCommand, HelperAppPluginActivationPlan) {
        let command = try makeCommand(plugin: plugin, activation: activation,
            desiredEnabled: desiredEnabled, snapshotRevision: snapshotRevision)
        let coordinator = try coordinatorFactory()
        let plan = try await coordinator.prepareAppPluginActivation(command)
        return (command, plan)
    }

    func commit(command: HelperAppPluginActivationCommand,
                plan: HelperAppPluginActivationPlan,
                userConfirmed: Bool) async throws -> HelperAppPluginActivationProof {
        let coordinator = try coordinatorFactory()
        return try await coordinator.commitAppPluginActivation(command,
            preparedPlan: plan, userConfirmed: userConfirmed)
    }
}
