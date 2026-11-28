import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Atomic writer for the non-authoritative active-release hint. Caller must hold the shared
/// installer acceptance lock and must independently verify the active artifacts immediately before.
/// This writer does not install/activate artifacts and is not wired into production recovery.
struct HelperInstallerActiveReleasePointerWriter {
    enum FaultPoint { case beforeRename }
    enum WriterError: Error, Equatable { case invalidRoot, unsafeDirectory, unsafeExistingPointer, io(Int32), invalidRelease }
    private let jbRootPath: String
    init(jbRootPath: String) { self.jbRootPath = jbRootPath }

    func write(transactionID: UUID,
               release: HelperRootReleaseSet.Verified,
               observedActiveHashes: [HelperRootReleaseSet.Artifact: String],
               faultAt: FaultPoint? = nil) throws {
        guard release.generation > 0, !release.releaseIdentifier.isEmpty,
              Set(release.hashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
              release.hashes == observedActiveHashes,
              release.hashes.values.allSatisfy(HelperPolicy.isValidHash) else { throw WriterError.invalidRelease }
        let rootFD = try openRoot(); defer { _ = close(rootFD) }
        let parentFD = try openDirectory("Library/FilterKit/Helper", from: rootFD)
        defer { _ = close(parentFD) }
        let leaf = "active-release.json"
        var existing = stat()
        let statResult = leaf.withCString { fstatat(parentFD, $0, &existing, AT_SYMLINK_NOFOLLOW) }
        if statResult == 0 {
            guard (existing.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), existing.st_uid == 0,
                  existing.st_nlink == 1, (existing.st_mode & 0o777) == 0o600 else { throw WriterError.unsafeExistingPointer }
        } else if errno != ENOENT { throw WriterError.io(errno) }

        let pointer = HelperInstallerDescriptorFilesystemObserver.ReleasePointer(
            schemaVersion: 2, transactionID: transactionID,
            releaseIdentifier: release.releaseIdentifier, generation: release.generation,
            artifactHashes: ["executable": release.hashes[.executable]!,
                             "deploymentManifest": release.hashes[.deploymentManifest]!,
                             "launchDaemon": release.hashes[.launchDaemon]!])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(pointer)
        let temporary = ".active-release-\(UUID().uuidString.lowercased()).tmp"
        let fd = temporary.withCString { openat(parentFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard fd >= 0 else { throw WriterError.io(errno) }
        var keepTemporary = true
        defer {
            _ = close(fd)
            if keepTemporary { _ = temporary.withCString { unlinkat(parentFD, $0, 0) } }
        }
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                #if canImport(Darwin)
                return Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                #elseif canImport(Glibc)
                return Glibc.write(fd, base.advanced(by: offset), bytes.count - offset)
                #else
                return -1
                #endif
            }
            if written < 0 && errno == EINTR { continue }
            guard written > 0 else { throw WriterError.io(errno) }
            offset += written
        }
        guard fchmod(fd, 0o600) == 0, fsync(fd) == 0 else { throw WriterError.io(errno) }
        var writtenInfo = stat()
        guard fstat(fd, &writtenInfo) == 0, (writtenInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              writtenInfo.st_uid == 0, writtenInfo.st_nlink == 1, (writtenInfo.st_mode & 0o777) == 0o600 else {
            throw WriterError.unsafeExistingPointer
        }
        if faultAt == .beforeRename { throw WriterError.io(EIO) }
        guard temporary.withCString({ temp in leaf.withCString { destination in renameat(parentFD, temp, parentFD, destination) } }) == 0,
              fsync(parentFD) == 0 else { throw WriterError.io(errno) }
        keepTemporary = false
    }

    private func openRoot() throws -> Int32 {
        guard jbRootPath.hasPrefix("/"), jbRootPath != "/", !jbRootPath.contains("\0") else { throw WriterError.invalidRoot }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw WriterError.io(errno) }
        for component in jbRootPath.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            _ = close(fd)
            guard next >= 0 else { throw WriterError.unsafeDirectory }
            var info = stat()
            guard fstat(next, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  info.st_uid == 0, (info.st_mode & 0o022) == 0 || (info.st_mode & mode_t(S_ISVTX)) != 0 else {
                _ = close(next); throw WriterError.unsafeDirectory
            }
            fd = next
        }
        var finalInfo = stat()
        guard fstat(fd, &finalInfo) == 0, finalInfo.st_uid == 0, (finalInfo.st_mode & 0o022) == 0 else {
            _ = close(fd); throw WriterError.unsafeDirectory
        }
        return fd
    }

    private func openDirectory(_ path: String, from rootFD: Int32) throws -> Int32 {
        var fd = dup(rootFD); guard fd >= 0 else { throw WriterError.io(errno) }
        for component in path.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            _ = close(fd)
            guard next >= 0 else { throw WriterError.unsafeDirectory }
            var info = stat()
            guard fstat(next, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  info.st_uid == 0, (info.st_mode & 0o022) == 0 else {
                _ = close(next); throw WriterError.unsafeDirectory
            }
            fd = next
        }
        return fd
    }
}
