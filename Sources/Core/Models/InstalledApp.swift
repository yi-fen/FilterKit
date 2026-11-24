import Foundation

enum AppSystemClassification: String, Codable, Equatable {
    case system
    case user
    case hidden
    case unknown
}

enum AppDiscoverySource: String, Codable, Equatable {
    case launchServices
    case directoryScan
}

/// Read-only metadata for an installed app. Paths are descriptive; FilterKit never edits app bundles.
struct InstalledApp: Identifiable, Codable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let displayName: String
    let systemClassification: AppSystemClassification
    let bundleURL: URL?
    let shortVersion: String?
    let buildVersion: String?
    let executableName: String?
    let iconDescriptor: AppIconDescriptor?
    let discoverySource: AppDiscoverySource

    var isSystemApp: Bool { systemClassification == .system }

    init(bundleIdentifier: String, displayName: String, isSystemApp: Bool, bundleURL: URL? = nil) {
        self.init(bundleIdentifier: bundleIdentifier, displayName: displayName,
                  systemClassification: isSystemApp ? .system : .user, bundleURL: bundleURL)
    }

    init(bundleIdentifier: String, displayName: String,
         systemClassification: AppSystemClassification, bundleURL: URL? = nil,
         shortVersion: String? = nil, buildVersion: String? = nil,
         executableName: String? = nil, iconDescriptor: AppIconDescriptor? = nil,
         discoverySource: AppDiscoverySource = .launchServices) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.systemClassification = systemClassification
        self.bundleURL = bundleURL
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.executableName = executableName
        self.iconDescriptor = iconDescriptor
        self.discoverySource = discoverySource
    }
}

struct AppIconDescriptor: Codable, Hashable {
    let fileCandidates: [URL]
    let assetName: String?
    let bundleURL: URL?
    let embeddedIconData: Data?

    init(fileCandidates: [URL], assetName: String?, bundleURL: URL?, embeddedIconData: Data? = nil) {
        self.fileCandidates = fileCandidates
        self.assetName = assetName
        self.bundleURL = bundleURL
        self.embeddedIconData = embeddedIconData
    }
}
