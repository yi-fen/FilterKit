import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Root-owned durable replay ledger for deployment batches. The store is deliberately
/// single-file and bounded; callers must place it in a dedicated root-owned directory.
/// A corrupt or inaccessible ledger is a hard failure, never an empty-ledger fallback.
struct HelperDeploymentDurableLedgerStore {
    enum StoreError: Error, Equatable { case unsafeDirectory, unsafeFile, oversized, invalidData, io(Int32) }
    struct Record: Codable, Equatable {
        enum State: String, Codable { case inProgress, completed, indeterminate, rolledBack }
        let batchID: UUID
        let digest: String
        let requestIDs: [UUID]
        var transactionID: UUID?
        var state: State
        var updatedAt: Date
    }
    static let leaf = ".filterkit-deployment-ledger.json"
    let directoryPath: String
    let maximumBytes: Int
    init(directoryPath: String, maximumBytes: Int = 256 * 1024) throws {
        guard HelperPolicy.isAbsoluteCleanPath(directoryPath), directoryPath != "/" else { throw StoreError.unsafeDirectory }
        self.directoryPath = directoryPath
        self.maximumBytes = max(4096, maximumBytes)
    }

    func load() throws -> [Record] {
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
            let n = read(fd, &buffer, buffer.count)
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw StoreError.io(errno) }
            if n == 0 { break }
            data.append(contentsOf: buffer.prefix(n)); guard data.count <= maximumBytes else { throw StoreError.oversized }
        }
        guard let records = try? JSONDecoder().decode([Record].self, from: data), validate(records) else { throw StoreError.invalidData }
        return records
    }

    func save(_ records: [Record]) throws {
        guard validate(records) else { throw StoreError.invalidData }
        let data = try JSONEncoder().encode(records); guard data.count <= maximumBytes else { throw StoreError.oversized }
        let dir = try openDirectory(); defer { _ = close(dir) }
        let temp = ".filterkit-ledger-\(UUID().uuidString.lowercased()).tmp"
        let fd = temp.withCString { openat(dir, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard fd >= 0 else { throw StoreError.io(errno) }
        var keep = true
        defer { _ = close(fd); if keep { _ = temp.withCString { unlinkat(dir, $0, 0) } } }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let n = write(fd, base.advanced(by: offset), raw.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw StoreError.io(errno) }; offset += n
            }
        }
        guard fchmod(fd, 0o600) == 0, fchown(fd, 0, 0) == 0, fsync(fd) == 0 else { throw StoreError.io(errno) }
        let result = temp.withCString { t in Self.leaf.withCString { dst in renameat(dir, t, dir, dst) } }
        guard result == 0, fsync(dir) == 0 else { throw StoreError.io(errno) }
        keep = false
    }



    enum RecoveryFinalization: Equatable { case committed, rolledBack }
    enum RecoveryFinalizationError: Error, Equatable {
        case bindingInvalid, recordMissing, identityMismatch, stateConflict
    }

    /// Finalizes a recovered transaction only after the caller has verified the matching
    /// transaction journal and completed the filesystem reconciliation. This method never
    /// creates a missing ledger row and never changes a completed row to another state.
    func finalizeRecovered(binding: HelperDeploymentTransactionBinding,
                           disposition: RecoveryFinalization) throws {
        guard binding.validate() else { throw RecoveryFinalizationError.bindingInvalid }
        var records = try load()
        guard let index = records.firstIndex(where: { $0.batchID == binding.batchID }) else {
            throw RecoveryFinalizationError.recordMissing
        }
        var record = records[index]
        guard record.digest.caseInsensitiveCompare(binding.batchDigest) == .orderedSame,
              record.transactionID == binding.transactionID,
              Set(record.requestIDs) == Set(binding.requestIDs) else {
            throw RecoveryFinalizationError.identityMismatch
        }
        let target: Record.State = disposition == .committed ? .completed : .rolledBack
        if record.state == target { return } // idempotent retry after ledger fsync succeeded
        guard record.state == .inProgress || record.state == .indeterminate else {
            throw RecoveryFinalizationError.stateConflict
        }
        record.state = target
        record.updatedAt = Date()
        records[index] = record
        try save(records)
    }

    private func validate(_ records: [Record]) -> Bool {
        guard records.count <= 256, Set(records.map(\.batchID)).count == records.count else { return false }
        var owners = Set<UUID>()
        for r in records {
            guard HelperPolicy.isValidHash(r.digest), !r.requestIDs.isEmpty,
                  Set(r.requestIDs).count == r.requestIDs.count,
                  r.requestIDs.allSatisfy({ owners.insert($0).inserted }) else { return false }
        }
        return true
    }
    private func openDirectory() throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw StoreError.io(errno) }
        for component in directoryPath.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let e = errno; _ = close(fd); throw StoreError.io(e) }
            _ = close(fd); fd = next
        }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              st.st_uid == 0, st.st_gid == 0, (st.st_mode & 0o022) == 0 else { _ = close(fd); throw StoreError.unsafeDirectory }
        return fd
    }
}
