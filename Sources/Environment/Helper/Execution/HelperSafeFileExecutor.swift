import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// fd-relative, no-follow transaction executor. It is deliberately NOT wired into HelperRuntime
/// in P1-22; production execution remains disabled until Darwin/rootless device validation.
final class HelperSafeFileExecutor {
    enum ExecutorError: Error, Equatable {
        case invalidRoots, invalidPlan, ownershipProofRequired, sourceMissingOrUnsafe
        case sourceHashMismatch, invalidPlist, targetConflict, targetUnsafe
        case writeFailed(Int32), commitFailed(Int32), rollbackFailed(Int32), unsupportedOperation
    }

    struct Roots: Equatable {
        let stagingRoot: String
        let targetDirectory: String
        let expectedStagingUID: UInt32
        init(stagingRoot: String, targetDirectory: String, expectedStagingUID: UInt32) throws {
            guard HelperPolicy.isAbsoluteCleanPath(stagingRoot), HelperPolicy.isAbsoluteCleanPath(targetDirectory),
                  stagingRoot != "/", targetDirectory != "/" else { throw ExecutorError.invalidRoots }
            self.stagingRoot = stagingRoot
            self.targetDirectory = targetDirectory
            self.expectedStagingUID = expectedStagingUID
        }
    }

    struct TransactionReceipt: Equatable {
        let requestIDs: [UUID]
        let pluginID: UUID
        let changedPaths: [String]
        let dylibSHA256: String
        let plistSHA256: String
        let completedAt: Date
        var manifestSHA256: String? = nil
    }

    private let roots: Roots
    private let maximumFileBytes: Int
    private let transactionLock = NSLock()
    init(roots: Roots, maximumFileBytes: Int = 64 * 1024 * 1024) {
        self.roots = roots
        self.maximumFileBytes = max(1, maximumFileBytes)
    }

