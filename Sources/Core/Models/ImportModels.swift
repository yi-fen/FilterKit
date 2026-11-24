import Foundation

enum PluginImportSource: String, Codable {
    case dylib
    case zip
    case deb
}

struct PluginImportPreview {
    let source: PluginImportSource
    let targetBundleIdentifier: String
    let proposedDylibFileName: String
    let containsOriginalPlist: Bool
    let warnings: [String]
}

struct PluginImportPlan {
    let operationID: UUID
    let stagingIdentifier: UUID
    let targetBundleIdentifier: String
    let dylibSHA256: String
    let plistSHA256: String
    let profileIdentifier: String
}
