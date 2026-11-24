import Foundation

/// Separates the writable jailbreak prefix from the real system root.
/// Values are observations, not authorization to write to either location.
struct JailbreakPaths: Codable, Equatable {
    let jbroot: URL
    let rootfs: URL?
    let bootUUID: String?
    let jbrand: UInt64?
    let source: JailbreakPathSource
}

enum JailbreakPathSource: String, Codable {
    case librootAPI
    case filesystemFallback
}

struct LibrootPathEvidence: Codable, Equatable {
    let libraryPath: String?
    let jbrootPrefix: String?
    let rootPrefix: String?
    let bootUUID: String?
    let loaded: Bool
    let diagnosticCode: String
}

/// Path conversion is deliberately isolated. No conversion is attempted until
/// a device-validated adapter is supplied for the active jailbreak profile.
protocol JailbreakPathTranslator {
    func toJBRoot(_ rootfsPath: String) throws -> String
    func toRootFS(_ jbrootPath: String) throws -> String
}
