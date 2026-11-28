import Foundation

/// Scans the supported third-party plugin directories reported by PluginDirectoryLocator.
/// It never writes, renames, chmods, or deletes files and never invokes dpkg.
/// Optional package ownership evidence is read from the existing dpkg database index.
final class ReadOnlyPluginScanner: PluginDiscoveryProvider {
    private let fileManager: FileManager
    private let assessmentProvider: (() -> PluginDirectoryAssessment)?
    private let packageOwnershipProvider: PackageOwnershipProviding?
    private let maximumManifestBytes = 64 * 1024
    private let maximumDylibBytes: UInt64 = 128 * 1024 * 1024
    private let maximumPlistBytes: UInt64 = 2 * 1024 * 1024

    init(fileManager: FileManager = .default,
         assessmentProvider: (() -> PluginDirectoryAssessment)? = nil,
         packageOwnershipProvider: PackageOwnershipProviding? = nil) {
        self.fileManager = fileManager
        self.assessmentProvider = assessmentProvider
        self.packageOwnershipProvider = packageOwnershipProvider
    }

    func scanPlugins() async throws -> PluginScanResult {
        guard let assessmentProvider else {
            return scan(assessment: .unresolved("plugin_scan.directory_assessment_not_injected"))
        }
        return scan(assessment: assessmentProvider())
    }

