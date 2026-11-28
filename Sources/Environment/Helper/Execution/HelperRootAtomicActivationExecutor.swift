import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if !canImport(Darwin)
@_silgen_name("renameat2") private func fk_renameat2(_ oldDirectory: Int32, _ oldPath: UnsafePointer<CChar>, _ newDirectory: Int32, _ newPath: UnsafePointer<CChar>, _ flags: UInt32) -> Int32
#endif

/// Journaled three-directory activation primitive. It is deliberately standalone and is not
/// wired to HelperRuntime or the production deployment backend while the release gate is closed.
final class HelperRootAtomicActivationExecutor {
    enum Artifact: String, CaseIterable, Codable { case executable, deploymentManifest, launchDaemon }
    enum Phase: String, Codable { case prepared, staged, preserving, activating, committed, rollingBack, rolledBack, manualIntervention }
    enum Failure: Error, Equatable { case notRoot, unsafeRoot, unsafeParent, invalidRelease, conflict, journalExists, journalInvalid, hashMismatch, lockBusy, io(Int32), injectedCrash(Artifact), injectedFault(FaultPoint), recoveryRequiresManualIntervention, durableJournalMismatch, stagedSetNotComplete, previousSetNotComplete, serviceNotAuthenticatedOrStopped, journalCommitIndeterminate, activePointerCommitIndeterminate }
    enum FaultPoint: String, CaseIterable { case afterPreparedJournal, afterFirstStage, afterFirstBackup, afterFirstActivation, afterFirstProgressJournal, afterCommittedJournal, beforePointerRename, afterPointerCommit }
    struct Release {
        let bundle: HelperInstallerProvisioningBundle
        let bytes: [Artifact: Data]
        let expectedDigests: [HelperInstallerArtifactDigest]
        let expectedPreviousHashes: [Artifact: String?]
    }
    struct Result: Equatable { let transactionID: UUID; let installedHashes: [Artifact: String] }
    private struct Record: Codable {
        let schema: Int; let id: UUID; let names: [Artifact: String]
        let releaseIdentifier: String; let generation: UInt64
        let newHashes: [Artifact: String]; let oldHashes: [Artifact: String?]
        var phase: Phase; var completed: [Artifact]
    }
    private let root: String
    private let destinations: [Artifact: String] = [
        .executable: "usr/libexec/filterkit-helper",
        .deploymentManifest: "Library/FilterKit/Helper/Deployment.json",
        .launchDaemon: "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
    ]
    private static let lock = NSLock()
    private let journal = ".filterkit-root-activation.json"
    private let lockFile = ".filterkit-root-activation.lock"

    init(rootDirectory: String) throws {
        guard HelperPolicy.isAbsoluteCleanPath(rootDirectory), rootDirectory != "/" else { throw Failure.unsafeRoot }
        root = rootDirectory
    }

    /// Legacy host primitive. Production callers must use the journal-bound overload below.
    func activate(_ release: Release, crashAfter: Artifact? = nil, faultAt: FaultPoint? = nil) throws -> Result {
        try activateInternal(release, transactionID: UUID(), durableJournal: nil, journalStore: nil,
                             crashAfter: crashAfter, faultAt: faultAt)
    }

    /// Compatibility activation API for the existing host smoke harness. Production integration
    /// must use the disk-evidence overload below; Inspection values are not authoritative.
    @available(*, deprecated, message: "Use disk-evidence activation overload; caller-supplied Inspection is compatibility-only")
    /// Journal-bound activation. The caller must have durably recorded `intentActivateRelease`;
    /// the method independently reloads it, authenticates a stopped-service observation, and
    /// requires complete staged/previous inventories before touching Active files.
    func activate(_ release: Release,
                  durableJournal: HelperInstallerTransactionJournal,
                  journalStore: HelperInstallerDurableJournalStore,
                  stagedInspection: HelperInstallerStagedReleaseStore.Inspection,
                  previousInspection: HelperInstallerPreviousReleaseStore.Inspection?,
                  serviceReport: HelperInstallerAuthenticatedServiceObserver.Report,
                  expectedChallenge: UUID,
                  authenticatedPeer: HelperPeerIdentity,
                  observerPin: HelperInstallerAuthenticatedServiceObserver.Pin,
                  expectedObservedHelperSHA256: String,
                  crashAfter: Artifact? = nil,
                  faultAt: FaultPoint? = nil) throws -> Result {
        var expectedStagedHashes: [HelperRootReleaseSet.Artifact: String] = [:]
        for artifact in HelperRootReleaseSet.Artifact.allCases {
            guard let bytes = release.bytes[Self.mapArtifact(artifact)] else { throw Failure.invalidRelease }
            expectedStagedHashes[artifact] = SHA256Digest.hex(bytes)
        }
        guard durableJournal.state == .staged,
              durableJournal.pendingOperation == .activateRelease,
              stagedInspection.transactionID == durableJournal.transactionID,
              stagedInspection.state == .complete,
              stagedInspection.observedHashes == expectedStagedHashes else { throw Failure.stagedSetNotComplete }
        if durableJournal.action == .upgrade || durableJournal.action == .repin {
            let expectedPrevious = release.expectedPreviousHashes.reduce(into: [HelperRootReleaseSet.Artifact: String]()) { result, pair in
                guard let hash = pair.value else { return }
                switch pair.key {
                case .executable: result[.executable] = hash
                case .deploymentManifest: result[.deploymentManifest] = hash
                case .launchDaemon: result[.launchDaemon] = hash
                }
            }
            guard let previousInspection, previousInspection.transactionID == durableJournal.transactionID,
                  previousInspection.state == .complete,
                  previousInspection.observedHashes == expectedPrevious else { throw Failure.previousSetNotComplete }
        } else if previousInspection != nil || release.expectedPreviousHashes.values.contains(where: { $0 != nil }) {
            throw Failure.previousSetNotComplete
        }
        return try activateInternal(release, transactionID: durableJournal.transactionID,
                                    durableJournal: durableJournal, journalStore: journalStore,
                                    preflight: {
                                        let persisted: HelperInstallerTransactionJournal
                                        do { persisted = try journalStore.load(transactionID: durableJournal.transactionID) }
                                        catch { throw Failure.durableJournalMismatch }
                                        guard persisted == durableJournal else { throw Failure.durableJournalMismatch }
                                        do {
                                            let observation = try HelperInstallerAuthenticatedServiceObserver.validate(
                                                report: serviceReport, expectedChallenge: expectedChallenge,
                                                authenticatedPeer: authenticatedPeer, pin: observerPin,
                                                expectedHelperExecutableSHA256: expectedObservedHelperSHA256)
                                            guard observation.state == .stopped else { throw Failure.serviceNotAuthenticatedOrStopped }
                                        } catch { throw Failure.serviceNotAuthenticatedOrStopped }
                                    },
                                    crashAfter: crashAfter, faultAt: faultAt)
    }

