import Foundation

enum PluginOwnership: String, Codable, CaseIterable {
    case filterKit
    case packageManager
    case unknown
}

enum PluginAvailability: String, Codable {
    case installed
    case partiallyInstalled
    case unavailable
}

/// The immutable source identity is kept separate from currently available associations.
struct PluginAssociations: Codable, Equatable {
    let hardBoundBundleIdentifier: String
    var softAssociatedBundleIdentifiers: Set<String>
    var effectiveBundleIdentifiers: Set<String>

    init(hardBoundBundleIdentifier: String,
         softAssociatedBundleIdentifiers: Set<String> = [],
         effectiveBundleIdentifiers: Set<String> = []) {
        self.hardBoundBundleIdentifier = hardBoundBundleIdentifier
        self.softAssociatedBundleIdentifiers = softAssociatedBundleIdentifiers
        self.effectiveBundleIdentifiers = effectiveBundleIdentifiers
    }
}

struct PluginRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let displayName: String
    let dylibFileName: String
    let plistFileName: String?
    let ownership: PluginOwnership
    let availability: PluginAvailability
    let hardBoundBundleIdentifier: String?
    let softAssociatedBundleIdentifiers: Set<String>
    let dylibSHA256: String?

    init(id: UUID = UUID(), displayName: String, dylibFileName: String,
         plistFileName: String? = nil, ownership: PluginOwnership,
         availability: PluginAvailability = .installed,
         hardBoundBundleIdentifier: String? = nil,
         softAssociatedBundleIdentifiers: Set<String> = [], dylibSHA256: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.dylibFileName = dylibFileName
        self.plistFileName = plistFileName
        self.ownership = ownership
        self.availability = availability
        self.hardBoundBundleIdentifier = hardBoundBundleIdentifier
        self.softAssociatedBundleIdentifiers = softAssociatedBundleIdentifiers
        self.dylibSHA256 = dylibSHA256
    }
}

