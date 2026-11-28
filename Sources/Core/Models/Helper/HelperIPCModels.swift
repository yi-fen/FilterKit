import Foundation

/// Versioned, bounded IPC envelope. The transport is intentionally abstract in P1-19.
enum HelperIPCMessageType: String, Codable {
    case hello, helloAck, operationRequest, deploymentBatchRequest, deploymentBatchReceipt, operationReceipt, healthRequest, healthResponse, maintenanceRecoveryRequest, maintenanceRecoveryResponse, pluginFilterMutationPrepareRequest, pluginFilterMutationPrepared, pluginFilterMutationCommitRequest, pluginFilterMutationCommitted, pluginIdentityAttestationRequest, pluginIdentityAttestationResponse, appPluginActivationPrepareRequest, appPluginActivationPrepared, appPluginActivationCommitRequest, appPluginActivationCommitted, appPluginActivationTransactionQueryRequest, appPluginActivationTransactionReconcileRequest, appPluginActivationTransactionStatusResponse, pluginUninstallRequest, pluginUninstallResponse, rejected
}

struct HelperIPCEnvelope: Codable, Equatable {
    let protocolVersion: Int
    let messageType: HelperIPCMessageType
    let requestID: UUID
    let createdAt: Date
    let nonce: String?
    let payload: Data?

    static let currentVersion = 1
    static let maximumFrameBytes = 96 * 1024

    init(messageType: HelperIPCMessageType, requestID: UUID = UUID(), createdAt: Date = Date(), nonce: String? = nil, payload: Data? = nil) {
        self.protocolVersion = Self.currentVersion
        self.messageType = messageType
        self.requestID = requestID
        self.createdAt = createdAt
        self.nonce = nonce
        self.payload = payload
    }
}


/// Public, path-free Helper state returned to the App. It intentionally exposes no filesystem paths,
/// peer identifiers, hashes, or audit contents.
enum HelperRecoveryStatus: String, Codable, Equatable {
    case clean
    case legacyRecoveryRequired
    case threeFileRecoveryRequired
    case bothRecoveryRequired
    case associationTransactionRecoveryRequired
    case invalidJournal
    case unavailable
}

struct HelperStatusResponse: Codable, Equatable {
    let helperReachable: Bool
    let recoveryStatus: HelperRecoveryStatus
    let checkedAt: Date
    let protocolVersion: Int
}

enum HelperMaintenanceAction: String, Codable { case inspect, reconcileThreeFileTransaction }

struct HelperMaintenanceRecoveryRequest: Codable, Equatable {
    let action: HelperMaintenanceAction
    /// Must equal the enclosing IPC envelope requestID; the replay guard then protects it.
    let requestNonce: UUID
    let requestedAt: Date
    /// Required for reconciliation; inspection requests leave it nil.
    let transactionID: UUID?
    /// UI confirmation signal. It is not treated as cryptographic proof of a human gesture.
    let operatorConfirmed: Bool

    init(action: HelperMaintenanceAction, requestNonce: UUID, requestedAt: Date,
         transactionID: UUID? = nil, operatorConfirmed: Bool = false) {
        self.action = action
        self.requestNonce = requestNonce
        self.requestedAt = requestedAt
        self.transactionID = transactionID
        self.operatorConfirmed = operatorConfirmed
    }
}

enum HelperMaintenanceResult: String, Codable {
    case inspected
    case recoveryNotReleased
    case recoveryRequired
    case invalidRequest
}

struct HelperMaintenanceRecoveryResponse: Codable, Equatable {
    let result: HelperMaintenanceResult
    let recoveryStatus: HelperRecoveryStatus
    let completedAt: Date
    let transactionID: UUID?

    init(result: HelperMaintenanceResult, recoveryStatus: HelperRecoveryStatus,
         completedAt: Date, transactionID: UUID? = nil) {
        self.result = result
        self.recoveryStatus = recoveryStatus
        self.completedAt = completedAt
        self.transactionID = transactionID
    }
}

enum HelperIPCCodecError: Error, Equatable {
    case frameTooLarge, truncatedFrame, invalidLength, unsupportedVersion, invalidEnvelope
}

/// UInt32 big-endian length prefix followed by sorted-key JSON. Does not open sockets.
struct HelperIPCFrameCodec {
    func encode(_ envelope: HelperIPCEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(envelope)
        guard !body.isEmpty, body.count <= HelperIPCEnvelope.maximumFrameBytes else { throw HelperIPCCodecError.frameTooLarge }
        var length = UInt32(body.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(body)
        return frame
    }

    func decode(_ frame: Data) throws -> HelperIPCEnvelope {
        guard frame.count >= 4 else { throw HelperIPCCodecError.truncatedFrame }
        let length = frame.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= HelperIPCEnvelope.maximumFrameBytes else { throw HelperIPCCodecError.invalidLength }
        guard frame.count == Int(length) + 4 else { throw HelperIPCCodecError.truncatedFrame }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(HelperIPCEnvelope.self, from: frame.dropFirst(4))
        guard envelope.protocolVersion == HelperIPCEnvelope.currentVersion else { throw HelperIPCCodecError.unsupportedVersion }
        guard envelope.requestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else { throw HelperIPCCodecError.invalidEnvelope }
        return envelope
    }
}

struct HelperPeerIdentity: Codable, Equatable {
    let uid: UInt32
    let gid: UInt32
    let pid: Int32
    let cdHashHex: String
    /// Reserved for a separately verified process-generation source. Audit-token bytes
    /// are not mislabeled as a PID version.
    let pidVersion: UInt64?
    let auditSessionID: UInt32?
    /// SHA-256 of the kernel LOCAL_PEERTOKEN snapshot; never a caller-supplied value.
    let auditTokenDigest: String?
    /// OS-verified code-signing identifier (normally the signed bundle identifier).
    /// Never populated from an IPC payload. Nil means the platform adapter did not
    /// obtain an independently verified identifier.
    let verifiedCodeIdentifier: String?
    /// OS-verified Team ID from the code signature; not inferred from CDHash.
    let verifiedTeamIdentifier: String?

