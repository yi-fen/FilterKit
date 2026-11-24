import Foundation

struct PluginManifestMigrationPreview: Equatable {
    let sourceSchemaVersion: Int
    let targetSchemaVersion: Int
    let migratedManifest: FilterKitPluginManifest
    let warnings: [String]
    let requiresBinaryIdentityVerification: Bool
    let writesToDisk: Bool

    init(sourceSchemaVersion: Int, migratedManifest: FilterKitPluginManifest,
         warnings: [String], requiresBinaryIdentityVerification: Bool) {
        self.sourceSchemaVersion = sourceSchemaVersion
        self.targetSchemaVersion = 3
        self.migratedManifest = migratedManifest
        self.warnings = warnings
        self.requiresBinaryIdentityVerification = requiresBinaryIdentityVerification
        self.writesToDisk = false
    }
}

enum PluginManifestMigrationError: Error, Equatable {
    case unsupportedSchema(Int)
    case invalidPluginIdentifier
    case invalidFileName
    case invalidSHA256
    case invalidHardBoundBundleIdentifier
    case invalidSoftAssociation(String)
    case duplicateSoftAssociation(String)
    case missingBinaryIdentity
    case binaryIdentityMismatch
    case fileHashMismatch
    case missingHardBoundBundleIdentifier
    case inconsistentSchemaThreeAssociations
}

