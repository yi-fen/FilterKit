import Foundation

struct BackupPluginEntry: Codable, Equatable {
    let pluginIdentifier: UUID
    let dylibFileName: String
    let dylibDataBase64: String
    let dylibSHA256: String
    let plistFileName: String
    let plistDataBase64: String
    let plistSHA256: String
    let hardBoundBundleIdentifier: String
    let softAssociatedBundleIdentifiers: [String]
    /// Present in backup schema 2+; nil in legacy backups means enabled by compatibility policy.
    var softAssociations: [FilterKitManifestSoftAssociation]? = nil
    /// Optional provenance fields; older schema-1/2 archives remain decodable.
    var machOIdentitySHA256: String? = nil
    var manifestDataBase64: String? = nil
    var manifestSHA256: String? = nil

    var resolvedSoftAssociations: [FilterKitManifestSoftAssociation] {
        softAssociations ?? softAssociatedBundleIdentifiers.map {
            FilterKitManifestSoftAssociation(bundleIdentifier: $0, isEnabled: true)
        }
    }
}

struct FilterKitBackupDocument: Codable, Equatable {
    static let formatIdentifier = "FilterKitBackup"
    static let currentSchemaVersion = 2
    let format: String
    let schemaVersion: Int
    let createdAt: Date
    let plugins: [BackupPluginEntry]

    init(schemaVersion: Int = Self.currentSchemaVersion, createdAt: Date = Date(), plugins: [BackupPluginEntry]) {
        self.format = Self.formatIdentifier
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.plugins = plugins
    }
}

enum BackupAssociationCompatibilityError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case missingAssociationStatesForSchemaTwo
    case associationStateMismatch
    case invalidHardBoundBundleIdentifier
    case invalidSoftAssociation(String)
    case duplicateSoftAssociation(String)
    case hardBoundRepeatedAsSoftAssociation
}

struct BackupAssociationCompatibility {
    func resolvedPlan(from entry: BackupPluginEntry, backupSchemaVersion: Int = 1) throws -> PluginAssociationPlan {
        guard backupSchemaVersion == 1 || backupSchemaVersion == 2 else {
            throw BackupAssociationCompatibilityError.unsupportedSchemaVersion(backupSchemaVersion)
        }
        if backupSchemaVersion == 2 && entry.softAssociations == nil {
            throw BackupAssociationCompatibilityError.missingAssociationStatesForSchemaTwo
        }
        if let states = entry.softAssociations,
           Set(states.map(\.bundleIdentifier)) != Set(entry.softAssociatedBundleIdentifiers) || states.count != entry.softAssociatedBundleIdentifiers.count {
            throw BackupAssociationCompatibilityError.associationStateMismatch
        }
        guard PluginAssociationPlanResolver.isValidBundleIdentifier(entry.hardBoundBundleIdentifier) else {
            throw BackupAssociationCompatibilityError.invalidHardBoundBundleIdentifier
        }
        let associations = entry.resolvedSoftAssociations
        var seen = Set<String>()
        for association in associations {
            guard PluginAssociationPlanResolver.isValidBundleIdentifier(association.bundleIdentifier) else {
                throw BackupAssociationCompatibilityError.invalidSoftAssociation(association.bundleIdentifier)
            }
            guard association.bundleIdentifier != entry.hardBoundBundleIdentifier else {
                throw BackupAssociationCompatibilityError.hardBoundRepeatedAsSoftAssociation
            }
            guard seen.insert(association.bundleIdentifier).inserted else {
                throw BackupAssociationCompatibilityError.duplicateSoftAssociation(association.bundleIdentifier)
            }
        }
        return PluginAssociationPlan(pluginID: entry.pluginIdentifier,
            hardBoundBundleIdentifier: entry.hardBoundBundleIdentifier,
            softAssociations: associations.map {
                PluginSoftAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled)
            })
    }
}

enum BackupValidationError: Error, Equatable {
    case invalidFormat
    case unsupportedSchema(Int)
    case emptyPluginList
    case duplicatePluginIdentifier
    case unsafeFileName(String)
    case invalidBase64(String)
    case hashMismatch(String)
    case invalidHash(String)
    case incompleteManifestPayload
    case invalidAssociation(String)
}

struct ValidatedBackupPlugin: Equatable {
    let entry: BackupPluginEntry
    let dylibData: Data
    let plistData: Data
    let manifestData: Data?
    let associationPlan: PluginAssociationPlan
}

