import Foundation

enum JailbreakEnvironmentKind: String, Codable {
    case rootHide
    case rootless
    case unsupported
    case unknown
}

struct ElleKitInstallation: Codable, Equatable {
    let version: String?
    let commit: String?
    let isPresent: Bool
    let evidenceStatus: ElleKitEvidenceStatus
    let installationState: ElleKitInstallationState
    let architecture: String?

    init(version: String?, commit: String?, isPresent: Bool,
         evidenceStatus: ElleKitEvidenceStatus = .notDetected, installationState: ElleKitInstallationState = .notFound, architecture: String? = nil) {
        self.version = version
        self.commit = commit
        self.isPresent = isPresent
        self.evidenceStatus = evidenceStatus
        self.installationState = installationState
        self.architecture = architecture
    }
}

struct EnvironmentPaths: Codable, Equatable {
    /// Resolved by a verified environment adapter; never supplied by UI input.
    let pluginDirectory: URL
    let dynamicLibrariesDirectory: URL
}

struct EnvironmentCapabilities: Codable, Equatable {
    let canDiscoverApps: Bool
    let canReadPluginDirectory: Bool
    let canDeployFilterKitPlugins: Bool
    let supportedArchitectures: [String]
}

struct JailbreakEnvironment: Codable, Equatable {
    let kind: JailbreakEnvironmentKind
    let displayVersion: String?
    let elleKit: ElleKitInstallation
}
