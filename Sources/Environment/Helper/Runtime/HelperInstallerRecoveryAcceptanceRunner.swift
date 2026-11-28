import Foundation

/// Read-only acceptance orchestration for the real recovery components. The caller supplies a
/// fresh service observation on every pass; production adapters must obtain it through
/// HelperInstallerAuthenticatedServiceObserver.validate using the OS-authenticated IPC peer.
/// This runner never exposes file mutation, launchd control, or execution authorization.
struct HelperInstallerRecoveryAcceptanceRunner {
    enum Result: String, Codable { case reviewOnly, keepServiceStopped }

    struct ArtifactEvidence: Codable, Equatable {
        let artifact: String
        let relativePath: String
        let sha256: String
        let byteCount: Int
        let ownerUID: UInt32
        let groupID: UInt32
        let mode: UInt16
        let device: UInt64
        let inode: UInt64
    }

    struct Report: Codable, Equatable {
        let schemaVersion: Int
        let transactionID: String
        let result: Result
        let journalSequence: UInt64
        let journalHeadHash: String
        let active: [ArtifactEvidence]
        let staged: [ArtifactEvidence]
        let previous: [ArtifactEvidence]
        let pointerMatchesObservedArtifacts: Bool
        let pointerReleaseIdentifier: String?
        let pointerGeneration: UInt64?
        let ownershipVerified: Bool
        let serviceLabel: String
        let serviceObserverCodeIdentitySHA256: String
        let serviceState: String
        let evidenceDigest: String
        let executionAuthorized: Bool
        let limitations: [String]
    }

    enum RunnerError: Error, Equatable {
        case invalidTransactionID, invalidDigest, reportEncodingFailed
    }

    private let preflight: HelperInstallerRecoveryPreflight

    init(preflight: HelperInstallerRecoveryPreflight) { self.preflight = preflight }

    /// Validates the OS-authenticated IPC peer and one-time challenge before the observation is
    /// handed to the preflight closure. The peer identity must come from the transport layer,
    /// never from fields decoded out of the report payload.
    static func validateAuthenticatedServiceReport(
        report: HelperInstallerAuthenticatedServiceObserver.Report,
        expectedChallenge: UUID,
        authenticatedPeer: HelperPeerIdentity,
        pin: HelperInstallerAuthenticatedServiceObserver.Pin,
        expectedHelperExecutableSHA256: String
    ) throws -> HelperInstallerServiceObservation {
        try HelperInstallerAuthenticatedServiceObserver.validate(
            report: report, expectedChallenge: expectedChallenge,
            authenticatedPeer: authenticatedPeer, pin: pin,
            expectedHelperExecutableSHA256: expectedHelperExecutableSHA256)
    }

