import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Root-owned, transaction-scoped preservation of the currently active Helper release.
/// The caller must supply a release inventory obtained from the trusted installed baseline;
/// this store independently verifies every active byte against that inventory before copying.
/// It never activates, launches, deletes, or overwrites an existing backup.
struct HelperInstallerPreviousReleaseStore {
    enum StoreError: Error, Equatable {
        case notRoot, invalidRoot, openFailed(Int32), unsafeDirectory, unsafeArtifact
        case invalidPreviousInventory, activeReleaseMismatch, journalIntentRequired
        case backupAlreadyExists, missingBackup, partialBackup, mismatchedBackup
        case writeFailed(Int32), syncFailed(Int32), renameFailed(Int32)
        case injectedCrash(HelperRootReleaseSet.Artifact), journalCommitIndeterminate
    }
    enum State: Equatable { case missing, complete, partial, mismatched }
    enum FaultPoint: Equatable { case afterExecutable, afterManifest, afterLaunchDaemon }

    struct Receipt: Equatable {
        let transactionID: UUID
        let previousReleaseIdentifier: String
        let previousGeneration: UInt64
        let relativeDirectory: String
        let hashes: [HelperRootReleaseSet.Artifact: String]
        let byteCounts: [HelperRootReleaseSet.Artifact: Int]
    }
    struct Inspection: Equatable {
        let state: State
        let transactionID: UUID
        let observedHashes: [HelperRootReleaseSet.Artifact: String]
        let missingArtifacts: Set<HelperRootReleaseSet.Artifact>
        let mismatchedArtifacts: Set<HelperRootReleaseSet.Artifact>
        let unexpectedEntries: Set<String>
    }

    static let relativeRootPath = "Library/FilterKit/Helper/Recovery/PreviousReleases"
    private let jbRootPath: String

    init(jbRootPath: String) throws {
        guard HelperPolicy.isAbsoluteCleanPath(jbRootPath), jbRootPath != "/" else { throw StoreError.invalidRoot }
        self.jbRootPath = jbRootPath
    }

    /// `previousRelease` must come from the trusted installed-release baseline, not from
    /// hashes computed from the files being backed up. The journal must already contain the
    /// durable `.intentPreservePreviousRelease` record.
    func preserve(prepared: HelperPreparedRootInstall,
                  previousRelease: HelperRootReleaseSet.Verified,
                  previousHelperCDHash: String,
                  previousTeamIdentifier: String,
                  journal: HelperInstallerTransactionJournal,
                  journalStore: HelperInstallerDurableJournalStore,
                  faultAt: FaultPoint? = nil) throws -> Receipt {
        #if canImport(Darwin)
        return try HelperInstallerSharedTransactionLock.withExclusiveLock(jbroot: jbRootPath) {
            try preserveLocked(prepared: prepared, previousRelease: previousRelease,
                previousHelperCDHash: previousHelperCDHash, previousTeamIdentifier: previousTeamIdentifier,
                journal: journal, journalStore: journalStore, faultAt: faultAt)
        }
        #else
        return try preserveLocked(prepared: prepared, previousRelease: previousRelease,
            previousHelperCDHash: previousHelperCDHash, previousTeamIdentifier: previousTeamIdentifier,
            journal: journal, journalStore: journalStore, faultAt: faultAt)
        #endif
    }