    /// Production-shaped activation entry point. Unlike the compatibility overload above, it
    /// accepts no caller-created Inspection evidence: staged and previous bytes are reopened
    /// from their root-owned stores only after this executor has acquired its persistent lock.
    func activate(_ release: Release,
                  durableJournal: HelperInstallerTransactionJournal,
                  journalStore: HelperInstallerDurableJournalStore,
                  prepared: HelperPreparedRootInstall,
                  stagedStore: HelperInstallerStagedReleaseStore,
                  previousRelease: HelperRootReleaseSet.Verified?,
                  previousStore: HelperInstallerPreviousReleaseStore?,
                  serviceReport: HelperInstallerAuthenticatedServiceObserver.Report,
                  expectedChallenge: UUID,
                  authenticatedPeer: HelperPeerIdentity,
                  observerPin: HelperInstallerAuthenticatedServiceObserver.Pin,
                  expectedObservedHelperSHA256: String,
                  crashAfter: Artifact? = nil,
                  faultAt: FaultPoint? = nil) throws -> Result {
        let evidenceCheck: () throws -> Void = {
            guard prepared.plan.jbRootPath == self.root,
                  prepared.initialJournal.transactionID == durableJournal.transactionID,
                  prepared.initialJournal.action == durableJournal.action,
                  prepared.initialJournal.releaseIdentifier == durableJournal.releaseIdentifier,
                  prepared.initialJournal.generation == durableJournal.generation,
                  prepared.plan.action == durableJournal.action,
                  durableJournal.releaseIdentifier == release.bundle.releaseIdentifier,
                  durableJournal.generation == release.bundle.generation,
                  prepared.release.releaseIdentifier == release.bundle.releaseIdentifier,
                  prepared.release.generation == release.bundle.generation,
                  prepared.release.hashes == Dictionary(uniqueKeysWithValues: HelperRootReleaseSet.Artifact.allCases.map {
                      ($0, SHA256Digest.hex(release.bytes[Self.mapArtifact($0)] ?? Data()))
                  }),
                  SHA256Digest.hex(prepared.provisioningEnvelopeData) == prepared.provisioningEnvelopeSHA256,
                  durableJournal.state == .staged,
                  durableJournal.pendingOperation == .activateRelease else {
                throw Failure.stagedSetNotComplete
            }
            // Re-bind the immutable prepared value to the exact signed-envelope payload at the
            // point of activation. `prepare()` verifies the signature; this second check prevents
            // a mismatched plan/release/envelope tuple from crossing the privileged boundary.
            guard let envelope = try? JSONDecoder().decode(
                    HelperSignedProvisioningManifest.self,
                    from: prepared.provisioningEnvelopeData),
                  envelope.payload.jbRootPath == self.root,
                  envelope.payload.releaseIdentifier == release.bundle.releaseIdentifier,
                  envelope.payload.generation == release.bundle.generation,
                  envelope.payload.helperCDHash == release.bundle.helperCDHash,
                  envelope.payload.teamIdentifier == release.bundle.teamIdentifier else {
                throw Failure.stagedSetNotComplete
            }
            do { try prepared.initialJournal.validateChain() }
            catch { throw Failure.durableJournalMismatch }
            let expectedPathByArtifact: [HelperRootReleaseSet.Artifact: String] = [
                .executable: HelperRootReleaseSet.executablePath,
                .deploymentManifest: HelperRootReleaseSet.manifestPath,
                .launchDaemon: HelperRootReleaseSet.launchDaemonPath
            ]
            var expectedDigestMap: [String: String] = [:]
            for digest in release.expectedDigests {
                guard expectedDigestMap[digest.relativePath] == nil else {
                    throw Failure.invalidRelease
                }
                expectedDigestMap[digest.relativePath] = digest.sha256
            }
            guard expectedDigestMap.count == HelperRootReleaseSet.Artifact.allCases.count,
                  HelperRootReleaseSet.Artifact.allCases.allSatisfy({ artifact in
                      guard let path = expectedPathByArtifact[artifact],
                            let expected = expectedDigestMap[path],
                            let actual = prepared.release.hashes[artifact] else { return false }
                      return expected == actual
                  }) else { throw Failure.stagedSetNotComplete }
            let stagedBytes = try stagedStore.loadVerifiedArtifactsForActivation(
                transactionID: durableJournal.transactionID, expectedHashes: prepared.release.hashes)
            let stagedPaths: [String: Data] = [
                HelperRootReleaseSet.executablePath: stagedBytes[.executable]!,
                HelperRootReleaseSet.manifestPath: stagedBytes[.deploymentManifest]!,
                HelperRootReleaseSet.launchDaemonPath: stagedBytes[.launchDaemon]!
            ]
            let verifiedStaged = try HelperRootReleaseSet().verify(
                bundle: release.bundle, artifacts: stagedPaths, expectedDigests: release.expectedDigests)
            guard verifiedStaged == prepared.release,
                  HelperRootReleaseSet.Artifact.allCases.allSatisfy({ artifact in
                      stagedBytes[artifact] == release.bytes[Self.mapArtifact(artifact)]
                  }) else { throw Failure.stagedSetNotComplete }

            if durableJournal.action == .upgrade || durableJournal.action == .repin {
                guard let previousRelease, let previousStore,
                      previousRelease.releaseIdentifier != release.bundle.releaseIdentifier,
                      previousRelease.generation > 0,
                      Set(previousRelease.hashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
                      Set(previousRelease.byteCounts.keys) == Set(HelperRootReleaseSet.Artifact.allCases) else {
                    throw Failure.previousSetNotComplete
                }
                let expectedPrevious = release.expectedPreviousHashes.reduce(into: [HelperRootReleaseSet.Artifact: String]()) { result, pair in
                    guard let hash = pair.value else { return }
                    switch pair.key {
                    case .executable: result[.executable] = hash
                    case .deploymentManifest: result[.deploymentManifest] = hash
                    case .launchDaemon: result[.launchDaemon] = hash
                    }
                }
                guard expectedPrevious.count == HelperRootReleaseSet.Artifact.allCases.count,
                      previousRelease.hashes == expectedPrevious else { throw Failure.previousSetNotComplete }
                let previousBytes = try previousStore.loadVerifiedArtifactsForActivation(
                    transactionID: durableJournal.transactionID, expectedHashes: expectedPrevious)
                guard HelperRootReleaseSet.Artifact.allCases.allSatisfy({ artifact in
                    guard let bytes = previousBytes[artifact] else { return false }
                    return previousRelease.byteCounts[artifact] == bytes.count &&
                        SHA256Digest.hex(bytes) == previousRelease.hashes[artifact]
                }) else { throw Failure.previousSetNotComplete }
            } else if previousRelease != nil || previousStore != nil ||
                        release.expectedPreviousHashes.values.contains(where: { $0 != nil }) {
                throw Failure.previousSetNotComplete
            }
            let persisted: HelperInstallerTransactionJournal
            do { persisted = try journalStore.load(transactionID: durableJournal.transactionID) }
            catch { throw Failure.durableJournalMismatch }
            guard persisted == durableJournal else { throw Failure.durableJournalMismatch }
            do {
                let observation = try HelperInstallerAuthenticatedServiceObserver.validate(
                    report: serviceReport, expectedChallenge: expectedChallenge,
                    authenticatedPeer: authenticatedPeer, pin: observerPin,
                    expectedHelperExecutableSHA256: expectedObservedHelperSHA256)
                guard observation.state == .stopped else { throw Failure.serviceNotAuthenticatedOrStopped }
            } catch { throw Failure.serviceNotAuthenticatedOrStopped }
        }
        return try activateInternal(release, transactionID: durableJournal.transactionID,
                                    durableJournal: durableJournal, journalStore: journalStore,
                                    preflight: evidenceCheck, crashAfter: crashAfter, faultAt: faultAt)
    }

    private func activateInternal(_ release: Release, transactionID: UUID,
                                  durableJournal: HelperInstallerTransactionJournal?,
                                  journalStore: HelperInstallerDurableJournalStore?,
                                  preflight: (() throws -> Void)? = nil,
                                  crashAfter: Artifact?, faultAt: FaultPoint?) throws -> Result {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard (durableJournal == nil) == (journalStore == nil) else { throw Failure.durableJournalMismatch }
        guard geteuid() == 0 else { throw Failure.notRoot }
        guard Set(release.bytes.keys) == Set(Artifact.allCases), Set(release.expectedPreviousHashes.keys) == Set(Artifact.allCases),
              release.bytes[.executable]!.count >= 4, release.bytes[.executable]!.count <= 64 * 1024 * 1024,
              release.bytes[.deploymentManifest]!.count <= 256 * 1024,
              (try? PropertyListSerialization.propertyList(from: release.bytes[.launchDaemon]!, options: [], format: nil)) != nil,
              release.expectedPreviousHashes.values.compactMap({$0}).allSatisfy(HelperPolicy.isValidHash) else { throw Failure.invalidRelease }
        let staged = [HelperRootReleaseSet.executablePath: release.bytes[.executable]!,
                      HelperRootReleaseSet.manifestPath: release.bytes[.deploymentManifest]!,
                      HelperRootReleaseSet.launchDaemonPath: release.bytes[.launchDaemon]!]
        do { _ = try HelperRootReleaseSet().verify(bundle: release.bundle, artifacts: staged, expectedDigests: release.expectedDigests) }
        catch { throw Failure.invalidRelease }
        let rootFD = try openRoot(); defer { _ = close(rootFD) }
        let lockFD = try acquireTransactionLock(rootFD); defer { _ = flock(lockFD, LOCK_UN); _ = close(lockFD) }
        try preflight?()
        guard try readRecord(rootFD) == nil else { throw Failure.journalExists }
        var old: [Artifact: String?] = [:]
        for item in Artifact.allCases {
            let (parent, leaf) = try openParent(item, rootFD: rootFD)
            defer { _ = close(parent) }
            let observed = try hashAt(parent, leaf)
            let expected = release.expectedPreviousHashes[item]!
            guard observed == expected else { throw Failure.conflict }
            old[item] = observed
        }
        let id = transactionID
        let names = Dictionary(uniqueKeysWithValues: Artifact.allCases.map { ($0, destinations[$0]!) })
        var record = Record(schema: 2, id: id, names: names,
            releaseIdentifier: release.bundle.releaseIdentifier, generation: release.bundle.generation,
            newHashes: Dictionary(uniqueKeysWithValues: Artifact.allCases.map { ($0, SHA256Digest.hex(release.bytes[$0]!)) }),
            oldHashes: old, phase: .prepared, completed: [])
        try writeRecord(record, rootFD: rootFD)
        if faultAt == .afterPreparedJournal { throw Failure.injectedFault(.afterPreparedJournal) }
        do {
            var injectedStage = false
            for item in Artifact.allCases {
                let (parent, _) = try openParent(item, rootFD: rootFD); defer { _ = close(parent) }
                let temp = tempName(id, item)
                try writeExclusive(release.bytes[item]!, name: temp, parent: parent, mode: item == .deploymentManifest ? 0o600 : (item == .executable ? 0o755 : 0o644))
                guard fsync(parent) == 0 else { throw Failure.io(errno) }
                guard try hashAt(parent, temp) == record.newHashes[item] else { throw Failure.hashMismatch }
                if !injectedStage { injectedStage = true; if faultAt == .afterFirstStage { throw Failure.injectedFault(.afterFirstStage) } }
            }
            record.phase = .staged; try writeRecord(record, rootFD: rootFD)
            record.phase = .preserving; try writeRecord(record, rootFD: rootFD)
            for item in Artifact.allCases {
                guard record.oldHashes[item]! != nil else { continue }
                let (parent, leaf) = try openParent(item, rootFD: rootFD); defer { _ = close(parent) }
                let backup = backupName(id, item)
                try renameNoReplace(parent, leaf, backup)
                guard fsync(parent) == 0 else { throw Failure.io(errno) }
                guard try hashAt(parent, backup) == record.oldHashes[item]! else { throw Failure.hashMismatch }
                if faultAt == .afterFirstBackup { throw Failure.injectedFault(.afterFirstBackup) }
            }
            record.phase = .activating; try writeRecord(record, rootFD: rootFD)
            for item in Artifact.allCases {
                let (parent, leaf) = try openParent(item, rootFD: rootFD); defer { _ = close(parent) }
                try renameNoReplace(parent, tempName(id, item), leaf)
                guard try hashAt(parent, leaf) == record.newHashes[item] else { throw Failure.hashMismatch }
                if faultAt == .afterFirstActivation { throw Failure.injectedFault(.afterFirstActivation) }
                record.completed.append(item); try writeRecord(record, rootFD: rootFD)
                if faultAt == .afterFirstProgressJournal { throw Failure.injectedFault(.afterFirstProgressJournal) }
                guard fsync(parent) == 0 else { throw Failure.io(errno) }
                if crashAfter == item { throw Failure.injectedCrash(item) }
            }
            record.phase = .committed; try writeRecord(record, rootFD: rootFD)
            var publishedJournal = durableJournal
            if let durableJournal, let journalStore {
                var completed = durableJournal
                do {
                    try completed.apply(.activateRelease)
                    try journalStore.save(completed)
                    publishedJournal = completed
                } catch {
                    // Keep the committed activation record and all backups. Recovery can compare
                    // Active bytes with the durable Journal and finish reconciliation safely.
                    throw Failure.journalCommitIndeterminate
                }
            }
            if faultAt == .afterCommittedJournal { throw Failure.injectedFault(.afterCommittedJournal) }
            // Pointer is a non-authoritative hint. It is committed only after all Active bytes
            // have been read back and the Durable Journal has advanced. Keep the transaction
            // record/backups if pointer publication fails; recovery republishes idempotently.
            do {
                // Re-open and re-hash the three Active destinations immediately before pointer
                // publication; do not merely echo the transaction's expected hashes.
                var observedPointerHashes: [HelperRootReleaseSet.Artifact: String] = [:]
                for artifact in HelperRootReleaseSet.Artifact.allCases {
                    let mapped = Self.mapArtifact(artifact)
                    let (parent, leaf) = try openParent(mapped, rootFD: rootFD); defer { _ = close(parent) }
                    guard let observed = try hashAt(parent, leaf), observed == record.newHashes[mapped] else {
                        throw Failure.hashMismatch
                    }
                    observedPointerHashes[artifact] = observed
                }
                let verified = HelperRootReleaseSet.Verified(
                    releaseIdentifier: release.bundle.releaseIdentifier,
                    generation: release.bundle.generation,
                    hashes: observedPointerHashes,
                    byteCounts: Dictionary(uniqueKeysWithValues: HelperRootReleaseSet.Artifact.allCases.map { artifact in
                        (artifact, release.bytes[Self.mapArtifact(artifact)]!.count)
                    }))
                try HelperInstallerActiveReleasePointerWriter(jbRootPath: root).write(
                    transactionID: id, release: verified,
                    observedActiveHashes: observedPointerHashes,
                    faultAt: faultAt == .beforePointerRename ? .beforeRename : nil)
                try verifyPublishedPointer(record: record, expectedHashes: observedPointerHashes,
                                           durableJournal: publishedJournal)
            } catch Failure.hashMismatch { throw Failure.hashMismatch }
            catch { throw Failure.activePointerCommitIndeterminate }
            if faultAt == .afterPointerCommit { throw Failure.injectedFault(.afterPointerCommit) }
            for item in Artifact.allCases {
                let (parent, _) = try openParent(item, rootFD: rootFD); defer { _ = close(parent) }
                _ = backupName(id, item).withCString { unlinkat(parent, $0, 0) }
                _ = tempName(id, item).withCString { unlinkat(parent, $0, 0) }
                guard fsync(parent) == 0 else { throw Failure.io(errno) }
            }
            try clearRecord(rootFD)
            return Result(transactionID: id, installedHashes: record.newHashes)
        } catch Failure.injectedCrash { throw Failure.injectedCrash(crashAfter!) }
        catch { throw error }
    }

    /// Legacy recovery entry point for the isolated transaction host tests.
    func recover() throws -> Phase? {
        try recoverInternal(durableJournal: nil, journalStore: nil, preflight: nil)
    }

    /// Reconciles the activation record with the durable installer Journal while holding the
    /// same persistent transaction lock. A partial activation is rolled back only when every
    /// observed byte is attributable to this transaction; the Journal is then marked for
    /// manual intervention rather than silently advancing the installer workflow.
    func recover(durableJournal: HelperInstallerTransactionJournal,
                 journalStore: HelperInstallerDurableJournalStore,
                 serviceReport: HelperInstallerAuthenticatedServiceObserver.Report,
                 expectedChallenge: UUID,
                 authenticatedPeer: HelperPeerIdentity,
                 observerPin: HelperInstallerAuthenticatedServiceObserver.Pin,
                 expectedObservedHelperSHA256: String) throws -> Phase? {
        try recoverInternal(durableJournal: durableJournal, journalStore: journalStore, preflight: {
            let persisted: HelperInstallerTransactionJournal
            do { persisted = try journalStore.load(transactionID: durableJournal.transactionID) }
            catch { throw Failure.durableJournalMismatch }
            guard persisted == durableJournal else { throw Failure.durableJournalMismatch }
            do {
                let observation = try HelperInstallerAuthenticatedServiceObserver.validate(
                    report: serviceReport, expectedChallenge: expectedChallenge,
                    authenticatedPeer: authenticatedPeer, pin: observerPin,
                    expectedHelperExecutableSHA256: expectedObservedHelperSHA256)
                guard observation.state == .stopped else { throw Failure.serviceNotAuthenticatedOrStopped }
            } catch { throw Failure.serviceNotAuthenticatedOrStopped }
        })
    }

    private func recoverInternal(durableJournal: HelperInstallerTransactionJournal?,
                                 journalStore: HelperInstallerDurableJournalStore?,
                                 preflight: (() throws -> Void)?) throws -> Phase? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard (durableJournal == nil) == (journalStore == nil) else { throw Failure.durableJournalMismatch }
        guard geteuid() == 0 else { throw Failure.notRoot }
        let rootFD = try openRoot(); defer { _ = close(rootFD) }
        let lockFD = try acquireTransactionLock(rootFD); defer { _ = flock(lockFD, LOCK_UN); _ = close(lockFD) }
        try preflight?()
        guard var record = try readRecord(rootFD) else { return nil }
        if let durableJournal, record.id != durableJournal.transactionID { throw Failure.durableJournalMismatch }
        guard record.schema == 2, record.names == destinations,
              !record.releaseIdentifier.isEmpty, record.releaseIdentifier.count <= 128,
              record.generation > 0,
              Set(record.newHashes.keys) == Set(Artifact.allCases),
              Set(record.oldHashes.keys) == Set(Artifact.allCases),
              record.newHashes.values.allSatisfy(HelperPolicy.isValidHash),
              record.oldHashes.values.compactMap({ $0 }).allSatisfy(HelperPolicy.isValidHash),
              Set(record.completed).count == record.completed.count,
              record.completed.allSatisfy({ Artifact.allCases.contains($0) }) else { throw Failure.journalInvalid }
        if record.phase == .manualIntervention { throw Failure.recoveryRequiresManualIntervention }
        if record.phase == .committed {
            for item in Artifact.allCases {
                let (parent, leaf) = try openParent(item, rootFD: rootFD); defer { _ = close(parent) }
                let activeHash = try hashAt(parent, leaf)
                guard activeHash == record.newHashes[item] else {
                    fputs("R5 recovery active mismatch \(item.rawValue): observed=\(activeHash ?? "nil") expected=\(record.newHashes[item] ?? "nil")\n", stderr)
                    throw Failure.recoveryRequiresManualIntervention
                }
                let backupHash = try hashAt(parent, backupName(record.id, item))
                guard backupHash == record.oldHashes[item]! else {
                    fputs("R5 recovery backup mismatch \(item.rawValue): observed=\(backupHash ?? "nil") expected=\(record.oldHashes[item]! ?? "nil")\n", stderr)
                    throw Failure.recoveryRequiresManualIntervention
                }
            }
            var verifiedJournal = durableJournal
            if let durableJournal, let journalStore {
                var reconciled = durableJournal
                if reconciled.pendingOperation == .activateRelease && reconciled.state == .staged {
                    do { try reconciled.apply(.activateRelease); try journalStore.save(reconciled) }
                    catch { throw Failure.journalCommitIndeterminate }
                } else if !(reconciled.pendingOperation == nil && reconciled.state == .activated) {
                    throw Failure.durableJournalMismatch
                }
                verifiedJournal = reconciled
            }
            var observedPointerHashes: [HelperRootReleaseSet.Artifact: String] = [:]
            for artifact in HelperRootReleaseSet.Artifact.allCases {
                let mapped = Self.mapArtifact(artifact)
                let (parent, leaf) = try openParent(mapped, rootFD: rootFD); defer { _ = close(parent) }
                guard let observed = try hashAt(parent, leaf), observed == record.newHashes[mapped] else {
                    record.phase = .manualIntervention; try writeRecord(record, rootFD: rootFD)
                    throw Failure.recoveryRequiresManualIntervention
                }
                observedPointerHashes[artifact] = observed
            }
            let verified = HelperRootReleaseSet.Verified(
                releaseIdentifier: record.releaseIdentifier, generation: record.generation,
                hashes: observedPointerHashes, byteCounts: [:])
            do {
                try HelperInstallerActiveReleasePointerWriter(jbRootPath: root).write(
                    transactionID: record.id, release: verified, observedActiveHashes: observedPointerHashes)
                try verifyPublishedPointer(record: record, expectedHashes: observedPointerHashes,
                                           durableJournal: verifiedJournal)
            } catch { throw Failure.activePointerCommitIndeterminate }
            for item in Artifact.allCases {
                let (parent, _) = try openParent(item, rootFD: rootFD); defer { _ = close(parent) }
                _ = backupName(record.id, item).withCString { unlinkat(parent, $0, 0) }
                _ = tempName(record.id, item).withCString { unlinkat(parent, $0, 0) }
                guard fsync(parent) == 0 else { throw Failure.io(errno) }
            }
            try clearRecord(rootFD); return .committed
        }
        if record.phase == .rolledBack {
            if let durableJournal, let journalStore, durableJournal.pendingOperation == .activateRelease {
                var reconciled = durableJournal
                do { try reconciled.apply(.requireManualIntervention); try journalStore.save(reconciled) }
                catch { throw Failure.journalCommitIndeterminate }
            }
            try clearRecord(rootFD); return .rolledBack
        }
        // Validate the complete rollback set before changing any Active destination.
        // In particular, never unlink a newly activated file until its trusted Previous
        // backup has been proven present and hash-correct. A missing backup must leave
        // the current bytes untouched and force manual intervention.
        for item in Artifact.allCases.reversed() {
            let (parent, leaf) = try openParent(item, rootFD: rootFD); defer { _ = close(parent) }
            let current = try hashAt(parent, leaf)
            let backupHash = try hashAt(parent, backupName(record.id, item))
            let newHash = record.newHashes[item]!
            let oldHash = record.oldHashes[item]!
            let currentIsKnown = current == nil || current == newHash || current == oldHash
            let backupIsKnown = backupHash == nil || backupHash == oldHash
            let backupIsSufficient = oldHash == nil ? backupHash == nil : (current == oldHash || backupHash == oldHash)
            guard currentIsKnown && backupIsKnown && backupIsSufficient else {
                record.phase = .manualIntervention
                try writeRecord(record, rootFD: rootFD)
                if let durableJournal, let journalStore {
                    var manual = try journalStore.load(transactionID: durableJournal.transactionID)
                    if manual.state != .manualIntervention {
                        try manual.apply(.requireManualIntervention)
                        do { try journalStore.save(manual) }
                        catch { throw Failure.journalCommitIndeterminate }
                    }
                }
                throw Failure.recoveryRequiresManualIntervention
            }
        }
        record.phase = .rollingBack; try writeRecord(record, rootFD: rootFD)
        for item in Artifact.allCases.reversed() {
            let (parent, leaf) = try openParent(item, rootFD: rootFD); defer { _ = close(parent) }
            let current = try hashAt(parent, leaf)
            let backup = backupName(record.id, item)
            let backupHash = try hashAt(parent, backup)
            let newHash = record.newHashes[item]!
            let oldHash = record.oldHashes[item]!
            if current == newHash { _ = leaf.withCString { unlinkat(parent, $0, 0) } }
            if let oldHash, backupHash == oldHash {
                guard (try hashAt(parent, leaf)) == nil else {
                    record.phase = .manualIntervention; try writeRecord(record, rootFD: rootFD)
                    throw Failure.recoveryRequiresManualIntervention
                }
                try renameNoReplace(parent, backup, leaf)
            }
            _ = tempName(record.id, item).withCString { unlinkat(parent, $0, 0) }
            guard fsync(parent) == 0 else { throw Failure.io(errno) }
        }
        // Read-after-rollback acceptance: never persist `.rolledBack` merely because
        // rename/unlink syscalls returned success. Every Active destination must now
        // match its trusted Previous hash (or remain absent when the prior release
        // had no artifact). A mismatch is quarantined for manual repair.
        for item in Artifact.allCases {
            let (parent, leaf) = try openParent(item, rootFD: rootFD); defer { _ = close(parent) }
            let observed = try hashAt(parent, leaf)
            let expected = record.oldHashes[item]!
            guard observed == expected else {
                record.phase = .manualIntervention
                try writeRecord(record, rootFD: rootFD)
                if let durableJournal, let journalStore {
                    var manual = try journalStore.load(transactionID: durableJournal.transactionID)
                    if manual.state != .manualIntervention {
                        try manual.apply(.requireManualIntervention)
                        do { try journalStore.save(manual) }
                        catch { throw Failure.journalCommitIndeterminate }
                    }
                }
                throw Failure.recoveryRequiresManualIntervention
            }
        }
        record.phase = .rolledBack; try writeRecord(record, rootFD: rootFD)
        if let durableJournal, let journalStore {
            var reconciled = durableJournal
            if reconciled.pendingOperation == .activateRelease {
                do { try reconciled.apply(.requireManualIntervention); try journalStore.save(reconciled) }
                catch { throw Failure.journalCommitIndeterminate }
            }
        }
        try clearRecord(rootFD)
        return .rolledBack
    }

