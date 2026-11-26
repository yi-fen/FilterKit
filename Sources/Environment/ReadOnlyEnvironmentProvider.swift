import Foundation

/// Conservative, read-only environment inspection. This implementation never
/// creates, changes, renames, or deletes files and never invokes a shell.
final class ReadOnlyEnvironmentProvider: EnvironmentProvider {
    private let fileManager: FileManager
    private let rootResolver: JBRootResolver
    private let elleKitInspector: ElleKitInspector
    private let pluginDirectoryLocator: PluginDirectoryLocator

    init(fileManager: FileManager = .default, rootResolver: JBRootResolver? = nil,
         elleKitInspector: ElleKitInspector? = nil,
         pluginDirectoryLocator: PluginDirectoryLocator? = nil) {
        self.fileManager = fileManager
        self.rootResolver = rootResolver ?? JBRootResolver(fileManager: fileManager)
        self.elleKitInspector = elleKitInspector ?? ElleKitInspector(fileManager: fileManager)
        self.pluginDirectoryLocator = pluginDirectoryLocator ?? PluginDirectoryLocator(fileManager: fileManager)
    }

    func detectEnvironment() async throws -> JailbreakEnvironment {
        let report = makeDiagnosticReport()
        return report.environment
    }

    func resolvePaths() async throws -> EnvironmentPaths {
        let report = makeDiagnosticReport()
        guard report.resolvedRootPath != nil else {
            if report.rootCandidates.filter({ $0.status == .found }).count > 1 {
                throw EnvironmentProbeError.ambiguousRoot
            }
            throw EnvironmentProbeError.noSupportedRootFound
        }
        guard let libraries = report.resolvedDynamicLibrariesPath else {
            throw EnvironmentProbeError.dynamicLibrariesDirectoryUnavailable
        }
        return EnvironmentPaths(pluginDirectory: URL(fileURLWithPath: libraries, isDirectory: true),
                                dynamicLibrariesDirectory: URL(fileURLWithPath: libraries, isDirectory: true))
    }

    func inspectElleKit() async throws -> ElleKitInstallation {
        let report = makeDiagnosticReport()
        let assessment = report.elleKitAssessment
        let metadata = assessment?.packageMetadata
        let evidence = assessment?.evidenceStatus ?? .notDetected
        let installationState = assessment?.installationState ?? .notFound
        let isDetected = installationState == .installed || installationState == .suspected
        return ElleKitInstallation(version: metadata?.version, commit: nil,
                                   isPresent: isDetected, evidenceStatus: evidence,
                                   installationState: installationState,
                                   architecture: metadata?.architecture)
    }

    func validateCapabilities() async throws -> EnvironmentCapabilities {
        let report = makeDiagnosticReport()
        let hasReadableLibraries = report.dynamicLibrariesCandidates.contains {
            $0.status == .found && $0.isDirectory
        }
        // Read-only P1-01 cannot authorize deployment. These remain false until
        // separate, device-validated permission and helper checks are implemented.
        return EnvironmentCapabilities(canDiscoverApps: false,
                                       canReadPluginDirectory: hasReadableLibraries,
                                       canDeployFilterKitPlugins: false,
                                       supportedArchitectures: [])
    }

