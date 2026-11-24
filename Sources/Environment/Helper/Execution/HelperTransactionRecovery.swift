import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Durable record schema for the paired deployment transaction. The journal is written by
/// the privileged Helper, never by the UI process. P1-23 defines validation and recovery plans;
/// filesystem mutation remains behind the disabled runtime release gate.
struct HelperTransactionJournal: Codable, Equatable {
    enum Phase: String, Codable, CaseIterable {
        case prepared
        case movingPreviousPlist
        case installingDylib
        case installingPlist
        case committed
    }

    let schemaVersion: Int
    let transactionID: UUID
    let pluginID: UUID
    let dylibFileName: String
    let plistFileName: String
    let dylibSHA256: String
    let plistSHA256: String
    let previousPlistSHA256: String?
    let createdAt: Date
    var phase: Phase

    static let currentSchemaVersion = 1

    init(transactionID: UUID, pluginID: UUID, dylibFileName: String, plistFileName: String,
         dylibSHA256: String, plistSHA256: String, previousPlistSHA256: String?,
         createdAt: Date = Date(), phase: Phase = .prepared) throws {
        guard HelperPolicy.isSafeLeafName(dylibFileName), dylibFileName.lowercased().hasSuffix(".dylib"),
              HelperPolicy.isSafeLeafName(plistFileName), plistFileName.lowercased().hasSuffix(".plist"),
              String(dylibFileName.dropLast(6)).lowercased() == String(plistFileName.dropLast(6)).lowercased(),
              HelperPolicy.isValidHash(dylibSHA256), HelperPolicy.isValidHash(plistSHA256),
              previousPlistSHA256.map(HelperPolicy.isValidHash) ?? true else {
            throw HelperTransactionJournalError.invalidRecord
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.transactionID = transactionID
        self.pluginID = pluginID
        self.dylibFileName = dylibFileName
        self.plistFileName = plistFileName
        self.dylibSHA256 = dylibSHA256.lowercased()
        self.plistSHA256 = plistSHA256.lowercased()
        self.previousPlistSHA256 = previousPlistSHA256?.lowercased()
        self.createdAt = createdAt
        self.phase = phase
    }

    var temporaryDylibName: String { ".filterkit-\(transactionID.uuidString.lowercased()).dylib.tmp" }
    var temporaryPlistName: String { ".filterkit-\(transactionID.uuidString.lowercased()).plist.tmp" }
    var previousPlistName: String { ".filterkit-\(transactionID.uuidString.lowercased()).plist.bak" }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              HelperPolicy.isSafeLeafName(dylibFileName), dylibFileName.lowercased().hasSuffix(".dylib"),
              HelperPolicy.isSafeLeafName(plistFileName), plistFileName.lowercased().hasSuffix(".plist"),
              String(dylibFileName.dropLast(6)).lowercased() == String(plistFileName.dropLast(6)).lowercased(),
              HelperPolicy.isValidHash(dylibSHA256), HelperPolicy.isValidHash(plistSHA256),
              previousPlistSHA256.map(HelperPolicy.isValidHash) ?? true,
              temporaryDylibName == ".filterkit-\(transactionID.uuidString.lowercased()).dylib.tmp",
              temporaryPlistName == ".filterkit-\(transactionID.uuidString.lowercased()).plist.tmp",
              previousPlistName == ".filterkit-\(transactionID.uuidString.lowercased()).plist.bak" else {
            throw HelperTransactionJournalError.invalidRecord
        }
    }
}

enum HelperTransactionJournalError: Error, Equatable {
    case invalidRecord, invalidObservation, unsafeRecoveryState, journalAlreadyExists
}

struct HelperTransactionFileObservation: Equatable {
    /// nil means the exact leaf is absent. A non-nil value is the SHA-256 of a verified
    /// root-owned regular file read without following symlinks.
    let temporaryDylibHash: String?
    let temporaryPlistHash: String?
    let deployedDylibHash: String?
    let deployedPlistHash: String?
    let previousPlistHash: String?
}

enum HelperTransactionRecoveryAction: Equatable {
    case removeTemporaryDylib(String, expectedSHA256: String)
    case removeTemporaryPlist(String, expectedSHA256: String)
    case removeDeployedDylib(String, expectedSHA256: String)
    case removeDeployedPlist(String, expectedSHA256: String)
    case restorePreviousPlist(backup: String, destination: String, expectedSHA256: String)
    case removePreviousPlist(String, expectedSHA256: String)
    case clearJournal
    case manualIntervention
}

