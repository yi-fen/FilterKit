import Foundation

/// Exact three-artifact release envelope. Verification is byte-for-byte integrity validation;
/// it does not establish Apple code-signature validity or publisher provenance.
struct HelperRootReleaseSet: Equatable {
    enum Artifact: String, CaseIterable { case executable, deploymentManifest, launchDaemon }
    enum VerificationError: Error, Equatable {
        case invalidBundle, artifactSetMismatch, digestSetMismatch, digestMismatch
        case executableInvalid, manifestInvalid, launchDaemonInvalid
    }
    struct Verified: Equatable {
        let releaseIdentifier: String
        let generation: UInt64
        let hashes: [Artifact: String]
        let byteCounts: [Artifact: Int]
    }

    static let executablePath = "usr/libexec/filterkit-helper"
    static let manifestPath = "Library/FilterKit/Helper/Deployment.json"
    static let launchDaemonPath = "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"

    func verify(bundle: HelperInstallerProvisioningBundle, artifacts: [String: Data],
                expectedDigests: [HelperInstallerArtifactDigest]) throws -> Verified {
        do { try bundle.validate() } catch { throw VerificationError.invalidBundle }
        let paths = [Self.executablePath, Self.manifestPath, Self.launchDaemonPath]
        guard Set(artifacts.keys) == Set(paths) else { throw VerificationError.artifactSetMismatch }
        let digestMap = Dictionary(expectedDigests.map { ($0.relativePath, $0.sha256.lowercased()) },
                                   uniquingKeysWith: { first, _ in first })
        guard expectedDigests.count == 3, Set(digestMap.keys) == Set(paths),
              expectedDigests.allSatisfy({ $0.validate() }) else { throw VerificationError.digestSetMismatch }
        guard let executable = artifacts[Self.executablePath], executable.count >= 4,
              executable.count <= 64 * 1024 * 1024 else { throw VerificationError.executableInvalid }
        guard let manifest = artifacts[Self.manifestPath], manifest.count <= 256 * 1024,
              let object = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              (object["schemaVersion"] as? NSNumber)?.intValue == 1,
              object["jbRootPath"] as? String == bundle.jbRootPath,
              object["routeIdentifier"] as? String == bundle.routeIdentifier,
              object["executionEnabled"] as? Bool == false else { throw VerificationError.manifestInvalid }
        guard let launch = artifacts[Self.launchDaemonPath],
              let plist = try? PropertyListSerialization.propertyList(from: launch, options: [], format: nil) as? [String: Any],
              plist["Label"] as? String == "cn.yfen.filterkit.helper",
              plist["ProgramArguments"] as? [String] == [bundle.jbRootPath + "/usr/libexec/filterkit-helper"],
              plist["Disabled"] as? Bool == true,
              plist["RunAtLoad"] as? Bool == false,
              plist["KeepAlive"] as? Bool == false else { throw VerificationError.launchDaemonInvalid }
        var hashes: [Artifact: String] = [:]
        var counts: [Artifact: Int] = [:]
        for (artifact, path) in zip(Artifact.allCases, paths) {
            let data = artifacts[path]!
            let hash = SHA256Digest.hex(data)
            guard digestMap[path] == hash else { throw VerificationError.digestMismatch }
            hashes[artifact] = hash; counts[artifact] = data.count
        }
        return Verified(releaseIdentifier: bundle.releaseIdentifier, generation: bundle.generation,
                        hashes: hashes, byteCounts: counts)
    }
}

/// Read-only reconciliation decision for an interrupted three-artifact activation.
/// Any unknown hash or ownership ambiguity fails closed; no filesystem operation is performed.
struct HelperRootReleaseRecoveryAssessment: Equatable {
    enum Decision: Equatable { case resumeActivation, restorePreviousRelease, finalizeCommittedRelease, noAction, manualIntervention }
    struct ArtifactObservation: Equatable {
        let currentHash: String?
        let previousBackupHash: String?
        let currentOwnedByFilterKit: Bool
        let backupOwnedByFilterKit: Bool
    }
    struct Snapshot: Equatable {
        let executable: ArtifactObservation
        let manifest: ArtifactObservation
        let launchDaemon: ArtifactObservation
    }
    let decision: Decision
    let reason: String

    static func assess(state: HelperInstallerTransactionJournal.State,
                       newHashes: [HelperRootReleaseSet.Artifact: String],
                       previousHashes: [HelperRootReleaseSet.Artifact: String?],
                       snapshot: Snapshot) -> Self {
        let observations = [snapshot.executable, snapshot.manifest, snapshot.launchDaemon]
        guard Set(newHashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
              Set(previousHashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
              newHashes.values.allSatisfy(HelperPolicy.isValidHash),
              previousHashes.values.compactMap({ $0 }).allSatisfy(HelperPolicy.isValidHash) else {
            return .init(decision: .manualIntervention, reason: "incomplete or malformed hash inventory")
        }
        for (index, artifact) in HelperRootReleaseSet.Artifact.allCases.enumerated() {
            let observed = observations[index]
            let expectedNew = newHashes[artifact]!
            let expectedOld = previousHashes[artifact]!
            if let current = observed.currentHash, current != expectedNew && current != expectedOld {
                return .init(decision: .manualIntervention, reason: "unexpected current artifact hash")
            }
            if let backup = observed.previousBackupHash, backup != expectedOld {
                return .init(decision: .manualIntervention, reason: "backup hash does not match previous release")
            }
            if observed.currentHash != nil && observed.currentHash != expectedNew && !observed.currentOwnedByFilterKit {
                return .init(decision: .manualIntervention, reason: "current artifact ownership is unproven")
            }
            if observed.previousBackupHash != nil && !observed.backupOwnedByFilterKit {
                return .init(decision: .manualIntervention, reason: "backup ownership is unproven")
            }
            if expectedOld != nil && observed.currentHash == nil && observed.previousBackupHash == nil {
                return .init(decision: .manualIntervention, reason: "previous artifact and backup both missing")
            }
        }
        switch state {
        case .prepared, .artifactsVerified: return .init(decision: .resumeActivation, reason: "no activation phase recorded")
        case .previousReleasePreserved, .staged, .rollbackRequired: return .init(decision: .restorePreviousRelease, reason: "activation was not durably committed")
        case .activated, .serviceVerified: return .init(decision: .finalizeCommittedRelease, reason: "all artifacts must be reverified before finalization")
        case .committed, .rolledBack: return .init(decision: .noAction, reason: "terminal journal state")
        case .manualIntervention: return .init(decision: .manualIntervention, reason: "journal explicitly requires operator review")
        }
    }
}
