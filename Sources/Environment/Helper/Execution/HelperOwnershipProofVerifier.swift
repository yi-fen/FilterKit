import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Reconstructs ownership evidence from the deployed root-owned manifest and the exact
/// deployed payloads. It never trusts hashes or metadata supplied by the App process.
struct HelperOwnershipProofVerifier {
    enum VerificationError: Error, Equatable {
        case invalidPath, unsafeDirectory, unsafeFile, oversized, readFailed
        case invalidManifest, unsupportedSchema, pluginIdentityMismatch
        case payloadHashMismatch, binaryIdentityMismatch, packageOwnershipConflict, ownershipEvidenceUnavailable
    }

    enum PackageOwnershipEvidence: Equatable {
        case verifiedUnowned
        case packageOwned
        case conflictingOwners
        case unavailable
    }

    let maximumManifestBytes: Int
    let maximumPluginBytes: Int

    init(maximumManifestBytes: Int = 64 * 1024, maximumPluginBytes: Int = 64 * 1024 * 1024) {
        self.maximumManifestBytes = max(1024, maximumManifestBytes)
        self.maximumPluginBytes = max(1, maximumPluginBytes)
    }

    func verify(pluginDirectory: String, dylibFileName: String, plistFileName: String,
                manifestFileName: String, packageOwnership: PackageOwnershipEvidence) throws -> HelperOwnershipProof {
        switch packageOwnership {
        case .verifiedUnowned: break
        case .packageOwned, .conflictingOwners: throw VerificationError.packageOwnershipConflict
        case .unavailable: throw VerificationError.ownershipEvidenceUnavailable
        }
        guard HelperPolicy.isAbsoluteCleanPath(pluginDirectory), pluginDirectory != "/",
              HelperPolicy.isSafeLeafName(dylibFileName), dylibFileName.lowercased().hasSuffix(".dylib"),
              HelperPolicy.isSafeLeafName(plistFileName), plistFileName.lowercased().hasSuffix(".plist"),
              HelperPolicy.isSafeLeafName(manifestFileName), manifestFileName.lowercased().hasSuffix(".fk.json"),
              String(dylibFileName.dropLast(6)).lowercased() == String(plistFileName.dropLast(6)).lowercased(),
              String(dylibFileName.dropLast(6)).lowercased() == String(manifestFileName.dropLast(8)).lowercased() else {
            throw VerificationError.invalidPath
        }
        let directoryFD = try openDirectory(pluginDirectory)
        defer { _ = close(directoryFD) }
        try validatePluginDirectory(directoryFD)

        let manifestData = try readLeaf(directoryFD, name: manifestFileName,
                                        maximumBytes: maximumManifestBytes, allowedModes: [0o600])
        guard let manifest = try? JSONDecoder().decode(FilterKitPluginManifest.self, from: manifestData) else {
            throw VerificationError.invalidManifest
        }
        guard manifest.schemaVersion == 3 else { throw VerificationError.unsupportedSchema }
        guard let pluginID = UUID(uuidString: manifest.pluginID),
              manifest.dylibFileName == dylibFileName,
              manifest.plistFileName == plistFileName,
              let expectedIdentity = manifest.machOIdentitySHA256,
              HelperPolicy.isValidHash(expectedIdentity),
              let hardBound = manifest.hardBoundBundleIdentifier,
              Self.isValidBundleIdentifier(hardBound),
              let associations = manifest.softAssociations,
              associations.allSatisfy({ Self.isValidBundleIdentifier($0.bundleIdentifier) }),
              Set(associations.map(\.bundleIdentifier)).count == associations.count,
              !associations.contains(where: { $0.bundleIdentifier == hardBound }),
              Set(associations.map(\.bundleIdentifier)) == Set(manifest.softAssociatedBundleIdentifiers ?? []),
              Set(manifest.softAssociatedBundleIdentifiers ?? []).count == (manifest.softAssociatedBundleIdentifiers ?? []).count else {
            throw VerificationError.pluginIdentityMismatch
        }

        let dylibData = try readLeaf(directoryFD, name: dylibFileName,
                                     maximumBytes: maximumPluginBytes, allowedModes: [0o644, 0o640, 0o600])
        let plistData = try readLeaf(directoryFD, name: plistFileName,
                                     maximumBytes: maximumPluginBytes, allowedModes: [0o644, 0o640, 0o600])
        let dylibHash = SHA256Digest.hex(dylibData)
        let plistHash = SHA256Digest.hex(plistData)
        guard HelperPolicy.isValidHash(manifest.dylibSHA256),
              HelperPolicy.isValidHash(manifest.plistSHA256),
              dylibHash == manifest.dylibSHA256.lowercased(),
              plistHash == manifest.plistSHA256.lowercased() else {
            throw VerificationError.payloadHashMismatch
        }
        guard (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) != nil else {
            throw VerificationError.invalidManifest
        }
        let slices: [MachOSliceMetadata]
        do { slices = try MachOMetadataReader().readSlices(data: dylibData) }
        catch { throw VerificationError.binaryIdentityMismatch }
        let actualIdentity = PluginIdentityFingerprint.make(slices: slices)
        guard actualIdentity == expectedIdentity.lowercased() else { throw VerificationError.binaryIdentityMismatch }

        return try HelperOwnershipProof(pluginID: pluginID, dylibFileName: dylibFileName,
            plistFileName: plistFileName, dylibSHA256: dylibHash, plistSHA256: plistHash,
            manifestSchemaVersion: manifest.schemaVersion, manifestSHA256: SHA256Digest.hex(manifestData),
            binaryIdentityVerified: true)
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.first!.isLetter && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    private func openDirectory(_ path: String) throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw VerificationError.unsafeDirectory }
        for component in path.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { _ = close(fd); throw VerificationError.unsafeDirectory }
            _ = close(fd); fd = next
        }
        return fd
    }

    private func validatePluginDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o022) == 0 else { throw VerificationError.unsafeDirectory }
    }

    private func readLeaf(_ directoryFD: Int32, name: String, maximumBytes: Int,
                          allowedModes: Set<mode_t>) throws -> Data {
        let fd = name.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw VerificationError.unsafeFile }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0,
              allowedModes.contains(info.st_mode & 0o777),
              (info.st_mode & 0o6000) == 0 else { throw VerificationError.unsafeFile }
        guard info.st_size >= 0, info.st_size <= maximumBytes else { throw VerificationError.oversized }
        var result = Data(); result.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw VerificationError.readFailed }
            if count == 0 { break }
            result.append(contentsOf: buffer.prefix(count))
            guard result.count <= maximumBytes else { throw VerificationError.oversized }
        }
        return result
    }
}

/// Kept byte-for-byte compatible with PluginIdentityAnalyzer.fingerprint().
enum PluginIdentityFingerprint {
    static func make(slices: [MachOSliceMetadata]) -> String? {
        func normalize(_ values: [String]) -> [String] {
            Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty })).sorted()
        }
        let names = normalize(slices.compactMap(\.installName))
        let uuids = normalize(slices.compactMap(\.uuid))
        let hashes = normalize(slices.compactMap(\.cdHash))
        let architectures = normalize(slices.compactMap(\.architecture))
        guard !uuids.isEmpty || !hashes.isEmpty else { return nil }
        let components = [
            names.isEmpty ? nil : "install=\(names.joined(separator: ","))",
            uuids.isEmpty ? nil : "uuid=\(uuids.joined(separator: ","))",
            hashes.isEmpty ? nil : "cdhash=\(hashes.joined(separator: ","))",
            architectures.isEmpty ? nil : "arch=\(architectures.joined(separator: ","))"
        ].compactMap { $0 }
        return SHA256Digest.hex(Data(components.joined(separator: "|").utf8))
    }
}
