import Foundation

enum ProbeStatus: String, Codable {
    case found
    case missing
    case inaccessible
    case invalid
    case ambiguous
    case notChecked
}

struct PathProbeResult: Codable, Equatable, Identifiable {
    let id: String
    let path: String
    let status: ProbeStatus
    let isDirectory: Bool
    let detailCode: String
}

struct EnvironmentDiagnosticReport: Codable, Equatable {
    let detectedAt: Date
    let environment: JailbreakEnvironment
    let rootCandidates: [PathProbeResult]
    let rootValidation: JBRootValidationReport
    let dynamicLibrariesCandidates: [PathProbeResult]
    let elleKitCandidates: [PathProbeResult]
    var elleKitAssessment: ElleKitAssessment? = nil
    let resolvedRootPath: String?
    let resolvedDynamicLibrariesPath: String?
    let warnings: [String]
    var pluginDirectoryAssessment: PluginDirectoryAssessment? = nil
    let isReadOnly: Bool
}

enum EnvironmentProbeError: Error {
    case noSupportedRootFound
    case ambiguousRoot
    case dynamicLibrariesDirectoryUnavailable
}
