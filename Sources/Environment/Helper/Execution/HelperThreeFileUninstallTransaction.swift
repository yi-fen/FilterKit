import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Root-only, ownership-proof-bound removal of one FilterKit plugin's dylib, Filter.plist,
/// and manifest. Files are first moved into transaction-specific quarantine names. A durable
/// journal makes the operation recoverable: pre-commit crashes roll back; post-commit crashes
/// finish deleting quarantined files. This primitive is intentionally not wired to production IPC.
final class HelperThreeFileUninstallTransaction {
    enum Phase: String, Codable, CaseIterable {
        case prepared, movingDylib, movingPlist, movingManifest, committed
    }
    enum TransactionError: Error, Equatable {
        case notRoot, invalidProof, unsafeDirectory, unsafeFile, conflict
        case journalInvalid, manualIntervention, io(Int32), injectedCrash(Phase)
    }
    struct Receipt: Equatable {
        let transactionID: UUID
        let pluginID: UUID
        let removedDylibSHA256: String
        let removedPlistSHA256: String
        let removedManifestSHA256: String
    }
    private struct Journal: Codable {
        let schemaVersion: Int
        let transactionID: UUID
        let pluginID: UUID
        let dylibName: String
        let plistName: String
        let manifestName: String
        let dylibHash: String
        let plistHash: String
        let manifestHash: String
        var phase: Phase
        var quarantineDylib: String { ".fk-uninstall-\(transactionID.uuidString.lowercased()).dylib.q" }
        var quarantinePlist: String { ".fk-uninstall-\(transactionID.uuidString.lowercased()).plist.q" }
        var quarantineManifest: String { ".fk-uninstall-\(transactionID.uuidString.lowercased()).manifest.q" }
        func validate() throws {
            let base = String(dylibName.dropLast(6))
            guard schemaVersion == 1,
                  HelperPolicy.isSafeLeafName(dylibName), dylibName.lowercased().hasSuffix(".dylib"),
                  HelperPolicy.isSafeLeafName(plistName), plistName.lowercased().hasSuffix(".plist"),
                  base.lowercased() == String(plistName.dropLast(6)).lowercased(),
                  manifestName == base + ".fk.json",
                  [dylibHash, plistHash, manifestHash].allSatisfy(HelperPolicy.isValidHash) else {
                throw TransactionError.journalInvalid
            }
        }
    }

    private let directoryPath: String
    private let journalLeaf = ".filterkit-uninstall.journal"
    private static let processLock = NSLock()

    init(directoryPath: String) throws {
        guard HelperPolicy.isAbsoluteCleanPath(directoryPath), directoryPath != "/" else {
            throw TransactionError.unsafeDirectory
        }
        self.directoryPath = directoryPath
    }

