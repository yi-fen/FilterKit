import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Crash-consistent transaction for the deployed dylib, matching Filter.plist and Root-owned
/// FilterKit manifest. This primitive is intentionally not registered with HelperRuntime.
final class HelperThreeFileTransactionExecutor {
    enum Route: Equatable { case firstInstall, update }
    enum Phase: String, Codable, CaseIterable {
        case prepared, backingUp, installingDylib, installingPlist, installingManifest, committed
    }
    enum TransactionError: Error, Equatable {
        case notRoot, invalidInput, unsafeDirectory, unsafeFile, conflict, hashMismatch
        case io(Int32), journalInvalid, manualIntervention, injectedCrash(Phase)
    }
    struct Receipt: Equatable {
        let transactionID: UUID
        let pluginID: UUID
        let route: String
        let dylibSHA256: String
        let plistSHA256: String
        let manifestSHA256: String
        let completedAt: Date
    }
    private struct Journal: Codable {
        let schemaVersion: Int
        let transactionID: UUID
        let pluginID: UUID
        let dylibName: String
        let plistName: String
        let manifestName: String
        let newDylibHash: String
        let newPlistHash: String
        let newManifestHash: String
        let oldDylibHash: String?
        let oldPlistHash: String?
        let oldManifestHash: String?
        let deploymentBinding: HelperDeploymentTransactionBinding?
        var phase: Phase
        var tempDylib: String { ".fk-\(transactionID.uuidString.lowercased()).dylib.tmp" }
        var tempPlist: String { ".fk-\(transactionID.uuidString.lowercased()).plist.tmp" }
        var tempManifest: String { ".fk-\(transactionID.uuidString.lowercased()).manifest.tmp" }
        var backupDylib: String { ".fk-\(transactionID.uuidString.lowercased()).dylib.bak" }
        var backupPlist: String { ".fk-\(transactionID.uuidString.lowercased()).plist.bak" }
        var backupManifest: String { ".fk-\(transactionID.uuidString.lowercased()).manifest.bak" }
        func validate() throws {
            guard ((schemaVersion == 1 && deploymentBinding == nil) || (schemaVersion == 2 && deploymentBinding != nil)),
                  (deploymentBinding == nil || deploymentBinding!.validate()),
                  deploymentBinding.map({ $0.transactionID == transactionID && $0.pluginID == pluginID &&
                      $0.dylibSHA256.caseInsensitiveCompare(newDylibHash) == .orderedSame &&
                      $0.plistSHA256.caseInsensitiveCompare(newPlistHash) == .orderedSame &&
                      $0.manifestSHA256.caseInsensitiveCompare(newManifestHash) == .orderedSame }) ?? true,
                  HelperPolicy.isSafeLeafName(dylibName), dylibName.lowercased().hasSuffix(".dylib"),
                  HelperPolicy.isSafeLeafName(plistName), plistName.lowercased().hasSuffix(".plist"),
                  String(dylibName.dropLast(6)).lowercased() == String(plistName.dropLast(6)).lowercased(),
                  manifestName == String(dylibName.dropLast(6)) + ".fk.json",
                  [newDylibHash, newPlistHash, newManifestHash].allSatisfy(HelperPolicy.isValidHash),
                  [oldDylibHash, oldPlistHash, oldManifestHash].compactMap({ $0 }).allSatisfy(HelperPolicy.isValidHash),
                  (oldDylibHash == nil) == (oldPlistHash == nil),
                  (oldDylibHash == nil) == (oldManifestHash == nil) else { throw TransactionError.journalInvalid }
        }
    }

    private let directoryPath: String
    private static let processLock = NSLock()
    private let journalLeaf = ".filterkit-three-file.journal"
    init(directoryPath: String) throws {
        guard HelperPolicy.isAbsoluteCleanPath(directoryPath), directoryPath != "/" else { throw TransactionError.unsafeDirectory }
        self.directoryPath = directoryPath
    }

