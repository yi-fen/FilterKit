import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Root-owned durable ledger for APP activation commands. A corrupt, oversized, unsafe, or
/// inaccessible ledger is a hard failure; it is never treated as an empty ledger.
struct HelperAppPluginActivationTransactionLedgerStore {
    enum StoreError: Error, Equatable {
        case unsafeDirectory, unsafeFile, oversized, capacityReached, invalidData, duplicateCommand, recordMissing
        case identityMismatch, stateConflict, io(Int32)
    }

    static let leaf = ".filterkit-app-activation-ledger.json"
    private static let lock = NSLock()
    let directoryPath: String
    let maximumBytes: Int
    let maximumRecords: Int

    init(directoryPath: String, maximumBytes: Int = 512 * 1024, maximumRecords: Int = 512) throws {
        guard HelperPolicy.isAbsoluteCleanPath(directoryPath), directoryPath != "/" else {
            throw StoreError.unsafeDirectory
        }
        self.directoryPath = directoryPath
        self.maximumBytes = max(16 * 1024, maximumBytes)
        self.maximumRecords = max(1, min(maximumRecords, 2048))
    }

    func load() throws -> [HelperAppPluginActivationTransactionRecord] {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let processLock = try acquireProcessLock(); defer { _ = close(processLock) }
        let dir = try openDirectory(); defer { _ = close(dir) }
        let fd = Self.leaf.withCString { openat(dir, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        if fd < 0 { if errno == ENOENT { return [] }; throw StoreError.io(errno) }
        defer { _ = close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0,
              (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              st.st_uid == 0, st.st_gid == 0,
              (st.st_mode & 0o777) == 0o600,
              (st.st_mode & 0o6000) == 0 else { throw StoreError.unsafeFile }
        guard st.st_size >= 0, st.st_size <= maximumBytes else { throw StoreError.oversized }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw StoreError.io(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maximumBytes else { throw StoreError.oversized }
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([HelperAppPluginActivationTransactionRecord].self, from: data),
              validate(records) else { throw StoreError.invalidData }
        return records
    }

    /// Inserts the Executing row durably before the file transaction may begin.
    func insertExecuting(_ record: HelperAppPluginActivationTransactionRecord) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let processLock = try acquireProcessLock(); defer { _ = close(processLock) }
        try record.validate()
        guard record.state == .executing else { throw StoreError.invalidData }
        var records = try loadUnlocked()
        guard !records.contains(where: { $0.commandRequestID == record.commandRequestID || $0.transactionID == record.transactionID }) else {
            throw StoreError.duplicateCommand
        }
        guard records.count < maximumRecords else { throw StoreError.capacityReached }
        records.append(record)
        try saveUnlocked(records)
    }

    func transition(commandRequestID: UUID, pluginID: UUID, targetBundleIdentifier: String,
                    to state: HelperAppPluginActivationTransactionRecord.State,
                    now: Date = Date()) throws -> HelperAppPluginActivationTransactionRecord {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let processLock = try acquireProcessLock(); defer { _ = close(processLock) }
        var records = try loadUnlocked()
        guard let index = records.firstIndex(where: { $0.commandRequestID == commandRequestID }) else {
            throw StoreError.recordMissing
        }
        guard records[index].pluginID == pluginID,
              HelperBundleIdentifierKey.make(records[index].targetBundleIdentifier) == HelperBundleIdentifierKey.make(targetBundleIdentifier) else {
            throw StoreError.identityMismatch
        }
        try records[index].transition(to: state, now: now)
        try records[index].validate()
        try saveUnlocked(records)
        return records[index]
    }

    /// On Helper restart, an Executing row cannot be assumed committed or rolled back.
    /// Convert it to Outcome Unknown before serving status queries.
    func markInterruptedExecutionsUnknown(now: Date = Date()) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let processLock = try acquireProcessLock(); defer { _ = close(processLock) }
        var records = try loadUnlocked()
        var changed = false
        for index in records.indices where records[index].state == .executing {
            try records[index].transition(to: .outcomeUnknown, now: max(now, records[index].updatedAt))
            changed = true
        }
        if changed { try saveUnlocked(records) }
    }

    /// Resolve Outcome Unknown only when the transaction journal has already supplied
    /// a fully matched disposition and the observed hashes equal this exact ledger row.
    func resolveUnknown(commandRequestID: UUID, transactionID: UUID, pluginID: UUID,
                        targetBundleIdentifier: String,
                        disposition: HelperPluginFilterConfigurationTransaction.ActivationEvidenceDisposition,
                        observedPlistSHA256: String, observedManifestSHA256: String,
                        now: Date = Date()) throws -> HelperAppPluginActivationTransactionRecord {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let processLock = try acquireProcessLock(); defer { _ = close(processLock) }
        var records = try loadUnlocked()
        guard let index = records.firstIndex(where: { $0.commandRequestID == commandRequestID }) else {
            throw StoreError.recordMissing
        }
        let current = records[index]
        guard current.state == .outcomeUnknown, current.transactionID == transactionID,
              current.pluginID == pluginID,
              HelperBundleIdentifierKey.make(current.targetBundleIdentifier) == HelperBundleIdentifierKey.make(targetBundleIdentifier) else {
            throw StoreError.identityMismatch
        }
        let targetState: HelperAppPluginActivationTransactionRecord.State
        switch disposition {
        case .committed:
            guard observedPlistSHA256.caseInsensitiveCompare(current.filterAfterSHA256) == .orderedSame,
                  observedManifestSHA256.caseInsensitiveCompare(current.manifestAfterSHA256) == .orderedSame else {
                throw StoreError.stateConflict
            }
            targetState = .committed
        case .rolledBack:
            guard observedPlistSHA256.caseInsensitiveCompare(current.filterBeforeSHA256) == .orderedSame,
                  observedManifestSHA256.caseInsensitiveCompare(current.manifestBeforeSHA256) == .orderedSame else {
                throw StoreError.stateConflict
            }
            targetState = .rolledBack
        case .unknown:
            throw StoreError.stateConflict
        }
        try records[index].transition(to: targetState, now: max(now, records[index].updatedAt))
        try records[index].validate()
        try saveUnlocked(records)
        return records[index]
    }

    func record(commandRequestID: UUID, pluginID: UUID,
                targetBundleIdentifier: String) throws -> HelperAppPluginActivationTransactionRecord? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let processLock = try acquireProcessLock(); defer { _ = close(processLock) }
        let records = try loadUnlocked()
        guard let record = records.first(where: { $0.commandRequestID == commandRequestID }) else { return nil }
        guard record.pluginID == pluginID,
              HelperBundleIdentifierKey.make(record.targetBundleIdentifier) == HelperBundleIdentifierKey.make(targetBundleIdentifier) else {
            throw StoreError.identityMismatch
        }
        return record
    }

    /// Serializes Ledger read/modify/write operations across both threads and Helper
    /// processes. The lock file has a stable inode; locking the replaceable JSON Ledger
    /// itself would lose exclusion after atomic rename.
    private func acquireProcessLock() throws -> Int32 {
        let dir = try openDirectory(); defer { _ = close(dir) }
        let leaf = ".filterkit-app-activation-ledger.lock"
        var created = false
        var fd = leaf.withCString { openat(dir, $0, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        if fd >= 0 {
            created = true
        } else if errno == EEXIST {
            fd = leaf.withCString { openat(dir, $0, O_RDWR | O_NOFOLLOW | O_CLOEXEC) }
        }
        guard fd >= 0 else { throw StoreError.io(errno) }
        var st = stat()
        guard fstat(fd, &st) == 0,
              (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            _ = close(fd); throw StoreError.unsafeFile
        }
        if created {
            guard fchmod(fd, 0o600) == 0, fchown(fd, 0, 0) == 0, fsync(fd) == 0 else {
                let error = errno; _ = close(fd); throw StoreError.io(error)
            }
            guard fstat(fd, &st) == 0 else { let error = errno; _ = close(fd); throw StoreError.io(error) }
        }
        guard st.st_uid == 0, st.st_gid == 0,
              (st.st_mode & 0o777) == 0o600, (st.st_mode & 0o6000) == 0 else {
            _ = close(fd); throw StoreError.unsafeFile
        }
        guard flock(fd, LOCK_EX) == 0 else { let error = errno; _ = close(fd); throw StoreError.io(error) }
        return fd
    }

    private func loadUnlocked() throws -> [HelperAppPluginActivationTransactionRecord] {
        // The public load path takes the same process lock; this internal path is used while
        // already serialized by callers, but deliberately delegates to the same safe reader.
        let dir = try openDirectory(); defer { _ = close(dir) }
        let fd = Self.leaf.withCString { openat(dir, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        if fd < 0 { if errno == ENOENT { return [] }; throw StoreError.io(errno) }
        defer { _ = close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              st.st_uid == 0, st.st_gid == 0, (st.st_mode & 0o777) == 0o600,
              (st.st_mode & 0o6000) == 0 else { throw StoreError.unsafeFile }
        guard st.st_size >= 0, st.st_size <= maximumBytes else { throw StoreError.oversized }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw StoreError.io(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count)); guard data.count <= maximumBytes else { throw StoreError.oversized }
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([HelperAppPluginActivationTransactionRecord].self, from: data), validate(records) else {
            throw StoreError.invalidData
        }
        return records
    }

    private func saveUnlocked(_ records: [HelperAppPluginActivationTransactionRecord]) throws {
        guard validate(records) else { throw StoreError.invalidData }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(records); guard data.count <= maximumBytes else { throw StoreError.oversized }
        let dir = try openDirectory(); defer { _ = close(dir) }
        let temp = ".filterkit-app-activation-ledger-\(UUID().uuidString.lowercased()).tmp"
        let fd = temp.withCString { openat(dir, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard fd >= 0 else { throw StoreError.io(errno) }
        var keep = true
        defer { _ = close(fd); if keep { _ = temp.withCString { unlinkat(dir, $0, 0) } } }
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
        guard fchmod(fd, 0o600) == 0, fchown(fd, 0, 0) == 0, fsync(fd) == 0 else { throw StoreError.io(errno) }
        let renamed = temp.withCString { source in Self.leaf.withCString { destination in renameat(dir, source, dir, destination) } }
        guard renamed == 0, fsync(dir) == 0 else { throw StoreError.io(errno) }
        keep = false
    }

    private func validate(_ records: [HelperAppPluginActivationTransactionRecord]) -> Bool {
        guard records.count <= maximumRecords,
              Set(records.map(\.commandRequestID)).count == records.count,
              Set(records.map(\.transactionID)).count == records.count else { return false }
        return records.allSatisfy { (try? $0.validate()) != nil }
    }

    private func openDirectory() throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw StoreError.io(errno) }
        for component in directoryPath.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let error = errno; _ = close(fd); throw StoreError.io(error) }
            _ = close(fd); fd = next
        }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              st.st_uid == 0, st.st_gid == 0, (st.st_mode & 0o022) == 0 else {
            _ = close(fd); throw StoreError.unsafeDirectory
        }
        return fd
    }
}
