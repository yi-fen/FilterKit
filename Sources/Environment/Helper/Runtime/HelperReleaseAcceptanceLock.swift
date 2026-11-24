import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Shares the persistent activation lock inode with the multi-file installer. This serializes
/// release-generation acceptance against another Helper startup or a concurrent activation.
enum HelperReleaseAcceptanceLock {
    enum Failure: Error, Equatable { case unavailable(Int32), unsafeLock, busy(Int32) }

    static func withLock<T>(root: String, body: () throws -> T) throws -> T {
        #if canImport(Darwin)
        guard HelperPolicy.isAbsoluteCleanPath(root), root != "/" else { throw Failure.unsafeLock }
        var directoryFD = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directoryFD >= 0 else { throw Failure.unavailable(errno) }
        for component in root.split(separator: "/").map(String.init) {
            let next = component.withCString { Darwin.openat(directoryFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let code = errno; _ = Darwin.close(directoryFD); throw Failure.unavailable(code) }
            _ = Darwin.close(directoryFD)
            directoryFD = next
            var directoryInfo = stat()
            guard fstat(directoryFD, &directoryInfo) == 0,
                  (directoryInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  directoryInfo.st_uid == 0, directoryInfo.st_gid == 0,
                  (directoryInfo.st_mode & 0o022) == 0 else {
                _ = Darwin.close(directoryFD); throw Failure.unsafeLock
            }
        }
        defer { _ = Darwin.close(directoryFD) }
        let fd = ".filterkit-root-activation.lock".withCString {
            Darwin.openat(directoryFD, $0, O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard fd >= 0 else { throw Failure.unavailable(errno) }
        defer { _ = Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0, info.st_nlink == 1,
              (info.st_mode & 0o777) == 0o600 else { throw Failure.unsafeLock }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy(errno) }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
        #else
        throw Failure.unavailable(ENOTSUP)
        #endif
    }
}
