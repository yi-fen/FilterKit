import Foundation

enum PluginPairingState: String, Codable {
    case paired
    case orphanDylib
    case orphanPlist
    case unreadable
    case invalid
}

enum PluginBinaryKind: String, Codable {
    case machO
    case unsupportedOrUnknown
    case notMachO
}

enum PluginIdentityStatus: String, Codable {
    case unique
    case duplicateIdentity
    case installNameCollision
    case uuidCDHashMismatch
    case insufficientFingerprint
    case unresolvedBasenameCollision
}

enum PluginOwnershipConflict: String, Codable {
    case none
    case filterKitVsPackageManager
    case multiplePackageOwners
}

enum PluginManifestIdentityBinding: String, Codable {
    case notPresent
    case fileHashesOnly
    case binaryIdentityVerified
    case unverified
}

struct PluginIdentityConflict: Codable, Equatable, Identifiable {
    let id: String
    let kind: PluginIdentityStatus
    let pluginIDs: [String]
    let detail: String
}

struct PackageOwnershipEvidence: Equatable {
    let isOwnedByPackage: Bool
    let packageIdentifier: String?
    let evidenceSource: String?
    var packageVersion: String? = nil
}

protocol PackageOwnershipProviding {
    func ownershipEvidence(for fileURL: URL) throws -> PackageOwnershipEvidence
}

struct NoPackageOwnershipEvidenceProvider: PackageOwnershipProviding {
    func ownershipEvidence(for fileURL: URL) throws -> PackageOwnershipEvidence {
        PackageOwnershipEvidence(isOwnedByPackage: false, packageIdentifier: nil, evidenceSource: nil)
    }
}

struct PluginScanIssue: Codable, Equatable, Identifiable {
    let id: String
    let code: String
    let fileName: String?
    let detail: String?
}

struct PluginScanFileObservation: Codable, Equatable {
    let fileSize: UInt64
    let modificationDate: Date?
    let systemFileNumber: UInt64?
}

struct PluginScanItem: Codable, Equatable, Identifiable {
    let id: String
    let baseName: String
    let dylibFileName: String?
    let plistFileName: String?
    let manifestFileName: String?
    let pairingState: PluginPairingState
    let binaryKind: PluginBinaryKind?
    var ownership: PluginOwnership
    let filterKitPluginID: String?
    let packageIdentifier: String?
    let dylibSHA256: String?
    let plistSHA256: String?
    let hardBoundBundleIdentifier: String?
    let softAssociatedBundleIdentifiers: [String]
    let warnings: [String]
    let filterConfiguration: PluginFilterConfiguration?
    var managementPermission: PluginManagementPermission?
    var packageVersion: String? = nil
    /// Read-only provenance of package ownership lookup; never grants management permission.
    var packageEvidenceSource: String? = nil
    var machOInstallName: String? = nil
    var machOCurrentVersion: String? = nil
    var machOCompatibilityVersion: String? = nil
    var machOUUID: String? = nil
    var machOUUIDs: [String] = []
    var machOArchitectures: [String] = []
    var machOCDHashes: [String] = []
    var machOTeamIdentifiers: [String] = []
    var codeSignatureStates: [String] = []
    var machOSliceDetails: [String] = []
    var identityFingerprint: String? = nil
    var identityStatus: PluginIdentityStatus = .insufficientFingerprint
    var identityConflictIDs: [String] = []
    var dylibPackageIdentifier: String? = nil
    var plistPackageIdentifier: String? = nil
    var ownershipConflict: PluginOwnershipConflict = .none
    var manifestIdentityBinding: PluginManifestIdentityBinding = .notPresent
    var helperIdentityAttestation: HelperPluginIdentityAttestation? = nil
    /// Hash of the exact manifest bytes observed by the read-only scanner.
    /// It is compared with Helper evidence and never treated as ownership proof.
    var manifestSHA256: String? = nil
    var dylibFileObservation: PluginScanFileObservation? = nil
    var plistFileObservation: PluginScanFileObservation? = nil
    var manifestFileObservation: PluginScanFileObservation? = nil
    var softAssociationStates: [FilterKitManifestSoftAssociation]? = nil
    // Absolute source paths are retained for multi-directory read-only inventories.
    // These are descriptive scan evidence, not permission to mutate the files.
    var dylibPath: String? = nil
    var plistPath: String? = nil
    var manifestPath: String? = nil
}

struct PluginScanResult: Codable, Equatable {
    let scannedAt: Date
    let scannedDirectory: String?
    let directoryState: PluginDirectoryResolutionState
    let plugins: [PluginScanItem]
    let issues: [PluginScanIssue]
    let isReadOnly: Bool
    var identityConflicts: [PluginIdentityConflict] = []
    var scannedDirectories: [String]? = nil
}

