import Foundation

struct BackupPluginEntry: Codable, Equatable {
    let pluginIdentifier: UUID
    let dylibFileName: String
    let dylibDataBase64: String
    let dylibSHA256: String
    let plistFileName: String
    let plistDataBase64: String
    let plistSHA256: String
    /// Optional in schema 3 so a plugin may have no fixed owner.
    let hardBoundBundleIdentifier: String?
    let softAssociatedBundleIdentifiers: [String]
    /// Present in backup schema 2+; nil in legacy backups means enabled by compatibility policy.
    var softAssociations: [FilterKitManifestSoftAssociation]? = nil
    /// Schema-3 authoritative topology. The legacy fields above are retained as validated mirrors.
    var bindingTopology: FilterKitManifestBindingTopology? = nil
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
    static let currentSchemaVersion = 3
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
    case missingBindingTopologyForSchemaThree
    case associationStateMismatch
    case invalidHardBoundBundleIdentifier
    case invalidSoftAssociation(String)
    case duplicateSoftAssociation(String)
    case hardBoundRepeatedAsSoftAssociation
    case invalidTopologySchema
    case emptyBindingTopology
    case topologyMirrorMismatch
}

struct BackupAssociationCompatibility {
    func resolvedTopology(from entry: BackupPluginEntry, backupSchemaVersion: Int,
                          pluginID: UUID) throws -> PluginBindingTopology {
        guard (1...3).contains(backupSchemaVersion) else {
            throw BackupAssociationCompatibilityError.unsupportedSchemaVersion(backupSchemaVersion)
        }
        if backupSchemaVersion == 3 {
            guard let wire = entry.bindingTopology else {
                throw BackupAssociationCompatibilityError.missingBindingTopologyForSchemaThree
            }
            guard wire.schemaVersion == 1 else { throw BackupAssociationCompatibilityError.invalidTopologySchema }
            let states = wire.additionalAssociations
            guard BackupBundleIdentity.matches(entry.hardBoundBundleIdentifier, wire.fixedOwnerBundleIdentifier),
                  BackupBundleIdentity.sameSet(entry.softAssociatedBundleIdentifiers, states.map(\.bundleIdentifier)),
                  let entryStates = entry.softAssociations,
                  BackupBundleIdentity.sameStates(
                    entryStates.map { (bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled) },
                    states.map { (bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled) }) else {
                throw BackupAssociationCompatibilityError.topologyMirrorMismatch
            }
            let topology = PluginBindingTopology(pluginID: pluginID,
                fixedOwnerBundleIdentifier: wire.fixedOwnerBundleIdentifier,
                fixedOwnerIsEnabled: wire.fixedOwnerIsEnabled,
                additionalAssociations: states.map {
                    PluginBindingAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled)
                })
            try validate(topology)
            return topology
        }

