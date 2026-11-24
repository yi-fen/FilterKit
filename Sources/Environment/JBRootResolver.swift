import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Read-only JBROOT resolver. API evidence is cross-checked against filesystem
/// structure; it never wins over contradictory or ambiguous filesystem evidence.
final class JBRootResolver {
    private let fileManager: FileManager
    private let rootlessCandidates: [(String, JBRootCandidateSource)]
    private let rootHideContainers: [String]
    private let librootProbe: LibrootRuntimeProbe

    init(fileManager: FileManager = .default,
         rootlessCandidates: [(String, JBRootCandidateSource)] = [
            ("/var/jb", .rootlessStandard),
            ("/private/var/jb", .rootlessPrivateAlias)
         ],
         rootHideContainers: [String] = [
            "/var/containers/Bundle/Application",
            "/private/var/containers/Bundle/Application"
         ],
         librootProbe: LibrootRuntimeProbe = LibrootRuntimeProbe()) {
        self.fileManager = fileManager
        self.rootlessCandidates = rootlessCandidates
        self.rootHideContainers = rootHideContainers
        self.librootProbe = librootProbe
    }

    /// Compatibility initializer for existing tests/callers.
    convenience init(fileManager: FileManager = .default,
                     rootlessCandidates: [(String, JBRootCandidateSource)],
                     rootHideContainer: String) {
        self.init(fileManager: fileManager, rootlessCandidates: rootlessCandidates,
                  rootHideContainers: [rootHideContainer], librootProbe: LibrootRuntimeProbe())
    }

    func validate() -> JBRootValidationReport {
        let api = librootProbe.inspect()
        var rawCandidates = discoverCandidates()
        if let apiPath = api.jbrootPrefix {
            rawCandidates.insert((apiPath, .librootAPI), at: 0)
        }
        let validated = rawCandidates.map(validateCandidate)
        let grouped = Dictionary(grouping: validated) { $0.canonicalPath ?? $0.candidatePath }
        let merged = grouped.values.map(mergeAliases).sorted { $0.candidatePath < $1.candidatePath }
        let valid = merged.filter(\.isStructurallyValid)

        // API evidence is not a shortcut: its candidate must pass the same
        // structural checks and must not conflict with another distinct root.
        let selectedPath = valid.count == 1 ? valid[0].canonicalPath : nil
        let kind: JailbreakEnvironmentKind
        if valid.count != 1 { kind = .unknown }
        else if valid[0].sources.contains(.rootHideContainer) ||
                    valid[0].sources.contains(.rootHidePrivateContainer) ||
                    valid[0].candidatePath.contains(".jbroot-") { kind = .rootHide }
        else { kind = .rootless }

        var warnings: [String] = []
        if valid.isEmpty { warnings.append("environment.root.validation_failed") }
        if valid.count > 1 { warnings.append("environment.root.ambiguous") }
        if merged.contains(where: { $0.isSymbolicLink }) { warnings.append("environment.root.symlink_resolved") }
        if api.loaded && api.jbrootPrefix != nil && selectedPath == nil {
            warnings.append("environment.root.libroot_conflicts_or_unvalidated")
        }
        warnings.append("environment.probe.read_only")
        return JBRootValidationReport(validatedAt: Date(), candidates: merged,
            validatedRootPath: selectedPath, environmentKind: kind, warnings: warnings,
            isReadOnly: true, apiEvidence: api)
    }

