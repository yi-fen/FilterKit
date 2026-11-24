import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Root-owned JSONL audit sink. It refuses symlinks, non-regular files, foreign owners,
/// and files whose mode is not exactly 0600. It never logs request payload/file contents.
final class HelperAuditFileSink: HelperAuditSink {
    enum SinkError: Error { case invalidPath, openFailed(Int32), unsafeFile, writeFailed(Int32), rotationFailed(Int32) }
    private let path: String
    private let maximumBytes: Int
    private let retainedFiles: Int
    private let lock = NSLock()

    init(path: String, maximumBytes: Int = 1_048_576, retainedFiles: Int = 3) {
        self.path = path
        self.maximumBytes = max(4096, maximumBytes)
        self.retainedFiles = max(1, min(8, retainedFiles))
    }

    func append(_ record: HelperAuditRecord) throws {
        lock.lock(); defer { lock.unlock() }
        let (directoryFD, leaf) = try openParentDirectory()
        defer { _ = close(directoryFD) }
        let fd = leaf.withCString { openat(directoryFD, $0, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard fd >= 0 else { throw SinkError.openFailed(errno) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o777) == 0o600 else { _ = close(fd); throw SinkError.unsafeFile }
        if info.st_size >= maximumBytes {
            _ = close(fd)
            try rotate(directoryFD: directoryFD, leaf: leaf)
            let rotatedFD = leaf.withCString { openat(directoryFD, $0, O_WRONLY | O_APPEND | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
            guard rotatedFD >= 0 else { throw SinkError.openFailed(errno) }
            defer { _ = close(rotatedFD) }
            try write(record, to: rotatedFD)
        } else {
            defer { _ = close(fd) }
            try write(record, to: fd)
        }
    }

    private func write(_ record: HelperAuditRecord, to fd: Int32) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(record); data.append(0x0A)
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
                guard count > 0 else { throw SinkError.writeFailed(errno) }
                offset += count
            }
        }
    }

    private func openParentDirectory() throws -> (Int32, String) {
        guard path.hasPrefix("/"), !path.contains("\0"),
              path.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }) else { throw SinkError.invalidPath }
        let parts = path.split(separator: "/").map(String.init)
        guard let leaf = parts.last else { throw SinkError.invalidPath }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw SinkError.openFailed(errno) }
        for part in parts.dropLast() {
            let next = part.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let code = errno; _ = close(fd); throw SinkError.openFailed(code) }
            _ = close(fd); fd = next
        }
        var directoryInfo = stat()
        guard fstat(fd, &directoryInfo) == 0, directoryInfo.st_uid == 0,
              directoryInfo.st_gid == 0,
              (directoryInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              (directoryInfo.st_mode & 0o022) == 0 else { _ = close(fd); throw SinkError.unsafeFile }
        return (fd, leaf)
    }

    private func rotate(directoryFD: Int32, leaf: String) throws {
        // Existing rotation targets must themselves be root-owned regular files; symlinks are refused.
        for index in stride(from: retainedFiles - 1, through: 1, by: -1) {
            let source = "\(leaf).\(index)"
            let destination = "\(leaf).\(index + 1)"
            try validateRotationTarget(directoryFD, source, allowMissing: true)
            try validateRotationTarget(directoryFD, destination, allowMissing: true)
            var sourceInfo = stat()
            if source.withCString({ fstatat(directoryFD, $0, &sourceInfo, AT_SYMLINK_NOFOLLOW) }) == 0 {
                let result = source.withCString { src in destination.withCString { dst in renameat(directoryFD, src, directoryFD, dst) } }
                guard result == 0 else { throw SinkError.rotationFailed(errno) }
            }
        }
        try validateRotationTarget(directoryFD, leaf)
        let result = leaf.withCString { source in "\(leaf).1".withCString { destination in renameat(directoryFD, source, directoryFD, destination) } }
        guard result == 0 else { throw SinkError.rotationFailed(errno) }
    }

    private func validateRotationTarget(_ directoryFD: Int32, _ name: String, allowMissing: Bool = false) throws {
        var info = stat()
        let result = name.withCString { fstatat(directoryFD, $0, &info, AT_SYMLINK_NOFOLLOW) }
        if result != 0 {
            if allowMissing && errno == ENOENT { return }
            if errno == ENOENT { return }
            throw SinkError.rotationFailed(errno)
        }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_uid == 0,
              (info.st_mode & 0o777) == 0o600 else { throw SinkError.unsafeFile }
    }
}
