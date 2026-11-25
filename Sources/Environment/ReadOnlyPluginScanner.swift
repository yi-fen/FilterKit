import Foundation

/// Scans the supported third-party plugin directories reported by PluginDirectoryLocator.
/// It never writes, renames, chmods, or deletes files and never invokes dpkg.
final class ReadOnlyPluginScanner: PluginDiscoveryProvider {
    private let fileManager: FileManager
    private let packageOwnershipProvider: PackageOwnershipProviding
    private let assessmentProvider: (() -> PluginDirectoryAssessment)?
    private let maximumManifestBytes = 64 * 1024

    init(fileManager: FileManager = .default,
         packageOwnershipProvider: PackageOwnershipProviding = NoPackageOwnershipEvidenceProvider(),
         assessmentProvider: (() -> PluginDirectoryAssessment)? = nil) {
        self.fileManager = fileManager
        self.packageOwnershipProvider = packageOwnershipProvider
        self.assessmentProvider = assessmentProvider
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
        for directoryURL in readableDirectories {
            guard let names = try? fileManager.contentsOfDirectory(atPath: directoryURL.path) else {
                issues.append(issue("directory-enumeration-\(directoryURL.lastPathComponent)",
                                    "plugin_scan.enumeration_failed", directoryURL.lastPathComponent))
                continue
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
            var binaryKind: PluginBinaryKind?
            var dylibHash: String?, plistHash: String?
            var ownership: PluginOwnership = .unknown
            var packageID: String?
            var dylibPackageID: String?
            var plistPackageID: String?
            var ownershipConflict: PluginOwnershipConflict = .none
            var manifestIdentityBinding: PluginManifestIdentityBinding = manifest == nil ? .notPresent : .unverified
            var verifiedPluginID: String?
            var hardBound: String?
            var soft: [String] = []
            var softStates: [FilterKitManifestSoftAssociation] = []
            var filterConfiguration: PluginFilterConfiguration?
            var packageVersion: String?
            var machoSlices: [MachOSliceMetadata] = []

            // Fast inventory deliberately does not read/hash dylib binaries, parse
            // Mach-O slices, query package ownership, or verify manifests. Those
            // expensive checks belong to the explicit detail/diagnostics path.
            // A dylib remains visible even when its metadata cannot be inspected.
            if let plist {
                do {
                    let data = try Data(contentsOf: plist, options: .mappedIfSafe)
                    _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
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

            // Ownership remains unknown during inventory. This is intentional:
            // visibility must not depend on dpkg or FilterKit manifest validation.
            // Management permissions therefore remain conservative until a future
            // explicit detail verification establishes ownership and binary identity.
            if manifest != nil {
                warnings.append("plugin_scan.manifest_verification_deferred")
            }
            let permission = PluginManagementPermission.evaluate(ownership: ownership, pairing: pairing,
                binaryKind: binaryKind, verifiedPluginID: verifiedPluginID, filterConfiguration: filterConfiguration)
            let itemID = "\(normalizedStem).dylib"
            items.append(PluginScanItem(id: itemID, baseName: stem,
                dylibFileName: dylib?.lastPathComponent, plistFileName: plist?.lastPathComponent,
                manifestFileName: manifest?.lastPathComponent, pairingState: pairing,
                binaryKind: binaryKind, ownership: ownership, filterKitPluginID: verifiedPluginID, packageIdentifier: packageID,
                dylibSHA256: dylibHash, plistSHA256: plistHash,
                hardBoundBundleIdentifier: hardBound,
                softAssociatedBundleIdentifiers: soft, warnings: warnings,
                filterConfiguration: filterConfiguration, managementPermission: permission,
                packageVersion: packageVersion,
                machOInstallName: Set(machoSlices.compactMap(\.installName)).count == 1 ? machoSlices.compactMap(\.installName).first : nil,
                machOCurrentVersion: Set(machoSlices.compactMap(\.currentVersion)).count == 1 ? machoSlices.compactMap(\.currentVersion).first : nil,
                machOCompatibilityVersion: Set(machoSlices.compactMap(\.compatibilityVersion)).count == 1 ? machoSlices.compactMap(\.compatibilityVersion).first : nil,
                machOUUID: Set(machoSlices.compactMap(\.uuid)).count == 1 ? machoSlices.compactMap(\.uuid).first : nil,
                machOUUIDs: Array(Set(machoSlices.compactMap(\.uuid))).sorted(),
                machOArchitectures: Array(Set(machoSlices.compactMap(\.architecture))).sorted(),
                machOCDHashes: Array(Set(machoSlices.compactMap(\.cdHash))).sorted(),
                codeSignatureStates: Array(Set(machoSlices.map(\.codeSignatureState))).sorted(),
                machOSliceDetails: machoSlices.map { slice in "\(slice.architecture ?? "unknown"): \(slice.installName ?? "—") | \(slice.currentVersion ?? "—") | UUID \(slice.uuid ?? "—") | CDHash \(slice.cdHash ?? "—")" }.sorted(),
                dylibPackageIdentifier: dylibPackageID,
                plistPackageIdentifier: plistPackageID,
                ownershipConflict: ownershipConflict,
                manifestIdentityBinding: manifestIdentityBinding,
                softAssociationStates: softStates,
                dylibPath: dylib?.path, plistPath: plist?.path, manifestPath: manifest?.path))
        }
        let identityAnalysis = PluginIdentityAnalyzer().analyze(items)
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

    private func packageEvidence(for url: URL?, issues: inout [PluginScanIssue]) -> PackageOwnershipEvidence? {
        guard let url else { return nil }
        do { return try packageOwnershipProvider.ownershipEvidence(for: url) }
        catch {
            issues.append(issue("package-evidence-\(url.lastPathComponent)", "plugin_scan.package_evidence_unavailable", url.lastPathComponent))
            return nil
        }
    }

    private func verifyManifest(at url: URL, expectedStem: String, dylibName: String,
                                plistName: String, dylibHash: String, plistHash: String,
                                machoSlices: [MachOSliceMetadata]) -> FilterKitPluginManifest? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= maximumManifestBytes,
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(FilterKitPluginManifest.self, from: data),
              (1...3).contains(manifest.schemaVersion),
              !manifest.pluginID.isEmpty,
              manifest.dylibFileName == dylibName,
              manifest.plistFileName == plistName,
              manifest.dylibSHA256.lowercased() == dylibHash,
              manifest.plistSHA256.lowercased() == plistHash,
              URL(fileURLWithPath: manifest.dylibFileName).lastPathComponent == manifest.dylibFileName,
              URL(fileURLWithPath: manifest.plistFileName).lastPathComponent == manifest.plistFileName,
              expectedStem == String(dylibName.dropLast(6)),
              expectedStem == String(plistName.dropLast(6)) else { return nil }
        if manifest.schemaVersion >= 2 {
            let identityDigest = PluginIdentityAnalyzer.fingerprint(
                installNames: machoSlices.compactMap(\.installName),
                uuids: machoSlices.compactMap(\.uuid),
                cdHashes: machoSlices.compactMap(\.cdHash),
                architectures: machoSlices.compactMap(\.architecture))
            guard let expectedIdentity = manifest.machOIdentitySHA256?.lowercased(),
                  let identityDigest, expectedIdentity == identityDigest else { return nil }
        }
        if manifest.schemaVersion == 3 {
            guard let hardBound = manifest.hardBoundBundleIdentifier,
                  PluginAssociationPlanResolver.isValidBundleIdentifier(hardBound),
                  let associations = manifest.softAssociations,
                  associations.allSatisfy({ PluginAssociationPlanResolver.isValidBundleIdentifier($0.bundleIdentifier) }),
                  Set(associations.map(\.bundleIdentifier)).count == associations.count,
                  !associations.contains(where: { $0.bundleIdentifier == hardBound }),
                  Set(associations.map(\.bundleIdentifier)) == Set(manifest.softAssociatedBundleIdentifiers ?? []) else { return nil }
        }
        return manifest
    }

    private func issue(_ id: String, _ code: String, _ file: String?) -> PluginScanIssue {
        PluginScanIssue(id: id, code: code, fileName: file, detail: nil)
    }

    private static func binaryKind(_ data: Data) -> PluginBinaryKind {
        guard data.count >= 4 else { return .notMachO }
        let magic = data.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        switch magic {
        case 0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe,
             0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca: return .machO
        default: return .notMachO
        }
    }
}