    private func preserveLocked(prepared: HelperPreparedRootInstall,
        previousRelease: HelperRootReleaseSet.Verified, previousHelperCDHash: String,
        previousTeamIdentifier: String, journal: HelperInstallerTransactionJournal,
        journalStore: HelperInstallerDurableJournalStore, faultAt: FaultPoint?) throws -> Receipt {
        guard geteuid() == 0 else { throw StoreError.notRoot }
        guard prepared.plan.jbRootPath == jbRootPath,
              prepared.plan.action == .upgrade || prepared.plan.action == .repin,
              previousRelease.releaseIdentifier != prepared.release.releaseIdentifier,
              previousRelease.generation > 0,
              Set(previousRelease.hashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
              previousRelease.hashes.values.allSatisfy(HelperPolicy.isValidHash),
              previousRelease.byteCounts.count == HelperRootReleaseSet.Artifact.allCases.count,
              HelperPolicy.isValidCDHash(previousHelperCDHash), !previousTeamIdentifier.isEmpty else {
            throw StoreError.invalidPreviousInventory
        }
        guard journal.transactionID == prepared.initialJournal.transactionID,
              journal.action == prepared.plan.action,
              journal.releaseIdentifier == prepared.release.releaseIdentifier,
              journal.generation == prepared.release.generation else { throw StoreError.journalIntentRequired }

        let rootFD = try openVerifiedJBRoot()
        defer { _ = close(rootFD) }
        let backupRootFD = try openVerifiedBackupRoot(rootFD: rootFD)
        defer { _ = close(backupRootFD) }
        let transactionName = journal.transactionID.uuidString.lowercased()
        var existing = stat()
        let existingResult = transactionName.withCString { fstatat(backupRootFD, $0, &existing, AT_SYMLINK_NOFOLLOW) }
        if existingResult == 0 { throw StoreError.backupAlreadyExists }
        guard errno == ENOENT else { throw StoreError.openFailed(errno) }
        let persisted: HelperInstallerTransactionJournal
        do { persisted = try journalStore.load(transactionID: journal.transactionID) }
        catch { throw StoreError.journalIntentRequired }
        guard journal.state == .artifactsVerified,
              journal.pendingOperation == .preservePreviousRelease,
              persisted == journal else { throw StoreError.journalIntentRequired }

        var sourceBytes: [HelperRootReleaseSet.Artifact: Data] = [:]
        let activePaths: [HelperRootReleaseSet.Artifact: String] = [
            .executable: HelperRootReleaseSet.executablePath,
            .deploymentManifest: HelperRootReleaseSet.manifestPath,
            .launchDaemon: HelperRootReleaseSet.launchDaemonPath
        ]
        for artifact in HelperRootReleaseSet.Artifact.allCases {
            guard let path = activePaths[artifact], let expectedHash = previousRelease.hashes[artifact] else {
                throw StoreError.invalidPreviousInventory
            }
            let bytes = try readActiveArtifact(path, artifact: artifact, rootFD: rootFD)
            guard SHA256Digest.hex(bytes) == expectedHash,
                  previousRelease.byteCounts[artifact] == bytes.count else { throw StoreError.activeReleaseMismatch }
            sourceBytes[artifact] = bytes
        }
        guard let executable = sourceBytes[.executable] else { throw StoreError.activeReleaseMismatch }
        try verifyMachOIdentity(executable, expectedCDHash: previousHelperCDHash,
                                expectedTeamIdentifier: previousTeamIdentifier)
        try verifyPreviousMetadata(manifest: sourceBytes[.deploymentManifest] ?? Data(),
                                    launchDaemon: sourceBytes[.launchDaemon] ?? Data(), jbRootPath: jbRootPath)

        guard transactionName.withCString({ mkdirat(backupRootFD, $0, 0o700) }) == 0 else {
            if errno == EEXIST { throw StoreError.backupAlreadyExists }
            throw StoreError.openFailed(errno)
        }
        guard fsync(backupRootFD) == 0 else { throw StoreError.syncFailed(errno) }
        let backupFD = transactionName.withCString {
            openat(backupRootFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard backupFD >= 0 else { throw StoreError.openFailed(errno) }
        defer { _ = close(backupFD) }
        do {
            try validatePrivateDirectory(backupFD)
            for artifact in HelperRootReleaseSet.Artifact.allCases {
                guard let bytes = sourceBytes[artifact], let hash = previousRelease.hashes[artifact] else {
                    throw StoreError.invalidPreviousInventory
                }
                try writeArtifact(bytes, artifact: artifact, expectedHash: hash, directoryFD: backupFD)
                guard try hashArtifact(artifact, directoryFD: backupFD) == hash else { throw StoreError.unsafeArtifact }
                if (artifact == .executable && faultAt == .afterExecutable) ||
                   (artifact == .deploymentManifest && faultAt == .afterManifest) ||
                   (artifact == .launchDaemon && faultAt == .afterLaunchDaemon) {
                    throw StoreError.injectedCrash(artifact)
                }
            }
            guard try entryNames(directoryFD: backupFD) == expectedEntryNames,
                  fsync(backupFD) == 0, fsync(backupRootFD) == 0 else { throw StoreError.syncFailed(errno) }
        } catch let StoreError.injectedCrash(artifact) {
            throw StoreError.injectedCrash(artifact)
        } catch {
            removeKnownArtifacts(directoryFD: backupFD)
            _ = transactionName.withCString { unlinkat(backupRootFD, $0, AT_REMOVEDIR) }
            _ = fsync(backupRootFD)
            throw error
        }

        var completed = journal
        do {
            try completed.apply(.preservePreviousRelease)
            try journalStore.save(completed)
        } catch {
            // The complete backup is retained for read-only reconciliation. Never delete it
            // or pretend the Journal completion was durable.
            throw StoreError.journalCommitIndeterminate
        }
        return Receipt(transactionID: journal.transactionID,
            previousReleaseIdentifier: previousRelease.releaseIdentifier,
            previousGeneration: previousRelease.generation,
            relativeDirectory: Self.relativeRootPath + "/" + transactionName,
            hashes: previousRelease.hashes, byteCounts: previousRelease.byteCounts)
    }

    /// Reads the preserved previous-release bytes while the caller holds the activation lock.
    /// It deliberately does not acquire HelperInstallerSharedTransactionLock a second time.
    func loadVerifiedArtifactsForActivation(transactionID: UUID,
                                            expectedHashes: [HelperRootReleaseSet.Artifact: String]) throws -> [HelperRootReleaseSet.Artifact: Data] {
        guard Set(expectedHashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
              expectedHashes.values.allSatisfy(HelperPolicy.isValidHash) else { throw StoreError.invalidPreviousInventory }
        let rootFD = try openVerifiedJBRoot(); defer { _ = close(rootFD) }
        let backupRootFD = try openVerifiedBackupRoot(rootFD: rootFD); defer { _ = close(backupRootFD) }
        let name = transactionID.uuidString.lowercased()
        let directoryFD = name.withCString { openat(backupRootFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard directoryFD >= 0 else { throw StoreError.missingBackup }
        defer { _ = close(directoryFD) }
        try validatePrivateDirectory(directoryFD)
        guard try entryNames(directoryFD: directoryFD) == expectedEntryNames else { throw StoreError.unsafeArtifact }
        var result: [HelperRootReleaseSet.Artifact: Data] = [:]
        for artifact in HelperRootReleaseSet.Artifact.allCases {
            let bytes = try readBackupArtifact(artifact, directoryFD: directoryFD)
            guard let expected = expectedHashes[artifact], SHA256Digest.hex(bytes) == expected else {
                throw StoreError.mismatchedBackup
            }
            result[artifact] = bytes
        }
        return result
    }

    func inspect(transactionID: UUID, expected: HelperRootReleaseSet.Verified) throws -> Inspection {
        #if canImport(Darwin)
        return try HelperInstallerSharedTransactionLock.withExclusiveLock(jbroot: jbRootPath) {
            try inspectLocked(transactionID: transactionID, expected: expected)
        }
        #else
        return try inspectLocked(transactionID: transactionID, expected: expected)
        #endif
    }

    private func inspectLocked(transactionID: UUID, expected: HelperRootReleaseSet.Verified) throws -> Inspection {
        let rootFD = try openVerifiedJBRoot(); defer { _ = close(rootFD) }
        let backupRootFD = try openVerifiedBackupRoot(rootFD: rootFD); defer { _ = close(backupRootFD) }
        let name = transactionID.uuidString.lowercased()
        let directoryFD = name.withCString { openat(backupRootFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        if directoryFD < 0 {
            if errno == ENOENT {
                return Inspection(state: .missing, transactionID: transactionID, observedHashes: [:],
                    missingArtifacts: Set(HelperRootReleaseSet.Artifact.allCases), mismatchedArtifacts: [], unexpectedEntries: [])
            }
            throw StoreError.openFailed(errno)
        }
        defer { _ = close(directoryFD) }
        try validatePrivateDirectory(directoryFD)
        let unexpected = try entryNames(directoryFD: directoryFD).subtracting(expectedEntryNames)
        var hashes: [HelperRootReleaseSet.Artifact: String] = [:]
        var missing = Set<HelperRootReleaseSet.Artifact>(), mismatched = Set<HelperRootReleaseSet.Artifact>()
        for artifact in HelperRootReleaseSet.Artifact.allCases {
            do {
                let hash = try hashArtifact(artifact, directoryFD: directoryFD)
                hashes[artifact] = hash
                if hash != expected.hashes[artifact] { mismatched.insert(artifact) }
            } catch StoreError.missingBackup { missing.insert(artifact) }
        }
        let state: State = (!mismatched.isEmpty || !unexpected.isEmpty) ? .mismatched : (!missing.isEmpty ? .partial : .complete)
        return Inspection(state: state, transactionID: transactionID, observedHashes: hashes,
            missingArtifacts: missing, mismatchedArtifacts: mismatched, unexpectedEntries: unexpected)
    }

    private var expectedEntryNames: Set<String> {
        Set(["filterkit-helper", "Deployment.json", "cn.yfen.filterkit.helper.plist"])
    }
    private func fileName(_ artifact: HelperRootReleaseSet.Artifact) -> String {
        switch artifact {
        case .executable: return "filterkit-helper"
        case .deploymentManifest: return "Deployment.json"
        case .launchDaemon: return "cn.yfen.filterkit.helper.plist"
        }
    }

    private func openVerifiedJBRoot() throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw StoreError.openFailed(errno) }
        for component in jbRootPath.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let code = errno; _ = close(fd); throw StoreError.openFailed(code) }
            _ = close(fd); fd = next
            var info = stat()
            guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  (info.st_mode & 0o022) == 0,
                  info.st_uid == 0 || (info.st_mode & 0o200) == 0 else {
                _ = close(fd); throw StoreError.unsafeDirectory
            }
        }
        var rootInfo = stat()
        guard fstat(fd, &rootInfo) == 0, rootInfo.st_uid == 0, rootInfo.st_gid == 0 else {
            _ = close(fd); throw StoreError.unsafeDirectory
        }
        return fd
    }

    private func openDirectory(relativePath: String, rootFD: Int32) throws -> Int32 {
        var fd = dup(rootFD); guard fd >= 0 else { throw StoreError.openFailed(errno) }
        for component in relativePath.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let code = errno; _ = close(fd); throw StoreError.openFailed(code) }
            _ = close(fd); fd = next
            var info = stat()
            guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o022) == 0 else {
                _ = close(fd); throw StoreError.unsafeDirectory
            }
        }
        try validatePrivateDirectory(fd)
        return fd
    }
    private func openVerifiedBackupRoot(rootFD: Int32) throws -> Int32 {
        try openDirectory(relativePath: Self.relativeRootPath, rootFD: rootFD)
    }
    private func validatePrivateDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o777) == 0o700 else {
            throw StoreError.unsafeDirectory
        }
    }

    private func openParent(of relativePath: String, rootFD: Int32) throws -> (Int32, String) {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts.allSatisfy({ $0 != "." && $0 != ".." }) else { throw StoreError.unsafeArtifact }
        var fd = dup(rootFD); guard fd >= 0 else { throw StoreError.openFailed(errno) }
        for component in parts.dropLast() {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let code = errno; _ = close(fd); throw StoreError.openFailed(code) }
            _ = close(fd); fd = next
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_gid == 0,
                  (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR), (info.st_mode & 0o022) == 0 else {
                _ = close(fd); throw StoreError.unsafeDirectory
            }
        }
        return (fd, parts.last!)
    }

    private func readActiveArtifact(_ path: String, artifact: HelperRootReleaseSet.Artifact, rootFD: Int32) throws -> Data {
        let (parent, leaf) = try openParent(of: path, rootFD: rootFD); defer { _ = close(parent) }
        let fd = leaf.withCString { openat(parent, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
        guard fd >= 0 else { throw StoreError.openFailed(errno) }; defer { _ = close(fd) }
        let expectedMode: mode_t = artifact == .executable ? 0o755 : (artifact == .deploymentManifest ? 0o600 : 0o644)
        let maximum: Int64 = artifact == .executable ? 64 * 1024 * 1024 : 256 * 1024
        var before = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              before.st_uid == 0, before.st_gid == 0, before.st_nlink == 1,
              (before.st_mode & 0o777) == expectedMode, before.st_size >= 0, before.st_size <= maximum else {
            throw StoreError.unsafeArtifact
        }
        var data = Data(); data.reserveCapacity(Int(before.st_size)); var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count: Int
            #if canImport(Darwin)
            count = Darwin.read(fd, &buffer, buffer.count)
            #else
            count = Glibc.read(fd, &buffer, buffer.count)
            #endif
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw StoreError.openFailed(errno) }
            if count == 0 { break }; data.append(contentsOf: buffer.prefix(count))
            guard data.count <= Int(maximum) else { throw StoreError.unsafeArtifact }
        }
        var after = stat()
        guard fstat(fd, &after) == 0, FileIdentity(before) == FileIdentity(after),
              data.count == Int(after.st_size) else { throw StoreError.unsafeArtifact }
        return data
    }

    private func writeArtifact(_ data: Data, artifact: HelperRootReleaseSet.Artifact,
                               expectedHash: String, directoryFD: Int32) throws {
        let final = fileName(artifact), temp = "." + final + "." + UUID().uuidString.lowercased() + ".tmp"
        let mode: mode_t = artifact == .executable ? 0o755 : (artifact == .deploymentManifest ? 0o600 : 0o644)
        let fd = temp.withCString { openat(directoryFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode) }
        guard fd >= 0 else { throw StoreError.openFailed(errno) }
        var keep = true
        defer { _ = close(fd); if keep { _ = temp.withCString { unlinkat(directoryFD, $0, 0) } } }
        guard fchmod(fd, mode) == 0 else { throw StoreError.writeFailed(errno) }
        try writeAll(data, fd: fd)
        guard fsync(fd) == 0 else { throw StoreError.syncFailed(errno) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0, info.st_nlink == 1,
              (info.st_mode & 0o777) == mode, SHA256Digest.hex(data) == expectedHash else { throw StoreError.unsafeArtifact }
        let result = temp.withCString { source in final.withCString { destination in renameat(directoryFD, source, directoryFD, destination) } }
        guard result == 0 else { throw StoreError.renameFailed(errno) }; keep = false
        guard fsync(directoryFD) == 0 else { throw StoreError.syncFailed(errno) }
    }

    private func readBackupArtifact(_ artifact: HelperRootReleaseSet.Artifact, directoryFD: Int32) throws -> Data {
        let name = fileName(artifact)
        let fd = name.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
        if fd < 0 { if errno == ENOENT { throw StoreError.missingBackup }; throw StoreError.openFailed(errno) }
        defer { _ = close(fd) }
        let mode: mode_t = artifact == .executable ? 0o755 : (artifact == .deploymentManifest ? 0o600 : 0o644)
        let maximum: Int64 = artifact == .executable ? 64 * 1024 * 1024 : 256 * 1024
        var before = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              before.st_uid == 0, before.st_gid == 0, before.st_nlink == 1,
              (before.st_mode & 0o777) == mode, (before.st_mode & 0o6000) == 0,
              before.st_size >= 0, before.st_size <= maximum else {
            throw StoreError.unsafeArtifact
        }
        var bytes = Data(); bytes.reserveCapacity(Int(before.st_size)); var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count: Int
            #if canImport(Darwin)
            count = Darwin.read(fd, &buffer, buffer.count)
            #else
            count = Glibc.read(fd, &buffer, buffer.count)
            #endif
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw StoreError.openFailed(errno) }
            if count == 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
            guard bytes.count <= Int(maximum) else { throw StoreError.unsafeArtifact }
        }
        var after = stat()
        guard fstat(fd, &after) == 0, FileIdentity(before) == FileIdentity(after),
              bytes.count == Int(after.st_size) else { throw StoreError.unsafeArtifact }
        return bytes
    }

    private func hashArtifact(_ artifact: HelperRootReleaseSet.Artifact, directoryFD: Int32) throws -> String {
        let name = fileName(artifact)
        let fd = name.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
        if fd < 0 { if errno == ENOENT { throw StoreError.missingBackup }; throw StoreError.openFailed(errno) }
        defer { _ = close(fd) }
        let mode: mode_t = artifact == .executable ? 0o755 : (artifact == .deploymentManifest ? 0o600 : 0o644)
        let max: Int64 = artifact == .executable ? 64 * 1024 * 1024 : 256 * 1024
        var before = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              before.st_uid == 0, before.st_gid == 0, before.st_nlink == 1,
              (before.st_mode & 0o777) == mode, before.st_size >= 0, before.st_size <= max else { throw StoreError.unsafeArtifact }
        var bytes = Data(); bytes.reserveCapacity(Int(before.st_size)); var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count: Int
            #if canImport(Darwin)
            count = Darwin.read(fd, &buffer, buffer.count)
            #else
            count = Glibc.read(fd, &buffer, buffer.count)
            #endif
            if count < 0 && errno == EINTR { continue }; guard count >= 0 else { throw StoreError.openFailed(errno) }
            if count == 0 { break }; bytes.append(contentsOf: buffer.prefix(count)); guard bytes.count <= Int(max) else { throw StoreError.unsafeArtifact }
        }
        var after = stat()
        guard fstat(fd, &after) == 0, FileIdentity(before) == FileIdentity(after), bytes.count == Int(after.st_size) else { throw StoreError.unsafeArtifact }
        return SHA256Digest.hex(bytes)
    }

    private func entryNames(directoryFD: Int32) throws -> Set<String> {
        let duplicate = dup(directoryFD); guard duplicate >= 0 else { throw StoreError.openFailed(errno) }
        guard let stream = fdopendir(duplicate) else { let code = errno; _ = close(duplicate); throw StoreError.openFailed(code) }
        defer { _ = closedir(stream) }; var names = Set<String>()
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) } }
            if name != "." && name != ".." { names.insert(name) }
        }
        return names
    }
    private func verifyMachOIdentity(_ data: Data, expectedCDHash: String, expectedTeamIdentifier: String) throws {
        let slices: [MachOSliceMetadata]
        do { slices = try MachOMetadataReader().readSlices(data: data) } catch { throw StoreError.activeReleaseMismatch }
        guard !slices.isEmpty, slices.allSatisfy({ $0.codeSignatureState == "cdhash_extracted" && $0.codeSignatureTeamIdentifier == expectedTeamIdentifier }),
              slices.contains(where: { $0.cdHash?.caseInsensitiveCompare(expectedCDHash) == .orderedSame }) else { throw StoreError.activeReleaseMismatch }
    }
    private func verifyPreviousMetadata(manifest: Data, launchDaemon: Data, jbRootPath: String) throws {
        guard let object = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              object["schemaVersion"] as? Int == 2,
              object["jbRootPath"] as? String == jbRootPath,
              object["executionEnabled"] as? Bool == false,
              let plist = try? PropertyListSerialization.propertyList(from: launchDaemon, options: [], format: nil) as? [String: Any],
              plist["Label"] as? String == "cn.yfen.filterkit.helper",
              plist["ProgramArguments"] as? [String] == [jbRootPath + "/usr/libexec/filterkit-helper"],
              plist["Disabled"] as? Bool == true, plist["RunAtLoad"] as? Bool == false,
              plist["KeepAlive"] as? Bool == false else { throw StoreError.activeReleaseMismatch }
    }
    private func removeKnownArtifacts(directoryFD: Int32) { for artifact in HelperRootReleaseSet.Artifact.allCases { _ = fileName(artifact).withCString { unlinkat(directoryFD, $0, 0) } }; _ = fsync(directoryFD) }
    private func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }; var offset = 0
            while offset < raw.count {
                let count: Int
                #if canImport(Darwin)
                count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                #else
                count = Glibc.write(fd, base.advanced(by: offset), raw.count - offset)
                #endif
                if count < 0 && errno == EINTR { continue }; guard count > 0 else { throw StoreError.writeFailed(count == 0 ? EIO : errno) }; offset += count
            }
        }
    }
    private struct FileIdentity: Equatable {
        let device: UInt64; let inode: UInt64; let size: Int64
        let modifiedSeconds: Int64; let modifiedNanos: Int64; let changedSeconds: Int64; let changedNanos: Int64
        init(_ value: stat) {
            device = UInt64(value.st_dev); inode = UInt64(value.st_ino); size = Int64(value.st_size)
            #if canImport(Darwin)
            modifiedSeconds = Int64(value.st_mtimespec.tv_sec); modifiedNanos = Int64(value.st_mtimespec.tv_nsec)
            changedSeconds = Int64(value.st_ctimespec.tv_sec); changedNanos = Int64(value.st_ctimespec.tv_nsec)
            #else
            modifiedSeconds = Int64(value.st_mtim.tv_sec); modifiedNanos = Int64(value.st_mtim.tv_nsec)
            changedSeconds = Int64(value.st_ctim.tv_sec); changedNanos = Int64(value.st_ctim.tv_nsec)
            #endif
        }
    }
}
