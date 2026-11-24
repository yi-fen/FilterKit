import Foundation

/// Builds and inspects FilterKitBackup archives. This service is deliberately read-only:
/// it never deploys files or changes plugin configuration.
final class FilterKitBackupService {
    enum ServiceError: Error, Equatable {
        case unresolvedDirectory
        case pluginNotFound(UUID)
        case pluginNotManageable(UUID)
        case incompletePluginRecord(UUID)
        case fileMissing(String)
        case unsafeFile(String)
        case fileTooLarge(String)
        case fileChanged(String)
        case invalidManifest(String)
    }

    private let fileManager: FileManager
    private let codec: FilterKitBackupCodec
    private let maximumPluginFileBytes: Int
    private let maximumManifestBytes: Int
    private let maximumBackupBytes: Int

    init(fileManager: FileManager = .default,
         codec: FilterKitBackupCodec = FilterKitBackupCodec(),
         maximumPluginFileBytes: Int = 256 * 1024 * 1024,
         maximumManifestBytes: Int = 64 * 1024,
         maximumBackupBytes: Int = 1024 * 1024 * 1024) {
        self.fileManager = fileManager
        self.codec = codec
        self.maximumPluginFileBytes = maximumPluginFileBytes
        self.maximumManifestBytes = maximumManifestBytes
        self.maximumBackupBytes = maximumBackupBytes
    }

    func makeBackup(scan: PluginScanResult, pluginIDs: [UUID]) throws -> Data {
        guard scan.directoryState == .resolved, let directory = scan.scannedDirectory else {
            throw ServiceError.unresolvedDirectory
        }
        let root = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
        guard root.resolvingSymlinksInPath().standardizedFileURL.path == root.path else {
            throw ServiceError.unsafeFile(directory)
        }
        let requested = Array(Set(pluginIDs)).sorted { $0.uuidString < $1.uuidString }
        guard !requested.isEmpty else { throw BackupValidationError.emptyPluginList }

        let entries = try requested.map { id -> BackupPluginEntry in
            guard let item = scan.plugins.first(where: { $0.filterKitPluginID == id.uuidString }) else {
                throw ServiceError.pluginNotFound(id)
            }
            guard item.managementPermission?.canModify == true,
                  item.ownership == .filterKit,
                  item.ownershipConflict == .none,
                  item.identityStatus == .unique || item.identityStatus == .insufficientFingerprint else {
                throw ServiceError.pluginNotManageable(id)
            }
            guard let dylibName = item.dylibFileName,
                  let plistName = item.plistFileName,
                  let manifestName = item.manifestFileName,
                  let expectedDylibHash = item.dylibSHA256,
                  let expectedPlistHash = item.plistSHA256,
                  let hardBound = item.hardBoundBundleIdentifier,
                  let uuid = UUID(uuidString: id.uuidString) else {
                throw ServiceError.incompletePluginRecord(id)
            }
            let dylib = try readRegularFile(named: dylibName, in: root, maximumBytes: maximumPluginFileBytes)
            let plist = try readRegularFile(named: plistName, in: root, maximumBytes: maximumPluginFileBytes)
            let manifest = try readRegularFile(named: manifestName, in: root, maximumBytes: maximumManifestBytes)
            guard SHA256Digest.hex(dylib).caseInsensitiveCompare(expectedDylibHash) == .orderedSame else {
                throw ServiceError.fileChanged(dylibName)
            }
            guard SHA256Digest.hex(plist).caseInsensitiveCompare(expectedPlistHash) == .orderedSame else {
                throw ServiceError.fileChanged(plistName)
            }
            let decodedManifest = try JSONDecoder().decode(FilterKitPluginManifest.self, from: manifest)
            guard (1...3).contains(decodedManifest.schemaVersion),
                  decodedManifest.pluginID == id.uuidString,
                  decodedManifest.dylibFileName == dylibName,
                  decodedManifest.plistFileName == plistName,
                  decodedManifest.hardBoundBundleIdentifier == hardBound,
                  decodedManifest.dylibSHA256.caseInsensitiveCompare(expectedDylibHash) == .orderedSame,
                  decodedManifest.plistSHA256.caseInsensitiveCompare(expectedPlistHash) == .orderedSame else {
                throw ServiceError.invalidManifest(manifestName)
            }
            if decodedManifest.schemaVersion >= 2 {
                guard let manifestIdentity = decodedManifest.machOIdentitySHA256,
                      let scannedIdentity = item.identityFingerprint,
                      manifestIdentity.caseInsensitiveCompare(scannedIdentity) == .orderedSame else {
                    throw ServiceError.invalidManifest(manifestName)
                }
            }
            let manifestAssociations = decodedManifest.softAssociations ??
                (decodedManifest.softAssociatedBundleIdentifiers ?? []).map {
                    FilterKitManifestSoftAssociation(bundleIdentifier: $0, isEnabled: true)
                }
            guard Set(manifestAssociations.map(\.bundleIdentifier)) == Set(item.softAssociatedBundleIdentifiers),
                  manifestAssociations.count == item.softAssociatedBundleIdentifiers.count,
                  item.softAssociationStates == nil || item.softAssociationStates == manifestAssociations else {
                throw ServiceError.invalidManifest(manifestName)
            }
            let stateByBundle = Dictionary(uniqueKeysWithValues: manifestAssociations.map { ($0.bundleIdentifier, $0.isEnabled) })
            let associationStates = item.softAssociatedBundleIdentifiers.sorted().map {
                FilterKitManifestSoftAssociation(bundleIdentifier: $0,
                    isEnabled: stateByBundle[$0] ?? true)
            }
            let identityDigest = decodedManifest.machOIdentitySHA256
            return BackupPluginEntry(pluginIdentifier: uuid,
                dylibFileName: dylibName, dylibDataBase64: dylib.base64EncodedString(),
                dylibSHA256: SHA256Digest.hex(dylib),
                plistFileName: plistName, plistDataBase64: plist.base64EncodedString(),
                plistSHA256: SHA256Digest.hex(plist),
                hardBoundBundleIdentifier: hardBound,
                softAssociatedBundleIdentifiers: associationStates.map(\.bundleIdentifier),
                softAssociations: associationStates,
                machOIdentitySHA256: identityDigest,
                manifestDataBase64: manifest.base64EncodedString(),
                manifestSHA256: SHA256Digest.hex(manifest))
        }
        let document = FilterKitBackupDocument(schemaVersion: 2, plugins: entries)
        return try codec.encode(document)
    }

