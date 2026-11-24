import Foundation

/// Debian package identity. Values are taken from the installed dpkg status stanza,
/// never inferred from a dylib filename or Mach-O compatibility version.
struct ElleKitPackageIdentity: Codable, Equatable {
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

/// Mach-O's linker compatibility metadata; deliberately separate from Debian Version.
struct ElleKitBinaryVersion: Codable, Equatable {
    let currentVersion: String?
    let compatibilityVersion: String?
    let installName: String?
    let uuid: String?
    let architecture: String?
    let is64Bit: Bool
}

enum ElleKitBinaryMetadataError: Error, Equatable {
    case notMachO
    case truncated
    case malformedLoadCommand
    case unsupportedFatBinary
    case noSupportedSlice
}

/// CDHash is provided by a platform adapter because the iOS app sandbox and
/// available signing APIs differ by OS/build. `nil` means unavailable, not mismatch.
protocol ElleKitCDHashProviding {
    func cdHash(for binaryURL: URL) throws -> String?
}

struct ElleKitBinaryFingerprint: Codable, Equatable {
    let installName: String?
    let currentVersion: String?
    let compatibilityVersion: String?
    let uuid: String?
    let cdHash: String?
    let architecture: String?
}
