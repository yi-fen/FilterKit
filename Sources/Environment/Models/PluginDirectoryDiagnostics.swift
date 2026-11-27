import Foundation

enum PluginDirectoryKind: String, Codable {
    case tweakInject
    case elleKitDynamicLibraries
    case mobileSubstrateDynamicLibraries
    case elleKitComponentDirectory
}

enum PluginDirectoryRole: String, Codable {
    case thirdPartyPluginDirectory
    case elleKitComponentDirectory
}

enum PluginDirectoryResolutionState: String, Codable {
    case resolved
    case ambiguous
    case unavailable
    case inaccessible
}

struct PluginDirectoryCandidate: Codable, Equatable, Identifiable {
    let path: String
    let canonicalPath: String?
    let kind: PluginDirectoryKind
    let role: PluginDirectoryRole
    let exists: Bool
    let isDirectory: Bool
    let isReadable: Bool
    let isEnumerable: Bool
    let isWritable: Bool
    let isSymbolicLink: Bool
    let dylibCount: Int
    let plistCount: Int
    /// Directory entries captured during the read-only assessment. The inventory
    /// scanner reuses this listing instead of enumerating the same directory again.
    var entryNames: [String]? = nil
    let detailCode: String

    var id: String { canonicalPath ?? path }
    var isUsable: Bool {
        exists && isDirectory && isReadable && isEnumerable && role == .thirdPartyPluginDirectory
    }
}

struct PluginDirectoryAssessment: Codable, Equatable {
    let state: PluginDirectoryResolutionState
    let selectedPath: String?
    let candidates: [PluginDirectoryCandidate]
    let warnings: [String]
    let isReadOnly: Bool

    static func unresolved(_ warning: String) -> PluginDirectoryAssessment {
        PluginDirectoryAssessment(state: .unavailable, selectedPath: nil,
                                  candidates: [], warnings: [warning], isReadOnly: true)
    }
}