    /// The shared lock remains held by preflight for both complete evidence passes. The returned
    /// JSON is an audit artifact only; evidenceDigest is not a signature or execution capability.
    func run(jbroot: String, transactionID: UUID,
             verifiedRelease: HelperRootReleaseSet.Verified,
             previousExpectedHashes: [HelperRootReleaseSet.Artifact: String]?,
             expectedObserverCodeIdentitySHA256: String,
             serviceObservation: () throws -> HelperInstallerServiceObservation) throws -> Report {
        let (outcome, evidence) = try preflight.inspectTwiceUnderSharedLock(
            jbroot: jbroot, transactionID: transactionID, verifiedRelease: verifiedRelease,
            previousExpectedHashes: previousExpectedHashes,
            expectedObserverCodeIdentitySHA256: expectedObserverCodeIdentitySHA256,
            serviceObservation: serviceObservation)

        let result: Result
        switch outcome {
        case .safeToContinueReviewOnly: result = .reviewOnly
        case .keepServiceStopped: result = .keepServiceStopped
        }
        let active = Self.artifacts(evidence.activeRecords)
        let staged = Self.artifacts(evidence.stagedRecords)
        let previous = Self.artifacts(evidence.previousRecords)
        let serviceState: String
        switch evidence.serviceState {
        case .stopped: serviceState = "stopped"
        case .unknown: serviceState = "unknown"
        case .running(let pid, let hash): serviceState = "running:pid=\(pid):sha256=\(hash)"
        }
        let digest = Self.digest(transactionID: transactionID, result: result,
            sequence: evidence.journalSequence, head: evidence.journalHeadHash,
            active: active, staged: staged, previous: previous,
            pointerMatches: evidence.activePointerMatchesObservedArtifacts,
            pointerID: evidence.activePointer?.releaseIdentifier,
            pointerGeneration: evidence.activePointer?.generation,
            ownership: evidence.ownershipVerified, serviceLabel: evidence.serviceLabel,
            observerHash: evidence.serviceObserverCodeIdentitySHA256, serviceState: serviceState)

        return Report(schemaVersion: 1, transactionID: transactionID.uuidString.lowercased(),
            result: result, journalSequence: evidence.journalSequence,
            journalHeadHash: evidence.journalHeadHash, active: active, staged: staged,
            previous: previous,
            pointerMatchesObservedArtifacts: evidence.activePointerMatchesObservedArtifacts,
            pointerReleaseIdentifier: evidence.activePointer?.releaseIdentifier,
            pointerGeneration: evidence.activePointer?.generation,
            ownershipVerified: evidence.ownershipVerified, serviceLabel: evidence.serviceLabel,
            serviceObserverCodeIdentitySHA256: evidence.serviceObserverCodeIdentitySHA256,
            serviceState: serviceState, evidenceDigest: digest, executionAuthorized: false,
            limitations: [
                "Read-only acceptance report; no filesystem or launchd mutation was performed.",
                "Service observation must be produced by the platform adapter after OS-authenticated peer validation.",
                "Evidence digest is deterministic diagnostic data, not a signature or authorization token.",
                "A separate platform/device acceptance is required before any production write gate can open."
            ])
    }

    /// Optional human review binds to this exact report digest. It does not open an execution gate.
    func approveForReview(_ report: Report, reviewerID: String) throws -> HelperInstallerRecoveryAuthorization.Decision {
        guard report.schemaVersion == 1, report.executionAuthorized == false,
              HelperPolicy.isValidHash(report.evidenceDigest) else { throw RunnerError.invalidDigest }
        return try HelperInstallerRecoveryAuthorization.approveForReview(
            reviewerID: reviewerID, evidenceDigest: report.evidenceDigest)
    }

    func encodeJSON(_ report: Report) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(report)
        } catch { throw RunnerError.reportEncodingFailed }
    }

    private static func artifacts(_ records: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.FileRecord]) -> [ArtifactEvidence] {
        records.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { key in
            guard let value = records[key] else { return nil }
            return ArtifactEvidence(artifact: key.rawValue, relativePath: value.relativePath,
                sha256: value.sha256, byteCount: value.byteCount, ownerUID: value.ownerUID,
                groupID: value.groupID, mode: value.mode, device: value.device, inode: value.inode)
        }
    }

    private static func digest(transactionID: UUID, result: Result, sequence: UInt64, head: String,
        active: [ArtifactEvidence], staged: [ArtifactEvidence], previous: [ArtifactEvidence],
        pointerMatches: Bool, pointerID: String?, pointerGeneration: UInt64?, ownership: Bool,
        serviceLabel: String, observerHash: String, serviceState: String) -> String {
        var lines = ["schema=1", "transaction=\(transactionID.uuidString.lowercased())",
            "result=\(result.rawValue)", "journal.sequence=\(sequence)", "journal.head=\(head)"]
        for (name, values) in [("active", active), ("staged", staged), ("previous", previous)] {
            for item in values {
                lines.append("\(name).\(item.artifact)=\(item.relativePath)|\(item.sha256)|\(item.byteCount)|\(item.ownerUID)|\(item.groupID)|\(item.mode)|\(item.device)|\(item.inode)")
            }
        }
        lines += ["pointer.matches=\(pointerMatches)", "pointer.id=\(pointerID ?? "")",
            "pointer.generation=\(pointerGeneration.map(String.init) ?? "")",
            "ownership=\(ownership)", "service.label=\(serviceLabel)",
            "service.observer=\(observerHash)", "service.state=\(serviceState)"]
        return SHA256Digest.hex(Data(lines.joined(separator: "\n").utf8))
    }
}