/// Pure recovery planner. It never guesses based on filenames alone: every removal or restore
/// is bound to an exact journal-generated leaf and the expected byte hash.
struct HelperTransactionRecoveryPlanner {
    func plan(journal: HelperTransactionJournal,
              observed: HelperTransactionFileObservation) throws -> [HelperTransactionRecoveryAction] {
        try journal.validate()
        for hash in [observed.temporaryDylibHash, observed.temporaryPlistHash,
                     observed.deployedDylibHash, observed.deployedPlistHash,
                     observed.previousPlistHash].compactMap({ $0 }) {
            guard HelperPolicy.isValidHash(hash) else { throw HelperTransactionJournalError.invalidObservation }
        }

        let newDylibIsOurs = observed.deployedDylibHash == journal.dylibSHA256
        let newPlistIsOurs = observed.deployedPlistHash == journal.plistSHA256
        let oldPlistIsOurs = journal.previousPlistSHA256 != nil &&
            observed.previousPlistHash == journal.previousPlistSHA256

        if let hash = observed.temporaryDylibHash, hash != journal.dylibSHA256 { return [.manualIntervention] }
        if let hash = observed.temporaryPlistHash, hash != journal.plistSHA256 { return [.manualIntervention] }
        if journal.previousPlistSHA256 == nil && observed.previousPlistHash != nil { return [.manualIntervention] }

        if journal.phase == .committed {
            guard newDylibIsOurs, newPlistIsOurs else { return [.manualIntervention] }
            if observed.previousPlistHash != nil && !oldPlistIsOurs { return [.manualIntervention] }
            var actions: [HelperTransactionRecoveryAction] = []
            if observed.temporaryDylibHash == journal.dylibSHA256 {
                actions.append(.removeTemporaryDylib(journal.temporaryDylibName, expectedSHA256: journal.dylibSHA256))
            }
            if observed.temporaryPlistHash == journal.plistSHA256 {
                actions.append(.removeTemporaryPlist(journal.temporaryPlistName, expectedSHA256: journal.plistSHA256))
            }
            if oldPlistIsOurs {
                actions.append(.removePreviousPlist(journal.previousPlistName, expectedSHA256: journal.previousPlistSHA256!))
            }
            actions.append(.clearJournal)
            return actions
        }

        // Before commit, an existing plist must still be present either at its original leaf
        // or in the transaction backup. Missing/foreign bytes cannot be repaired by guessing.
        if let previousHash = journal.previousPlistSHA256 {
            let originalStillInPlace = observed.deployedPlistHash == previousHash
            if !oldPlistIsOurs && !originalStillInPlace { return [.manualIntervention] }
        }
        if journal.previousPlistSHA256 != nil && observed.previousPlistHash != nil && !oldPlistIsOurs {
            return [.manualIntervention]
        }
        if observed.deployedDylibHash != nil && !newDylibIsOurs { return [.manualIntervention] }
        if let deployedPlistHash = observed.deployedPlistHash,
           deployedPlistHash != journal.plistSHA256 && deployedPlistHash != journal.previousPlistSHA256 {
            return [.manualIntervention]
        }

        var actions: [HelperTransactionRecoveryAction] = []
        if newPlistIsOurs { actions.append(.removeDeployedPlist(journal.plistFileName, expectedSHA256: journal.plistSHA256)) }
        if newDylibIsOurs { actions.append(.removeDeployedDylib(journal.dylibFileName, expectedSHA256: journal.dylibSHA256)) }
        if oldPlistIsOurs {
            actions.append(.restorePreviousPlist(backup: journal.previousPlistName,
                destination: journal.plistFileName, expectedSHA256: journal.previousPlistSHA256!))
        }
        if observed.temporaryDylibHash == journal.dylibSHA256 {
            actions.append(.removeTemporaryDylib(journal.temporaryDylibName, expectedSHA256: journal.dylibSHA256))
        }
        if observed.temporaryPlistHash == journal.plistSHA256 {
            actions.append(.removeTemporaryPlist(journal.temporaryPlistName, expectedSHA256: journal.plistSHA256))
        }
        actions.append(.clearJournal)
        return actions
    }
}

/// Root-owned, single-slot journal store. The containing directory must be a root-owned,
/// non-group/world-writable directory selected by the Helper configuration, not by IPC input.
struct HelperTransactionJournalStore {
    enum StoreError: Error, Equatable { case unsafeDirectory, unsafeJournal, oversized, io(Int32), invalidJournal, journalAlreadyExists }
    static let journalLeaf = ".filterkit-transaction.journal"
    let directoryPath: String
    let maximumBytes: Int

