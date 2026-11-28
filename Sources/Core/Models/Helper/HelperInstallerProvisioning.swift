import Foundation

/// Build/installer hand-off produced only after both binaries have their final signatures.
/// CDHashes are inputs from the signing pipeline; this model does not calculate or attest them.
struct HelperInstallerProvisioningBundle: Codable, Equatable {
    let schemaVersion: Int
    let generation: UInt64
    let releaseIdentifier: String
    let bundleIdentifier: String
    let jbRootPath: String
    let appCDHash: String
    let helperCDHash: String
    let allowedClientUID: UInt32
    /// Group used only for AF_UNIX socket connect permission; resolved from the installed App on-device.
    var socketGroupID: UInt32 = 501
    let stagingOwnerUID: UInt32
    let routeIdentifier: String
    let tweakInjectPath: String
    let stagingRootPath: String
    let socketPath: String
    let helperVersion: String
    /// Supplied by the signing pipeline; nil intentionally prevents production Helper startup.
    var teamIdentifier: String? = nil

    static let currentSchemaVersion = 2

    enum ValidationError: Error, Equatable {
        case unsupportedSchema, invalidGeneration, invalidReleaseIdentifier, invalidBundleIdentifier
        case invalidRootOrPaths, invalidCDHash, invalidUID, invalidRoute, invalidVersion
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw ValidationError.unsupportedSchema }
        guard generation > 0 else { throw ValidationError.invalidGeneration }
        guard !releaseIdentifier.isEmpty, releaseIdentifier.count <= 128,
              releaseIdentifier.range(of: "^[A-Za-z0-9._+-]+$", options: .regularExpression) != nil else {
            throw ValidationError.invalidReleaseIdentifier
        }
        let parts = bundleIdentifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.first!.isLetter && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else {
            throw ValidationError.invalidBundleIdentifier
        }
        guard HelperPolicy.isAbsoluteCleanPath(jbRootPath), jbRootPath != "/",
              HelperPolicy.isAbsoluteCleanPath(tweakInjectPath), tweakInjectPath.hasPrefix(jbRootPath + "/"),
              HelperPolicy.isAbsoluteCleanPath(stagingRootPath), stagingRootPath.hasPrefix(jbRootPath + "/"),
              HelperPolicy.isAbsoluteCleanPath(socketPath),
              socketPath == jbRootPath + "/Library/FilterKit/Helper/helper.sock",
              stagingRootPath != tweakInjectPath,
              !stagingRootPath.hasPrefix(tweakInjectPath + "/"),
              !tweakInjectPath.hasPrefix(stagingRootPath + "/"),
              socketPath.utf8.count < 100 else { throw ValidationError.invalidRootOrPaths }
        guard HelperPolicy.isValidCDHash(appCDHash), HelperPolicy.isValidCDHash(helperCDHash),
              appCDHash.lowercased() != helperCDHash.lowercased() else { throw ValidationError.invalidCDHash }
        guard allowedClientUID != 0, socketGroupID != 0, stagingOwnerUID != 0 else { throw ValidationError.invalidUID }
        guard !routeIdentifier.isEmpty, routeIdentifier.count <= 128,
              routeIdentifier.range(of: "^[A-Za-z0-9._+-]+$", options: .regularExpression) != nil else {
            throw ValidationError.invalidRoute
        }
        guard !helperVersion.isEmpty, helperVersion.count <= 64 else { throw ValidationError.invalidVersion }
    }

    func appTrustConfiguration() throws -> HelperAppTrustConfiguration {
        try validate()
        let config = HelperAppTrustConfiguration(schemaVersion: 1, bundleIdentifier: bundleIdentifier,
            allowedHelperCDHashes: [helperCDHash.lowercased()], generation: generation,
            allowedHelperUIDs: [0], allowedHelperGIDs: [0])
        try config.validate()
        return config
    }

    func disabledRootManifest() throws -> HelperDeploymentManifest {
        try validate()
        let pins = HelperTrustPinSet(schemaVersion: HelperTrustPinSet.currentSchemaVersion,
            bundleIdentifier: bundleIdentifier, allowedClientUIDs: [allowedClientUID],
            allowedAppCDHashes: [appCDHash.lowercased()], allowedHelperCDHashes: [helperCDHash.lowercased()],
            generation: generation, clientTeamIdentifier: teamIdentifier)
        return try pins.makeDisabledManifest(routeIdentifier: routeIdentifier, jbRootPath: jbRootPath,
            tweakInjectPath: tweakInjectPath, stagingRootPath: stagingRootPath, socketPath: socketPath,
            stagingOwnerUID: stagingOwnerUID, socketGroupID: socketGroupID)
    }

    /// Conservative launchd artifact. It is intentionally disabled and is not bootstrapped by this code.
    func disabledLaunchDaemonPlist() throws -> Data {
        try validate()
        let dictionary: [String: Any] = [
            "Label": "cn.yfen.filterkit.helper",
            "ProgramArguments": [jbRootPath + "/usr/libexec/filterkit-helper"],
            "Disabled": true,
            "RunAtLoad": false,
            "KeepAlive": false,
            "ProcessType": "Background",
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null"
        ]
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}

