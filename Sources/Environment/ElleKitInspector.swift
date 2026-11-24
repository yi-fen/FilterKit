import Foundation

/// Read-only ElleKit inspector. Package version comes only from an installed
/// dpkg status stanza; binary presence is supporting evidence, never a version source.
final class ElleKitInspector {
    private let fileManager: FileManager
    private let maximumStatusFileSize: UInt64 = 8 * 1024 * 1024
    private let cdHashProvider: ElleKitCDHashProviding?
    private let profileRegistry: ElleKitProfileRegistry

    init(fileManager: FileManager = .default, cdHashProvider: ElleKitCDHashProviding? = nil,
         profileRegistry: ElleKitProfileRegistry? = nil) {
        self.fileManager = fileManager
        self.cdHashProvider = cdHashProvider
        self.profileRegistry = profileRegistry ?? (try? ElleKitProfileRegistry.loadBundled()) ?? .builtIn
    }

    func inspect(rootPath: String, environment: JailbreakEnvironmentKind,
                 binaryCandidates: [String]) -> ElleKitAssessment {
        // The caller supplies the environment-specific root. All paths below are
        // read-only observations relative to that root.
        let layoutCandidates: [(String, ElleKitLayoutItemKind, Bool)] = [
            (rootPath + "/Library/TweakInject/ellekit.dylib", .mainDylib, true),
            (rootPath + "/Library/TweakInject/libellekit.dylib", .mainDylib, true),
            (rootPath + "/usr/lib/libellekit.dylib", .mainDylib, true),
            (rootPath + "/Library/TweakInject/pspawn.dylib", .companionDylib, true),
            (rootPath + "/usr/lib/TweakInject/pspawn.dylib", .companionDylib, true),
            (rootPath + "/usr/local/lib/libsubstrate.dylib", .compatibilityLink, false),
            (rootPath + "/Library/Frameworks/libsubstrate.dylib", .compatibilityLink, false),
            (rootPath + "/Library/Frameworks/ellekit.dylib", .compatibilityLink, false),
            (rootPath + "/usr/local/bin/loader", .loader, false),
            (rootPath + "/usr/libexec/ellekit/loader", .loader, false),
            (rootPath + "/Library/LaunchDaemons/com.evln.ellekit.startup.plist", .launchDaemon, false),
            (rootPath + "/var/lib/dpkg/info/ellekit.list", .dpkgInfo, false)
        ]
        let layout = layoutCandidates.map { path, kind, shouldCheckMachO in
            inspectLayoutItem(path: path, kind: kind, checkMachO: shouldCheckMachO)
        }
        let mainDylibEvidence = layout.filter { $0.kind == .mainDylib && $0.exists }
        let validMainDylib = mainDylibEvidence.contains { $0.isReadable && $0.isMachO == true }
        let binaryFound = binaryCandidates.filter { path in
            guard path.hasSuffix(".dylib") else { return false }
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }

        let statusPaths = [
            (rootPath + "/var/lib/dpkg/status", true),
            (rootPath + "/var/lib/dpkg/status-old", false)
        ]
        var metadataCandidates: [ElleKitPackageMetadata] = []
        var inaccessiblePaths: [String] = []
        for (path, isCurrent) in statusPaths {
            if fileManager.fileExists(atPath: path) && !fileManager.isReadableFile(atPath: path) {
                inaccessiblePaths.append(path)
            }
            guard let text = readStatusFile(at: path) else { continue }
            if let metadata = DpkgStatusParser.installedMetadata(in: text, sourcePath: path,
                                                                 isCurrentStatusDatabase: isCurrent) {
                metadataCandidates.append(metadata)
            }
        }

        let current = metadataCandidates.filter(\.isCurrentStatusDatabase)
        let fallback = metadataCandidates.filter { !$0.isCurrentStatusDatabase }
        let metadata: ElleKitPackageMetadata? = current.count == 1 ? current.first : (current.isEmpty && fallback.count == 1 ? fallback.first : nil)
        if current.count > 1 || (current.isEmpty && fallback.count > 1) {
            // Multiple installed stanzas/databases are not silently resolved.
        }

        inaccessiblePaths.append(contentsOf: layout.filter { $0.exists && !$0.isReadable }.map(\.path))
        inaccessiblePaths = Array(Set(inaccessiblePaths)).sorted()

        var warnings: [String] = []
        if current.count > 1 || (current.isEmpty && fallback.count > 1) { warnings.append("environment.ellekit.metadata_ambiguous") }
        if metadata == nil { warnings.append("environment.ellekit.package_metadata_unavailable") }
        if metadata?.isCurrentStatusDatabase == false { warnings.append("environment.ellekit.metadata_from_status_old") }
        if let currentMetadata = current.first, let fallbackMetadata = fallback.first,
           currentMetadata.version != fallbackMetadata.version || currentMetadata.architecture != fallbackMetadata.architecture {
            warnings.append("environment.ellekit.status_database_conflict")
        }
        if !binaryFound.isEmpty && metadata == nil { warnings.append("environment.ellekit.binary_without_package_metadata") }
        if metadata != nil && !validMainDylib { warnings.append("environment.ellekit.package_without_valid_main_dylib") }
        if !validMainDylib && !mainDylibEvidence.isEmpty { warnings.append("environment.ellekit.main_dylib_not_valid_macho") }
        if !inaccessiblePaths.isEmpty { warnings.append("environment.ellekit.paths_inaccessible") }

        let evidence: ElleKitEvidenceStatus
        if current.count > 1 || (current.isEmpty && fallback.count > 1) { evidence = .ambiguous }
        else if metadata?.isCurrentStatusDatabase == false { evidence = .metadataFallbackOnly }
        else if metadata != nil && validMainDylib { evidence = .installed }
        else if metadata != nil && !mainDylibEvidence.isEmpty { evidence = .inconsistent }
        else if metadata != nil { evidence = .packageMetadataOnly }
        else if !mainDylibEvidence.isEmpty { evidence = .binaryOnly }
        else { evidence = .notDetected }

        let installationState: ElleKitInstallationState
        if !inaccessiblePaths.isEmpty && metadata == nil && !validMainDylib { installationState = .inaccessible }
        else if metadata?.isCurrentStatusDatabase == true && validMainDylib { installationState = .installed }
        else if validMainDylib { installationState = .installed }
        else if metadata != nil || layout.contains(where: { $0.exists }) { installationState = .suspected }
        else { installationState = .notFound }


        var binaryMetadata: [String: ElleKitBinaryVersion] = [:]
        let metadataReader = MachOMetadataReader()
        for path in Set(binaryFound + mainDylibEvidence.filter { $0.isMachO == true }.map(\.path)) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let parsed = try? metadataReader.read(data: data) else { continue }
            binaryMetadata[path] = parsed
        }