    func scan(assessment: PluginDirectoryAssessment) -> PluginScanResult {
        guard assessment.state == .resolved || assessment.state == .ambiguous || assessment.state == .inaccessible else {
            return PluginScanResult(scannedAt: Date(), scannedDirectory: nil,
                directoryState: assessment.state, plugins: [],
                issues: [PluginScanIssue(id: "directory-unresolved", code: "plugin_scan.directory_not_resolved", fileName: nil, detail: nil)],
                isReadOnly: true)
        }

        // R16 inventory inspected all supported DynamicLibraries locations beneath
        // the same jailbreak root. The modern locator may mark multiple populated
        // locations as ambiguous; for read-only inventory we can safely aggregate
        // them instead of dropping every plugin. Management still uses each file's
        // real URL and ownership evidence, so no directory is silently preferred.
        var issues: [PluginScanIssue] = assessment.candidates.compactMap { candidate in
            guard candidate.role == .thirdPartyPluginDirectory, candidate.exists, !candidate.isUsable else { return nil }
            return issue("candidate-unavailable-\(candidate.path)",
                         "plugin_scan.directory_candidate_unavailable", candidate.path)
        }
        var candidatePaths = assessment.candidates
            .filter { $0.isUsable }
            .map { $0.canonicalPath ?? $0.path }
        if let selected = assessment.selectedPath { candidatePaths.append(selected) }
        let scanPaths = Array(Set(candidatePaths)).sorted()
        if scanPaths.isEmpty {
            return PluginScanResult(scannedAt: Date(), scannedDirectory: nil,
                directoryState: assessment.state, plugins: [], issues: issues,
                isReadOnly: true)
        }
        var readableDirectories: [URL] = []
        for candidate in scanPaths {
            let directoryURL = URL(fileURLWithPath: candidate, isDirectory: true).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue, fileManager.isReadableFile(atPath: directoryURL.path) else {
                issues.append(issue("directory-inaccessible-\(directoryURL.lastPathComponent)",
                                    "plugin_scan.directory_candidate_inaccessible", directoryURL.lastPathComponent))
                continue
            }
            let canonical = directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard directoryURL.path == canonical else {
                issues.append(issue("directory-canonical-\(directoryURL.lastPathComponent)",
                                    "plugin_scan.directory_path_mismatch", directoryURL.lastPathComponent))
                continue
            }
            readableDirectories.append(directoryURL)
        }
        guard !readableDirectories.isEmpty else {
            return PluginScanResult(scannedAt: Date(), scannedDirectory: nil,
                directoryState: .inaccessible, plugins: [],
                issues: issues + [PluginScanIssue(id: "directory-inaccessible", code: "plugin_scan.directory_inaccessible", fileName: nil, detail: nil)],
                isReadOnly: true)
        }

        var dylibs: [String: [URL]] = [:]
        var plists: [String: [URL]] = [:]
        var manifests: [String: [URL]] = [:]
        let assessedEntries = Dictionary(assessment.candidates.compactMap { candidate -> (String, [String])? in
            guard let canonical = candidate.canonicalPath, let names = candidate.entryNames else { return nil }
            return (canonical, names)
        }, uniquingKeysWith: { first, _ in first })
        for directoryURL in readableDirectories {
            let names: [String]
            if let reused = assessedEntries[directoryURL.path] {
                PluginInventoryPerformanceDiagnostics.recordDirectoryListingReuse()
                names = reused
            } else {
                PluginInventoryPerformanceDiagnostics.recordDirectoryEnumeration()
                guard let enumerated = try? fileManager.contentsOfDirectory(atPath: directoryURL.path) else {
                    issues.append(issue("directory-enumeration-\(directoryURL.lastPathComponent)",
                                        "plugin_scan.enumeration_failed", directoryURL.lastPathComponent))
                    continue
                }
                names = enumerated
            }
            for name in names.sorted() {
                let url = directoryURL.appendingPathComponent(name)
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                if values?.isSymbolicLink == true {
                    issues.append(issue("symlink-\(directoryURL.lastPathComponent)-\(name)", "plugin_scan.symlink_skipped", name)); continue
                }
                guard values?.isRegularFile == true else { continue }
                let lower = name.lowercased()
                if lower.hasSuffix(".dylib") {
                    let stem = String(name.dropLast(6)).lowercased(); dylibs[stem, default: []].append(url)
                } else if lower.hasSuffix(".plist") {
                    let stem = String(name.dropLast(6)).lowercased(); plists[stem, default: []].append(url)
                } else if lower.hasSuffix(".fk.json") {
                    let stem = String(name.dropLast(8)).lowercased(); manifests[stem, default: []].append(url)
                }
            }
        }

        let stems = Set(dylibs.keys).union(plists.keys).union(manifests.keys).sorted()
        var items: [PluginScanItem] = []
        for normalizedStem in stems {
            let dylibGroup = dylibs[normalizedStem] ?? []
            let plistGroup = plists[normalizedStem] ?? []
            let manifestGroup = manifests[normalizedStem] ?? []
            // Never pick an arbitrary file when case-insensitive names collide.
            let dylib = dylibGroup.count == 1 ? dylibGroup.first : nil
            let plist = plistGroup.count == 1 ? plistGroup.first : nil
            let manifest = manifestGroup.count == 1 ? manifestGroup.first : nil
            let stem: String
            if let dylib { stem = String(dylib.lastPathComponent.dropLast(6)) }
            else if let plist { stem = String(plist.lastPathComponent.dropLast(6)) }
            else if let manifest { stem = String(manifest.lastPathComponent.dropLast(8)) }
            else { stem = normalizedStem }
            var warnings: [String] = []
            var pairing: PluginPairingState = .paired
            if dylibGroup.count > 1 || plistGroup.count > 1 || manifestGroup.count > 1 {
                pairing = .invalid
                warnings.append("plugin_scan.duplicate_case_insensitive_basename")
                issues.append(issue("duplicate-\(normalizedStem)", "plugin_scan.duplicate_case_insensitive_basename", stem))
            }
            var ownership = PluginOwnership.unknown
            var ownershipConflict: PluginOwnershipConflict = .none
            var packageIdentifier: String?
            var packageVersion: String?
            var packageEvidenceSource: String?
            var dylibPackageIdentifier: String?
            var plistPackageIdentifier: String?
            if let packageOwnershipProvider {
                let dylibEvidence: PackageOwnershipEvidence?
                let plistEvidence: PackageOwnershipEvidence?
                if let dylib { dylibEvidence = try? packageOwnershipProvider.ownershipEvidence(for: dylib) }
                else { dylibEvidence = nil }
                if let plist { plistEvidence = try? packageOwnershipProvider.ownershipEvidence(for: plist) }
                else { plistEvidence = nil }
                dylibPackageIdentifier = dylibEvidence?.packageIdentifier
                plistPackageIdentifier = plistEvidence?.packageIdentifier
                packageEvidenceSource = [dylibEvidence?.evidenceSource, plistEvidence?.evidenceSource]
                    .compactMap { $0 }.first(where: { $0 == "dpkg-info-list" })
                    ?? [dylibEvidence?.evidenceSource, plistEvidence?.evidenceSource].compactMap { $0 }.first
                let owners = Set([dylibPackageIdentifier, plistPackageIdentifier].compactMap { $0 })
                if owners.count > 1 {
                    ownershipConflict = .multiplePackageOwners
                    ownership = .packageManager
                } else if !owners.isEmpty {
                    ownership = .packageManager
                    packageIdentifier = owners.first
                    packageVersion = [dylibEvidence, plistEvidence].compactMap { $0 }
                        .first(where: { $0.packageIdentifier == packageIdentifier })?.packageVersion
                }
            }
            let manifestIdentityBinding: PluginManifestIdentityBinding = manifest == nil ? .notPresent : .unverified
            var hardBound: String?
            // A manifest UUID is only a lookup hint for the Helper attestation request.
            // It is never treated as verified ownership or management permission here.
            var filterKitPluginID: String?
            var soft: [String] = []
            var softStates: [FilterKitManifestSoftAssociation] = []
            var filterConfiguration: PluginFilterConfiguration?

            // Read-only inventory now enriches each visible entry with bounded
            // Mach-O and plist metadata. It never loads or executes a plugin.
            var binaryKind: PluginBinaryKind? = nil
            var dylibHash: String? = nil
            var plistHash: String? = nil
            var manifestHash: String? = nil
            var dylibObservation: PluginScanFileObservation? = nil
            var plistObservation: PluginScanFileObservation? = nil
            var manifestObservation: PluginScanFileObservation? = nil
            var installName: String? = nil
            var currentVersion: String? = nil
            var compatibilityVersion: String? = nil
            var uuids: [String] = []
            var architectures: [String] = []
            var cdHashes: [String] = []
            var teamIdentifiers: [String] = []
            var signatureStates: [String] = []
            var signatureDetails: [String] = []
            if let dylib {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: dylib.path)
                    let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                    dylibObservation = Self.fileObservation(attributes)
                    guard size > 0, size <= maximumDylibBytes else { throw CocoaError(.fileReadTooLarge) }
                    let data = try Data(contentsOf: dylib, options: .mappedIfSafe)
                    guard let afterAttributes = try? fileManager.attributesOfItem(atPath: dylib.path),
                          Self.fileObservation(afterAttributes) == dylibObservation else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    dylibHash = SHA256Digest.hex(data)
                    let slices = try MachOMetadataReader().readSlices(data: data)
                    binaryKind = .machO
                    for slice in slices {
                        if installName == nil { installName = slice.installName }
                        if currentVersion == nil { currentVersion = slice.currentVersion }
                        if compatibilityVersion == nil { compatibilityVersion = slice.compatibilityVersion }
                        if let uuid = slice.uuid { uuids.append(uuid) }
                        if let arch = slice.architecture { architectures.append(arch) }
                        if let hash = slice.cdHash { cdHashes.append(hash) }
                        if let team = slice.codeSignatureTeamIdentifier, !team.isEmpty { teamIdentifiers.append(team) }
                        signatureStates.append(slice.codeSignatureState)
                        signatureDetails.append("arch=\(slice.architecture ?? "unknown"); identifier=\(slice.codeSignatureIdentifier ?? "—"); team=\(slice.codeSignatureTeamIdentifier ?? "—"); flags=\(slice.codeSignatureFlags.map(String.init) ?? "—"); platform=\(slice.codeSignaturePlatform.map(String.init) ?? "—")")
                    }
                } catch {
                    binaryKind = .notMachO
                    warnings.append("plugin_scan.macho_metadata_unavailable")
                }
            }
            if let plist {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: plist.path)
                    let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                    plistObservation = Self.fileObservation(attributes)
                    guard size > 0, size <= maximumPlistBytes else { throw CocoaError(.fileReadTooLarge) }
                    PluginInventoryPerformanceDiagnostics.recordPluginPlistRead()
                    let data = try Data(contentsOf: plist, options: .mappedIfSafe)
                    guard let afterAttributes = try? fileManager.attributesOfItem(atPath: plist.path),
                          Self.fileObservation(afterAttributes) == plistObservation else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    plistHash = SHA256Digest.hex(data)
                    // PluginFilterConfiguration.parse performs the single plist decode;
                    // avoid parsing the same bytes twice on every inventory refresh.
                    filterConfiguration = PluginFilterConfiguration.parse(data)
                    if filterConfiguration?.parseState == .invalid {
                        warnings.append(contentsOf: filterConfiguration?.warnings ?? [])
                    } else if filterConfiguration?.parseState == .partial {
                        warnings.append(contentsOf: filterConfiguration?.warnings ?? [])
                    }
                } catch {
                    warnings.append("plugin_scan.plist_invalid_or_unreadable")
                }
            }
            if pairing == .paired {
                if dylib == nil && plist != nil { pairing = .orphanPlist }
                if dylib != nil && plist == nil { pairing = .orphanDylib; warnings.append("plugin_scan.plist_generation_required") }
                if dylib == nil && plist == nil { pairing = .invalid; warnings.append("plugin_scan.manifest_without_pair") }
            }

            // Ownership and FilterKit manifest identity remain unverified during
            // inventory. Binary metadata improves identification only; it never
            // grants ownership or management permission.
            var manifestData: Data?
            if let manifest {
                if let attributes = try? fileManager.attributesOfItem(atPath: manifest.path) {
                    manifestObservation = Self.fileObservation(attributes)
                }
                let beforeObservation = manifestObservation
                manifestData = readManifestData(from: manifest)
                let afterObservation = (try? fileManager.attributesOfItem(atPath: manifest.path)).map(Self.fileObservation)
                if beforeObservation != afterObservation { manifestData = nil }
                manifestHash = manifestData.map(SHA256Digest.hex)
            }
            if let manifestData,
               let metadata = try? JSONDecoder().decode(FilterKitPluginManifest.self, from: manifestData) {
                // Read only the small association projection needed by the list UI.
                // This does NOT verify hashes, binary identity, ownership, or grant
                // management permission; full manifest verification remains deferred.
                filterKitPluginID = metadata.pluginID
                hardBound = metadata.hardBoundBundleIdentifier
                soft = metadata.softAssociatedBundleIdentifiers ?? []
                softStates = metadata.softAssociations ?? []
            }
            if manifest != nil {
                warnings.append("plugin_scan.manifest_verification_deferred")
            }
            let permission = PluginManagementPermission.evaluate(ownership: ownership, pairing: pairing,
                binaryKind: binaryKind, verifiedPluginID: nil, filterConfiguration: filterConfiguration)
            let itemID = "\(normalizedStem).dylib"
            items.append(PluginScanItem(id: itemID, baseName: stem,
                dylibFileName: dylib?.lastPathComponent, plistFileName: plist?.lastPathComponent,
                manifestFileName: manifest?.lastPathComponent, pairingState: pairing,
                binaryKind: binaryKind, ownership: ownership, filterKitPluginID: filterKitPluginID, packageIdentifier: packageIdentifier,
                dylibSHA256: dylibHash, plistSHA256: plistHash,
                hardBoundBundleIdentifier: hardBound,
                softAssociatedBundleIdentifiers: soft, warnings: warnings,
                filterConfiguration: filterConfiguration, managementPermission: permission,
                packageVersion: packageVersion, packageEvidenceSource: packageEvidenceSource,
                machOInstallName: installName, machOCurrentVersion: currentVersion, machOCompatibilityVersion: compatibilityVersion,
                machOUUID: uuids.first, machOUUIDs: Array(Set(uuids)).sorted(), machOArchitectures: Array(Set(architectures)).sorted(), machOCDHashes: Array(Set(cdHashes)).sorted(),
                machOTeamIdentifiers: Array(Set(teamIdentifiers)).sorted(), codeSignatureStates: signatureStates, machOSliceDetails: signatureDetails,
                dylibPackageIdentifier: dylibPackageIdentifier, plistPackageIdentifier: plistPackageIdentifier,
                ownershipConflict: ownershipConflict,
                manifestIdentityBinding: manifestIdentityBinding,
                manifestSHA256: manifestHash,
                dylibFileObservation: dylibObservation, plistFileObservation: plistObservation,
                manifestFileObservation: manifestObservation, softAssociationStates: softStates,
                dylibPath: dylib?.path, plistPath: plist?.path, manifestPath: manifest?.path))
        }
        let identityAnalysisStart = DispatchTime.now().uptimeNanoseconds
        let identityAnalysis = PluginIdentityAnalyzer().analyze(items)
        PluginInventoryPerformanceDiagnostics.recordIdentityAnalysis(
            milliseconds: PluginInventoryPerformanceDiagnostics.elapsedMilliseconds(since: identityAnalysisStart))
        let authorizedItems = identityAnalysis.items.map { item -> PluginScanItem in
            var adjusted = item
            if let permission = adjusted.managementPermission {
                adjusted.managementPermission = PluginManagementPermission.restricting(permission,
                    identityStatus: adjusted.identityStatus, ownershipConflict: adjusted.ownershipConflict)
            }
            return adjusted
        }
        let directoryPaths = readableDirectories.map(\.path).sorted()
        let primaryDirectory = assessment.selectedPath.flatMap { directoryPaths.contains($0) ? $0 : nil } ?? directoryPaths.first
        return PluginScanResult(scannedAt: Date(), scannedDirectory: primaryDirectory,
            directoryState: .resolved, plugins: authorizedItems, issues: issues,
            isReadOnly: true, identityConflicts: identityAnalysis.conflicts,
            scannedDirectories: directoryPaths)
    }

    private func readManifestData(from url: URL) -> Data? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0, size.intValue <= maximumManifestBytes else { return nil }
        PluginInventoryPerformanceDiagnostics.recordManifestRead()
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func fileObservation(_ attributes: [FileAttributeKey: Any]) -> PluginScanFileObservation {
        PluginScanFileObservation(
            fileSize: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date,
            systemFileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
    }

    private func issue(_ id: String, _ code: String, _ file: String?) -> PluginScanIssue {
        PluginScanIssue(id: id, code: code, fileName: file, detail: nil)
    }


}

