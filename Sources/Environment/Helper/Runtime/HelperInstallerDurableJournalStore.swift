import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Durable journal storage for a pre-created, root-owned 0700 directory.
/// It never creates/chowns/chmods the directory and exposes no install/launchd operations.
struct HelperInstallerDurableJournalStore {
    enum StoreError: Error, Equatable {
        case invalidDirectory, openFailed(Int32), unsafeDirectory, unsafeJournal
        case encodeFailed, writeFailed(Int32), syncFailed(Int32), renameFailed(Int32)
        case readFailed(Int32), oversized, decodeFailed, journalInvalid
    }

    private let directoryPath: String
    private let maximumBytes: Int

    init(directoryPath: String, maximumBytes: Int = 1_048_576) {
        self.directoryPath = directoryPath
        self.maximumBytes = max(4096, maximumBytes)
    }

    func save(_ journal: HelperInstallerTransactionJournal) throws {
        do { try journal.validateChain() } catch { throw StoreError.journalInvalid }
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(journal)
        } catch { throw StoreError.encodeFailed }
        guard data.count <= maximumBytes else { throw StoreError.oversized }

        let directoryFD = try openVerifiedDirectory()
        defer { _ = close(directoryFD) }
        let finalName = journal.transactionID.uuidString.lowercased() + ".json"
        let temporaryName = "." + finalName + "." + UUID().uuidString.lowercased() + ".tmp"
        let fd = temporaryName.withCString {
            openat(directoryFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        }
        guard fd >= 0 else { throw StoreError.openFailed(errno) }
        var keepTemporary = true
        defer {
            _ = close(fd)
            if keepTemporary { _ = temporaryName.withCString { unlinkat(directoryFD, $0, 0) } }
        }
        try writeAll(data, to: fd)
        guard fsync(fd) == 0 else { throw StoreError.syncFailed(errno) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o777) == 0o600 else { throw StoreError.unsafeJournal }
        let renameResult = temporaryName.withCString { source in
            finalName.withCString { destination in renameat(directoryFD, source, directoryFD, destination) }
        }
        guard renameResult == 0 else { throw StoreError.renameFailed(errno) }
        keepTemporary = false
        guard fsync(directoryFD) == 0 else { throw StoreError.syncFailed(errno) }
    }

    func load(transactionID: UUID) throws -> HelperInstallerTransactionJournal {
        let directoryFD = try openVerifiedDirectory()
        defer { _ = close(directoryFD) }
        let name = transactionID.uuidString.lowercased() + ".json"
        let fd = name.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw StoreError.openFailed(errno) }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o777) == 0o600 else { throw StoreError.unsafeJournal }
        guard info.st_size >= 0, info.st_size <= maximumBytes else { throw StoreError.oversized }
        var data = Data(); data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            #if canImport(Darwin)
            let count = Darwin.read(fd, &buffer, buffer.count)
            #elseif canImport(Glibc)
            let count = Glibc.read(fd, &buffer, buffer.count)
            #else
            let count = -1
            #endif
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw StoreError.readFailed(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer[0..<count])
            guard data.count <= maximumBytes else { throw StoreError.oversized }
        }
        let journal: HelperInstallerTransactionJournal
        do { journal = try JSONDecoder().decode(HelperInstallerTransactionJournal.self, from: data) }
        catch { throw StoreError.decodeFailed }
        guard journal.transactionID == transactionID else { throw StoreError.journalInvalid }
        do { try journal.validateChain() } catch { throw StoreError.journalInvalid }
        return journal
    }

    private func openVerifiedDirectory() throws -> Int32 {
        guard directoryPath.hasPrefix("/"), !directoryPath.contains("\0"),
              directoryPath.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw StoreError.invalidDirectory
        }
        let parts = directoryPath.split(separator: "/").map(String.init)
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw StoreError.openFailed(errno) }
        for part in parts {
            let next = part.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let code = errno; _ = close(fd); throw StoreError.openFailed(code) }
            _ = close(fd); fd = next
        }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o777) == 0o700 else {
            _ = close(fd); throw StoreError.unsafeDirectory
        }
        return fd
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                #if canImport(Darwin)
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                #elseif canImport(Glibc)
                let count = Glibc.write(fd, base.advanced(by: offset), raw.count - offset)
                #else
                let count = -1
                #endif
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw StoreError.writeFailed(errno) }
                offset += count
            }
        }
    }
}