    /// Executes exactly one paired dylib + plist install/replace transaction.
    /// The proof must bind the plugin UUID, exact leaf names and payload hashes.
    func execute(_ plans: [HelperClosedExecutionPlan], proof: HelperOwnershipProof) throws -> TransactionReceipt {
        transactionLock.lock(); defer { transactionLock.unlock() }
        guard geteuid() == 0 else { throw ExecutorError.targetUnsafe }
        guard plans.count == 2,
              let dylibPlan = plans.first(where: { $0.operation == .installDylib }),
              let plistPlan = plans.first(where: { $0.operation == .replaceFilterPlist }),
              plans.allSatisfy({ $0.action == .copyFile && $0.pluginID == proof.pluginID }),
              let dylibSource = dylibPlan.sourceRelativePath,
              let plistSource = plistPlan.sourceRelativePath,
              let dylibHash = dylibPlan.expectedSHA256?.lowercased(),
              let plistHash = plistPlan.expectedSHA256?.lowercased(),
              dylibPlan.destinationRelativePath == proof.dylibFileName,
              plistPlan.destinationRelativePath == proof.plistFileName,
              dylibHash == proof.dylibSHA256, plistHash == proof.plistSHA256,
              HelperPolicy.isSafeLeafName(dylibPlan.destinationRelativePath),
              HelperPolicy.isSafeLeafName(plistPlan.destinationRelativePath),
              HelperPolicy.isSafeRelativePath(dylibSource), HelperPolicy.isSafeRelativePath(plistSource)
        else { throw ExecutorError.ownershipProofRequired }
        guard plans[0].requestID != plans[1].requestID else { throw ExecutorError.invalidPlan }

        let stagingFD = try openDirectory(roots.stagingRoot)
        defer { _ = close(stagingFD) }
        try validateDirectory(stagingFD, owner: roots.expectedStagingUID, stagingDirectory: true)
        let targetFD = try openDirectory(roots.targetDirectory)
        defer { _ = close(targetFD) }
        try validateDirectory(targetFD, owner: 0, stagingDirectory: false)

        let dylibData = try readStagedFile(rootFD: stagingFD, relativePath: dylibSource)
        let plistData = try readStagedFile(rootFD: stagingFD, relativePath: plistSource)
        guard SHA256Digest.hex(dylibData) == dylibHash,
              SHA256Digest.hex(plistData) == plistHash else { throw ExecutorError.sourceHashMismatch }
        guard (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) != nil else {
            throw ExecutorError.invalidPlist
        }

        try requireTargetAbsent(targetFD, dylibPlan.destinationRelativePath)
        if proof.isFirstInstallAuthorization {
            try requireTargetAbsent(targetFD, plistPlan.destinationRelativePath)
        } else {
            try validateReplaceTargetIfPresent(targetFD, plistPlan.destinationRelativePath)
        }
        let previousPlistHash = try existingTargetHashIfPresent(targetFD, plistPlan.destinationRelativePath)

        let transactionID = UUID().uuidString.lowercased()
        let dylibTemp = ".filterkit-\(transactionID).dylib.tmp"
        let plistTemp = ".filterkit-\(transactionID).plist.tmp"
        let plistBackup = ".filterkit-\(transactionID).plist.bak"
        var hasPlistBackup = false
        var dylibCommitted = false
        var plistCommitted = false
        var journalCreated = false
        let journalStore = try HelperTransactionJournalStore(directoryPath: roots.targetDirectory)
        var journal = try HelperTransactionJournal(transactionID: UUID(uuidString: transactionID)!,
            pluginID: proof.pluginID, dylibFileName: dylibPlan.destinationRelativePath,
            plistFileName: plistPlan.destinationRelativePath, dylibSHA256: dylibHash,
            plistSHA256: plistHash, previousPlistSHA256: previousPlistHash)
        do {
            try journalStore.save(journal)
            journalCreated = true
            try writeTemporary(data: dylibData, leaf: dylibTemp, directoryFD: targetFD)
            try writeTemporary(data: plistData, leaf: plistTemp, directoryFD: targetFD)
            journal.phase = .movingPreviousPlist
            try journalStore.save(journal)
            let plistStillExists = targetExists(targetFD, plistPlan.destinationRelativePath)
            guard plistStillExists == (previousPlistHash != nil) else { throw ExecutorError.targetUnsafe }
            if plistStillExists {
                let result = plistPlan.destinationRelativePath.withCString { oldName in
                    plistBackup.withCString { backupName in renameat(targetFD, oldName, targetFD, backupName) }
                }
                guard result == 0 else { throw ExecutorError.commitFailed(errno) }
                hasPlistBackup = true
                let movedHash = try existingTargetHashIfPresent(targetFD, plistBackup)
                guard movedHash == previousPlistHash else { throw ExecutorError.targetUnsafe }
            }
            journal.phase = .installingDylib
            try journalStore.save(journal)
            let dylibResult = dylibTemp.withCString { temp in
                dylibPlan.destinationRelativePath.withCString { destination in renameat(targetFD, temp, targetFD, destination) }
            }
            guard dylibResult == 0 else { throw ExecutorError.commitFailed(errno) }
            dylibCommitted = true
            journal.phase = .installingPlist
            try journalStore.save(journal)
            let plistResult = plistTemp.withCString { temp in
                plistPlan.destinationRelativePath.withCString { destination in renameat(targetFD, temp, targetFD, destination) }
            }
            guard plistResult == 0 else { throw ExecutorError.commitFailed(errno) }
            plistCommitted = true
            guard fsync(targetFD) == 0 else { throw ExecutorError.commitFailed(errno) }
            journal.phase = .committed
            try journalStore.save(journal)
            var backupRemoved = true
            if hasPlistBackup {
                backupRemoved = plistBackup.withCString { unlinkat(targetFD, $0, 0) } == 0
            }
            let directorySynced = fsync(targetFD) == 0
            if backupRemoved && directorySynced { try? journalStore.clear() }
            return TransactionReceipt(requestIDs: [dylibPlan.requestID, plistPlan.requestID], pluginID: proof.pluginID,
                changedPaths: [dylibPlan.destinationRelativePath, plistPlan.destinationRelativePath].sorted(),
                dylibSHA256: dylibHash, plistSHA256: plistHash, completedAt: Date())
        } catch {
            var rollbackOK = true
            if plistCommitted { if plistPlan.destinationRelativePath.withCString({ unlinkat(targetFD, $0, 0) }) != 0 { rollbackOK = false } }
            if dylibCommitted { if dylibPlan.destinationRelativePath.withCString({ unlinkat(targetFD, $0, 0) }) != 0 { rollbackOK = false } }
            if hasPlistBackup {
                let restored = plistBackup.withCString { backup in
                    plistPlan.destinationRelativePath.withCString { destination in renameat(targetFD, backup, targetFD, destination) }
                }
                if restored != 0 { rollbackOK = false }
            }
            _ = dylibTemp.withCString { unlinkat(targetFD, $0, 0) }
            _ = plistTemp.withCString { unlinkat(targetFD, $0, 0) }
            _ = fsync(targetFD)
            if !rollbackOK { throw ExecutorError.rollbackFailed(errno) }
            if journalCreated { try? journalStore.clear() }
            throw error
        }
    }

