import Foundation

enum ElleKitInstallationState: String, Codable, Equatable {
    case installed
    case suspected
    case notFound
    case inaccessible
}

enum ElleKitLayoutItemKind: String, Codable, Equatable {
    case mainDylib
    case companionDylib
    case compatibilityLink
    case loader
    case launchDaemon
    case dpkgInfo
}

struct ElleKitLayoutEvidence: Codable, Equatable, Identifiable {
    let id: String
    let path: String
    let kind: ElleKitLayoutItemKind
    let exists: Bool
    let isReadable: Bool
    let isSymbolicLink: Bool
    let isMachO: Bool?
}

enum ElleKitEvidenceStatus: String, Codable, Equatable {
    case notDetected
    case binaryOnly
    case packageMetadataOnly
    case metadataFallbackOnly
    case installed
    case inconsistent
    case ambiguous
}

struct ElleKitPackageMetadata: Codable, Equatable {
    let package: String
    let version: String?
    let architecture: String?
    let status: String?
    let maintainer: String?
    let origin: String?
    let homepage: String?
    let sourcePath: String
    let isCurrentStatusDatabase: Bool
}

struct ElleKitAssessment: Codable, Equatable {
    let evidenceStatus: ElleKitEvidenceStatus
    let installationState: ElleKitInstallationState
    let layoutEvidence: [ElleKitLayoutEvidence]
    let inaccessiblePaths: [String]
    let packageMetadata: ElleKitPackageMetadata?
    let binaryPathsFound: [String]
    let binaryMetadata: [String: ElleKitBinaryVersion]
    let binaryFingerprints: [String: ElleKitBinaryFingerprint]
    let profileMatch: ElleKitProfileMatch
    let candidateProfileIdentifier: String?
    /// True only when the observed package and binary identity match a pinned Profile.
    let profileIdentityVerified: Bool
    /// Source-control commit provenance is not established by binary fingerprint matching.
    let commitVerified: Bool
    let warnings: [String]
}
