import Foundation

/// Structured security event. Never stores dylib/plist contents or arbitrary request payloads.
struct HelperAuditRecord: Codable, Equatable {
    enum Outcome: String, Codable { case accepted, rejected, succeeded, failed }
    let eventID: UUID
    let timestamp: Date
    let requestID: UUID?
    let operation: HelperOperation?
    let peerUID: UInt32?
    let peerGID: UInt32?
    let peerPID: Int32?
    let peerCDHash: String?
    let outcome: Outcome
    let reasonCode: String
    let changedRelativePaths: [String]
    let sourceSHA256: String?
    let output: String?

    init(requestID: UUID? = nil, operation: HelperOperation? = nil,
         peer: HelperPeerIdentity? = nil, outcome: Outcome, reasonCode: String,
         changedRelativePaths: [String] = [], sourceSHA256: String? = nil,
         output: String? = nil, timestamp: Date = Date()) {
        self.eventID = UUID()
        self.timestamp = timestamp
        self.requestID = requestID
        self.operation = operation
        self.peerUID = peer?.uid
        self.peerGID = peer?.gid
        self.peerPID = peer?.pid
        self.peerCDHash = peer?.cdHashHex
        self.outcome = outcome
        self.reasonCode = String(reasonCode.prefix(96))
        self.changedRelativePaths = Array(changedRelativePaths.prefix(8)).map { String($0.prefix(160)) }
        self.sourceSHA256 = sourceSHA256
        self.output = output.map { String($0.prefix(1024)) }
    }
}

protocol HelperAuditSink {
    func append(_ record: HelperAuditRecord) throws
}

/// Lifecycle defaults are a documented deployment profile, not an installed launchd plist.
struct HelperLifecycleProfile: Codable, Equatable {
    let runAtLoad: Bool
    let keepAlive: Bool
    let throttleIntervalSeconds: Int
    let maximumConcurrentConnections: Int
    let idleConnectionTimeoutSeconds: Int
    let socketModeOctal: String
    let auditFileModeOctal: String
    let maximumAuditFileBytes: Int
    let retainedAuditFiles: Int

    static let conservativePersistent = HelperLifecycleProfile(
        runAtLoad: true, keepAlive: true, throttleIntervalSeconds: 10,
        maximumConcurrentConnections: 8, idleConnectionTimeoutSeconds: 5,
        socketModeOctal: "0660", auditFileModeOctal: "0600",
        maximumAuditFileBytes: 1_048_576, retainedAuditFiles: 3
    )
}

struct HelperFingerprintRecoveryPolicy: Codable, Equatable {
    let automaticRepinAllowed: Bool
    let requiresPrivilegedInstaller: Bool
    let requiresFreshAppAndHelperHashes: Bool
    let appMayModifyManifest: Bool

    static let failClosed = HelperFingerprintRecoveryPolicy(
        automaticRepinAllowed: false, requiresPrivilegedInstaller: true,
        requiresFreshAppAndHelperHashes: true, appMayModifyManifest: false
    )
}