    private func discoverCandidates() -> [(String, JBRootCandidateSource)] {
        var result = rootlessCandidates
        for container in rootHideContainers {
            guard let children = try? fileManager.contentsOfDirectory(atPath: container) else { continue }
            result.append(contentsOf: children.filter(Self.isJBRootDirectoryName)
                .map { (container + "/" + $0, container.hasPrefix("/private/") ? .rootHidePrivateContainer : .rootHideContainer) })
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.0).inserted }
    }

    /// Format gate only. The historical jbrand checksum algorithm is not
    /// reimplemented here until verified against the target Dopamine source.
    static func isJBRootDirectoryName(_ name: String) -> Bool {
        guard name.hasPrefix(".jbroot-") else { return false }
        let suffix = String(name.dropFirst(".jbroot-".count))
        guard suffix.count == 16, suffix.allSatisfy({ $0.isHexDigit }) else { return false }
        return suffix.contains(where: { $0 != "0" })
    }

    private func validateCandidate(_ item: (String, JBRootCandidateSource)) -> JBRootCandidateValidation {
        let path = item.0
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        let readable = exists && fileManager.isReadableFile(atPath: path)
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let isSymlink = (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
        let canonical = exists ? URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path : nil
        let checks = ["usr", "usr/lib"].map { relativePath -> JBRootStructureCheck in
            let checkPath = path + "/" + relativePath
            var directory: ObjCBool = false
            let found = fileManager.fileExists(atPath: checkPath, isDirectory: &directory)
            return JBRootStructureCheck(path: relativePath, exists: found,
                isDirectory: found && directory.boolValue,
                isReadable: found && directory.boolValue && fileManager.isReadableFile(atPath: checkPath))
        }
        let structureValid = checks.allSatisfy { $0.exists && $0.isDirectory && $0.isReadable }
        let symlinkEvidence = symlinkEvidence(for: path, source: item.1)
        var score = exists ? 1 : 0
        if isDirectory.boolValue { score += 1 }
        if readable { score += 1 }
        if structureValid { score += 5 }
        let code: String
        if !exists { code = "root.not_found" }
        else if !isDirectory.boolValue { code = "root.not_directory" }
        else if !readable { code = "root.not_readable" }
        else if !structureValid { code = "root.required_structure_missing" }
        else { code = "root.validated" }
        return JBRootCandidateValidation(candidatePath: path, canonicalPath: canonical,
            sources: [item.1], exists: exists, isDirectory: isDirectory.boolValue,
            isReadable: readable, isSymbolicLink: isSymlink || !symlinkEvidence.isEmpty,
            symlinkEvidence: symlinkEvidence, structureChecks: checks, score: score,
            isStructurallyValid: exists && isDirectory.boolValue && readable && structureValid,
            detailCode: code)
    }

    /// Record link characteristics without treating an unverified marker as
    /// proof. RootHide link locations vary; the candidate itself is checked via
    /// lstat and its canonical target is retained as evidence.
    private func symlinkEvidence(for path: String, source: JBRootCandidateSource) -> [String] {
        var evidence: [String] = []
        #if canImport(Darwin)
        var info = stat()
        if lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK {
            evidence.append("candidate_is_symlink")
        }
        if source == .rootlessStandard || source == .rootlessPrivateAlias {
            if lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK {
                evidence.append("rootless_bootstrap_symlink")
            } else if lstat(path, &info) == 0 {
                evidence.append("rootless_bootstrap_not_symlink")
            }
        }
        #endif
        return evidence
    }

    private func mergeAliases(_ items: [JBRootCandidateValidation]) -> JBRootCandidateValidation {
        guard items.count > 1, let first = items.first else { return items[0] }
        let best = items.first(where: \.isStructurallyValid) ?? first
        return JBRootCandidateValidation(candidatePath: best.candidatePath,
            canonicalPath: best.canonicalPath,
            sources: Array(Set(items.flatMap(\.sources))).sorted { $0.rawValue < $1.rawValue },
            exists: items.contains(where: \.exists),
            isDirectory: items.contains(where: \.isDirectory),
            isReadable: items.contains(where: \.isReadable),
            isSymbolicLink: items.contains(where: \.isSymbolicLink),
            symlinkEvidence: Array(Set(items.flatMap(\.symlinkEvidence))).sorted(),
            structureChecks: best.structureChecks, score: items.map(\.score).max() ?? 0,
            isStructurallyValid: items.contains(where: \.isStructurallyValid),
            detailCode: items.contains(where: \.isStructurallyValid) ? "root.validated_aliases_merged" : best.detailCode)
    }
}
