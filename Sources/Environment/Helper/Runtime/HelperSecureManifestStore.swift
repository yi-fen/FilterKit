import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Reads a root-owned 0600 JSON manifest without following symlinks in any path component.
/// This is intentionally read-only; the App process has no API for changing the manifest.
struct HelperSecureManifestStore {
    enum StoreError: Error, Equatable {
        case invalidPath, openFailed(Int32), metadataFailed(Int32), notRegularRootOwned0600
        case oversized, readFailed(Int32), invalidJSON, invalidManifest
    }

    let maximumBytes: Int
    init(maximumBytes: Int = 64 * 1024) { self.maximumBytes = max(1024, maximumBytes) }

    func read(path: String) throws -> HelperDeploymentManifest {
        let data = try readRootOwnedFile(path: path, requiredMode: 0o600)
        guard let manifest = try? JSONDecoder().decode(HelperDeploymentManifest.self, from: data) else {
            throw StoreError.invalidJSON
        }
        guard manifest.schemaVersion == HelperDeploymentManifest.currentSchemaVersion,
              HelperPolicy.isAbsoluteCleanPath(manifest.jbRootPath),
              HelperPolicy.isAbsoluteCleanPath(manifest.tweakInjectPath),
              HelperPolicy.isAbsoluteCleanPath(manifest.stagingRootPath),
              HelperPolicy.isAbsoluteCleanPath(manifest.socketPath),
              !manifest.routeIdentifier.isEmpty,
              !manifest.allowedAppCDHashes.isEmpty,
              !manifest.allowedHelperCDHashes.isEmpty,
              manifest.allowedAppCDHashes.allSatisfy(HelperPolicy.isValidCDHash),
              manifest.allowedHelperCDHashes.allSatisfy(HelperPolicy.isValidCDHash),
              !manifest.allowedClientUIDs.isEmpty,
              manifest.allowedClientUIDs.allSatisfy({ $0 != 0 }),
              Set(manifest.allowedClientUIDs).count == manifest.allowedClientUIDs.count else { throw StoreError.invalidManifest }
        return manifest
    }

    func readRootOwnedFile(path: String, requiredMode: mode_t, maximumBytes overrideMaximumBytes: Int? = nil) throws -> Data {
        guard path.hasPrefix("/"), !path.contains("\0"),
              path.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw StoreError.invalidPath
        }
        let components = path.split(separator: "/").map(String.init)
        guard let leaf = components.last else { throw StoreError.invalidPath }
        #if canImport(Darwin) || canImport(Glibc)
        let rootFD = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard rootFD >= 0 else { throw StoreError.openFailed(errno) }
        var directoryFD = rootFD
        defer { _ = close(directoryFD) }
        for component in components.dropLast() {
            let next = component.withCString { openat(directoryFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { throw StoreError.openFailed(errno) }
            if directoryFD != rootFD { _ = close(directoryFD) }
            directoryFD = next
        }
        var parentInfo = stat()
        guard fstat(directoryFD, &parentInfo) == 0,
              (parentInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              parentInfo.st_uid == 0, parentInfo.st_gid == 0,
              (parentInfo.st_mode & 0o022) == 0 else { throw StoreError.notRegularRootOwned0600 }
        let fileFD = leaf.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fileFD >= 0 else { throw StoreError.openFailed(errno) }
        defer { _ = close(fileFD) }
        var info = stat()
        guard fstat(fileFD, &info) == 0 else { throw StoreError.metadataFailed(errno) }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o777) == requiredMode else { throw StoreError.notRegularRootOwned0600 }
        let byteLimit = overrideMaximumBytes ?? maximumBytes
        guard byteLimit > 0, info.st_size >= 0, info.st_size <= byteLimit else { throw StoreError.oversized }
        var data = Data(count: Int(info.st_size))
        let readResult = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return raw.count == 0 }
            var offset = 0
            while offset < raw.count {
                #if canImport(Darwin)
                let count = Darwin.read(fileFD, base.advanced(by: offset), raw.count - offset)
                #elseif canImport(Glibc)
                let count = Glibc.read(fileFD, base.advanced(by: offset), raw.count - offset)
                #else
                let count = -1
                #endif
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard readResult else { throw StoreError.readFailed(errno) }
        return data
        #else
        throw StoreError.openFailed(ENOTSUP)
        #endif
    }
}