        var fingerprints: [String: ElleKitBinaryFingerprint] = [:]
        for (path, parsed) in binaryMetadata {
            let cdHash = try? cdHashProvider?.cdHash(for: URL(fileURLWithPath: path))
            fingerprints[path] = ElleKitBinaryFingerprint(installName: parsed.installName,
                                                            currentVersion: parsed.currentVersion,
                                                            compatibilityVersion: parsed.compatibilityVersion,
                                                            uuid: parsed.uuid,
                                                            cdHash: cdHash ?? nil,
                                                            architecture: parsed.architecture)
        }

        let distinctBinaryIdentities = Set(fingerprints.values.map { fingerprint in
            [fingerprint.installName ?? "?", fingerprint.uuid ?? "?", fingerprint.cdHash ?? "?",
             fingerprint.architecture ?? "?"].joined(separator: "|")
        })
        if distinctBinaryIdentities.count > 1 {
            warnings.append("environment.ellekit.multiple_binary_candidates_conflict")
        }

        let profileMatchResult = ElleKitProfileMatcher(registry: profileRegistry).match(
            environment: environment,
            package: metadata?.isCurrentStatusDatabase == true ? metadata : nil,
            fingerprints: Array(fingerprints.values),
            hasInaccessibleEvidence: !inaccessiblePaths.isEmpty
        )
        if profileMatchResult.outcome == .unknownFingerprint {
            warnings.append("environment.ellekit.profile_fingerprint_unknown")
        } else if profileMatchResult.outcome == .unverifiable {
            warnings.append("environment.ellekit.profile_unverifiable")
        } else if profileMatchResult.outcome == .identityMismatch {
            warnings.append("environment.ellekit.profile_identity_mismatch")
        } else if profileMatchResult.outcome == .versionMismatch {
            warnings.append("environment.ellekit.profile_version_mismatch")
        } else if profileMatchResult.outcome == .ambiguous {
            warnings.append("environment.ellekit.profile_ambiguous")
        }

        return ElleKitAssessment(evidenceStatus: evidence, installationState: installationState,
                                 layoutEvidence: layout, inaccessiblePaths: inaccessiblePaths,
                                 packageMetadata: metadata, binaryPathsFound: binaryFound,
                                 binaryMetadata: binaryMetadata, binaryFingerprints: fingerprints,
                                 profileMatch: profileMatchResult.outcome, candidateProfileIdentifier: profileMatchResult.profileIdentifier,
                                 profileIdentityVerified: profileMatchResult.outcome == .matched,
                                 commitVerified: false, warnings: warnings)
    }

    private func inspectLayoutItem(path: String, kind: ElleKitLayoutItemKind,
                                   checkMachO: Bool) -> ElleKitLayoutEvidence {
        let exists = fileManager.fileExists(atPath: path)
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let isLink = attributes?[.type] as? FileAttributeType == .typeSymbolicLink
        let readable = exists && fileManager.isReadableFile(atPath: path)
        let macho: Bool? = checkMachO && readable ? hasMachOMagic(at: path) : (checkMachO ? false : nil)
        return ElleKitLayoutEvidence(id: "\(kind.rawValue):\(path)", path: path, kind: kind,
                                     exists: exists, isReadable: readable,
                                     isSymbolicLink: isLink, isMachO: macho)
    }

    private func hasMachOMagic(at path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let bytes = [UInt8](data)
        // Thin and fat Mach-O magic, both endian variants.
        let value = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return [0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE,
                0xCAFEBABE, 0xBEBAFECA, 0xCAFEBABF, 0xBFBAFECA].contains(value)
    }

    private func readStatusFile(at path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isReadableFile(atPath: path),
              let attributes = try? fileManager.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value <= maximumStatusFileSize,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}