    func execute(pluginID: UUID, dylibName: String, plistName: String, dylib: Data, plist: Data,
                 manifest: Data, route: Route, expectedPrevious: (dylib: String, plist: String, manifest: String)? = nil,
                 simulateCrashAfter: Phase? = nil, transactionID: UUID = UUID(),
                 deploymentBinding: HelperDeploymentTransactionBinding? = nil) throws -> Receipt {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        guard HelperPolicy.isSafeLeafName(dylibName), dylibName.lowercased().hasSuffix(".dylib"),
              HelperPolicy.isSafeLeafName(plistName), plistName.lowercased().hasSuffix(".plist"),
              String(dylibName.dropLast(6)).lowercased() == String(plistName.dropLast(6)).lowercased(),
              (try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil)) != nil,
              dylib.count <= 64 * 1024 * 1024, plist.count <= 64 * 1024 * 1024,
              manifest.count <= 256 * 1024 else { throw TransactionError.invalidInput }
        guard let manifestObject = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              (manifestObject["schemaVersion"] as? NSNumber)?.intValue == 3,
              (manifestObject["pluginID"] as? String).flatMap(UUID.init(uuidString:)) == pluginID,
              manifestObject["dylibFileName"] as? String == dylibName,
              manifestObject["plistFileName"] as? String == plistName,
              (manifestObject["dylibSHA256"] as? String)?.caseInsensitiveCompare(SHA256Digest.hex(dylib)) == .orderedSame,
              (manifestObject["plistSHA256"] as? String)?.caseInsensitiveCompare(SHA256Digest.hex(plist)) == .orderedSame,
              (manifestObject["hardBoundBundleIdentifier"] as? String)?.isEmpty == false,
              manifestObject["softAssociatedBundleIdentifiers"] as? [String] != nil,
              (manifestObject["machOIdentitySHA256"] as? String).map(HelperPolicy.isValidHash) == true else {
            throw TransactionError.invalidInput
        }
        let manifestName = String(dylibName.dropLast(6)) + ".fk.json"
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        guard try loadJournal(fd) == nil else { throw TransactionError.manualIntervention }
        let oldDylib = try hashIfPresent(fd, dylibName)
        let oldPlist = try hashIfPresent(fd, plistName)
        let oldManifest = try hashIfPresent(fd, manifestName)
        if oldManifest != nil { try validateManifestMode(fd, manifestName) }
        switch route {
        case .firstInstall:
            guard oldDylib == nil, oldPlist == nil, oldManifest == nil, expectedPrevious == nil else { throw TransactionError.conflict }
        case .update:
            guard let expectedPrevious, oldDylib == expectedPrevious.dylib.lowercased(),
                  oldPlist == expectedPrevious.plist.lowercased(), oldManifest == expectedPrevious.manifest.lowercased(),
                  oldDylib != nil, oldPlist != nil, oldManifest != nil else { throw TransactionError.conflict }
        }
        let tx = transactionID
        if let binding = deploymentBinding {
            guard binding.transactionID == tx, binding.pluginID == pluginID,
                  binding.dylibSHA256.caseInsensitiveCompare(SHA256Digest.hex(dylib)) == .orderedSame,
                  binding.plistSHA256.caseInsensitiveCompare(SHA256Digest.hex(plist)) == .orderedSame,
                  binding.manifestSHA256.caseInsensitiveCompare(SHA256Digest.hex(manifest)) == .orderedSame else {
                throw TransactionError.invalidInput
            }
        }
        let reservedLeaves = [
            ".fk-\(tx.uuidString.lowercased()).dylib.tmp", ".fk-\(tx.uuidString.lowercased()).plist.tmp",
            ".fk-\(tx.uuidString.lowercased()).manifest.tmp", ".fk-\(tx.uuidString.lowercased()).dylib.bak",
            ".fk-\(tx.uuidString.lowercased()).plist.bak", ".fk-\(tx.uuidString.lowercased()).manifest.bak"
        ]
        for leaf in reservedLeaves { try requireAbsentLeaf(fd, leaf) }
        var journal = Journal(schemaVersion: deploymentBinding == nil ? 1 : 2, transactionID: tx, pluginID: pluginID,
            dylibName: dylibName, plistName: plistName, manifestName: manifestName,
            newDylibHash: SHA256Digest.hex(dylib), newPlistHash: SHA256Digest.hex(plist),
            newManifestHash: SHA256Digest.hex(manifest), oldDylibHash: oldDylib,
            oldPlistHash: oldPlist, oldManifestHash: oldManifest, deploymentBinding: deploymentBinding, phase: .prepared)
        try saveJournal(journal, fd: fd)
        do {
            try crashIfRequested(.prepared, simulateCrashAfter)
            try writeTemp(dylib, name: journal.tempDylib, fd: fd, mode: 0o644)
            try writeTemp(plist, name: journal.tempPlist, fd: fd, mode: 0o644)
            try writeTemp(manifest, name: journal.tempManifest, fd: fd, mode: 0o600)
            journal.phase = .backingUp; try saveJournal(journal, fd: fd); try crashIfRequested(.backingUp, simulateCrashAfter)
            if let oldDylib {
                guard try hashIfPresent(fd, dylibName) == oldDylib else { throw TransactionError.conflict }
                try requireAbsentLeaf(fd, journal.backupDylib); try move(dylibName, journal.backupDylib, fd: fd)
            }
            if let oldPlist {
                guard try hashIfPresent(fd, plistName) == oldPlist else { throw TransactionError.conflict }
                try requireAbsentLeaf(fd, journal.backupPlist); try move(plistName, journal.backupPlist, fd: fd)
            }
            if let oldManifest {
                guard try hashIfPresent(fd, manifestName) == oldManifest else { throw TransactionError.conflict }
                try requireAbsentLeaf(fd, journal.backupManifest); try move(manifestName, journal.backupManifest, fd: fd)
            }
            guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
            journal.phase = .installingDylib; try saveJournal(journal, fd: fd); try crashIfRequested(.installingDylib, simulateCrashAfter)
            try requireAbsentLeaf(fd, dylibName); try move(journal.tempDylib, dylibName, fd: fd)
            journal.phase = .installingPlist; try saveJournal(journal, fd: fd); try crashIfRequested(.installingPlist, simulateCrashAfter)
            try requireAbsentLeaf(fd, plistName); try move(journal.tempPlist, plistName, fd: fd)
            journal.phase = .installingManifest; try saveJournal(journal, fd: fd); try crashIfRequested(.installingManifest, simulateCrashAfter)
            try requireAbsentLeaf(fd, manifestName); try move(journal.tempManifest, manifestName, fd: fd)
            guard try hashIfPresent(fd, dylibName) == journal.newDylibHash,
                  try hashIfPresent(fd, plistName) == journal.newPlistHash,
                  try hashIfPresent(fd, manifestName) == journal.newManifestHash,
                  fsync(fd) == 0 else { throw TransactionError.hashMismatch }
            try validateManifestMode(fd, manifestName)
            journal.phase = .committed; try saveJournal(journal, fd: fd); try crashIfRequested(.committed, simulateCrashAfter)
            try cleanupCommitted(journal, fd: fd)
            let routeName: String
            switch route { case .firstInstall: routeName = "firstInstall"; case .update: routeName = "update" }
            return Receipt(transactionID: tx, pluginID: pluginID, route: routeName,
                dylibSHA256: journal.newDylibHash, plistSHA256: journal.newPlistHash,
                manifestSHA256: journal.newManifestHash, completedAt: Date())
        } catch let error as TransactionError {
            if case .injectedCrash = error { throw error }
            let reconciled = try reconcileLocked(fd: fd)
            if journal.phase == .committed && reconciled {
                let routeName = route == .firstInstall ? "firstInstall" : "update"
                return Receipt(transactionID: tx, pluginID: pluginID, route: routeName,
                    dylibSHA256: journal.newDylibHash, plistSHA256: journal.newPlistHash,
                    manifestSHA256: journal.newManifestHash, completedAt: Date())
            }
            throw error
        } catch {
            let reconciled = try reconcileLocked(fd: fd)
            if journal.phase == .committed && reconciled {
                let routeName = route == .firstInstall ? "firstInstall" : "update"
                return Receipt(transactionID: tx, pluginID: pluginID, route: routeName,
                    dylibSHA256: journal.newDylibHash, plistSHA256: journal.newPlistHash,
                    manifestSHA256: journal.newManifestHash, completedAt: Date())
            }
            throw TransactionError.io(errno)
        }
    }

    struct PendingTransactionEvidence: Equatable {
        let transactionID: UUID
        let pluginID: UUID
        let phase: Phase
        let deploymentBinding: HelperDeploymentTransactionBinding?
        let expectedHashes: (String, String, String)
        let previousHashes: (String?, String?, String?)
        let actualHashes: (String?, String?, String?)
        let backupHashes: (String?, String?, String?)
        let temporaryHashes: (String?, String?, String?)
        func validateAuxiliaryArtifacts() -> Bool {
            let backups = [backupHashes.0, backupHashes.1, backupHashes.2]
            let previous = [previousHashes.0, previousHashes.1, previousHashes.2]
            let temporaries = [temporaryHashes.0, temporaryHashes.1, temporaryHashes.2]
            let expected = [expectedHashes.0, expectedHashes.1, expectedHashes.2]
            let destinations = [actualHashes.0, actualHashes.1, actualHashes.2]
            let backupsValid = zip(backups, previous).allSatisfy { actual, old in
                guard let actual else { return true }
                return old.map { actual.caseInsensitiveCompare($0) == .orderedSame } == true
            }
            let temporariesValid = zip(temporaries, expected).allSatisfy { actual, new in
                guard let actual else { return true }
                return actual.caseInsensitiveCompare(new) == .orderedSame
            }
            let destinationsValid = zip(destinations, zip(previous, zip(expected, backups))).allSatisfy { current, state in
                let (old, newAndBackup) = state
                let (new, backup) = newAndBackup
                if let current {
                    return current.caseInsensitiveCompare(new) == .orderedSame ||
                        old.map { current.caseInsensitiveCompare($0) == .orderedSame } == true
                }
                if let old { return backup?.caseInsensitiveCompare(old) == .orderedSame }
                return true
            }
            return backupsValid && temporariesValid && destinationsValid
        }
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.transactionID == rhs.transactionID && lhs.pluginID == rhs.pluginID && lhs.phase == rhs.phase &&
            lhs.deploymentBinding == rhs.deploymentBinding && lhs.expectedHashes.0 == rhs.expectedHashes.0 &&
            lhs.expectedHashes.1 == rhs.expectedHashes.1 && lhs.expectedHashes.2 == rhs.expectedHashes.2 &&
            lhs.previousHashes.0 == rhs.previousHashes.0 && lhs.previousHashes.1 == rhs.previousHashes.1 &&
            lhs.previousHashes.2 == rhs.previousHashes.2 && lhs.actualHashes.0 == rhs.actualHashes.0 &&
            lhs.actualHashes.1 == rhs.actualHashes.1 && lhs.actualHashes.2 == rhs.actualHashes.2 &&
            lhs.backupHashes.0 == rhs.backupHashes.0 && lhs.backupHashes.1 == rhs.backupHashes.1 &&
            lhs.backupHashes.2 == rhs.backupHashes.2 && lhs.temporaryHashes.0 == rhs.temporaryHashes.0 &&
            lhs.temporaryHashes.1 == rhs.temporaryHashes.1 && lhs.temporaryHashes.2 == rhs.temporaryHashes.2
        }
    }

    func inspectPendingEvidence() throws -> PendingTransactionEvidence? {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        guard let journal = try loadJournal(fd) else { return nil }
        try journal.validate()
        return PendingTransactionEvidence(transactionID: journal.transactionID, pluginID: journal.pluginID,
            phase: journal.phase, deploymentBinding: journal.deploymentBinding,
            expectedHashes: (journal.newDylibHash, journal.newPlistHash, journal.newManifestHash),
            previousHashes: (journal.oldDylibHash, journal.oldPlistHash, journal.oldManifestHash),
            actualHashes: (try hashIfPresent(fd, journal.dylibName), try hashIfPresent(fd, journal.plistName),
                           try hashIfPresent(fd, journal.manifestName)),
            backupHashes: (try hashIfPresent(fd, journal.backupDylib), try hashIfPresent(fd, journal.backupPlist),
                           try hashIfPresent(fd, journal.backupManifest)),
            temporaryHashes: (try hashIfPresent(fd, journal.tempDylib), try hashIfPresent(fd, journal.tempPlist),
                              try hashIfPresent(fd, journal.tempManifest)))
    }

    /// Read-only startup probe. A pending journal is reported to the Runtime, which exposes status-only IPC and blocks
    /// deployment requests; this method never mutates target files.
    func inspectPendingJournal() throws -> Bool {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        return try loadJournal(fd) != nil
    }

    enum RecoveryDisposition: Equatable { case committed, rolledBack }

    /// Explicit, transaction-ID-bound reconciliation. The caller must first obtain a
    /// separately authorized recovery capability and verify the Batch Ledger binding.
    /// The expected ID prevents a stale maintenance request from reconciling another journal.
    func reconcile(expectedTransactionID: UUID, preserveJournal: Bool = false) throws -> RecoveryDisposition {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        guard let journal = try loadJournal(fd), journal.transactionID == expectedTransactionID else {
            throw TransactionError.journalInvalid
        }
        let wasCommitted = journal.phase == .committed
        _ = try reconcileLocked(fd: fd, clearJournalAfter: !preserveJournal)
        if preserveJournal {
            guard let retained = try loadJournal(fd), retained.transactionID == expectedTransactionID else {
                throw TransactionError.manualIntervention
            }
        } else {
            guard try loadJournal(fd) == nil else { throw TransactionError.manualIntervention }
        }
        return wasCommitted ? .committed : .rolledBack
    }

    /// Clears the recovery marker only after the durable Batch Ledger has been finalized.
    /// The on-disk destination hashes and absence of all transaction auxiliaries are rechecked
    /// immediately before unlinking the journal. This closes the crash window between file
    /// reconciliation and ledger finalization: if the process exits, the journal remains and
    /// the same transaction can be safely reconciled again.
    func clearReconciledJournal(expectedTransactionID: UUID) throws {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        guard let journal = try loadJournal(fd), journal.transactionID == expectedTransactionID else {
            throw TransactionError.journalInvalid
        }
        let committed = journal.phase == .committed
        let expectedD = committed ? journal.newDylibHash : journal.oldDylibHash
        let expectedP = committed ? journal.newPlistHash : journal.oldPlistHash
        let expectedM = committed ? journal.newManifestHash : journal.oldManifestHash
        guard try hashIfPresent(fd, journal.dylibName) == expectedD,
              try hashIfPresent(fd, journal.plistName) == expectedP,
              try hashIfPresent(fd, journal.manifestName) == expectedM,
              try hashIfPresent(fd, journal.backupDylib) == nil,
              try hashIfPresent(fd, journal.backupPlist) == nil,
              try hashIfPresent(fd, journal.backupManifest) == nil,
              try hashIfPresent(fd, journal.tempDylib) == nil,
              try hashIfPresent(fd, journal.tempPlist) == nil,
              try hashIfPresent(fd, journal.tempManifest) == nil else {
            throw TransactionError.manualIntervention
        }
        try clearJournal(fd)
        guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
    }

    /// Legacy root-only primitive retained for host transaction smoke tests. Production
    /// maintenance must use the transaction-ID-bound overload above.
    func reconcile() throws -> Bool {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        return try reconcileLocked(fd: fd)
    }

    private func reconcileLocked(fd: Int32, clearJournalAfter: Bool = true) throws -> Bool {
        guard let j = try loadJournal(fd) else { return false }
        try j.validate()
        let committed = j.phase == .committed
        let currentD = try hashIfPresent(fd, j.dylibName), currentP = try hashIfPresent(fd, j.plistName), currentM = try hashIfPresent(fd, j.manifestName)
        let backupD = try hashIfPresent(fd, j.backupDylib), backupP = try hashIfPresent(fd, j.backupPlist), backupM = try hashIfPresent(fd, j.backupManifest)
        let tempD = try hashIfPresent(fd, j.tempDylib), tempP = try hashIfPresent(fd, j.tempPlist), tempM = try hashIfPresent(fd, j.tempManifest)
        for (actual, expected) in [(backupD, j.oldDylibHash), (backupP, j.oldPlistHash), (backupM, j.oldManifestHash)] where actual != nil && actual != expected {
            throw TransactionError.manualIntervention
        }
        if currentM != nil { try validateManifestMode(fd, j.manifestName) }
        if backupM != nil { try validateManifestMode(fd, j.backupManifest) }
        if tempM != nil { try validateManifestMode(fd, j.tempManifest) }
        for (actual, expected) in [(tempD, j.newDylibHash), (tempP, j.newPlistHash), (tempM, j.newManifestHash)] where actual != nil && actual != expected {
            throw TransactionError.manualIntervention
        }
        if committed {
            guard currentD == j.newDylibHash, currentP == j.newPlistHash, currentM == j.newManifestHash else { throw TransactionError.manualIntervention }
            try removeIfHash(fd, j.backupDylib, j.oldDylibHash)
            try removeIfHash(fd, j.backupPlist, j.oldPlistHash)
            try removeIfHash(fd, j.backupManifest, j.oldManifestHash)
        } else {
            // Validate each destination as either old, new, or absent for first install.
            for (actual, old, new) in [(currentD, j.oldDylibHash, j.newDylibHash), (currentP, j.oldPlistHash, j.newPlistHash), (currentM, j.oldManifestHash, j.newManifestHash)] {
                if let actual, actual != old && actual != new { throw TransactionError.manualIntervention }
            }
            try rollbackOne(fd, destination: j.dylibName, backup: j.backupDylib, oldHash: j.oldDylibHash, newHash: j.newDylibHash)
            try rollbackOne(fd, destination: j.plistName, backup: j.backupPlist, oldHash: j.oldPlistHash, newHash: j.newPlistHash)
            try rollbackOne(fd, destination: j.manifestName, backup: j.backupManifest, oldHash: j.oldManifestHash, newHash: j.newManifestHash)
        }
        try removeIfHash(fd, j.tempDylib, j.newDylibHash)
        try removeIfHash(fd, j.tempPlist, j.newPlistHash)
        try removeIfHash(fd, j.tempManifest, j.newManifestHash)
        guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
        if clearJournalAfter { try clearJournal(fd) }
        return true
    }

    private func rollbackOne(_ fd: Int32, destination: String, backup: String, oldHash: String?, newHash: String) throws {
        let current = try hashIfPresent(fd, destination), oldBackup = try hashIfPresent(fd, backup)
        if let current, current == newHash { try unlinkLeaf(fd, destination) }
        else if let current, current != oldHash { throw TransactionError.manualIntervention }
        if let oldHash {
            if oldBackup == oldHash {
                if try hashIfPresent(fd, destination) != nil { throw TransactionError.manualIntervention }
                try move(backup, destination, fd: fd)
            } else if try hashIfPresent(fd, destination) != oldHash { throw TransactionError.manualIntervention }
        } else if oldBackup != nil { throw TransactionError.manualIntervention }
    }

    private func cleanupCommitted(_ j: Journal, fd: Int32) throws {
        try removeIfHash(fd, j.backupDylib, j.oldDylibHash)
        try removeIfHash(fd, j.backupPlist, j.oldPlistHash)
        try removeIfHash(fd, j.backupManifest, j.oldManifestHash)
        try removeIfHash(fd, j.tempDylib, j.newDylibHash)
        try removeIfHash(fd, j.tempPlist, j.newPlistHash)
        try removeIfHash(fd, j.tempManifest, j.newManifestHash)
        guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
        try clearJournal(fd)
    }

    private func crashIfRequested(_ phase: Phase, _ requested: Phase?) throws {
        if requested == phase { throw TransactionError.injectedCrash(phase) }
    }
    private func hashIfPresent(_ fd: Int32, _ leaf: String) throws -> String? {
        var pathInfo = stat()
        let rc = leaf.withCString { fstatat(fd, $0, &pathInfo, AT_SYMLINK_NOFOLLOW) }
        if rc != 0 { if errno == ENOENT { return nil }; throw TransactionError.unsafeFile }
        guard (pathInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              pathInfo.st_uid == 0, pathInfo.st_gid == 0, pathInfo.st_nlink == 1,
              (pathInfo.st_mode & 0o6022) == 0,
              pathInfo.st_size >= 0, pathInfo.st_size <= 64 * 1024 * 1024 else {
            throw TransactionError.unsafeFile
        }
        let f = leaf.withCString { openat(fd, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard f >= 0 else { throw TransactionError.unsafeFile }
        defer { _ = close(f) }
        var openedInfo = stat()
        guard fstat(f, &openedInfo) == 0,
              openedInfo.st_dev == pathInfo.st_dev, openedInfo.st_ino == pathInfo.st_ino,
              openedInfo.st_uid == 0, openedInfo.st_gid == 0, openedInfo.st_nlink == 1,
              (openedInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              (openedInfo.st_mode & 0o6022) == 0,
              openedInfo.st_size == pathInfo.st_size else { throw TransactionError.unsafeFile }
        var data = Data(); data.reserveCapacity(Int(openedInfo.st_size))
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(f, &buf, buf.count)
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw TransactionError.io(errno) }
            if n == 0 { break }
            data.append(contentsOf: buf.prefix(n))
            guard data.count <= 64 * 1024 * 1024 else { throw TransactionError.unsafeFile }
        }
        var finalInfo = stat()
        guard fstat(f, &finalInfo) == 0,
              finalInfo.st_dev == openedInfo.st_dev, finalInfo.st_ino == openedInfo.st_ino,
              finalInfo.st_uid == openedInfo.st_uid, finalInfo.st_gid == openedInfo.st_gid,
              finalInfo.st_nlink == 1, finalInfo.st_mode == openedInfo.st_mode,
              finalInfo.st_size == openedInfo.st_size,
              data.count == finalInfo.st_size else { throw TransactionError.unsafeFile }
        return SHA256Digest.hex(data)
    }
    private func validateManifestMode(_ fd: Int32, _ leaf: String) throws {
        var st = stat()
        guard leaf.withCString({ fstatat(fd, $0, &st, AT_SYMLINK_NOFOLLOW) }) == 0,
              (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), st.st_uid == 0, st.st_gid == 0,
              (st.st_mode & 0o777) == 0o600, (st.st_mode & 0o6000) == 0,
              st.st_nlink == 1 else { throw TransactionError.unsafeFile }
        let fileFD = leaf.withCString { openat(fd, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fileFD >= 0 else { throw TransactionError.unsafeFile }
        defer { _ = close(fileFD) }
        var opened = stat()
        guard fstat(fileFD, &opened) == 0, opened.st_dev == st.st_dev, opened.st_ino == st.st_ino,
              opened.st_uid == 0, opened.st_gid == 0,
              (opened.st_mode & 0o777) == 0o600 else { throw TransactionError.unsafeFile }
    }
    private func writeTemp(_ data: Data, name: String, fd: Int32, mode: mode_t) throws {
        let f = name.withCString { openat(fd, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard f >= 0 else { throw TransactionError.io(errno) }
        var complete = false
        defer {
            _ = close(f)
            if !complete { _ = name.withCString { unlinkat(fd, $0, 0) } }
        }
        try data.withUnsafeBytes { raw in guard let p = raw.baseAddress else { return }; var off = 0; while off < raw.count { let n = write(f, p.advanced(by: off), raw.count - off); if n < 0 && errno == EINTR { continue }; guard n > 0 else { throw TransactionError.io(errno) }; off += n } }
        guard fchown(f, 0, 0) == 0, fchmod(f, mode) == 0, fsync(f) == 0 else { throw TransactionError.io(errno) }
        complete = true
    }
    private func requireAbsentLeaf(_ fd: Int32, _ leaf: String) throws {
        var st = stat()
        let rc = leaf.withCString { fstatat(fd, $0, &st, AT_SYMLINK_NOFOLLOW) }
        if rc == 0 { throw TransactionError.conflict }
        guard errno == ENOENT else { throw TransactionError.unsafeFile }
    }
    private func move(_ from: String, _ to: String, fd: Int32) throws {
        let rc = from.withCString { a in to.withCString { b in renameat(fd, a, fd, b) } }
        guard rc == 0 else { throw TransactionError.io(errno) }
    }
    private func unlinkLeaf(_ fd: Int32, _ leaf: String) throws { let rc = leaf.withCString { unlinkat(fd, $0, 0) }; guard rc == 0 else { throw TransactionError.io(errno) } }
    private func removeIfHash(_ fd: Int32, _ leaf: String, _ expected: String?) throws {
        guard let expected else { return }; guard let actual = try hashIfPresent(fd, leaf) else { return }; guard actual == expected else { throw TransactionError.manualIntervention }; try unlinkLeaf(fd, leaf)
    }
    private func openDirectory() throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC); guard fd >= 0 else { throw TransactionError.io(errno) }
        for c in directoryPath.split(separator: "/").map(String.init) { let n = c.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }; guard n >= 0 else { let e = errno; _ = close(fd); throw TransactionError.io(e) }; _ = close(fd); fd = n }
        return fd
    }
    private func validateDirectory(_ fd: Int32) throws { var st = stat(); guard fstat(fd, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR), st.st_uid == 0, st.st_gid == 0, (st.st_mode & 0o022) == 0 else { throw TransactionError.unsafeDirectory } }
    private func loadJournal(_ fd: Int32) throws -> Journal? {
        let f = journalLeaf.withCString { openat(fd, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }; if f < 0 { if errno == ENOENT { return nil }; throw TransactionError.io(errno) }; defer { _ = close(f) }
        var st = stat(); guard fstat(f, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), st.st_uid == 0, st.st_gid == 0, (st.st_mode & 0o777) == 0o600, st.st_size >= 0, st.st_size <= 32 * 1024 else { throw TransactionError.journalInvalid }
        let d = try readAll(f, limit: 32 * 1024); guard let j = try? JSONDecoder().decode(Journal.self, from: d) else { throw TransactionError.journalInvalid }; try j.validate(); return j
    }
    private func saveJournal(_ j: Journal, fd: Int32) throws {
        let data = try JSONEncoder().encode(j); let tmp = ".fk-journal-\(UUID().uuidString.lowercased()).tmp"
        let f = tmp.withCString { openat(fd, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }; guard f >= 0 else { throw TransactionError.io(errno) }; defer { _ = close(f); _ = tmp.withCString { unlinkat(fd, $0, 0) } }
        try writeAll(data, f); guard fchown(f, 0, 0) == 0, fchmod(f, 0o600) == 0, fsync(f) == 0 else { throw TransactionError.io(errno) }
        let rc = tmp.withCString { a in journalLeaf.withCString { b in renameat(fd, a, fd, b) } }; guard rc == 0, fsync(fd) == 0 else { throw TransactionError.io(errno) }
    }
    private func clearJournal(_ fd: Int32) throws { var st = stat(); let rc = journalLeaf.withCString { fstatat(fd, $0, &st, AT_SYMLINK_NOFOLLOW) }; if rc == 0 { guard (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), st.st_uid == 0, st.st_gid == 0, st.st_nlink == 1, (st.st_mode & 0o777) == 0o600 else { throw TransactionError.journalInvalid }; let u = journalLeaf.withCString { unlinkat(fd, $0, 0) }; guard u == 0 else { throw TransactionError.io(errno) } } else if errno != ENOENT { throw TransactionError.io(errno) }; guard fsync(fd) == 0 else { throw TransactionError.io(errno) } }
    private func readAll(_ fd: Int32, limit: Int) throws -> Data { var d = Data(); var b = [UInt8](repeating: 0, count: 4096); while true { let n = read(fd, &b, b.count); if n < 0 && errno == EINTR { continue }; guard n >= 0 else { throw TransactionError.io(errno) }; if n == 0 { break }; d.append(contentsOf: b.prefix(n)); guard d.count <= limit else { throw TransactionError.journalInvalid } }; return d }
    private func writeAll(_ d: Data, _ fd: Int32) throws { try d.withUnsafeBytes { raw in guard let p = raw.baseAddress else { return }; var o = 0; while o < raw.count { let n = write(fd, p.advanced(by: o), raw.count-o); if n < 0 && errno == EINTR { continue }; guard n > 0 else { throw TransactionError.io(errno) }; o += n } } }
}