    func inspectBackup(data: Data) throws -> (document: FilterKitBackupDocument, plugins: [ValidatedBackupPlugin]) {
        try codec.decodeAndValidate(data)
    }

    func inspectBackup(at url: URL) throws -> (document: FilterKitBackupDocument, plugins: [ValidatedBackupPlugin]) {
        try inspectBackup(data: readBackupFile(at: url))
    }

    func restorePreview(at url: URL, installedBundleIdentifiers: Set<String>,
                        existingFileNames: Set<String>, conflictingPluginIDs: Set<UUID> = []) throws -> BackupRestorePreview {
        try restorePreview(data: readBackupFile(at: url),
            installedBundleIdentifiers: installedBundleIdentifiers,
            existingFileNames: existingFileNames,
            conflictingPluginIDs: conflictingPluginIDs)
    }

    func restorePreview(data: Data, installedBundleIdentifiers: Set<String>,
                        existingFileNames: Set<String>, conflictingPluginIDs: Set<UUID> = []) throws -> BackupRestorePreview {
        let validated = try codec.decodeAndValidate(data).plugins
        return BackupRestorePreviewBuilder().build(validated: validated,
            installedBundleIdentifiers: installedBundleIdentifiers,
            existingFileNames: existingFileNames,
            conflictingPluginIDs: conflictingPluginIDs)
    }

    private func readBackupFile(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0 else {
            throw ServiceError.fileMissing(url.lastPathComponent)
        }
        guard size <= maximumBackupBytes else { throw ServiceError.fileTooLarge(url.lastPathComponent) }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == size else { throw ServiceError.fileChanged(url.lastPathComponent) }
        return data
    }

    private func readRegularFile(named name: String, in root: URL, maximumBytes: Int) throws -> Data {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.contains("\\"), !name.contains(".."), !name.hasPrefix(".") else {
            throw ServiceError.unsafeFile(name)
        }
        let url = root.appendingPathComponent(name).standardizedFileURL
        guard url.deletingLastPathComponent().path == root.path else { throw ServiceError.unsafeFile(name) }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else { throw ServiceError.fileMissing(name) }
        guard let size = values?.fileSize, size > 0 else { throw ServiceError.fileMissing(name) }
        guard size <= maximumBytes else { throw ServiceError.fileTooLarge(name) }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == size else { throw ServiceError.fileChanged(name) }
        return data
    }
}