        guard entry.bindingTopology == nil else { throw BackupAssociationCompatibilityError.topologyMirrorMismatch }
        if backupSchemaVersion == 2 && entry.softAssociations == nil {
            throw BackupAssociationCompatibilityError.missingAssociationStatesForSchemaTwo
        }
        if let states = entry.softAssociations,
           !BackupBundleIdentity.sameSet(entry.softAssociatedBundleIdentifiers, states.map(\.bundleIdentifier)) {
            throw BackupAssociationCompatibilityError.associationStateMismatch
        }
        guard let hardBound = entry.hardBoundBundleIdentifier,
              PluginAssociationPlanResolver.isValidBundleIdentifier(hardBound) else {
            throw BackupAssociationCompatibilityError.invalidHardBoundBundleIdentifier
        }
        let associations = entry.resolvedSoftAssociations
        let topology = PluginBindingTopology(pluginID: pluginID,
            fixedOwnerBundleIdentifier: hardBound,
            fixedOwnerIsEnabled: true,
            additionalAssociations: associations.map {
                PluginBindingAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled)
            })
        try validate(topology)
        return topology
    }

    /// Compatibility adapter for older call sites that still require the legacy plan shape.
    func resolvedPlan(from entry: BackupPluginEntry, backupSchemaVersion: Int = 1) throws -> PluginAssociationPlan {
        let topology = try resolvedTopology(from: entry, backupSchemaVersion: backupSchemaVersion,
                                            pluginID: entry.pluginIdentifier)
        guard let owner = topology.fixedOwnerBundleIdentifier else {
            throw BackupAssociationCompatibilityError.invalidHardBoundBundleIdentifier
        }
        return PluginAssociationPlan(pluginID: topology.pluginID, hardBoundBundleIdentifier: owner,
            softAssociations: topology.additionalAssociations.map {
                PluginSoftAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled)
            })
    }

    private func validate(_ topology: PluginBindingTopology) throws {
        let issues = PluginBindingTopologyValidator().validate(topology)
        if !issues.isEmpty { throw BackupAssociationCompatibilityError.invalidTopologySchema }
        guard topology.fixedOwnerBundleIdentifier != nil || !topology.additionalAssociations.isEmpty else {
            throw BackupAssociationCompatibilityError.emptyBindingTopology
        }
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
    let bindingTopology: PluginBindingTopology
    var associationPlan: PluginAssociationPlan? {
        guard let owner = bindingTopology.fixedOwnerBundleIdentifier else { return nil }
        return PluginAssociationPlan(pluginID: bindingTopology.pluginID, hardBoundBundleIdentifier: owner,
            softAssociations: bindingTopology.additionalAssociations.map {
                PluginSoftAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled)
            })
    }
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
        guard (1...3).contains(document.schemaVersion) else { throw BackupValidationError.unsupportedSchema(document.schemaVersion) }
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
            let topology: PluginBindingTopology
            do {
                topology = try BackupAssociationCompatibility().resolvedTopology(from: entry,
                    backupSchemaVersion: document.schemaVersion, pluginID: entry.pluginIdentifier)
            } catch { throw BackupValidationError.invalidAssociation(String(describing: error)) }
            if document.schemaVersion == 3 {
                guard let manifest else { throw BackupValidationError.incompleteManifestPayload }
                try Self.validateManifest(manifest, entry: entry, topology: topology)
            }
            validated.append(ValidatedBackupPlugin(entry: entry, dylibData: dylib, plistData: plist,
                manifestData: manifest, bindingTopology: topology))
        }
        return validated
    }

    private static func validateManifest(_ data: Data, entry: BackupPluginEntry,
                                         topology: PluginBindingTopology) throws {
        let manifest: FilterKitPluginManifest
        do { manifest = try JSONDecoder().decode(FilterKitPluginManifest.self, from: data) }
        catch { throw BackupValidationError.incompleteManifestPayload }
        guard (1...4).contains(manifest.schemaVersion),
              manifest.pluginID == entry.pluginIdentifier.uuidString,
              manifest.dylibFileName == entry.dylibFileName,
              manifest.plistFileName == entry.plistFileName,
              manifest.dylibSHA256.caseInsensitiveCompare(entry.dylibSHA256) == .orderedSame,
              manifest.plistSHA256.caseInsensitiveCompare(entry.plistSHA256) == .orderedSame,
              BackupBundleIdentity.matches(manifest.hardBoundBundleIdentifier, topology.fixedOwnerBundleIdentifier),
              BackupBundleIdentity.sameSet(manifest.softAssociatedBundleIdentifiers ?? [], topology.additionalAssociations.map(\.bundleIdentifier)) else {
            throw BackupValidationError.invalidAssociation("manifest/topology mismatch")
        }
        if let identity = entry.machOIdentitySHA256 {
            guard let manifestIdentity = manifest.machOIdentitySHA256,
                  manifestIdentity.caseInsensitiveCompare(identity) == .orderedSame else {
                throw BackupValidationError.invalidAssociation("manifest identity mismatch")
            }
        }
        if manifest.schemaVersion == 4 {
            guard let wire = manifest.bindingTopology,
                  wire.schemaVersion == 1,
                  BackupBundleIdentity.matches(wire.fixedOwnerBundleIdentifier, topology.fixedOwnerBundleIdentifier),
                  wire.fixedOwnerIsEnabled == topology.fixedOwnerIsEnabled,
                  BackupBundleIdentity.sameStates(
                    wire.additionalAssociations.map { (bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled) },
                    topology.additionalAssociations.map { (bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled) }) else {
                throw BackupValidationError.invalidAssociation("manifest binding topology mismatch")
            }
        } else {
            guard topology.fixedOwnerBundleIdentifier != nil,
                  topology.fixedOwnerIsEnabled,
                  manifest.schemaVersion < 3 || BackupBundleIdentity.sameStates(
                    (manifest.softAssociations ?? []).map { (bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled) },
                    topology.additionalAssociations.map { (bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled) }) else {
                throw BackupValidationError.invalidAssociation("legacy manifest cannot represent binding topology")
            }
        }
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

enum BackupRestoreDisposition: String, Codable {
    case ready
    /// Retained for decoding older preview snapshots; current policy does not hard-block
    /// restoration merely because the immutable Fixed Owner App is absent.
    case hardBoundAppMissing
    case softAppsMissing
    case fileConflict
    case identityConflict
    case skippedNoInstalledAssociation
    case externalDuplicate
}
struct BackupRestorePluginPreview: Equatable {
    let pluginIdentifier: UUID
    let disposition: BackupRestoreDisposition
    let missingBundleIdentifiers: [String]
    let conflictingFileNames: [String]
}
struct BackupRestorePreview: Equatable {
    let plugins: [BackupRestorePluginPreview]
    var readyCount: Int { plugins.filter { $0.disposition == .ready || $0.disposition == .softAppsMissing }.count }
    var skippedCount: Int { plugins.filter {
        $0.disposition == .skippedNoInstalledAssociation || $0.disposition == .externalDuplicate
    }.count }
    var blockedCount: Int { plugins.count - readyCount - skippedCount }
}

struct BackupRestorePreviewBuilder {
    func build(validated: [ValidatedBackupPlugin], installedBundleIdentifiers: Set<String>,
               existingFileNames: Set<String> = [], conflictingPluginIDs: Set<UUID> = [],
               packageManagedDylibSHA256s: Set<String> = [],
               filterToInstalledApps: Bool = true) -> BackupRestorePreview {
        let packageHashes = Set(packageManagedDylibSHA256s.map { $0.lowercased() })
        let existingNames = Set(existingFileNames.map { $0.lowercased() })
        let installedKeys = HelperBundleIdentifierKey.set(installedBundleIdentifiers)
        let previews = validated.map { plugin -> BackupRestorePluginPreview in
            let entry = plugin.entry
            let topology = plugin.bindingTopology
            let allAssociatedApps = Set(
                topology.fixedOwnerBundleIdentifier.map { [$0] } ?? []
            ).union(topology.additionalAssociations.map(\.bundleIdentifier))
            let installedAssociations = allAssociatedApps.filter {
                installedKeys.contains(HelperBundleIdentifierKey.make($0))
            }
            let missingApps = allAssociatedApps.filter {
                !installedKeys.contains(HelperBundleIdentifierKey.make($0))
            }.sorted()
            let conflicts = [entry.dylibFileName, entry.plistFileName]
                .filter { existingNames.contains($0.lowercased()) }.sorted()

            let disposition: BackupRestoreDisposition
            // Exact content already owned by a package manager is never copied over,
            // adopted, or re-registered by FilterKit.
            if PluginSourceOperationPolicy.decision(for: .packageManager, operation: .restore,
                exactPackageManagedSHA256Match: packageHashes.contains(entry.dylibSHA256.lowercased())) == .skipExternalDuplicate {
                disposition = .externalDuplicate
            } else if filterToInstalledApps && installedAssociations.isEmpty {
                disposition = .skippedNoInstalledAssociation
            } else if conflictingPluginIDs.contains(entry.pluginIdentifier) {
                disposition = .identityConflict
            } else if !conflicts.isEmpty {
                disposition = .fileConflict
            } else if !missingApps.isEmpty {
                disposition = .softAppsMissing
            } else {
                disposition = .ready
            }
            return BackupRestorePluginPreview(pluginIdentifier: entry.pluginIdentifier, disposition: disposition,
                missingBundleIdentifiers: missingApps,
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
            case .hardBoundAppMissing, .fileConflict, .identityConflict,
                 .skippedNoInstalledAssociation, .externalDuplicate: return nil
            }
        })
    }
}
