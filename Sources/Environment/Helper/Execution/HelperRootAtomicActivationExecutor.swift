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
    enum Failure: Error, Equatable { case notRoot, unsafeRoot, unsafeParent, invalidRelease, conflict, journalExists, journalInvalid, hashMismatch, lockBusy, io(Int32), injectedCrash(Artifact), injectedFault(FaultPoint), recoveryRequiresManualIntervention }
    enum FaultPoint: String, CaseIterable { case afterPreparedJournal, afterFirstStage, afterFirstBackup, afterFirstActivation, afterFirstProgressJournal, afterCommittedJournal }
    struct Release {
        let bundle: HelperInstallerProvisioningBundle
        let bytes: [Artifact: Data]
        let expectedDigests: [HelperInstallerArtifactDigest]
        let expectedPreviousHashes: [Artifact: String?]
    }
    struct Result: Equatable { let transactionID: UUID; let installedHashes: [Artifact: String] }
    private struct Record: Codable {
        let schema: Int; let id: UUID; let names: [Artifact: String]
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

    func activate(_ release: Release, crashAfter: Artifact? = nil, faultAt: FaultPoint? = nil) throws -> Result {
        Self.lock.lock(); defer { Self.lock.unlock() }
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
        let id = UUID()
        let names = Dictionary(uniqueKeysWithValues: Artifact.allCases.map { ($0, destinations[$0]!) })
        var record = Record(schema: 1, id: id, names: names,
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
            if faultAt == .afterCommittedJournal { throw Failure.injectedFault(.afterCommittedJournal) }
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

    /// Recovery only rolls back a known, hash-matching transaction. Unknown bytes or ownership
    /// changes stop with manual intervention; it never starts launchd or enables the plist.
    func recover() throws -> Phase? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard geteuid() == 0 else { throw Failure.notRoot }
        let rootFD = try openRoot(); defer { _ = close(rootFD) }
        let lockFD = try acquireTransactionLock(rootFD); defer { _ = flock(lockFD, LOCK_UN); _ = close(lockFD) }
        guard var record = try readRecord(rootFD) else { return nil }
        guard record.schema == 1, record.names == destinations,
              Set(record.newHashes.keys) == Set(Artifact.allCases),
              Set(record.oldHashes.keys) == Set(Artifact.allCases),
              record.newHashes.values.allSatisfy(HelperPolicy.isValidHash),
              record.oldHashes.values.compactMap({ $0 }).allSatisfy(HelperPolicy.isValidHash),
              Set(record.completed).count == record.completed.count,
              record.completed.allSatisfy({ Artifact.allCases.contains($0) }) else { throw Failure.journalInvalid }
        if record.phase == .manualIntervention { throw Failure.recoveryRequiresManualIntervention }
        if record.phase == .committed {
            for item in Artifact.allCases {
                let (parent, _) = try openParent(item, rootFD: rootFD); defer { _ = close(parent) }
                guard try hashAt(parent, destinations[item]!) == record.newHashes[item] else { throw Failure.recoveryRequiresManualIntervention }
                let backupHash = try hashAt(parent, backupName(record.id, item))
                guard backupHash == record.oldHashes[item]! else { throw Failure.recoveryRequiresManualIntervention }
                _ = backupName(record.id, item).withCString { unlinkat(parent, $0, 0) }
                _ = tempName(record.id, item).withCString { unlinkat(parent, $0, 0) }
                guard fsync(parent) == 0 else { throw Failure.io(errno) }
            }
            try clearRecord(rootFD); return .committed
        }
        if record.phase == .rolledBack { try clearRecord(rootFD); return .rolledBack }
        record.phase = .rollingBack; try writeRecord(record, rootFD: rootFD)
        for item in Artifact.allCases.reversed() {
            let (parent, leaf) = try openParent(item, rootFD: rootFD); defer { _ = close(parent) }
            let current = try hashAt(parent, leaf)
            let backup = backupName(record.id, item)
            let backupHash = try hashAt(parent, backup)
            let newHash = record.newHashes[item]!
            let oldHash = record.oldHashes[item]!
            if let current, current != newHash && current != oldHash { record.phase = .manualIntervention; try writeRecord(record, rootFD: rootFD); throw Failure.recoveryRequiresManualIntervention }
            if let backupHash, backupHash != oldHash { record.phase = .manualIntervention; try writeRecord(record, rootFD: rootFD); throw Failure.recoveryRequiresManualIntervention }
            if current == newHash { _ = leaf.withCString { unlinkat(parent, $0, 0) } }
            if let oldHash {
                if backupHash == oldHash {
                    guard (try hashAt(parent, leaf)) == nil else { throw Failure.recoveryRequiresManualIntervention }
                    try renameNoReplace(parent, backup, leaf)
                } else if current != oldHash { throw Failure.recoveryRequiresManualIntervention }
            } else if backupHash != nil { throw Failure.recoveryRequiresManualIntervention }
            _ = tempName(record.id, item).withCString { unlinkat(parent, $0, 0) }
            guard fsync(parent) == 0 else { throw Failure.io(errno) }
        }
        record.phase = .rolledBack; try writeRecord(record, rootFD: rootFD)
        try clearRecord(rootFD)
        return .rolledBack
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