/// Pure schema decoder/migrator. It never writes the manifest or plugin files.
struct PluginManifestSchemaMigrator {
    func makeSchemaThreeManifest(pluginID: UUID, dylibFileName: String, plistFileName: String,
                                 dylibSHA256: String, plistSHA256: String,
                                 machOIdentitySHA256: String,
                                 associationPlan: PluginAssociationPlan) throws -> FilterKitPluginManifest {
        guard associationPlan.pluginID == pluginID else { throw PluginManifestMigrationError.invalidPluginIdentifier }
        guard Self.isSafeFileName(dylibFileName), Self.isSafeFileName(plistFileName) else {
            throw PluginManifestMigrationError.invalidFileName
        }
        guard Self.isSHA256(dylibSHA256), Self.isSHA256(plistSHA256) else {
            throw PluginManifestMigrationError.invalidSHA256
        }
        guard Self.isSHA256(machOIdentitySHA256) else { throw PluginManifestMigrationError.missingBinaryIdentity }
        guard PluginAssociationPlanResolver.isValidBundleIdentifier(associationPlan.hardBoundBundleIdentifier) else {
            throw PluginManifestMigrationError.invalidHardBoundBundleIdentifier
        }
        let states = associationPlan.softAssociations.map {
            FilterKitManifestSoftAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled)
        }
        try validateAssociations(states, hardBound: associationPlan.hardBoundBundleIdentifier)
        return FilterKitPluginManifest(
            schemaVersion: 3, pluginID: pluginID.uuidString,
            dylibFileName: dylibFileName, plistFileName: plistFileName,
            dylibSHA256: dylibSHA256.lowercased(), plistSHA256: plistSHA256.lowercased(),
            hardBoundBundleIdentifier: associationPlan.hardBoundBundleIdentifier,
            softAssociatedBundleIdentifiers: states.map(\.bundleIdentifier).sorted(),
            machOIdentitySHA256: machOIdentitySHA256.lowercased(),
            softAssociations: states.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
        )
    }

    func encodeSchemaThreeManifest(_ manifest: FilterKitPluginManifest) throws -> Data {
        guard manifest.schemaVersion == 3,
              let states = manifest.softAssociations,
              let hardBound = manifest.hardBoundBundleIdentifier,
              Set(states.map(\.bundleIdentifier)) == Set(manifest.softAssociatedBundleIdentifiers ?? []) else {
            throw PluginManifestMigrationError.inconsistentSchemaThreeAssociations
        }
        try validateAssociations(states, hardBound: hardBound)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    func decodeAndPreviewUpgrade(_ data: Data, actualDylibSHA256: String,
                                 actualPlistSHA256: String,
                                 machOIdentitySHA256: String?) throws -> PluginManifestMigrationPreview {
        let manifest = try JSONDecoder().decode(FilterKitPluginManifest.self, from: data)
        guard (1...3).contains(manifest.schemaVersion) else {
            throw PluginManifestMigrationError.unsupportedSchema(manifest.schemaVersion)
        }
        try validateCommon(manifest)
        guard manifest.dylibSHA256.lowercased() == actualDylibSHA256.lowercased(),
              manifest.plistSHA256.lowercased() == actualPlistSHA256.lowercased() else {
            throw PluginManifestMigrationError.fileHashMismatch
        }
        guard let hardBound = manifest.hardBoundBundleIdentifier,
              PluginAssociationPlanResolver.isValidBundleIdentifier(hardBound) else {
            throw PluginManifestMigrationError.missingHardBoundBundleIdentifier
        }
        guard let identity = machOIdentitySHA256, Self.isSHA256(identity) else {
            throw PluginManifestMigrationError.missingBinaryIdentity
        }
        if manifest.schemaVersion >= 2 {
            guard manifest.machOIdentitySHA256?.lowercased() == identity.lowercased() else {
                throw PluginManifestMigrationError.binaryIdentityMismatch
            }
        }
        let associations: [FilterKitManifestSoftAssociation]
        var warnings: [String] = []
        if manifest.schemaVersion == 3 {
            guard let saved = manifest.softAssociations else {
                throw PluginManifestMigrationError.inconsistentSchemaThreeAssociations
            }
            associations = saved
            guard Set(saved.map(\.bundleIdentifier)) == Set(manifest.softAssociatedBundleIdentifiers ?? []),
                  saved.count == Set(saved.map(\.bundleIdentifier)).count else {
                throw PluginManifestMigrationError.inconsistentSchemaThreeAssociations
            }
        } else {
            associations = (manifest.softAssociatedBundleIdentifiers ?? []).map {
                FilterKitManifestSoftAssociation(bundleIdentifier: $0, isEnabled: true)
            }
            if !associations.isEmpty {
                warnings.append("legacy_soft_associations_interpreted_as_enabled")
            }
        }
        try validateAssociations(associations, hardBound: manifest.hardBoundBundleIdentifier)
        let upgraded = FilterKitPluginManifest(
            schemaVersion: 3,
            pluginID: manifest.pluginID,
            dylibFileName: manifest.dylibFileName,
            plistFileName: manifest.plistFileName,
            dylibSHA256: manifest.dylibSHA256,
            plistSHA256: manifest.plistSHA256,
            hardBoundBundleIdentifier: hardBound,
            softAssociatedBundleIdentifiers: associations.map(\.bundleIdentifier).sorted(),
            machOIdentitySHA256: identity.lowercased(),
            softAssociations: associations.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
        )
        return PluginManifestMigrationPreview(
            sourceSchemaVersion: manifest.schemaVersion,
            migratedManifest: upgraded,
            warnings: warnings,
            requiresBinaryIdentityVerification: manifest.schemaVersion < 2
        )
    }

    private func validateCommon(_ manifest: FilterKitPluginManifest) throws {
        guard UUID(uuidString: manifest.pluginID) != nil else { throw PluginManifestMigrationError.invalidPluginIdentifier }
        guard Self.isSafeFileName(manifest.dylibFileName), Self.isSafeFileName(manifest.plistFileName) else {
            throw PluginManifestMigrationError.invalidFileName
        }
        guard Self.isSHA256(manifest.dylibSHA256), Self.isSHA256(manifest.plistSHA256) else {
            throw PluginManifestMigrationError.invalidSHA256
        }
        if let hardBound = manifest.hardBoundBundleIdentifier,
           !PluginAssociationPlanResolver.isValidBundleIdentifier(hardBound) {
            throw PluginManifestMigrationError.invalidHardBoundBundleIdentifier
        }
    }

    private func validateAssociations(_ associations: [FilterKitManifestSoftAssociation], hardBound: String?) throws {
        var seen = Set<String>()
        for association in associations {
            let id = association.bundleIdentifier
            guard PluginAssociationPlanResolver.isValidBundleIdentifier(id), id != hardBound else {
                throw PluginManifestMigrationError.invalidSoftAssociation(id)
            }
            guard seen.insert(id).inserted else { throw PluginManifestMigrationError.duplicateSoftAssociation(id) }
        }
    }

    static func isSafeFileName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." &&
        URL(fileURLWithPath: value).lastPathComponent == value &&
        !value.contains("/") && !value.contains("\\\\")
    }

    static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }
}
