import Foundation

struct HelperDeploymentManifest: Codable, Equatable {
    let schemaVersion: Int
    let routeIdentifier: String
    let jbRootPath: String
    let tweakInjectPath: String
    let stagingRootPath: String
    let socketPath: String
    let allowedAppCDHashes: [String]
    let allowedHelperCDHashes: [String]
    let allowedClientUIDs: [UInt32]
    /// Explicit owner of the staging root; it is not inferred from the set of allowed clients.
    var stagingOwnerUID: UInt32? = nil
    let executionEnabled: Bool

    static let currentSchemaVersion = 1

    /// Safe template: deliberately disabled until on-device validation and explicit release approval.
    static func disabledTemplate(routeIdentifier: String, jbRootPath: String, tweakInjectPath: String,
                                 stagingRootPath: String, socketPath: String,
                                 appCDHashes: [String] = [], helperCDHashes: [String] = [],
                                 allowedClientUIDs: [UInt32] = [501],
                                 stagingOwnerUID: UInt32? = nil) -> Self {
        Self(schemaVersion: currentSchemaVersion, routeIdentifier: routeIdentifier,
             jbRootPath: jbRootPath, tweakInjectPath: tweakInjectPath,
             stagingRootPath: stagingRootPath, socketPath: socketPath,
             allowedAppCDHashes: appCDHashes, allowedHelperCDHashes: helperCDHashes,
             allowedClientUIDs: allowedClientUIDs, stagingOwnerUID: stagingOwnerUID, executionEnabled: false)
    }
}

enum HelperPolicyError: Error, Equatable {
    case executionDisabled, unsupportedManifest, untrustedPeer, invalidCDHash, helperIdentityMismatch
    case operationNotAllowed, invalidFileName, invalidStagingPath, invalidTargetPath
    case missingOrInvalidHash, targetMustNotExist, invalidPlist, replayedRequest, ownershipProofRequired
}

struct HelperClosedExecutionPlan: Codable, Equatable {
    let requestID: UUID
    let pluginID: UUID
    let action: HelperPlanAction
    let sourceRelativePath: String?
    let destinationRelativePath: String
    let expectedSHA256: String?
    let operation: HelperOperation
}

struct HelperPolicy {
    func authorize(_ request: HelperOperationRequest, peer: HelperPeerIdentity, helperCDHashHex: String,
                   manifest: HelperDeploymentManifest, targetExists: Bool,
                   sourceIsRegularNonSymlink: Bool, sourceHashMatches: Bool,
                   plistData: Data? = nil) throws -> HelperClosedExecutionPlan {
        guard manifest.schemaVersion == HelperDeploymentManifest.currentSchemaVersion,
              Self.isAbsoluteCleanPath(manifest.jbRootPath), Self.isAbsoluteCleanPath(manifest.tweakInjectPath),
              Self.isAbsoluteCleanPath(manifest.stagingRootPath), Self.isAbsoluteCleanPath(manifest.socketPath),
              !manifest.routeIdentifier.isEmpty else { throw HelperPolicyError.unsupportedManifest }
        guard abs(request.createdAt.timeIntervalSinceNow) <= 120 else { throw HelperPolicyError.untrustedPeer }
        guard manifest.executionEnabled else { throw HelperPolicyError.executionDisabled }
        guard manifest.allowedClientUIDs.contains(peer.uid) else { throw HelperPolicyError.untrustedPeer }
        guard Self.isValidCDHash(peer.cdHashHex), manifest.allowedAppCDHashes.contains(where: { $0.caseInsensitiveCompare(peer.cdHashHex) == .orderedSame }) else { throw HelperPolicyError.untrustedPeer }
        guard Self.isValidCDHash(helperCDHashHex), manifest.allowedHelperCDHashes.contains(where: { $0.caseInsensitiveCompare(helperCDHashHex) == .orderedSame }) else { throw HelperPolicyError.helperIdentityMismatch }
        guard Self.isSafeLeafName(request.targetFileName) else { throw HelperPolicyError.invalidFileName }

        switch request.operation {
        case .installDylib:
            guard request.targetFileName.lowercased().hasSuffix(".dylib") else { throw HelperPolicyError.invalidFileName }
            guard !targetExists else { throw HelperPolicyError.targetMustNotExist }
            guard let source = request.stagingRelativePath, Self.isSafeRelativePath(source), sourceIsRegularNonSymlink else { throw HelperPolicyError.invalidStagingPath }
            guard let hash = request.expectedSHA256, Self.isValidHash(hash), sourceHashMatches else { throw HelperPolicyError.missingOrInvalidHash }
            return HelperClosedExecutionPlan(requestID: request.requestID, pluginID: request.pluginID, action: .copyFile,
                sourceRelativePath: source, destinationRelativePath: request.targetFileName,
                expectedSHA256: hash.lowercased(), operation: request.operation)
        case .replaceFilterPlist:
            guard request.targetFileName.lowercased().hasSuffix(".plist") else { throw HelperPolicyError.invalidFileName }
            guard let source = request.stagingRelativePath, Self.isSafeRelativePath(source), sourceIsRegularNonSymlink else { throw HelperPolicyError.invalidStagingPath }
            guard let hash = request.expectedSHA256, Self.isValidHash(hash), sourceHashMatches else { throw HelperPolicyError.missingOrInvalidHash }
            guard let plistData, (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) != nil else { throw HelperPolicyError.invalidPlist }
            return HelperClosedExecutionPlan(requestID: request.requestID, pluginID: request.pluginID, action: .copyFile,
                sourceRelativePath: source, destinationRelativePath: request.targetFileName,
                expectedSHA256: hash.lowercased(), operation: request.operation)
        case .removeUnmanagedDylib:
            // Deletion remains unavailable until a separately verified FilterKit ownership proof
            // is carried through the request and checked against the root-owned manifest.
            throw HelperPolicyError.ownershipProofRequired
        }
    }

    static func isSafeLeafName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.hasPrefix(".") &&
        !value.contains("/") && !value.contains("\\") && !value.contains("..")
    }
    static func isAbsoluteCleanPath(_ value: String) -> Bool {
        value.hasPrefix("/") && !value.contains("\\") && !value.contains("\0") &&
        value.split(separator: "/").allSatisfy { $0 != "." && $0 != ".." } &&
        URL(fileURLWithPath: value).standardizedFileURL.path == value
    }
    static func isSafeRelativePath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.contains("\\") && !value.contains("\0") &&
        value.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func isValidHash(_ value: String) -> Bool { value.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil }
    static func isValidCDHash(_ value: String) -> Bool { value.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil }
}