    /// The transaction removes the complete dylib/plist/Manifest set. The caller must
    /// freshly revalidate ownership and Filter.plist/Manifest consistency before entry.
    func execute(proof: HelperOwnershipProof,
                 transactionID: UUID = UUID(), simulateCrashAfter: Phase? = nil,
                 preMutationAuthorization: (() throws -> Void)? = nil) throws -> Receipt {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        guard proof.binaryIdentityVerified, !proof.isFirstInstallAuthorization,
              proof.manifestSchemaVersion >= 3,
              HelperPolicy.isValidHash(proof.dylibSHA256), HelperPolicy.isValidHash(proof.plistSHA256),
              HelperPolicy.isValidHash(proof.manifestSHA256),
              HelperPolicy.isSafeLeafName(proof.dylibFileName),
              HelperPolicy.isSafeLeafName(proof.plistFileName) else { throw TransactionError.invalidProof }

        let manifestName = String(proof.dylibFileName.dropLast(6)) + ".fk.json"
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        guard try hashIfPresent(fd, ".filterkit-three-file.journal") == nil,
              try hashIfPresent(fd, journalLeaf) == nil,
              try hashIfPresent(fd, "\(journalLeaf).tmp") == nil else { throw TransactionError.manualIntervention }

        let actualDylib = try hashIfPresent(fd, proof.dylibFileName)
        let actualPlist = try hashIfPresent(fd, proof.plistFileName)
        let actualManifest = try hashIfPresent(fd, manifestName)
        guard actualDylib == proof.dylibSHA256,
              actualPlist == proof.plistSHA256,
              actualManifest == proof.manifestSHA256 else { throw TransactionError.conflict }
        // Re-check package ownership and authoritative activation state at the last safe
        // boundary before the durable Journal is created and any file is moved.
        try preMutationAuthorization?()

        let journal = Journal(schemaVersion: 1, transactionID: transactionID, pluginID: proof.pluginID,
            dylibName: proof.dylibFileName, plistName: proof.plistFileName, manifestName: manifestName,
            dylibHash: proof.dylibSHA256, plistHash: proof.plistSHA256,
            manifestHash: proof.manifestSHA256, phase: .prepared)
        for leaf in [journal.quarantineDylib, journal.quarantinePlist, journal.quarantineManifest] {
            try requireAbsent(fd, leaf)
        }
        try save(journal, fd: fd)
        var current = journal
        do {
            try crashIfRequested(.prepared, simulateCrashAfter)
            current.phase = .movingDylib; try save(current, fd: fd)
            try moveVerified(fd, source: current.dylibName, destination: current.quarantineDylib, hash: current.dylibHash)
            try crashIfRequested(.movingDylib, simulateCrashAfter)
            current.phase = .movingPlist; try save(current, fd: fd)
            try moveVerified(fd, source: current.plistName, destination: current.quarantinePlist, hash: current.plistHash)
            try crashIfRequested(.movingPlist, simulateCrashAfter)
            current.phase = .movingManifest; try save(current, fd: fd)
            try moveVerified(fd, source: current.manifestName, destination: current.quarantineManifest, hash: current.manifestHash)
            try crashIfRequested(.movingManifest, simulateCrashAfter)
            guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
            current.phase = .committed; try save(current, fd: fd)
            try crashIfRequested(.committed, simulateCrashAfter)
            try finishCommitted(current, fd: fd)
            return Receipt(transactionID: transactionID, pluginID: proof.pluginID,
                removedDylibSHA256: proof.dylibSHA256, removedPlistSHA256: proof.plistSHA256,
                removedManifestSHA256: proof.manifestSHA256)
        } catch let error as TransactionError {
            if case .injectedCrash = error { throw error }
            try reconcileLocked(fd: fd)
            throw error
        } catch {
            try reconcileLocked(fd: fd)
            throw TransactionError.io(errno)
        }
    }

    /// Read-only startup probe. A pending journal must block normal mutation IPC until
    /// an explicitly authorized recovery workflow reconciles it.
    func inspectPendingJournal() throws -> Bool {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        let journalExists = try hashIfPresent(fd, journalLeaf) != nil
        let temporaryExists = try hashIfPresent(fd, "\(journalLeaf).tmp") != nil
        guard journalExists || !temporaryExists else { throw TransactionError.journalInvalid }
        return journalExists
    }

    @discardableResult
    func reconcile(expectedTransactionID: UUID) throws -> Phase {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        guard let journal = try load(fd), journal.transactionID == expectedTransactionID else {
            throw TransactionError.journalInvalid
        }
        let disposition = journal.phase
        try reconcileLocked(fd: fd)
        guard try load(fd) == nil else { throw TransactionError.manualIntervention }
        return disposition
    }

    private func reconcileLocked(fd: Int32) throws {
        guard let journal = try load(fd) else { return }
        try journal.validate()
        if journal.phase == .committed {
            try finishCommitted(journal, fd: fd)
            return
        }
        try restoreOne(fd, destination: journal.dylibName, quarantine: journal.quarantineDylib, hash: journal.dylibHash)
        try restoreOne(fd, destination: journal.plistName, quarantine: journal.quarantinePlist, hash: journal.plistHash)
        try restoreOne(fd, destination: journal.manifestName, quarantine: journal.quarantineManifest, hash: journal.manifestHash)
        guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
        try clearJournal(fd)
    }

    private func finishCommitted(_ journal: Journal, fd: Int32) throws {
        for (destination, quarantine, hash) in [
            (journal.dylibName, journal.quarantineDylib, journal.dylibHash),
            (journal.plistName, journal.quarantinePlist, journal.plistHash),
            (journal.manifestName, journal.quarantineManifest, journal.manifestHash)
        ] {
            guard try hashIfPresent(fd, destination) == nil else { throw TransactionError.manualIntervention }
            if try hashIfPresent(fd, quarantine) != nil { try unlinkVerified(fd, quarantine, hash: hash) }
        }
        guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
        try clearJournal(fd)
    }

    private func restoreOne(_ fd: Int32, destination: String, quarantine: String, hash: String) throws {
        let current = try hashIfPresent(fd, destination)
        let held = try hashIfPresent(fd, quarantine)
        switch (current, held) {
        case (hash, nil):
            break
        case (nil, hash):
            try renameLeaf(fd, quarantine, destination)
        default:
            // Both missing, both present, or either hash changed means the transaction
            // cannot prove a lossless rollback. Keep the journal for manual recovery.
            throw TransactionError.manualIntervention
        }
    }

