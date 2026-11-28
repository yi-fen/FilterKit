import Foundation

/// Explicit, inactive path contract for recovery observation. Stage/previous roots are supplied
/// by the trusted installer integration; this type deliberately does not guess their locations.
struct HelperInstallerRecoveryLayout: Equatable {
    let activePaths: [HelperRootReleaseSet.Artifact: String]
    let stagedPaths: [HelperRootReleaseSet.Artifact: String]
    let previousPaths: [HelperRootReleaseSet.Artifact: String]?

    enum LayoutError: Error, Equatable { case incompleteSet, activePathMismatch, unsafePath, overlappingRoots }

    init(stagedRootRelativePath: String, previousRootRelativePath: String?) throws {
        let active: [HelperRootReleaseSet.Artifact: String] = [
            .executable: HelperRootReleaseSet.executablePath,
            .deploymentManifest: HelperRootReleaseSet.manifestPath,
            .launchDaemon: HelperRootReleaseSet.launchDaemonPath
        ]
        guard Set(active.keys) == Set(HelperRootReleaseSet.Artifact.allCases) else { throw LayoutError.incompleteSet }
        func validateRoot(_ value: String) -> Bool {
            HelperPolicy.isSafeRelativePath(value)
                && value.hasPrefix("Library/FilterKit/Helper/Recovery/")
                && !value.hasSuffix("/")
        }
        guard validateRoot(stagedRootRelativePath),
              previousRootRelativePath.map(validateRoot) ?? true else { throw LayoutError.unsafePath }
        if let previousRootRelativePath,
           stagedRootRelativePath == previousRootRelativePath
            || stagedRootRelativePath.hasPrefix(previousRootRelativePath + "/")
            || previousRootRelativePath.hasPrefix(stagedRootRelativePath + "/") {
            throw LayoutError.overlappingRoots
        }
        let names: [HelperRootReleaseSet.Artifact: String] = [
            .executable: "filterkit-helper",
            .deploymentManifest: "Deployment.json",
            .launchDaemon: "cn.yfen.filterkit.helper.plist"
        ]
        self.activePaths = active
        self.stagedPaths = Dictionary(uniqueKeysWithValues: names.map { ($0.key, stagedRootRelativePath + "/" + $0.value) })
        self.previousPaths = previousRootRelativePath.map { root in
            Dictionary(uniqueKeysWithValues: names.map { ($0.key, root + "/" + $0.value) })
        }
        let previousValues = Set(previousPaths?.values.map { $0 } ?? [])
        guard Set(stagedPaths.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
              previousPaths.map({ Set($0.keys) == Set(HelperRootReleaseSet.Artifact.allCases) }) ?? true,
              Set(active.values).isDisjoint(with: Set(stagedPaths.values)),
              Set(active.values).isDisjoint(with: previousValues),
              Set(stagedPaths.values).isDisjoint(with: previousValues) else {
            throw LayoutError.activePathMismatch
        }
    }
}

/// Facts from a separate, authenticated system-service observer. This is a data contract, not an
/// operating-system service-control implementation. The observer identity hash must be pinned by the trusted caller.
struct HelperInstallerServiceObservation: Equatable {
    enum State: Equatable { case running(pid: Int32, executableSHA256: String), stopped, unknown }
    let launchDaemonLabel: String
    let observerCodeIdentitySHA256: String
    let state: State