    init(uid: UInt32, gid: UInt32, pid: Int32, cdHashHex: String,
         pidVersion: UInt64?, auditSessionID: UInt32?, auditTokenDigest: String? = nil,
         verifiedCodeIdentifier: String? = nil, verifiedTeamIdentifier: String? = nil) {
        self.uid = uid
        self.gid = gid
        self.pid = pid
        self.cdHashHex = cdHashHex
        self.pidVersion = pidVersion
        self.auditSessionID = auditSessionID
        self.auditTokenDigest = auditTokenDigest
        self.verifiedCodeIdentifier = verifiedCodeIdentifier
        self.verifiedTeamIdentifier = verifiedTeamIdentifier
    }
}

enum HelperOperation: String, Codable, CaseIterable {
    case installDylib
    case removeUnmanagedDylib
    case replaceFilterPlist
}

enum HelperPlanAction: String, Codable { case copyFile, removeFile }

struct HelperFileExpectation: Codable, Equatable {
    let fileName: String
    let sha256: String?
}

struct HelperOperationRequest: Codable, Equatable {
    let requestID: UUID
    let operation: HelperOperation
    let pluginID: UUID
    let stagingRelativePath: String?
    let targetFileName: String
    let expectedSHA256: String?
    let createdAt: Date
}


/// One IPC message carries the complete dylib + plist deployment unit. The digest is computed
/// over canonical JSON for the immutable batch fields, excluding the digest itself.
struct HelperDeploymentBatchMetadata: Codable, Equatable {
    /// Required for first install. This is the App from whose detail page the import began.
    let hardBoundBundleIdentifier: String
    let softAssociations: [FilterKitManifestSoftAssociation]

    func validate() -> Bool {
        func valid(_ value: String) -> Bool {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            return parts.count >= 2 && parts.allSatisfy { part in
                !part.isEmpty && part.first!.isLetter && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
            }
        }
        return valid(hardBoundBundleIdentifier) &&
            HelperBundleIdentifierKey.set(softAssociations.map(\.bundleIdentifier)).count == softAssociations.count &&
            !softAssociations.contains(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(hardBoundBundleIdentifier) }) &&
            softAssociations.allSatisfy { valid($0.bundleIdentifier) }
    }
}

struct HelperDeploymentBatchRequest: Codable, Equatable {
    let batchID: UUID
    let pluginID: UUID
    let createdAt: Date
    let operations: [HelperOperationRequest]
    /// Optional for backward-compatible decoding; production first-install authorization rejects nil.
    var deploymentMetadata: HelperDeploymentBatchMetadata? = nil
    let batchSHA256: String

    enum BatchError: Error, Equatable { case invalidBatch, digestMismatch }

    static func make(pluginID: UUID, operations: [HelperOperationRequest],
                     deploymentMetadata: HelperDeploymentBatchMetadata? = nil,
                     createdAt: Date = Date()) throws -> Self {
        let unsigned = Unsigned(batchID: UUID(), pluginID: pluginID, createdAt: createdAt,
                                operations: operations, deploymentMetadata: deploymentMetadata)
        let digest = try digest(unsigned)
        return Self(batchID: unsigned.batchID, pluginID: pluginID, createdAt: createdAt,
                    operations: operations, deploymentMetadata: deploymentMetadata, batchSHA256: digest)
    }

    func validate(now: Date = Date(), clockSkewLimit: TimeInterval = 120) throws {
        guard batchID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              pluginID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              abs(now.timeIntervalSince(createdAt)) <= clockSkewLimit,
              operations.allSatisfy({ abs($0.createdAt.timeIntervalSince(createdAt)) <= 5 }),
              operations.allSatisfy({ $0.pluginID == pluginID }),
              deploymentMetadata.map({ $0.validate() }) ?? true else { throw BatchError.invalidBatch }
        _ = try HelperDeploymentBatchValidator().validate(operations)
        let unsigned = Unsigned(batchID: batchID, pluginID: pluginID, createdAt: createdAt, operations: operations, deploymentMetadata: deploymentMetadata)
        guard try Self.digest(unsigned) == batchSHA256.lowercased() else { throw BatchError.digestMismatch }
    }

    private struct Unsigned: Codable {
        let batchID: UUID
        let pluginID: UUID
        let createdAt: Date
        let operations: [HelperOperationRequest]
        let deploymentMetadata: HelperDeploymentBatchMetadata?
    }

    private static func digest(_ value: Unsigned) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return SHA256Digest.hex(try encoder.encode(value))
    }
}

struct HelperOperationReceipt: Codable, Equatable {
    let requestID: UUID
    let operation: HelperOperation
    let succeeded: Bool
    let exitCode: Int32
    let changedPaths: [String]
    let output: String
    let completedAt: Date

    func validates(against request: HelperOperationRequest, expectedPaths: Set<String>, now: Date = Date(), clockSkewLimit: TimeInterval = 120) -> Bool {
        requestID == request.requestID && operation == request.operation &&
        ((succeeded && exitCode == 0) || (!succeeded && exitCode != 0)) &&
        Set(changedPaths) == expectedPaths && changedPaths.count == expectedPaths.count &&
        output.utf8.count <= 32 * 1024 && abs(completedAt.timeIntervalSince(now)) <= clockSkewLimit
    }
}
