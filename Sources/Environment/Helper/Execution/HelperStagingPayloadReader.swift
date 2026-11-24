import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Reads only regular, non-symlink files below a fixed staging root. No IPC path is ever
/// interpreted as an absolute path; every component is opened relative to an already-open fd.
struct HelperStagingPayloadReader {
    enum ReaderError: Error, Equatable { case invalidPath, unsafeRoot, unsafeComponent, unsafeFile, oversized, readFailed(Int32) }
    let rootPath: String
    let expectedOwner: UInt32
    let maximumBytes: Int

    init(rootPath: String, expectedOwner: UInt32, maximumBytes: Int = 64 * 1024 * 1024) throws {
        guard HelperPolicy.isAbsoluteCleanPath(rootPath), rootPath != "/" else { throw ReaderError.invalidPath }
        self.rootPath = rootPath
        self.expectedOwner = expectedOwner
        self.maximumBytes = max(1, maximumBytes)
    }

    func read(relativePath: String) throws -> Data {
        guard HelperPolicy.isSafeRelativePath(relativePath) else { throw ReaderError.invalidPath }
        let rootFD = try openAbsoluteDirectory(rootPath)
        defer { _ = close(rootFD) }
        var rootInfo = stat()
        guard fstat(rootFD, &rootInfo) == 0,
              (rootInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              rootInfo.st_uid == expectedOwner,
              (rootInfo.st_mode & 0o077) == 0 else { throw ReaderError.unsafeRoot }

        let components = relativePath.split(separator: "/").map(String.init)
        guard let leaf = components.last else { throw ReaderError.invalidPath }
        var directoryFD = dup(rootFD)
        guard directoryFD >= 0 else { throw ReaderError.unsafeComponent }
        defer { _ = close(directoryFD) }
        for component in components.dropLast() {
            let next = component.withCString { openat(directoryFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { throw ReaderError.unsafeComponent }
            _ = close(directoryFD)
            directoryFD = next
            var info = stat()
            guard fstat(directoryFD, &info) == 0,
                  (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  info.st_uid == expectedOwner, (info.st_mode & 0o077) == 0 else {
                throw ReaderError.unsafeComponent
            }
        }
        let fileFD = leaf.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fileFD >= 0 else { throw ReaderError.unsafeFile }
        defer { _ = close(fileFD) }
        var info = stat()
        guard fstat(fileFD, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == expectedOwner, (info.st_mode & 0o077) == 0,
              (info.st_mode & 0o6000) == 0,
              info.st_size >= 0, info.st_size <= maximumBytes else { throw ReaderError.unsafeFile }
        var data = Data(); data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count: Int
            #if canImport(Darwin)
            count = Darwin.read(fileFD, &buffer, buffer.count)
            #elseif canImport(Glibc)
            count = Glibc.read(fileFD, &buffer, buffer.count)
            #else
            count = -1
            #endif
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw ReaderError.readFailed(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maximumBytes else { throw ReaderError.oversized }
        }
        return data
    }

    private func openAbsoluteDirectory(_ path: String) throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ReaderError.unsafeRoot }
        for component in path.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { _ = close(fd); throw ReaderError.unsafeRoot }
            _ = close(fd); fd = next
        }
        return fd
    }
}