    private func moveVerified(_ fd: Int32, source: String, destination: String, hash: String) throws {
        guard try hashIfPresent(fd, source) == hash else { throw TransactionError.conflict }
        try requireAbsent(fd, destination)
        try renameLeaf(fd, source, destination)
        guard try hashIfPresent(fd, destination) == hash else { throw TransactionError.conflict }
        guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
    }

    private func hashIfPresent(_ fd: Int32, _ leaf: String) throws -> String? {
        var info = stat()
        let rc = leaf.withCString { fstatat(fd, $0, &info, AT_SYMLINK_NOFOLLOW) }
        if rc != 0 { if errno == ENOENT { return nil }; throw TransactionError.unsafeFile }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_uid == 0,
              info.st_gid == 0, info.st_nlink == 1, (info.st_mode & 0o6022) == 0,
              info.st_size >= 0, info.st_size <= 64 * 1024 * 1024 else { throw TransactionError.unsafeFile }
        let file = leaf.withCString { openat(fd, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard file >= 0 else { throw TransactionError.unsafeFile }
        defer { _ = close(file) }
        var opened = stat()
        guard fstat(file, &opened) == 0, opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else {
            throw TransactionError.unsafeFile
        }
        var data = Data(); data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(file, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw TransactionError.io(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= 64 * 1024 * 1024 else { throw TransactionError.unsafeFile }
        }
        return SHA256Digest.hex(data)
    }

    private func openDirectory() throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw TransactionError.unsafeDirectory }
        for component in directoryPath.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { _ = close(fd); throw TransactionError.unsafeDirectory }
            _ = close(fd); fd = next
        }
        return fd
    }

    private func validateDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o022) == 0 else {
            throw TransactionError.unsafeDirectory
        }
    }

    private func requireAbsent(_ fd: Int32, _ leaf: String) throws {
        guard try hashIfPresent(fd, leaf) == nil else { throw TransactionError.conflict }
    }

    private func renameLeaf(_ fd: Int32, _ source: String, _ destination: String) throws {
        let result = source.withCString { sourcePtr in
            destination.withCString { destinationPtr in renameat(fd, sourcePtr, fd, destinationPtr) }
        }
        guard result == 0 else { throw TransactionError.io(errno) }
    }

    private func unlinkVerified(_ fd: Int32, _ leaf: String, hash: String) throws {
        guard try hashIfPresent(fd, leaf) == hash else { throw TransactionError.manualIntervention }
        guard leaf.withCString({ unlinkat(fd, $0, 0) }) == 0 else { throw TransactionError.io(errno) }
    }

    private func save(_ journal: Journal, fd: Int32) throws {
        let data = try JSONEncoder().encode(journal)
        let temp = "\(journalLeaf).tmp"
        if try hashIfPresent(fd, temp) != nil { throw TransactionError.conflict }
        let file = temp.withCString { openat(fd, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard file >= 0 else { throw TransactionError.io(errno) }
        var writeOK = true
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = write(file, base.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { writeOK = false; break }
                offset += count
            }
        }
        if !writeOK || fsync(file) != 0 { let code = errno; _ = close(file); _ = unlinkat(fd, temp, 0); throw TransactionError.io(code) }
        _ = close(file)
        if renameat(fd, temp, fd, journalLeaf) != 0 { let code = errno; _ = unlinkat(fd, temp, 0); throw TransactionError.io(code) }
        guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
    }

    private func load(_ fd: Int32) throws -> Journal? {
        guard let hash = try hashIfPresent(fd, journalLeaf) else { return nil }
        _ = hash
        let file = journalLeaf.withCString { openat(fd, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard file >= 0 else { throw TransactionError.journalInvalid }
        defer { _ = close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_size >= 0, info.st_size <= 32 * 1024 else {
            throw TransactionError.journalInvalid
        }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(file, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw TransactionError.journalInvalid }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= 32 * 1024 else { throw TransactionError.journalInvalid }
        }
        guard let journal = try? JSONDecoder().decode(Journal.self, from: data) else { throw TransactionError.journalInvalid }
        try journal.validate()
        return journal
    }

    private func clearJournal(_ fd: Int32) throws {
        guard journalLeaf.withCString({ unlinkat(fd, $0, 0) }) == 0 || errno == ENOENT else {
            throw TransactionError.io(errno)
        }
        guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
    }

    private func crashIfRequested(_ phase: Phase, _ requested: Phase?) throws {
        if requested == phase { throw TransactionError.injectedCrash(phase) }
    }
}