    init(directoryPath: String, maximumBytes: Int = 32 * 1024) throws {
        guard HelperPolicy.isAbsoluteCleanPath(directoryPath), directoryPath != "/" else {
            throw StoreError.unsafeDirectory
        }
        self.directoryPath = directoryPath
        self.maximumBytes = max(1024, maximumBytes)
    }

    func load() throws -> HelperTransactionJournal? {
        let directoryFD = try openDirectory()
        defer { _ = close(directoryFD) }
        let fd = Self.journalLeaf.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw StoreError.io(errno)
        }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o777) == 0o600,
              (info.st_mode & 0o6000) == 0 else { throw StoreError.unsafeJournal }
        guard info.st_size >= 0, info.st_size <= maximumBytes else { throw StoreError.oversized }
        var data = Data(); data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw StoreError.io(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maximumBytes else { throw StoreError.oversized }
        }
        guard let journal = try? JSONDecoder().decode(HelperTransactionJournal.self, from: data),
              (try? journal.validate()) != nil else { throw StoreError.invalidJournal }
        return journal
    }

    func save(_ journal: HelperTransactionJournal) throws {
        try journal.validate()
        if let existing = try load(), existing.transactionID != journal.transactionID {
            throw StoreError.journalAlreadyExists
        }
        let data = try JSONEncoder().encode(journal)
        guard data.count <= maximumBytes else { throw StoreError.oversized }
        let directoryFD = try openDirectory()
        defer { _ = close(directoryFD) }
        let tempLeaf = ".filterkit-journal-\(UUID().uuidString.lowercased()).tmp"
        let fd = tempLeaf.withCString { openat(directoryFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard fd >= 0 else { throw StoreError.io(errno) }
        var keepTemp = true
        defer {
            _ = close(fd)
            if keepTemp { _ = tempLeaf.withCString { unlinkat(directoryFD, $0, 0) } }
        }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw StoreError.io(errno) }
                offset += count
            }
        }
        guard fchmod(fd, 0o600) == 0, fchown(fd, 0, 0) == 0, fsync(fd) == 0 else {
            throw StoreError.io(errno)
        }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o777) == 0o600 else { throw StoreError.unsafeJournal }
        let renameResult = tempLeaf.withCString { temp in
            Self.journalLeaf.withCString { destination in renameat(directoryFD, temp, directoryFD, destination) }
        }
        guard renameResult == 0 else { throw StoreError.io(errno) }
        keepTemp = false
        guard fsync(directoryFD) == 0 else { throw StoreError.io(errno) }
    }

    func clear() throws {
        let directoryFD = try openDirectory()
        defer { _ = close(directoryFD) }
        var metadata = stat()
        let statResult = Self.journalLeaf.withCString { fstatat(directoryFD, $0, &metadata, AT_SYMLINK_NOFOLLOW) }
        if statResult == 0 {
            guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
                  metadata.st_uid == 0, metadata.st_gid == 0,
                  (metadata.st_mode & 0o777) == 0o600 else { throw StoreError.unsafeJournal }
            let result = Self.journalLeaf.withCString { unlinkat(directoryFD, $0, 0) }
            guard result == 0 else { throw StoreError.io(errno) }
        } else if errno != ENOENT { throw StoreError.io(errno) }
        guard fsync(directoryFD) == 0 else { throw StoreError.io(errno) }
    }

    private func openDirectory() throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw StoreError.io(errno) }
        for component in directoryPath.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let code = errno; _ = close(fd); throw StoreError.io(code) }
            _ = close(fd); fd = next
        }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o022) == 0 else { _ = close(fd); throw StoreError.unsafeDirectory }
        return fd
    }
}

/// Executes only planner-approved recovery actions. Every target is reopened relative to a
/// no-follow directory fd and its root-owned bytes are re-hashed immediately before mutation.
/// This executor is not called by HelperRuntime until Darwin/device recovery validation passes.
final class HelperTransactionRecoveryExecutor {
    enum RecoveryError: Error, Equatable { case notRoot, unsafeDirectory, unsafeFile, hashMismatch, actionFailed(Int32), manualIntervention }

