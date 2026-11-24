import Foundation

enum JBRootCandidateSource: String, Codable, Equatable {
    case rootHideContainer
    case rootlessStandard
    case rootlessPrivateAlias
    case rootHidePrivateContainer
    case librootAPI
}

struct JBRootStructureCheck: Codable, Equatable, Identifiable {
    let path: String
    let exists: Bool
    let isDirectory: Bool
    let isReadable: Bool
    var id: String { path }
}

struct JBRootCandidateValidation: Codable, Equatable, Identifiable {
    let candidatePath: String
    let canonicalPath: String?
    let sources: [JBRootCandidateSource]
    let exists: Bool
    let isDirectory: Bool
    let isReadable: Bool
    let isSymbolicLink: Bool
    let symlinkEvidence: [String]
    let structureChecks: [JBRootStructureCheck]
    let score: Int
    let isStructurallyValid: Bool
    let detailCode: String
    var id: String { canonicalPath ?? candidatePath }
}

struct JBRootValidationReport: Codable, Equatable {
    let validatedAt: Date
    let candidates: [JBRootCandidateValidation]
    let validatedRootPath: String?
    let environmentKind: JailbreakEnvironmentKind
    let warnings: [String]
    let isReadOnly: Bool
    let apiEvidence: LibrootPathEvidence?

    var hasAmbiguousRoots: Bool {
        candidates.filter(\.isStructurallyValid).count > 1
    }

    /// Returns distinct path domains only after a unique JBROOT is validated.
    /// RootHide rootfs is never guessed; it is populated only from libroot.
    var jailbreakPaths: JailbreakPaths? {
        guard let validatedRootPath else { return nil }
        let apiMatchesSelectedRoot: Bool = {
            guard let apiRoot = apiEvidence?.jbrootPrefix else { return false }
            let apiCanonical = URL(fileURLWithPath: apiRoot).resolvingSymlinksInPath().standardizedFileURL.path
            let selectedCanonical = URL(fileURLWithPath: validatedRootPath).resolvingSymlinksInPath().standardizedFileURL.path
            return apiCanonical == selectedCanonical
        }()
        let rootfs: URL?
        if apiMatchesSelectedRoot, let apiRoot = apiEvidence?.rootPrefix {
            rootfs = URL(fileURLWithPath: apiRoot, isDirectory: true)
        } else if environmentKind == .rootless {
            rootfs = URL(fileURLWithPath: "/", isDirectory: true)
        } else {
            rootfs = nil
        }
        return JailbreakPaths(jbroot: URL(fileURLWithPath: validatedRootPath, isDirectory: true),
            rootfs: rootfs, bootUUID: apiMatchesSelectedRoot ? apiEvidence?.bootUUID : nil, jbrand: nil,
            source: apiMatchesSelectedRoot ? .librootAPI : .filesystemFallback)
    }
}