    func makeDiagnosticReport() -> EnvironmentDiagnosticReport {
        let rootValidation = rootResolver.validate()
        let rootResults = rootValidation.candidates.map { candidate in
            PathProbeResult(id: "root-\(candidate.candidatePath)",
                            path: candidate.candidatePath,
                            status: candidate.isStructurallyValid ? .found : (!candidate.exists ? .missing : (!candidate.isReadable ? .inaccessible : .invalid)),
                            isDirectory: candidate.isDirectory,
                            detailCode: candidate.detailCode)
        }
        let selectedRoot = rootValidation.validatedRootPath
        let kind = rootValidation.environmentKind
        let selectedRoots = selectedRoot.map { [$0] } ?? []

        let pluginDirectoryAssessment = selectedRoot.map {
            pluginDirectoryLocator.inspect(jbroot: $0, environment: kind)
        }
        let libraryResults = (pluginDirectoryAssessment?.candidates ?? []).map { candidate in
            PathProbeResult(id: "plugin-dir-\(candidate.path)", path: candidate.path,
                status: candidate.isUsable ? .found : (!candidate.exists ? .missing :
                    ((!candidate.isReadable || !candidate.isEnumerable) ? .inaccessible : .invalid)),
                isDirectory: candidate.isDirectory, detailCode: candidate.detailCode)
        }
        let selectedLibraries = pluginDirectoryAssessment?.selectedPath

        let elleKitPaths = selectedRoots.flatMap { Self.elleKitCandidatePaths(for: $0) }
        let assessment = selectedRoot.map {
            elleKitInspector.inspect(rootPath: $0, environment: kind, binaryCandidates: elleKitPaths)
        }
        let elleKitResults = elleKitPaths.map { probe(path: $0, id: "ellekit-\($0)") }
        var warnings = rootValidation.warnings
        if selectedRoot == nil { warnings.append("environment.root.unresolved") }
        warnings.append(contentsOf: pluginDirectoryAssessment?.warnings ?? ["environment.plugin_directory.not_checked"])
        warnings.append(contentsOf: assessment?.warnings ?? ["environment.ellekit.not_checked"])

        let metadata = assessment?.packageMetadata
        let evidence = assessment?.evidenceStatus ?? .notDetected
        let installationState = assessment?.installationState ?? .notFound
        let isDetected = installationState == .installed || installationState == .suspected
        let installation = ElleKitInstallation(version: metadata?.version, commit: nil,
                                                isPresent: isDetected, evidenceStatus: evidence,
                                                installationState: installationState,
                                                architecture: metadata?.architecture)
        let environment = JailbreakEnvironment(kind: kind, displayVersion: nil, elleKit: installation)
        return EnvironmentDiagnosticReport(detectedAt: Date(), environment: environment,
                                           rootCandidates: rootResults, rootValidation: rootValidation,
                                           dynamicLibrariesCandidates: libraryResults,
                                           elleKitCandidates: elleKitResults,
                                           elleKitAssessment: assessment,
                                           resolvedRootPath: selectedRoot,
                                           resolvedDynamicLibrariesPath: selectedLibraries,
                                           warnings: warnings, pluginDirectoryAssessment: pluginDirectoryAssessment,
                                           isReadOnly: true)
    }


    private func probe(path: String, id: String) -> PathProbeResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return PathProbeResult(id: id, path: path, status: .missing,
                                   isDirectory: false, detailCode: "path.not_found")
        }
        let readable = fileManager.isReadableFile(atPath: path)
        return PathProbeResult(id: id, path: path,
                               status: readable ? .found : .inaccessible,
                               isDirectory: isDirectory.boolValue,
                               detailCode: readable ? "path.readable" : "path.not_readable")
    }

    private static func elleKitCandidatePaths(for root: String) -> [String] {
        [
            root + "/Library/TweakInject/ellekit.dylib",
            root + "/Library/TweakInject/libellekit.dylib",
            root + "/usr/lib/libellekit.dylib",
            root + "/Library/TweakInject/pspawn.dylib",
            root + "/usr/lib/TweakInject/pspawn.dylib",
            root + "/usr/local/lib/libsubstrate.dylib",
            root + "/Library/Frameworks/libsubstrate.dylib",
            root + "/Library/Frameworks/ellekit.dylib",
            root + "/usr/local/bin/loader",
            root + "/usr/libexec/ellekit/loader",
            root + "/Library/LaunchDaemons/com.evln.ellekit.startup.plist",
            root + "/var/lib/dpkg/info/ellekit.list"
        ]
    }
}