    /// Read-after-write acceptance for the complete Active set and its non-authoritative pointer.
    /// The caller already holds the persistent activation lock. A successful rename alone is not
    /// sufficient: every Active byte hash and every pointer identity field must agree before
    /// transaction backups can be removed.
    private func verifyPublishedPointer(
        record: Record,
        expectedHashes: [HelperRootReleaseSet.Artifact: String],
        durableJournal: HelperInstallerTransactionJournal?
    ) throws {
        let paths: [HelperRootReleaseSet.Artifact: String] = [
            .executable: HelperRootReleaseSet.executablePath,
            .deploymentManifest: HelperRootReleaseSet.manifestPath,
            .launchDaemon: HelperRootReleaseSet.launchDaemonPath
        ]
        let observer = HelperInstallerDescriptorFilesystemObserver(jbRootPath: root, expectedOwnerUID: 0)
        let observed = try observer.observeArtifactSet(paths: paths)
        for artifact in HelperRootReleaseSet.Artifact.allCases {
            guard let expected = expectedHashes[artifact],
                  observed[artifact]?.sha256 == expected else { throw Failure.hashMismatch }
        }
        let pointer = try observer.observeActiveReleasePointer()
        let pointerHashes: [HelperRootReleaseSet.Artifact: String] = [
            .executable: pointer.artifactHashes["executable"] ?? "",
            .deploymentManifest: pointer.artifactHashes["deploymentManifest"] ?? "",
            .launchDaemon: pointer.artifactHashes["launchDaemon"] ?? ""
        ]
        guard pointer.transactionID == record.id,
              pointer.releaseIdentifier == record.releaseIdentifier,
              pointer.generation == record.generation,
              pointerHashes == expectedHashes else { throw Failure.activePointerCommitIndeterminate }
        if let durableJournal {
            guard durableJournal.transactionID == record.id,
                  durableJournal.releaseIdentifier == record.releaseIdentifier,
                  durableJournal.generation == record.generation,
                  durableJournal.state == .activated,
                  durableJournal.pendingOperation == nil else { throw Failure.durableJournalMismatch }
        }
    }