struct HelperInstallerArtifactDigest: Codable, Equatable {
    let relativePath: String
    let sha256: String

    func validate() -> Bool {
        HelperPolicy.isSafeRelativePath(relativePath) && HelperPolicy.isValidHash(sha256)
    }
}

/// A closed, inspectable plan. It describes what a future trusted root installer may do;
/// it deliberately contains no arbitrary shell command or caller-supplied destination.
struct HelperInstallerTransactionPlan: Equatable {
    enum Action: String, Codable { case install, upgrade, stop, start, uninstall, repin }
    enum Step: String {
        case validateRoot, validateSignedArtifacts, stopExactJob, preservePreviousRelease
        case stageExecutable, stageLaunchDaemon, stageManifest, verifyStagedFiles
        case atomicallyActivateRelease, bootstrapExactJob, verifySocket, removeOwnedArtifacts
        case restorePreviousRelease, leaveServiceStopped
    }

    let action: Action
    let jbRootPath: String
    let steps: [Step]
    let rollbackSteps: [Step]
    let executionEnabled: Bool
    let mayRunFromApp: Bool

    static func make(action: Action, bundle: HelperInstallerProvisioningBundle) throws -> Self {
        try bundle.validate()
        let steps: [Step]
        let rollback: [Step]
        switch action {
        case .install:
            steps = [.validateRoot, .validateSignedArtifacts, .stageExecutable, .stageLaunchDaemon,
                     .stageManifest, .verifyStagedFiles, .atomicallyActivateRelease, .leaveServiceStopped]
            rollback = [.removeOwnedArtifacts, .leaveServiceStopped]
        case .upgrade, .repin:
            steps = [.validateRoot, .validateSignedArtifacts, .stopExactJob, .preservePreviousRelease,
                     .stageExecutable, .stageLaunchDaemon, .stageManifest, .verifyStagedFiles,
                     .atomicallyActivateRelease, .leaveServiceStopped]
            rollback = [.restorePreviousRelease, .leaveServiceStopped]
        case .stop:
            steps = [.validateRoot, .stopExactJob, .verifySocket]
            rollback = []
        case .start:
            steps = [.validateRoot, .validateSignedArtifacts, .verifyStagedFiles, .bootstrapExactJob, .verifySocket]
            rollback = [.stopExactJob, .leaveServiceStopped]
        case .uninstall:
            steps = [.validateRoot, .stopExactJob, .verifySocket, .removeOwnedArtifacts]
            rollback = [.leaveServiceStopped]
        }
        return Self(action: action, jbRootPath: bundle.jbRootPath, steps: steps,
                    rollbackSteps: rollback, executionEnabled: false, mayRunFromApp: false)
    }
}