struct FilterKitBackupCodec {
    func encode(_ document: FilterKitBackupDocument) throws -> Data {
        _ = try validate(document)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    func decodeAndValidate(_ data: Data) throws -> (document: FilterKitBackupDocument, plugins: [ValidatedBackupPlugin]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(FilterKitBackupDocument.self, from: data)
        return (document, try validate(document))
    }

    func validate(_ document: FilterKitBackupDocument) throws -> [ValidatedBackupPlugin] {
        guard document.format == FilterKitBackupDocument.formatIdentifier else { throw BackupValidationError.invalidFormat }
        guard document.schemaVersion == 1 || document.schemaVersion == 2 else { throw BackupValidationError.unsupportedSchema(document.schemaVersion) }
        guard !document.plugins.isEmpty else { throw BackupValidationError.emptyPluginList }
        var identifiers = Set<UUID>()
        var validated: [ValidatedBackupPlugin] = []
        for entry in document.plugins {
            guard identifiers.insert(entry.pluginIdentifier).inserted else { throw BackupValidationError.duplicatePluginIdentifier }
            try Self.validateFileName(entry.dylibFileName)
            try Self.validateFileName(entry.plistFileName)
            guard entry.dylibFileName.lowercased().hasSuffix(".dylib"), entry.plistFileName.lowercased().hasSuffix(".plist") else {
                throw BackupValidationError.unsafeFileName("expected dylib/plist extension")
            }
            let dylib = try Self.decode(entry.dylibDataBase64, field: entry.dylibFileName)
            let plist = try Self.decode(entry.plistDataBase64, field: entry.plistFileName)
            try Self.verifyHash(entry.dylibSHA256, data: dylib, field: entry.dylibFileName)
            try Self.verifyHash(entry.plistSHA256, data: plist, field: entry.plistFileName)
            let manifest: Data?
            if entry.manifestDataBase64 != nil || entry.manifestSHA256 != nil {
                guard let encoded = entry.manifestDataBase64, let hash = entry.manifestSHA256 else { throw BackupValidationError.incompleteManifestPayload }
                let decoded = try Self.decode(encoded, field: "manifest")
                try Self.verifyHash(hash, data: decoded, field: "manifest")
                manifest = decoded
            } else { manifest = nil }
            let plan: PluginAssociationPlan
            do { plan = try BackupAssociationCompatibility().resolvedPlan(from: entry, backupSchemaVersion: document.schemaVersion) }
            catch { throw BackupValidationError.invalidAssociation(String(describing: error)) }
            validated.append(ValidatedBackupPlugin(entry: entry, dylibData: dylib, plistData: plist, manifestData: manifest, associationPlan: plan))
        }
        return validated
    }

    private static func validateFileName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains(".."), !name.hasPrefix(".") else {
            throw BackupValidationError.unsafeFileName(name)
        }
    }
    private static func decode(_ value: String, field: String) throws -> Data {
        guard let data = Data(base64Encoded: value, options: []), !data.isEmpty else { throw BackupValidationError.invalidBase64(field) }
        return data
    }
    private static func verifyHash(_ hash: String, data: Data, field: String) throws {
        guard hash.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { throw BackupValidationError.invalidHash(field) }
        guard SHA256Digest.hex(data).caseInsensitiveCompare(hash) == .orderedSame else { throw BackupValidationError.hashMismatch(field) }
    }
}

enum BackupRestoreDisposition: String, Codable { case ready, hardBoundAppMissing, softAppsMissing, fileConflict, identityConflict }
struct BackupRestorePluginPreview: Equatable {
    let pluginIdentifier: UUID
    let disposition: BackupRestoreDisposition
    let missingBundleIdentifiers: [String]
    let conflictingFileNames: [String]
}
struct BackupRestorePreview: Equatable {
    let plugins: [BackupRestorePluginPreview]
    var readyCount: Int { plugins.filter { $0.disposition == .ready || $0.disposition == .softAppsMissing }.count }
    var blockedCount: Int { plugins.count - readyCount }
}

struct BackupRestorePreviewBuilder {
    func build(validated: [ValidatedBackupPlugin], installedBundleIdentifiers: Set<String>,
               existingFileNames: Set<String> = [], conflictingPluginIDs: Set<UUID> = []) -> BackupRestorePreview {
        let previews = validated.map { plugin -> BackupRestorePluginPreview in
            let entry = plugin.entry
            let missingSoft = plugin.associationPlan.softAssociations.map(\.bundleIdentifier).filter { !installedBundleIdentifiers.contains($0) }.sorted()
            let hardMissing = !installedBundleIdentifiers.contains(entry.hardBoundBundleIdentifier)
            let existingNames = Set(existingFileNames.map { $0.lowercased() })
            let conflicts = [entry.dylibFileName, entry.plistFileName]
                .filter { existingNames.contains($0.lowercased()) }.sorted()
            let disposition: BackupRestoreDisposition
            if hardMissing { disposition = .hardBoundAppMissing }
            else if conflictingPluginIDs.contains(entry.pluginIdentifier) { disposition = .identityConflict }
            else if !conflicts.isEmpty { disposition = .fileConflict }
            else if !missingSoft.isEmpty { disposition = .softAppsMissing }
            else { disposition = .ready }
            return BackupRestorePluginPreview(pluginIdentifier: entry.pluginIdentifier, disposition: disposition,
                missingBundleIdentifiers: (hardMissing ? [entry.hardBoundBundleIdentifier] : []) + missingSoft,
                conflictingFileNames: conflicts)
        }
        return BackupRestorePreview(plugins: previews)
    }
}


/// Only plugins with no hard-blocking restore conflict may be selected in the review UI.
enum BackupRestoreSelectionPolicy {
    static func selectablePluginIDs(in preview: BackupRestorePreview) -> Set<UUID> {
        Set(preview.plugins.compactMap { item in
            switch item.disposition {
            case .ready, .softAppsMissing: return item.pluginIdentifier
            case .hardBoundAppMissing, .fileConflict, .identityConflict: return nil
            }
        })
    }
}