    private func openDirectory(_ absolutePath: String) throws -> Int32 {
        guard HelperPolicy.isAbsoluteCleanPath(absolutePath) else { throw ExecutorError.invalidRoots }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ExecutorError.writeFailed(errno) }
        for component in absolutePath.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let code = errno; _ = close(fd); throw ExecutorError.writeFailed(code) }
            _ = close(fd); fd = next
        }
        return fd
    }

    private func validateDirectory(_ fd: Int32, owner: UInt32, stagingDirectory: Bool = false) throws {
        var info = stat()
        let forbiddenModeBits: mode_t = stagingDirectory ? 0o077 : 0o022
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == owner,
              (owner != 0 || info.st_gid == 0),
              (info.st_mode & forbiddenModeBits) == 0 else { throw ExecutorError.targetUnsafe }
    }

    private func readStagedFile(rootFD: Int32, relativePath: String) throws -> Data {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty, components.allSatisfy({ HelperPolicy.isSafeLeafName($0) }) else { throw ExecutorError.sourceMissingOrUnsafe }
        var directoryFD = dup(rootFD)
        guard directoryFD >= 0 else { throw ExecutorError.sourceMissingOrUnsafe }
        for component in components.dropLast() {
            let next = component.withCString { openat(directoryFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let code = errno; _ = close(directoryFD); throw ExecutorError.writeFailed(code) }
            var directoryInfo = stat()
            guard fstat(next, &directoryInfo) == 0,
                  (directoryInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  directoryInfo.st_uid == roots.expectedStagingUID,
                  (directoryInfo.st_mode & 0o077) == 0 else {
                _ = close(next); _ = close(directoryFD); throw ExecutorError.sourceMissingOrUnsafe
            }
            _ = close(directoryFD); directoryFD = next
        }
        defer { _ = close(directoryFD) }
        let leaf = components.last!
        let fd = leaf.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw ExecutorError.sourceMissingOrUnsafe }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == roots.expectedStagingUID,
              (info.st_mode & 0o777) == 0o600,
              info.st_size >= 0, info.st_size <= maximumFileBytes else { throw ExecutorError.sourceMissingOrUnsafe }
        var data = Data(); data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw ExecutorError.writeFailed(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maximumFileBytes else { throw ExecutorError.sourceMissingOrUnsafe }
        }
        return data
    }

    private func existingTargetHashIfPresent(_ directoryFD: Int32, _ leaf: String) throws -> String? {
        var metadata = stat()
        let result = leaf.withCString { fstatat(directoryFD, $0, &metadata, AT_SYMLINK_NOFOLLOW) }
        if result != 0 {
            guard errno == ENOENT else { throw ExecutorError.targetUnsafe }
            return nil
        }
        guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              metadata.st_uid == 0, metadata.st_gid == 0,
              (metadata.st_mode & 0o6000) == 0,
              metadata.st_size >= 0, metadata.st_size <= maximumFileBytes else {
            throw ExecutorError.targetUnsafe
        }
        let fd = leaf.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw ExecutorError.targetUnsafe }
        defer { _ = close(fd) }
        var data = Data(); data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw ExecutorError.writeFailed(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maximumFileBytes else { throw ExecutorError.targetUnsafe }
        }
        return SHA256Digest.hex(data)
    }

    private func targetExists(_ directoryFD: Int32, _ leaf: String) -> Bool {
        var info = stat()
        return leaf.withCString { fstatat(directoryFD, $0, &info, AT_SYMLINK_NOFOLLOW) } == 0
    }

    private func requireTargetAbsent(_ directoryFD: Int32, _ leaf: String) throws {
        var info = stat()
        let result = leaf.withCString { fstatat(directoryFD, $0, &info, AT_SYMLINK_NOFOLLOW) }
        if result == 0 { throw ExecutorError.targetConflict }
        guard errno == ENOENT else { throw ExecutorError.targetUnsafe }
    }

    private func validateReplaceTargetIfPresent(_ directoryFD: Int32, _ leaf: String) throws {
        var info = stat()
        let result = leaf.withCString { fstatat(directoryFD, $0, &info, AT_SYMLINK_NOFOLLOW) }
        if result != 0 { guard errno == ENOENT else { throw ExecutorError.targetUnsafe }; return }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_uid == 0,
              info.st_gid == 0, (info.st_mode & 0o6000) == 0 else { throw ExecutorError.targetUnsafe }
    }

    private func writeTemporary(data: Data, leaf: String, directoryFD: Int32) throws {
        let fd = leaf.withCString { openat(directoryFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard fd >= 0 else { throw ExecutorError.writeFailed(errno) }
        defer { _ = close(fd) }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ExecutorError.writeFailed(errno) }
                offset += count
            }
        }
        guard fchmod(fd, 0o644) == 0, fchown(fd, 0, 0) == 0, fsync(fd) == 0 else { throw ExecutorError.writeFailed(errno) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o777) == 0o644 else { throw ExecutorError.targetUnsafe }
    }
}