    func validates(expectedObserverCodeIdentitySHA256: String,
                   expectedExecutableSHA256: String) -> Bool {
        guard launchDaemonLabel == "cn.yfen.filterkit.helper",
              HelperPolicy.isValidHash(observerCodeIdentitySHA256),
              observerCodeIdentitySHA256 == expectedObserverCodeIdentitySHA256 else { return false }
        switch state {
        case .running(let pid, let executableHash):
            return pid > 0 && HelperPolicy.isValidHash(executableHash)
                && executableHash == expectedExecutableSHA256
        case .stopped: return true
        case .unknown: return false
        }
    }
}

/// Decision-only second-pass gate. It reloads the durable journal and re-observes all three
/// artifact sets; callers must invoke it again immediately before any separately authorized side
/// effect. No recovery executor, launchd mutation, or artifact mutation is exposed here.
struct HelperInstallerRecoveryPreflight {
    enum PreflightError: Error, Equatable {
        case journalUnavailable, filesystemObservationFailed, serviceObservationUntrusted
        case evidenceChanged, rollbackNotPermitted, recoveredStateNotVerified
    }
    enum Outcome: Equatable {
        case safeToContinueReviewOnly(journalSequence: UInt64, journalHeadHash: String)
        case keepServiceStopped(reason: String)
    }
    struct Evidence: Equatable {
        let journalSequence: UInt64
        let journalHeadHash: String
        let activeRecords: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.FileRecord]
        let stagedRecords: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.FileRecord]
        let previousRecords: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.FileRecord]
        let activePointer: HelperInstallerDescriptorFilesystemObserver.ReleasePointer?
        let activePointerMatchesObservedArtifacts: Bool
        let ownershipVerified: Bool
        let serviceLabel: String
        let serviceObserverCodeIdentitySHA256: String
        let serviceState: HelperInstallerServiceObservation.State
    }

    private let journalStore: HelperInstallerDurableJournalStore
    private let reconciliationBackend: HelperInstallerArtifactReconciliationBackend
    private let layout: HelperInstallerRecoveryLayout
    private let coordinator = HelperInstallerRecoveryCoordinator()

    init(journalStore: HelperInstallerDurableJournalStore,
         reconciliationBackend: HelperInstallerArtifactReconciliationBackend,
         layout: HelperInstallerRecoveryLayout) {
        self.journalStore = journalStore
        self.reconciliationBackend = reconciliationBackend
        self.layout = layout
    }

    func inspect(transactionID: UUID,
                 verifiedRelease: HelperRootReleaseSet.Verified,
                 previousExpectedHashes: [HelperRootReleaseSet.Artifact: String]?,
                 service: HelperInstallerServiceObservation,
                 expectedObserverCodeIdentitySHA256: String) throws -> (Outcome, Evidence?) {
        let journal: HelperInstallerTransactionJournal
        do { journal = try journalStore.load(transactionID: transactionID) }
        catch { throw PreflightError.journalUnavailable }
        let observation: HelperInstallerArtifactReconciliationBackend.Result
        do {
            observation = try reconciliationBackend.observe(activePaths: layout.activePaths,
                stagedPaths: layout.stagedPaths, previousPaths: layout.previousPaths)
        } catch { throw PreflightError.filesystemObservationFailed }
        guard service.validates(expectedObserverCodeIdentitySHA256: expectedObserverCodeIdentitySHA256,
                                expectedExecutableSHA256: verifiedRelease.hashes[.executable] ?? "") else {
            throw PreflightError.serviceObservationUntrusted
        }
        let assessment = coordinator.assess(journal: journal, verifiedRelease: verifiedRelease,
            observation: observation, previousExpectedHashes: previousExpectedHashes)
        let evidence = Evidence(journalSequence: journal.sequence, journalHeadHash: journal.previousEventHash,
            activeRecords: Self.records(observation.activeArtifacts),
            stagedRecords: Self.records(observation.stagedArtifacts),
            previousRecords: Self.records(observation.previousArtifacts),
            activePointer: observation.activeReleasePointer,
            activePointerMatchesObservedArtifacts: observation.activePointerMatchesObservedArtifacts,
            ownershipVerified: observation.ownershipVerified,
            serviceLabel: service.launchDaemonLabel,
            serviceObserverCodeIdentitySHA256: service.observerCodeIdentitySHA256,
            serviceState: service.state)
        switch assessment.decision {
        case .keepServiceStopped(let reason): return (.keepServiceStopped(reason: reason), evidence)
        case .evidenceConsistentButExecutionNotAuthorized:
            return (.safeToContinueReviewOnly(journalSequence: journal.sequence,
                                               journalHeadHash: journal.previousEventHash), evidence)
        }
    }

    /// Collects both evidence passes while holding the same persistent lock inode as atomic
    /// activation. The service observation closure must obtain a fresh authenticated report on
    /// every pass. The lock is held until both snapshots compare equal and the review-only result
    /// is returned; this still does not grant execution authorization.
    func inspectTwiceUnderSharedLock(jbroot: String, transactionID: UUID,
        verifiedRelease: HelperRootReleaseSet.Verified,
        previousExpectedHashes: [HelperRootReleaseSet.Artifact: String]?,
        expectedObserverCodeIdentitySHA256: String,
        serviceObservation: () throws -> HelperInstallerServiceObservation) throws -> (Outcome, Evidence) {
        try HelperInstallerSharedTransactionLock.withExclusiveLock(jbroot: jbroot) {
            let first = try inspect(transactionID: transactionID, verifiedRelease: verifiedRelease,
                previousExpectedHashes: previousExpectedHashes, service: serviceObservation(),
                expectedObserverCodeIdentitySHA256: expectedObserverCodeIdentitySHA256)
            guard let firstEvidence = first.1 else { throw PreflightError.evidenceChanged }
            let second = try inspect(transactionID: transactionID, verifiedRelease: verifiedRelease,
                previousExpectedHashes: previousExpectedHashes, service: serviceObservation(),
                expectedObserverCodeIdentitySHA256: expectedObserverCodeIdentitySHA256)
            guard let secondEvidence = second.1 else { throw PreflightError.evidenceChanged }
            try requireUnchangedEvidence(firstEvidence, secondEvidence)
            if case .keepServiceStopped(let reason) = first.0 {
                let outcome: Outcome = .keepServiceStopped(reason: reason)
                return (outcome, secondEvidence)
            }
            if case .keepServiceStopped(let reason) = second.0 {
                let outcome: Outcome = .keepServiceStopped(reason: reason)
                return (outcome, secondEvidence)
            }
            return (second.0, secondEvidence)
        }
    }

    /// Equality of two independently collected evidence snapshots is required. This does not
    /// authorize execution; it only rejects stale decisions when any fact has changed.
    func requireUnchangedEvidence(_ first: Evidence, _ second: Evidence) throws {
        guard first == second else { throw PreflightError.evidenceChanged }
    }

    /// Rollback is reviewable only for an upgrade/repin with a valid rollbackRequired journal,
    /// a complete previous release matching the trusted hash inventory, and a stopped service.
    func validateRollbackPrerequisites(journal: HelperInstallerTransactionJournal,
        previousArtifacts: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState],
        previousExpectedHashes: [HelperRootReleaseSet.Artifact: String],
        service: HelperInstallerServiceObservation,
        expectedObserverCodeIdentitySHA256: String) throws {
        guard (journal.action == .upgrade || journal.action == .repin),
              journal.state == .rollbackRequired, journal.pendingOperation == nil,
              (try? journal.validateChain()) != nil,
              Set(previousExpectedHashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
              previousExpectedHashes.values.allSatisfy(HelperPolicy.isValidHash),
              Self.hashes(previousArtifacts) == previousExpectedHashes,
              previousArtifacts.count == HelperRootReleaseSet.Artifact.allCases.count,
              previousArtifacts.values.allSatisfy({ if case .present = $0 { return true }; return false }),
              service.validates(expectedObserverCodeIdentitySHA256: expectedObserverCodeIdentitySHA256,
                                expectedExecutableSHA256: previousExpectedHashes[.executable] ?? ""),
              service.state == .stopped else { throw PreflightError.rollbackNotPermitted }
    }

    /// Post-recovery verification requires exact active hashes and a matching pointer. The caller
    /// supplies a fresh observation; the check never writes the pointer or starts the service.
    func validateRecoveredState(_ observation: HelperInstallerArtifactReconciliationBackend.Result,
        expectedHashes: [HelperRootReleaseSet.Artifact: String],
        expectedReleaseIdentifier: String, expectedGeneration: UInt64,
        service: HelperInstallerServiceObservation,
        expectedObserverCodeIdentitySHA256: String) throws {
        guard Self.hashes(observation.activeArtifacts) == expectedHashes,
              observation.activeArtifacts.count == HelperRootReleaseSet.Artifact.allCases.count,
              observation.activeArtifacts.values.allSatisfy({ if case .present = $0 { return true }; return false }),
              observation.ownershipVerified, observation.activePointerMatchesObservedArtifacts,
              observation.activeReleasePointer?.releaseIdentifier == expectedReleaseIdentifier,
              observation.activeReleasePointer?.generation == expectedGeneration,
              service.validates(expectedObserverCodeIdentitySHA256: expectedObserverCodeIdentitySHA256,
                                expectedExecutableSHA256: expectedHashes[.executable] ?? ""),
              service.state == .stopped else { throw PreflightError.recoveredStateNotVerified }
    }

    private static func records(_ states: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]) -> [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.FileRecord] {
        states.reduce(into: [:]) { output, item in
            if case .present(let record) = item.value { output[item.key] = record }
        }
    }

    private static func hashes(_ states: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]) -> [HelperRootReleaseSet.Artifact: String] {
        records(states).mapValues(\.sha256)
    }
}