    private static func mapArtifact(_ artifact: HelperRootReleaseSet.Artifact) -> Artifact {
        switch artifact {
        case .executable: return .executable
        case .deploymentManifest: return .deploymentManifest
        case .launchDaemon: return .launchDaemon
        }
    }

    /// A persistent root-owned lock inode coordinates separate Helper processes. The file is
    /// intentionally not unlinked: unlinking a held flock inode could split the lock domain.
    private func acquireTransactionLock(_ rootFD: Int32) throws -> Int32 {
        let fd = lockFile.withCString { openat(rootFD, $0, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard fd >= 0 else { throw Failure.io(errno) }
        var st = stat()
        guard fstat(fd, &st) == 0,
              (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              st.st_uid == 0, st.st_gid == 0, st.st_nlink == 1, (st.st_mode & 0o777) == 0o600 else {
            _ = close(fd); throw Failure.unsafeRoot
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno; _ = close(fd)
            if code == EWOULDBLOCK || code == EAGAIN { throw Failure.lockBusy }
            throw Failure.io(code)
        }
        return fd
    }

    private func openRoot() throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.io(errno) }
        let components = root.split(separator: "/").map(String.init)
        guard !components.isEmpty else { _ = close(fd); throw Failure.unsafeRoot }
        for component in components {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            _ = close(fd)
            guard next >= 0 else { throw Failure.unsafeRoot }
            var st = stat()
            guard fstat(next, &st) == 0, st.st_uid == 0, st.st_gid == 0,
                  (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  (st.st_mode & 0o022) == 0 || (st.st_mode & mode_t(S_ISVTX)) != 0 else {
                _ = close(next); throw Failure.unsafeRoot
            }
            fd = next
        }
        guard (fd >= 0) else { throw Failure.unsafeRoot }
        var finalInfo = stat()
        guard fstat(fd, &finalInfo) == 0, (finalInfo.st_mode & 0o077) == 0 else {
            _ = close(fd); throw Failure.unsafeRoot
        }
        return fd
    }
    private func openParent(_ item: Artifact, rootFD: Int32) throws -> (Int32, String) {
        let parts = destinations[item]!.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { throw Failure.invalidRelease }
        var fd = dup(rootFD); guard fd >= 0 else { throw Failure.io(errno) }
        for component in parts.dropLast() {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            _ = close(fd); guard next >= 0 else { throw Failure.unsafeParent }
            var st = stat(); guard fstat(next, &st) == 0, st.st_uid == 0, st.st_gid == 0,
                (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR), (st.st_mode & 0o022) == 0 else { _ = close(next); throw Failure.unsafeParent }
            fd = next
        }
        return (fd, parts.last!)
    }
    private func hashAt(_ fd: Int32, _ leaf: String) throws -> String? {
        let file = leaf.withCString { openat(fd, $0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC) }
        if file < 0 { if errno == ENOENT { return nil }; throw Failure.io(errno) }
        defer { _ = close(file) }
        var st = stat(); guard fstat(file, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), st.st_uid == 0, st.st_gid == 0, st.st_nlink == 1,
            (st.st_mode & 0o6000) == 0 else { throw Failure.unsafeParent }
        guard st.st_size >= 0, st.st_size <= 64 * 1024 * 1024 else { throw Failure.invalidRelease }
        var data = Data(); var buf = [UInt8](repeating: 0, count: 8192)
        while true { let n = read(file, &buf, buf.count); if n < 0 && errno == EINTR { continue }; guard n >= 0 else { throw Failure.io(errno) }; if n == 0 { break }; data.append(contentsOf: buf.prefix(n)) }
        return SHA256Digest.hex(data)
    }
    private func writeExclusive(_ data: Data, name: String, parent: Int32, mode: mode_t) throws {
        let fd = name.withCString { openat(parent, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode) }
        guard fd >= 0 else { throw Failure.io(errno) }; defer { _ = close(fd) }
        try data.withUnsafeBytes { raw in guard let base = raw.baseAddress else { return }; var offset = 0; while offset < raw.count { let n = write(fd, base.advanced(by: offset), raw.count-offset); if n < 0 && errno == EINTR { continue }; guard n > 0 else { throw Failure.io(errno) }; offset += n } }
        guard fchown(fd, 0, 0) == 0, fchmod(fd, mode) == 0 else { throw Failure.io(errno) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              st.st_uid == 0, st.st_gid == 0, st.st_nlink == 1,
              (st.st_mode & 0o777) == mode else { throw Failure.unsafeParent }
        guard fsync(fd) == 0 else { throw Failure.io(errno) }
    }
    private func renameNoReplace(_ fd: Int32, _ from: String, _ to: String) throws {
        #if canImport(Darwin)
        let result = from.withCString { a in to.withCString { b in renameatx_np(fd, a, fd, b, UInt32(RENAME_EXCL)) } }
        #else
        let result = from.withCString { a in to.withCString { b in fk_renameat2(fd, a, fd, b, 1) } }
        #endif
        guard result == 0 else { throw Failure.io(errno) }
    }
    private func tempName(_ id: UUID, _ a: Artifact) -> String { ".fk-\(id.uuidString.lowercased())-\(a.rawValue).new" }
    private func backupName(_ id: UUID, _ a: Artifact) -> String { ".fk-\(id.uuidString.lowercased())-\(a.rawValue).bak" }
    private func readRecord(_ fd: Int32) throws -> Record? {
        let f = journal.withCString { openat(fd, $0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC) }
        if f < 0 { if errno == ENOENT { return nil }; throw Failure.io(errno) }; defer { _ = close(f) }
        var st = stat(); guard fstat(f, &st) == 0, st.st_uid == 0, st.st_gid == 0, st.st_nlink == 1, (st.st_mode & 0o777) == 0o600, st.st_size >= 0, st.st_size <= 65536 else { throw Failure.journalInvalid }
        guard lseek(f, 0, SEEK_SET) >= 0 else { throw Failure.io(errno) }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(f, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw Failure.io(errno) }
            if count == 0 { break }
            guard data.count + count <= 65536 else { throw Failure.journalInvalid }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == Int(st.st_size), let r = try? JSONDecoder().decode(Record.self, from: data) else { throw Failure.journalInvalid }
        return r
    }
    private func writeRecord(_ record: Record, rootFD: Int32) throws {
        let data = try JSONEncoder().encode(record); let tmp = ".fk-root-journal-\(record.id.uuidString.lowercased())-\(UUID().uuidString.lowercased()).tmp"
        try writeExclusive(data, name: tmp, parent: rootFD, mode: 0o600)
        #if canImport(Darwin)
        let result = tmp.withCString { a in journal.withCString { b in renameatx_np(rootFD, a, rootFD, b, 0) } }
        #else
        let result = tmp.withCString { a in journal.withCString { b in renameat(rootFD, a, rootFD, b) } }
        #endif
        guard result == 0, fsync(rootFD) == 0 else { throw Failure.io(errno) }
    }
    private func clearRecord(_ fd: Int32) throws { guard journal.withCString({ unlinkat(fd, $0, 0) }) == 0 || errno == ENOENT, fsync(fd) == 0 else { throw Failure.io(errno) } }
}
