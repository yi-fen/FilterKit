import Foundation

/// Evidence produced only after the root-owned FilterKit manifest and both deployed files
/// have been independently verified. It binds one plugin's exact filenames and byte hashes.
struct HelperOwnershipProof: Equatable {
    let pluginID: UUID
    let dylibFileName: String
    let plistFileName: String
    let dylibSHA256: String
    let plistSHA256: String
    let manifestSchemaVersion: Int
    let manifestSHA256: String
    let binaryIdentityVerified: Bool
    /// True only for the one-time root-side bootstrap path; it forbids replacing an existing plist.
    let isFirstInstallAuthorization: Bool

    init(pluginID: UUID, dylibFileName: String, plistFileName: String,
         dylibSHA256: String, plistSHA256: String, manifestSchemaVersion: Int,
         manifestSHA256: String, binaryIdentityVerified: Bool,
         isFirstInstallAuthorization: Bool = false) throws {
        guard HelperPolicy.isSafeLeafName(dylibFileName), dylibFileName.lowercased().hasSuffix(".dylib"),
              HelperPolicy.isSafeLeafName(plistFileName), plistFileName.lowercased().hasSuffix(".plist"),
              HelperPolicy.isValidHash(dylibSHA256), HelperPolicy.isValidHash(plistSHA256),
              HelperPolicy.isValidHash(manifestSHA256), manifestSchemaVersion >= 3,
              binaryIdentityVerified else { throw HelperOwnershipProofError.invalidEvidence }
        self.pluginID = pluginID
        self.dylibFileName = dylibFileName
        self.plistFileName = plistFileName
        self.dylibSHA256 = dylibSHA256.lowercased()
        self.plistSHA256 = plistSHA256.lowercased()
        self.manifestSchemaVersion = manifestSchemaVersion
        self.manifestSHA256 = manifestSHA256.lowercased()
        self.binaryIdentityVerified = binaryIdentityVerified
        self.isFirstInstallAuthorization = isFirstInstallAuthorization
    }
}

enum HelperOwnershipProofError: Error, Equatable { case invalidEvidence, planDoesNotMatchProof }
