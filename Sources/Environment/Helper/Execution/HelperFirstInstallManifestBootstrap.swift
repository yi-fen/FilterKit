import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Root-side bootstrap for a first deployment. Callers must pass the authenticated socket
/// context produced by the transport after kernel peer and CDHash verification.
/// This type is intentionally not reachable from the App target's IPC payload decoder.
struct HelperFirstInstallManifestBootstrap {
    enum BootstrapError: Error, Equatable {
        case notRoot, unauthenticatedPeer, invalidRequest, invalidPayload
        case packageOwnershipNotVerified, unsafeDirectory, targetPayloadMismatch
        case manifestAlreadyExists, writeFailed(Int32)
    }

    func createManifest(directoryPath: String,
                        context: HelperAuthenticatedPeerContext,
                        requestID: UUID,
                        pluginID: UUID,
                        dylibFileName: String,
                        plistFileName: String,
                        hardBoundBundleIdentifier: String,
                        softAssociations: [FilterKitManifestSoftAssociation],
                        dylibBytes: Data,
                        plistBytes: Data,
                        packageOwnership: HelperPackageOwnershipProof) throws -> HelperOwnershipProof {
        guard geteuid() == 0 else { throw BootstrapError.notRoot }
        guard context.peer.uid == context.identity.uid,
              context.peer.gid == context.identity.gid,
              context.peer.pid == context.identity.pid,
              context.identity.pid > 0,
              context.identity.cdHashHex.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil,
              context.sessionNonce.range(of: "^[0-9a-fA-F]{32,128}$", options: .regularExpression) != nil,
              abs(Date().timeIntervalSince(context.authenticatedAt)) <= 120 else {
            throw BootstrapError.unauthenticatedPeer
        }
        guard requestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              HelperPolicy.isSafeLeafName(dylibFileName), dylibFileName.lowercased().hasSuffix(".dylib"),
              HelperPolicy.isSafeLeafName(plistFileName), plistFileName.lowercased().hasSuffix(".plist"),
              String(dylibFileName.dropLast(6)).lowercased() == String(plistFileName.dropLast(6)).lowercased(),
              Self.validBundleID(hardBoundBundleIdentifier),
              HelperBundleIdentifierKey.set(softAssociations.map(\.bundleIdentifier)).count == softAssociations.count,
              !softAssociations.contains(where: {
                  HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(hardBoundBundleIdentifier)
              }),
              softAssociations.allSatisfy({ Self.validBundleID($0.bundleIdentifier) }),
              dylibBytes.count > 0, dylibBytes.count <= 64 * 1024 * 1024,
              plistBytes.count > 0, plistBytes.count <= 4 * 1024 * 1024 else {
            throw BootstrapError.invalidRequest
        }
        guard packageOwnership.validates(directory: directoryPath, fileNames: [dylibFileName, plistFileName]) else {
            throw BootstrapError.packageOwnershipNotVerified
        }
        guard (try? PropertyListSerialization.propertyList(from: plistBytes, options: [], format: nil)) != nil else {
            throw BootstrapError.invalidPayload
        }
        let slices: [MachOSliceMetadata]
        do { slices = try MachOMetadataReader().readSlices(data: dylibBytes) }
        catch { throw BootstrapError.invalidPayload }
        guard let identity = PluginIdentityFingerprint.make(slices: slices),
              HelperPolicy.isValidHash(identity) else { throw BootstrapError.invalidPayload }

        let directoryFD = try openRootDirectory(directoryPath)
        defer { _ = close(directoryFD) }
        try validateDirectory(directoryFD)
        try requireAbsent(directoryFD, dylibFileName)
        try requireAbsent(directoryFD, plistFileName)
        let manifest: FilterKitPluginManifest
        do {
            manifest = try PluginFirstInstallBindingPolicy.makeManifest(
                pluginID: pluginID, dylibFileName: dylibFileName, plistFileName: plistFileName,
                dylibSHA256: SHA256Digest.hex(dylibBytes), plistSHA256: SHA256Digest.hex(plistBytes),
                machOIdentitySHA256: identity, fixedOwnerBundleIdentifier: hardBoundBundleIdentifier,
                additionalAssociations: softAssociations, filterPlistData: plistBytes)
        } catch { throw BootstrapError.invalidPayload }
        let data = try JSONEncoder().encode(manifest)
        let manifestLeaf = String(dylibFileName.dropLast(6)) + ".fk.json"
        guard HelperPolicy.isSafeLeafName(manifestLeaf) else { throw BootstrapError.invalidRequest }
        let fd = manifestLeaf.withCString { openat(directoryFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        if fd < 0 {
            if errno != EEXIST { throw BootstrapError.writeFailed(errno) }
            let existing = try readManifest(directoryFD, leaf: manifestLeaf)
            guard let existingManifest = try? JSONDecoder().decode(FilterKitPluginManifest.self, from: existing),
                  existingManifest == manifest else { throw BootstrapError.manifestAlreadyExists }
            return try makeProof(pluginID: pluginID, dylibFileName: dylibFileName, plistFileName: plistFileName,
                dylibHash: SHA256Digest.hex(dylibBytes), plistHash: SHA256Digest.hex(plistBytes), manifestData: existing)
        }
        var success = false
        defer { _ = close(fd); if !success { _ = manifestLeaf.withCString { unlinkat(directoryFD, $0, 0) }; _ = fsync(directoryFD) } }
        try writeAll(data, fd: fd)
        guard fchmod(fd, 0o600) == 0, fchown(fd, 0, 0) == 0, fsync(fd) == 0 else {
            throw BootstrapError.writeFailed(errno)
        }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o777) == 0o600,
              fsync(directoryFD) == 0 else { throw BootstrapError.writeFailed(errno) }
        success = true
        return try makeProof(pluginID: pluginID, dylibFileName: dylibFileName, plistFileName: plistFileName,
            dylibHash: SHA256Digest.hex(dylibBytes), plistHash: SHA256Digest.hex(plistBytes), manifestData: data)
    }

    private func makeProof(pluginID: UUID, dylibFileName: String, plistFileName: String,
                           dylibHash: String, plistHash: String, manifestData: Data) throws -> HelperOwnershipProof {
        try HelperOwnershipProof(pluginID: pluginID, dylibFileName: dylibFileName, plistFileName: plistFileName,
            dylibSHA256: dylibHash, plistSHA256: plistHash, manifestSchemaVersion: 4,
            manifestSHA256: SHA256Digest.hex(manifestData), binaryIdentityVerified: true,
            isFirstInstallAuthorization: true)
    }

    private func readManifest(_ directoryFD: Int32, leaf: String) throws -> Data {
        let fd = leaf.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw BootstrapError.manifestAlreadyExists }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o777) == 0o600,
              info.st_size >= 0, info.st_size <= 64 * 1024 else { throw BootstrapError.manifestAlreadyExists }
        var data = Data(); data.reserveCapacity(Int(info.st_size)); var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw BootstrapError.manifestAlreadyExists }
            if n == 0 { break }
            data.append(contentsOf: buffer.prefix(n))
            guard data.count <= 64 * 1024 else { throw BootstrapError.manifestAlreadyExists }
        }
        return data
    }

    private func requireAbsent(_ directoryFD: Int32, _ leaf: String) throws {
        var info = stat()
        let result = leaf.withCString { fstatat(directoryFD, $0, &info, AT_SYMLINK_NOFOLLOW) }
        guard result != 0 && errno == ENOENT else { throw BootstrapError.targetPayloadMismatch }
    }

    private static func validBundleID(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty && $0.first!.isLetter && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
    }

    private func openRootDirectory(_ path: String) throws -> Int32 {
        guard HelperPolicy.isAbsoluteCleanPath(path), path != "/" else { throw BootstrapError.unsafeDirectory }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw BootstrapError.unsafeDirectory }
        for component in path.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { _ = close(fd); throw BootstrapError.unsafeDirectory }
            _ = close(fd); fd = next
        }
        return fd
    }

    private func validateDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o022) == 0 else {
            throw BootstrapError.unsafeDirectory
        }
    }

    private func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let n = write(fd, base.advanced(by: offset), raw.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw BootstrapError.writeFailed(errno) }
                offset += n
            }
        }
    }
}