    func reconcile(directoryPath: String) throws -> HelperTransactionRecoveryResult {
        guard geteuid() == 0 else { throw RecoveryError.notRoot }
        let store = try HelperTransactionJournalStore(directoryPath: directoryPath)
        guard let journal = try store.load() else { return .clean }
        let fd = try openDirectory(directoryPath)
        defer { _ = close(fd) }
        try validateDirectory(fd)
        let observation = try observe(fd, journal: journal)
        let actions = try HelperTransactionRecoveryPlanner().plan(journal: journal, observed: observation)
        guard !actions.contains(.manualIntervention) else { return .manualIntervention }
        for action in actions {
            switch action {
            case let .removeTemporaryDylib(name, hash), let .removeTemporaryPlist(name, hash),
                 let .removeDeployedDylib(name, hash), let .removeDeployedPlist(name, hash),
                 let .removePreviousPlist(name, hash):
                try unlinkVerified(fd, leaf: name, expectedHash: hash)
            case let .restorePreviousPlist(backup, destination, hash):
                try requireAbsent(fd, destination)
                try verifyLeaf(fd, leaf: backup, expectedHash: hash)
                let result = backup.withCString { source in destination.withCString { target in renameat(fd, source, fd, target) } }
                guard result == 0 else { throw RecoveryError.actionFailed(errno) }
            case .clearJournal:
                try store.clear()
            case .manualIntervention:
                return .manualIntervention
            }
            guard fsync(fd) == 0 else { throw RecoveryError.actionFailed(errno) }
        }
        return .recovered
    }

    private func observe(_ fd: Int32, journal: HelperTransactionJournal) throws -> HelperTransactionFileObservation {
        HelperTransactionFileObservation(
            temporaryDylibHash: try hashIfPresent(fd, journal.temporaryDylibName),
            temporaryPlistHash: try hashIfPresent(fd, journal.temporaryPlistName),
            deployedDylibHash: try hashIfPresent(fd, journal.dylibFileName),
            deployedPlistHash: try hashIfPresent(fd, journal.plistFileName),
            previousPlistHash: try hashIfPresent(fd, journal.previousPlistName))
    }

    private func hashIfPresent(_ directoryFD: Int32, _ leaf: String) throws -> String? {
        do { return try verifyLeaf(directoryFD, leaf: leaf, expectedHash: nil) }
        catch RecoveryError.unsafeFile {
            var info = stat()
            let result = leaf.withCString { fstatat(directoryFD, $0, &info, AT_SYMLINK_NOFOLLOW) }
            if result != 0 && errno == ENOENT { return nil }
            throw RecoveryError.unsafeFile
        }
    }

    @discardableResult
    private func verifyLeaf(_ directoryFD: Int32, leaf: String, expectedHash: String?) throws -> String {
        // Journal-generated internal leaves begin with a dot; public leaf-name policy
        // intentionally rejects those. Journal validation binds their exact spellings.
        guard !leaf.isEmpty, leaf != ".", leaf != "..", !leaf.contains("/"), !leaf.contains("\0") else {
            throw RecoveryError.unsafeFile
        }
        let fd = leaf.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw RecoveryError.unsafeFile }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o6000) == 0,
              info.st_size >= 0, info.st_size <= 64 * 1024 * 1024 else { throw RecoveryError.unsafeFile }
        var data = Data(); data.reserveCapacity(Int(info.st_size)); var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw RecoveryError.unsafeFile }
            if n == 0 { break }
            data.append(contentsOf: buffer.prefix(n))
            guard data.count <= 64 * 1024 * 1024 else { throw RecoveryError.unsafeFile }
        }
        let hash = SHA256Digest.hex(data)
        if let expectedHash, hash != expectedHash { throw RecoveryError.hashMismatch }
        return hash
    }

    private func unlinkVerified(_ directoryFD: Int32, leaf: String, expectedHash: String) throws {
        try verifyLeaf(directoryFD, leaf: leaf, expectedHash: expectedHash)
        let result = leaf.withCString { unlinkat(directoryFD, $0, 0) }
        guard result == 0 else { throw RecoveryError.actionFailed(errno) }
    }

    private func requireAbsent(_ directoryFD: Int32, _ leaf: String) throws {
        var info = stat()
        let result = leaf.withCString { fstatat(directoryFD, $0, &info, AT_SYMLINK_NOFOLLOW) }
        guard result != 0 && errno == ENOENT else { throw RecoveryError.unsafeFile }
    }

    private func openDirectory(_ path: String) throws -> Int32 {
        guard HelperPolicy.isAbsoluteCleanPath(path), path != "/" else { throw RecoveryError.unsafeDirectory }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw RecoveryError.unsafeDirectory }
        for component in path.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { _ = close(fd); throw RecoveryError.unsafeDirectory }
            _ = close(fd); fd = next
        }
        return fd
    }

    private func validateDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o022) == 0 else {
            throw RecoveryError.unsafeDirectory
        }
    }
}

enum HelperTransactionRecoveryResult: Equatable { case clean, recovered, manualIntervention }
