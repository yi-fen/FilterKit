//
// ReadOnlyDiagnosticsEngine.swift
// FilterKit — 0.1.18/0.1.19 diagnostic capability port (Swift)
//
// Ported from the supplied 0.1.19 Objective-C reference implementation.
// All device inspection is read-only. No plist/configuration writes, no
// plugin changes, no dpkg mutations, no helper launch/IPC, and no injection.
//
// Stage 2.5 alignment: evidence fields enriched against the 18-item checklist
// (P0 core paths; P1 items present but marked unverified where evidence is
// absent). The flattened [[String:String]] report shape is preserved; no
// frozen public model, Adapter protocol, Plist parser, or Stage1 fixture changes.

import Foundation

#if canImport(Darwin)
import Darwin
// `_dyld_image_count` / `_dyld_get_image_name` live in the MachO.dyld submodule;
// the iOS SDK does not re-export them through the Darwin umbrella, so import the
// submodule explicitly on Darwin platforms (absent on Linux/non-Darwin).
import MachO.dyld
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif
#if canImport(ObjectiveC)
import ObjectiveC
#endif
#if canImport(UIKit)
import UIKit
#endif

public struct FKDiagnosticFinding: Codable, Equatable {
    public let id: String
    public let title: String
    public let state: String
    public let detail: String
    public let payload: [String: String]

    public init(id: String, title: String, state: String, detail: String,
                payload: [String: String] = [:]) {
        self.id = id
        self.title = title
        self.state = state
        self.detail = detail
        self.payload = payload
    }
}

public struct FKDiagnosticReport: Codable, Equatable {
    public let generatedAt: Date
    public let environment: [String: String]
    public let roots: [[String: String]]
    public let dynamicLibraryDirectories: [[String: String]]
    public let plugins: [[String: String]]
    public let filters: [[String: String]]
    public let injectorEvidence: [[String: String]]
    public let packages: [[String: String]]
    public let fileOwnership: [[String: String]]
    public let integrity: [[String: String]]
    public let helperCandidates: [[String: String]]
    public let helperRegistrations: [[String: String]]
    public let applications: [[String: String]]
    public let associations: [[String: String]]
    public let findings: [FKDiagnosticFinding]

    public init(generatedAt: Date = Date(), environment: [String: String],
                roots: [[String: String]], dynamicLibraryDirectories: [[String: String]],
                plugins: [[String: String]], filters: [[String: String]],
                injectorEvidence: [[String: String]], packages: [[String: String]],
                fileOwnership: [[String: String]], integrity: [[String: String]],
                helperCandidates: [[String: String]], helperRegistrations: [[String: String]],
                applications: [[String: String]], associations: [[String: String]],
                findings: [FKDiagnosticFinding]) {
        self.generatedAt = generatedAt
        self.environment = environment
        self.roots = roots
        self.dynamicLibraryDirectories = dynamicLibraryDirectories
        self.plugins = plugins
        self.filters = filters
        self.injectorEvidence = injectorEvidence
        self.packages = packages
        self.fileOwnership = fileOwnership
        self.integrity = integrity
        self.helperCandidates = helperCandidates
        self.helperRegistrations = helperRegistrations
        self.applications = applications
        self.associations = associations
        self.findings = findings
    }
}

/// Performs the 18 legacy diagnostics without modifying the jailbreak filesystem.
/// A caller may supply an app-bundle path for deterministic JBROOT discovery tests.
public final class ReadOnlyDiagnosticsEngine {
    private let fileManager: FileManager
    private let appBundlePath: String
    private var findings: [FKDiagnosticFinding] = []

    // RTLD_DEFAULT is the C macro `((void *) -2)` in dlfcn.h. Swift does not
    // import pointer-cast macros, so reconstruct the handle from its bit
    // pattern instead of referencing the unavailable `RTLD_DEFAULT` symbol.
    // The optional type matches dlsym's handle parameter (`UnsafeMutableRawPointer?`).
    private static let rtldDefaultHandle: UnsafeMutableRawPointer? = UnsafeMutableRawPointer(bitPattern: -2)

    public init(fileManager: FileManager = .default,
                appBundlePath: String = Bundle.main.bundlePath) {
        self.fileManager = fileManager
        self.appBundlePath = appBundlePath
    }

    public func scan() -> FKDiagnosticReport {
        findings = []
        var environment: [String: String] = [
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": Self.machineArchitecture,
            "scan_mode": "read_only",
            "runtime_loaded_state": "unknown_without_independent_evidence"
        ]

        // 15/16. Installed applications and their bundle metadata are gathered first;
        // app bundle paths are also one possible source of JBROOT evidence.
        let applications = scanInstalledApplications()
        let installedBundleIDs = Set(applications.compactMap { $0["bundle_id"] }.filter { !$0.isEmpty })
        let installedExecutables = Set(applications.compactMap { $0["executable"] }
            .filter { !$0.isEmpty }.map { $0.lowercased() })

        // 1. JBROOT candidates and structural validation.
        let roots = discoverJBRoots(applicationPaths: applications.compactMap { $0["bundle_path"] })
        let selectedRoot = roots.first(where: {
            $0["status"] == "validated" && $0["source"] == "libroothide_jbroot_api"
        })?["path"] ?? roots.first(where: { $0["status"] == "validated" })?["path"]
        environment["jbroot"] = selectedRoot ?? "unknown"
        environment["jbrand"] = Self.roothideJBrand() ?? "unknown"
        environment["route"] = selectedRoot == nil ? "unknown" : ((selectedRoot ?? "").contains(".jbroot-") ? "roothide" : "rootless")

        // 2/3. DynamicLibraries directory reachability and dylib inventory.
        let directories = discoverDynamicLibraryDirectories(root: selectedRoot)
        var plugins: [[String: String]] = []
        for directory in directories where directory["enumerable"] == "true" {
            guard let path = directory["path"] else { continue }
            let children = (try? fileManager.contentsOfDirectory(atPath: path)) ?? []
            for name in children where name.lowercased().hasSuffix(".dylib") {
                let fullPath = (path as NSString).appendingPathComponent(name)
                let attrs = try? fileManager.attributesOfItem(atPath: fullPath)
                var isDirectory: ObjCBool = false
                _ = fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory)
                plugins.append([
                    "name": name,
                    "path": fullPath,
                    "exists": fileManager.fileExists(atPath: fullPath) ? "true" : "false",
                    "readable": fileManager.isReadableFile(atPath: fullPath) ? "true" : "false",
                    "file_type": Self.fileType(at: fullPath),
                    "size": String((attrs?[.size] as? NSNumber)?.intValue ?? 0),
                    "source": "unknown",
                    "loaded": "unknown"
                ])
            }
        }
        let enumerationCompleted = directories.contains { $0["enumerable"] == "true" }

        // 4/5. Filter plist reads and conservative Bundles/Executables/Classes parsing.
        var filters: [[String: String]] = []
        var plistPaths: [String] = []
        for directory in directories where directory["enumerable"] == "true" {
            guard let path = directory["path"], let names = try? fileManager.contentsOfDirectory(atPath: path) else { continue }
            plistPaths += names.filter { $0.lowercased().hasSuffix(".plist") }.map { (path as NSString).appendingPathComponent($0) }
        }
        for plistPath in Set(plistPaths).sorted() {
            let base = (plistPath as NSString).deletingPathExtension
            let matchingPlugin = plugins.first(where: { (($0["path"] ?? "") as NSString).deletingPathExtension == base })
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: plistPath), options: [.mappedIfSafe])
                let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                let dictionary = object as? [String: Any]
                // Theos filter plists may nest the rules under a `Filter` dictionary;
                // accept the nested layout first, then fall back to top-level keys.
                let filterObject = (dictionary?["Filter"] as? [String: Any]) ?? dictionary
                let parsed = Self.parseFilterDictionary(filterObject,
                                                        installedBundleIDs: installedBundleIDs,
                                                        installedExecutables: installedExecutables)
                let topLevelKeys = (dictionary?.keys.sorted() ?? []).joined(separator: ",")
                filters.append([
                    "plugin": matchingPlugin?["name"] ?? ((plistPath as NSString).lastPathComponent),
                    "dylib_match": String(matchingPlugin != nil),
                    "plist_path": plistPath,
                    "read_status": "readable",
                    "parse_status": dictionary == nil ? "type_mismatch" : "parsed",
                    "data_length": String(data.count),
                    "top_level_type": String(describing: type(of: object)),
                    "top_level_keys": topLevelKeys,
                    "has_filter_dictionary": String((dictionary?["Filter"] as? [String: Any]) != nil),
                    "bundles": parsed["bundles"] ?? "",
                    "executables": parsed["executables"] ?? "",
                    "classes": parsed["classes"] ?? "",
                    "other_keys": parsed["other_keys"] ?? "",
                    "global": parsed["global"] ?? "false",
                    "matched_bundle_ids": parsed["matched_bundle_ids"] ?? "",
                    "unmatched_bundle_ids": parsed["unmatched_bundle_ids"] ?? "",
                    "matched_executables": parsed["matched_executables"] ?? "",
                    "unmatched_executables": parsed["unmatched_executables"] ?? "",
                    "warnings": parsed["warnings"] ?? "",
                    "valid": parsed["valid"] ?? "false",
                    "entry_count": parsed["entry_count"] ?? "0",
                    "protocol_verified": "false",
                    "global_semantics_verified": "false"
                ])
            } catch {
                filters.append(["plugin": matchingPlugin?["name"] ?? ((plistPath as NSString).lastPathComponent),
                                "dylib_match": String(matchingPlugin != nil), "plist_path": plistPath,
                                "read_status": "read_failed", "parse_status": "not_parsed", "error": error.localizedDescription])
            }
        }

        // 6. Injector identification: package metadata + current-process dyld images +
        // fixed filesystem fingerprints. Static and runtime evidence are reported separately.
        let dpkgStatus = locateDpkgStatus(root: selectedRoot)
        let parsedPackages = dpkgStatus.map(Self.parseDpkgStatus(at:)) ?? ([], ["dpkg_status_not_found"])
        let packages = parsedPackages.0
        let runtimeImages = Self.runtimeInjectorImages()
        var injectorEvidence = identifyInjectors(packages: packages, runtimeImages: runtimeImages)
        injectorEvidence += fingerprintInjectors(root: selectedRoot)
        environment["injector"] = injectorEvidence.first?["type"] ?? "unknown"
        environment["injector_runtime_scope"] = "current_process_only"

        // 7/8/9/10/11/12/13/18. DPKG status, .list ownership, metadata, file state,
        // checksums, source classification, ownership conflicts and Conffiles.
        let dpkgResult = analyzeDpkg(statusPath: dpkgStatus, packages: packages,
                                     plugins: plugins, plists: filters, selectedRoot: selectedRoot)
        let ownershipByPath = Dictionary(grouping: dpkgResult.ownership, by: { $0["path"] ?? "" })
        let classifiedPlugins: [[String: String]] = plugins.map { plugin in
            var item = plugin
            let path = plugin["path"] ?? ""
            let logical = Self.canonicalDpkgPath(path, root: selectedRoot)
            let owners = ownershipByPath[logical]?.first?["packages"] ?? ""
            let ownerList = owners.isEmpty ? [] : owners.split(separator: ",").map(String.init)
            item["source"] = owners.isEmpty ? (dpkgStatus == nil ? "unknown" : "manual_inferred") : "dpkg"
            item["package_owners"] = owners
            item["package_candidates"] = owners
            item["exact_package_record"] = String(!ownerList.isEmpty)
            item["source_evidence"] = owners.isEmpty ? (dpkgStatus == nil ? "insufficient" : "no_exact_dpkg_list_owner") : "dpkg_list_exact_path"
            return item
        }

        // 14. RootHelper static preflight and reverse LaunchDaemons lookup only.
        let helpers = inspectHelpers(root: selectedRoot, ownership: dpkgResult.ownership)

        // 17. Static plugin↔App matching only; never label this as successful injection.
        let associations = buildAssociations(applications: applications, filters: filters)
        let associationSummary = Self.associationSummary(filters: filters, plugins: classifiedPlugins)

        add("jbroot", "JBROOT path validation", roots.isEmpty ? "unconfirmed" : (selectedRoot == nil ? "warning" : "passed"),
            "Candidates: \(roots.count); validated: \(selectedRoot == nil ? 0 : 1)")
        add("dynamic_libraries", "DynamicLibraries enumeration", directories.isEmpty ? "unconfirmed" : "passed",
            "Directories: \(directories.count); dylibs: \(plugins.count); enumeration_completed=\(enumerationCompleted)")
        add("filter_parse", "Filter plist read and parse", "completed", "Filter records: \(filters.count)")
        add("injector", "Injector recognition", injectorEvidence.isEmpty ? "unconfirmed" : "partial",
            "Static package, filesystem fingerprint and current-process image evidence are reported separately")
        add("dpkg", "DPKG status and metadata", dpkgStatus == nil ? "unconfirmed" : "completed",
            "Package records: \(packages.count)")
        add("dpkg_integrity", "DPKG file integrity and checksums", dpkgStatus == nil ? "unconfirmed" : "completed",
            "Integrity records: \(dpkgResult.integrity.count); mismatches: \(dpkgResult.mismatchCount); no-checksum records: \(dpkgResult.noChecksumCount); hard failures: \(dpkgResult.hardFailureCount); warnings: \(dpkgResult.warningCount); not confirmed: \(dpkgResult.notConfirmedCount)")
        add("ownership_conflict", "Cross-package ownership conflicts", dpkgStatus == nil ? "unconfirmed" : "completed",
            "Conflicting paths: \(dpkgResult.conflictCount); unattributed plugin files: \(dpkgResult.unownedPluginFiles)")
        add("helper_preflight", "RootHelper read-only preflight", "completed",
            "Candidates: \(helpers.candidates.count); LaunchDaemons references: \(helpers.registrations.count)")
        add("apps", "Installed application inventory", applications.isEmpty ? "unconfirmed" : "partial",
            "Application records: \(applications.count)")
        add("association", "Static plugin to App association", "completed",
            "Associations: \(associations.count); global: \(associationSummary.global); unmatched: \(associationSummary.unmatched); missing dylib: \(associationSummary.missingDylib); missing plist: \(associationSummary.missingPlist); this is not runtime injection evidence")
        for warning in parsedPackages.1 {
            add("dpkg_warning", "DPKG parse warning", "warning", warning)
        }

        return FKDiagnosticReport(environment: environment, roots: roots,
            dynamicLibraryDirectories: directories, plugins: classifiedPlugins, filters: filters,
            injectorEvidence: injectorEvidence, packages: dpkgResult.packages,
            fileOwnership: dpkgResult.ownership, integrity: dpkgResult.integrity,
            helperCandidates: helpers.candidates, helperRegistrations: helpers.registrations,
            applications: applications, associations: associations, findings: findings)
    }

    // MARK: 1 — JBROOT

    private func discoverJBRoots(applicationPaths: [String]) -> [[String: String]] {
        var candidates = Set<String>()
        candidates.formUnion(["/var/jb", "/var/rootless", "/private/var/jb"])
        if let apiRoot = Self.roothideJBRoot() { candidates.insert(apiRoot) }
        if let root = Self.rootFromJBRootPath(appBundlePath) { candidates.insert(root) }
        for path in applicationPaths {
            if let root = Self.rootFromJBRootPath(path) { candidates.insert(root) }
        }
        let containerParent = "/var/containers/Bundle/Application"
        if let entries = try? fileManager.contentsOfDirectory(atPath: containerParent) {
            for entry in entries where entry.hasPrefix(".jbroot-") {
                candidates.insert((containerParent as NSString).appendingPathComponent(entry))
            }
        }
        let markerSuffixes = ["Applications", "Library", "var/lib/dpkg/status",
                              "Library/MobileSubstrate/DynamicLibraries",
                              "Library/ElleKit/DynamicLibraries"]
        let results = candidates.sorted().map { path -> [String: String] in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            let readable = exists && fileManager.isReadableFile(atPath: path)
            let markers = markerSuffixes.filter { suffix in
                fileManager.fileExists(atPath: (path as NSString).appendingPathComponent(suffix))
            }
            let hasLibrary = fileManager.fileExists(atPath: (path as NSString).appendingPathComponent("Library"))
            let hasUsr = fileManager.fileExists(atPath: (path as NSString).appendingPathComponent("usr"))
            let structure = isDirectory.boolValue && (hasLibrary || hasUsr)
            let validated = exists && readable && structure
            let rootOK = exists && isDirectory.boolValue
            let confidence: String
            if validated { confidence = "confirmed" }
            else if rootOK { confidence = "candidate" }
            else { confidence = "path_hint_only" }
            return ["path": path, "exists": String(exists), "directory": String(isDirectory.boolValue),
                    "readable": String(readable), "structure_match": String(structure),
                    "is_symlink": Self.symlinkFlag(at: path),
                    "markers": markers.joined(separator: ","),
                    "confidence": confidence,
                    "status": validated ? "validated" : (exists ? "candidate_unverified" : "not_found"),
                    "source": path.contains(".jbroot-") ? "filesystem_name" : (path == Self.roothideJBRoot() ? "libroothide_jbroot_api" : "known_rootless_fallback")]
        }
        return results
    }

    private static func rootFromJBRootPath(_ path: String) -> String? {
        guard let range = path.range(of: #"/\.jbroot-[A-Fa-f0-9]{16}(?=/|$)"#, options: .regularExpression) else { return nil }
        return String(path[..<range.upperBound])
    }

    /// Resolves jbroot("/") dynamically when libroothide exports it.
    /// The symbol is optional; absence is evidence-unavailable, not a hard failure.
    private static func roothideJBRoot() -> String? {
        #if canImport(Darwin)
        guard let symbol = dlsym(Self.rtldDefaultHandle, "jbroot") else { return nil }
        typealias JBRootFunction = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
        let function = unsafeBitCast(symbol, to: JBRootFunction.self)
        let result = "/".withCString { function($0) }
        guard let result, let path = String(validatingUTF8: result), !path.isEmpty else { return nil }
        return (path as NSString).standardizingPath
        #else
        return nil
        #endif
    }

    private static func roothideJBrand() -> String? {
        #if canImport(Darwin)
        guard let symbol = dlsym(Self.rtldDefaultHandle, "jbrand") else { return nil }
        typealias JBrandFunction = @convention(c) () -> UInt64
        let function = unsafeBitCast(symbol, to: JBrandFunction.self)
        return String(format: "%016llX", function())
        #else
        return nil
        #endif
    }

    // MARK: 2/3 — DynamicLibraries

    private func discoverDynamicLibraryDirectories(root: String?) -> [[String: String]] {
        var paths: [String] = []
        if let root {
            paths += [
                (root as NSString).appendingPathComponent("Library/ElleKit/DynamicLibraries"),
                (root as NSString).appendingPathComponent("Library/MobileSubstrate/DynamicLibraries"),
                (root as NSString).appendingPathComponent("library/MobileSubstrate/DynamicLibraries"),
                (root as NSString).appendingPathComponent("usr/lib/TweakInject")
            ]
        }
        for fixedRoot in ["/var/jb", "/var/rootless", "/private/var/jb"] {
            paths += [
                (fixedRoot as NSString).appendingPathComponent("Library/ElleKit/DynamicLibraries"),
                (fixedRoot as NSString).appendingPathComponent("Library/MobileSubstrate/DynamicLibraries"),
                (fixedRoot as NSString).appendingPathComponent("library/MobileSubstrate/DynamicLibraries")
            ]
        }
        paths += ["/Library/ElleKit/DynamicLibraries", "/Library/MobileSubstrate/DynamicLibraries", "/usr/lib/TweakInject"]
        return Array(Set(paths)).sorted().map { path in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            let readable = exists && fileManager.isReadableFile(atPath: path)
            let entries = readable ? (try? fileManager.contentsOfDirectory(atPath: path)) : nil
            return ["path": path, "exists": String(exists), "directory": String(isDirectory.boolValue),
                    "readable": String(readable), "is_symlink": Self.symlinkFlag(at: path),
                    "enumerable": String(entries != nil),
                    "entry_count": String(entries?.count ?? 0)]
        }
    }

    // MARK: 6 — Injector recognition

    private func identifyInjectors(packages: [[String: String]], runtimeImages: [[String: String]]) -> [[String: String]] {
        let known: [(String, [String])] = [
            ("ellekit", ["ellekit"]),
            ("substrate", ["mobilesubstrate", "substrate"]),
            ("substitute", ["substitute"]),
            ("libhooker", ["libhooker", "hooker"]),
            ("sandy", ["sandy"])
        ]
        var output: [[String: String]] = []
        for package in packages {
            let id = package["Package"] ?? ""
            if let match = known.first(where: { item in item.1.contains(where: { id.lowercased().contains($0) }) }) {
                let profile = Self.injectorProfile(match.0)
                let status = package["Status"] ?? ""
                output.append(["type": match.0, "package_id": id, "version": package["Version"] ?? "",
                               "architecture": package["Architecture"] ?? "",
                               "installed": String(status.contains(" installed")),
                               "version_source": "dpkg_status", "evidence_level": "partial",
                               "static_evidence": "dpkg_status", "runtime_image_match": "not_inferred",
                               "filter_parsing": profile.filterParsing, "app_targeting": profile.appTargeting,
                               "global_injection": profile.globalInjection,
                               "compatibility": "profile_only_not_runtime_validation"])
            }
        }
        for image in runtimeImages {
            output.append(["type": image["type"] ?? "unknown", "image_path": image["path"] ?? "",
                           "runtime_evidence": "current_process_image", "scope": "current_process_only"])
        }
        return output
    }

    /// Fixed filesystem fingerprints (dylib/framework paths) are existence evidence only;
    /// they do not prove the injector is loaded, enabled, or runtime-compatible.
    private func fingerprintInjectors(root: String?) -> [[String: String]] {
        let fingerprints: [(type: String, relative: [String])] = [
            ("ellekit", ["usr/lib/libellekit.dylib"]),
            ("substrate", ["Library/Frameworks/CydiaSubstrate.framework", "usr/lib/libsubstrate.dylib"]),
            ("substitute", ["usr/lib/libsubstitute.dylib", "Library/Frameworks/Substitute.framework"]),
            ("libhooker", ["usr/lib/libhooker.dylib", "Library/Frameworks/libhooker.framework"]),
            ("sandy", ["usr/lib/libsandy.dylib", "Library/Frameworks/Sandy.framework"])
        ]
        let roots = [root, "/var/jb", "/private/var/jb"].compactMap { $0 }
        var output: [[String: String]] = []
        for entry in fingerprints {
            for relative in entry.relative {
                for base in roots {
                    let full = (base as NSString).appendingPathComponent(relative)
                    var isDirectory: ObjCBool = false
                    let exists = fileManager.fileExists(atPath: full, isDirectory: &isDirectory)
                    let readable = exists && fileManager.isReadableFile(atPath: full)
                    output.append(["type": entry.type, "relative_path": relative, "path": full,
                                   "exists": String(exists), "readable": String(readable),
                                   "is_directory": String(isDirectory.boolValue),
                                   "version": "", "version_source": "none",
                                   "static_evidence": "fingerprint_filesystem", "scope": "static_filesystem_only"])
                }
            }
        }
        return output
    }

    private static func runtimeInjectorImages() -> [[String: String]] {
        #if canImport(Darwin)
        var result: [[String: String]] = []
        for index in 0..<_dyld_image_count() {
            guard let pointer = _dyld_get_image_name(index), let path = String(validatingUTF8: pointer) else { continue }
            let lower = path.lowercased()
            let type = ["ellekit", "substrate", "substitute", "libhooker", "sandy"].first(where: { lower.contains($0) })
            if let type { result.append(["type": type, "path": path, "scope": "current_process_only"]) }
        }
        return result
        #else
        return []
        #endif
    }

    private struct InjectorProfile {
        let filterParsing: String
        let appTargeting: String
        let globalInjection: String
    }

    private static func injectorProfile(_ name: String) -> InjectorProfile {
        switch name {
        case "ellekit": return InjectorProfile(filterParsing: "supported", appTargeting: "supported", globalInjection: "supported")
        case "substrate": return InjectorProfile(filterParsing: "unsupported", appTargeting: "supported", globalInjection: "supported")
        case "substitute": return InjectorProfile(filterParsing: "unsupported", appTargeting: "supported", globalInjection: "supported")
        case "libhooker": return InjectorProfile(filterParsing: "supported", appTargeting: "supported", globalInjection: "supported")
        default: return InjectorProfile(filterParsing: "unknown", appTargeting: "unknown", globalInjection: "unknown")
        }
    }

    // MARK: 7 — DPKG status parser

    private func locateDpkgStatus(root: String?) -> String? {
        var paths = ["/var/lib/dpkg/status", "/var/jb/var/lib/dpkg/status"]
        if let root { paths.insert((root as NSString).appendingPathComponent("var/lib/dpkg/status"), at: 0) }
        return paths.first(where: { fileManager.isReadableFile(atPath: $0) })
    }

    private static func parseDpkgStatus(at path: String) -> ([[String: String]], [String]) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8) else {
            return ([], ["status_missing_or_invalid_utf8"])
        }
        var records: [[String: String]] = []
        var warnings: [String] = []
        var current: [String: String] = [:]
        var currentKey: String?
        var seen = Set<String>()
        func flush() {
            if current["Package"] != nil { records.append(current) }
            current = [:]; currentKey = nil; seen = []
        }
        for line in text.components(separatedBy: .newlines) {
            if line.isEmpty || line.trimmingCharacters(in: .whitespaces).isEmpty { flush(); continue }
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if let key = currentKey { current[key, default: ""] += "\n" + String(line.dropFirst()) }
                else { warnings.append("orphan_continuation_line") }
                continue
            }
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else {
                warnings.append("malformed_field_line"); continue
            }
            let key = String(line[..<colon])
            let lower = key.lowercased()
            if !seen.insert(lower).inserted { warnings.append("duplicate_field:\(key)") }
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let canonical = current.keys.first(where: { $0.lowercased() == lower }) ?? key
            current[canonical] = value
            currentKey = canonical
        }
        flush()
        return (records, warnings)
    }

    // MARK: 8/9/10/11/12/13/18 — DPKG analysis

    private struct DpkgAnalysis {
        var packages: [[String: String]]
        var ownership: [[String: String]]
        var integrity: [[String: String]]
        var mismatchCount: Int
        var noChecksumCount: Int
        var hardFailureCount: Int
        var warningCount: Int
        var notConfirmedCount: Int
        var conflictCount: Int
        var unownedPluginFiles: Int
    }

    private func analyzeDpkg(statusPath: String?, packages: [[String: String]],
                             plugins: [[String: String]], plists: [[String: String]],
                             selectedRoot: String?) -> DpkgAnalysis {
        guard let statusPath else {
            return DpkgAnalysis(packages: [], ownership: [], integrity: [], mismatchCount: 0,
                                noChecksumCount: 0, hardFailureCount: 0, warningCount: 0,
                                notConfirmedCount: 0, conflictCount: 0, unownedPluginFiles: 0)
        }
        let infoDirectory = (statusPath as NSString).deletingLastPathComponent + "/info"
        var owners: [String: Set<String>] = [:]
        var packageResults: [[String: String]] = []
        var integrity: [[String: String]] = []
        var mismatchCount = 0, hardFailureCount = 0, warningCount = 0, notConfirmedCount = 0
        let pluginPaths = Set(plugins.compactMap { $0["path"] } + plists.compactMap { $0["plist_path"] })

        for fields in packages {
            let packageID = fields["Package"] ?? ""
            guard !packageID.isEmpty, !packageID.contains("/"), !packageID.contains("..") else { continue }
            let listPath = (infoDirectory as NSString).appendingPathComponent(packageID + ".list")
            let listText = (try? String(contentsOfFile: listPath, encoding: .utf8)) ?? ""
            var listed = 0, existing = 0, missing = 0, unreadable = 0, notChecked = 0
            var listedLogicalPaths: [String] = []
            for line in listText.components(separatedBy: .newlines) where !line.isEmpty {
                let logical = Self.canonicalDpkgPath(line, root: selectedRoot)
                listedLogicalPaths.append(logical)
                owners[logical, default: []].insert(packageID)
                listed += 1
                let physical = Self.physicalDpkgPath(line, root: selectedRoot)
                var isDirectory: ObjCBool = false
                if !fileManager.fileExists(atPath: physical, isDirectory: &isDirectory) {
                    missing += 1
                } else if isDirectory.boolValue {
                    notChecked += 1
                } else if !fileManager.isReadableFile(atPath: physical) {
                    unreadable += 1
                } else {
                    existing += 1
                }
            }
            let conffiles = Set(Self.conffilePaths(fields: fields, infoDirectory: infoDirectory).map {
                Self.canonicalDpkgPath($0, root: selectedRoot)
            })
            let state = Self.dpkgState(fields["Status"] ?? "")
            packageResults.append([
                "package_id": packageID, "version": fields["Version"] ?? "",
                "architecture": fields["Architecture"] ?? "", "status": fields["Status"] ?? "",
                "want": state.want, "error_flag": state.errorFlag, "current_state": state.current,
                "state": state.state,
                "maintainer": fields["Maintainer"] ?? "", "description": fields["Description"] ?? "",
                "depends": fields["Depends"] ?? "", "pre_depends": fields["Pre-Depends"] ?? "",
                "recommends": fields["Recommends"] ?? "", "suggests": fields["Suggests"] ?? "",
                "provides": fields["Provides"] ?? "", "conflicts": fields["Conflicts"] ?? "",
                "replaces": fields["Replaces"] ?? "", "essential": fields["Essential"] ?? "",
                "homepage": fields["Homepage"] ?? "",
                "source": fields["Source"] ?? "", "section": fields["Section"] ?? "",
                "listed_files": String(listed), "existing_files": String(existing),
                "missing_files": String(missing), "unreadable_files": String(unreadable),
                "not_checked_files": String(notChecked), "conffiles": String(conffiles.count),
                "source_classification": fields["Status"]?.contains(" installed") == true ? "dpkg" : "unknown"
            ])

            // 11. Compare dpkg .md5sums using MD5 only (format compatibility, not a signature).
            let md5Path = (infoDirectory as NSString).appendingPathComponent(packageID + ".md5sums")
            var checksumPaths = Set<String>()
            if let md5Text = try? String(contentsOfFile: md5Path, encoding: .utf8) {
                for row in md5Text.components(separatedBy: .newlines) where !row.isEmpty {
                    let parts = row.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                    guard parts.count == 2 else { continue }
                    let expected = String(parts[0]).lowercased()
                    let entry = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines).droppingPrefix("*")
                    let logical = Self.canonicalDpkgPath(entry, root: selectedRoot)
                    checksumPaths.insert(logical)
                    let physical = Self.physicalDpkgPath(entry, root: selectedRoot)
                    guard fileManager.fileExists(atPath: physical) else {
                        integrity.append(["package_id": packageID, "path": logical, "status": "checksum_unavailable", "reason": "missing"])
                        continue
                    }
                    guard let actual = Self.md5File(atPath: physical) else {
                        integrity.append(["package_id": packageID, "path": logical, "status": "checksum_unavailable", "reason": "unreadable_or_hash_unavailable"])
                        continue
                    }
                    if actual == expected { continue }
                    let classification = Self.classifyFile(path: logical, physicalPath: physical)
                    let isConffile = conffiles.contains(logical)
                    let disposition: String
                    let reason: String
                    switch classification.fileType {
                    case "mach_o":
                        disposition = "warning"
                        reason = "二进制内容与记录不同；可能为重签名、补丁、重定位或其他变更，本工具不判定成因"
                        warningCount += 1
                    case "configuration" where isConffile:
                        disposition = "mutable_config"
                        reason = "已在 Conffiles 声明，允许本地配置差异"
                        warningCount += 1
                    case "configuration" where (logical as NSString).pathExtension.lowercased() == "plist":
                        disposition = "configuration_review"
                        reason = "非 Conffiles 的 plist/配置差异，需复核；不直接判定为损坏或篡改"
                        notConfirmedCount += 1
                    case "configuration":
                        disposition = "hard_failure"
                        reason = "非 Conffiles 配置文件内容不一致"
                        hardFailureCount += 1
                    case "text":
                        disposition = "hard_failure"
                        reason = "文本文件内容不一致"
                        hardFailureCount += 1
                    case "resource":
                        disposition = "hard_failure"
                        reason = "资源文件内容不一致"
                        hardFailureCount += 1
                    default:
                        disposition = "not_confirmed"
                        reason = "文件类型无法可靠识别，差异未定性"
                        notConfirmedCount += 1
                    }
                    mismatchCount += 1
                    integrity.append(["package_id": packageID, "path": logical, "status": "mismatch",
                                      "file_type": classification.fileType, "format": classification.format,
                                      "detection_method": classification.detectionMethod,
                                      "confidence": classification.confidence,
                                      "disposition": disposition, "reason": reason,
                                      "path_category": Self.pathCategory(logical),
                                      "extension": Self.extensionKey(logical),
                                      "conffile_declared": String(isConffile),
                                      "expected_md5": expected, "actual_md5": actual])
                }
            }
            // Files listed in .list but absent from .md5sums carry a no-checksum-record bucket.
            let md5Available = (try? String(contentsOfFile: md5Path, encoding: .utf8)) != nil
            if listText.isEmpty == false && md5Available {
                for logical in listedLogicalPaths where !checksumPaths.contains(logical) {
                    integrity.append(["package_id": packageID, "path": logical,
                                      "status": "no_checksum_record", "reason": "no_checksum_record"])
                }
            }
        }

        let ownershipRows = owners.keys.sorted().map { path -> [String: String] in
            let ids = owners[path, default: []].sorted()
            return ["path": path, "packages": ids.joined(separator: ","),
                    "conflict": String(ids.count > 1),
                    "plugin_file": String(pluginPaths.contains(where: { Self.canonicalDpkgPath($0, root: selectedRoot) == path }))]
        }
        let conflictCount = ownershipRows.filter { $0["conflict"] == "true" }.count
        let unownedPluginFiles = pluginPaths.filter { path in
            let logical = Self.canonicalDpkgPath(path, root: selectedRoot)
            return owners[logical] == nil
        }.count
        return DpkgAnalysis(packages: packageResults, ownership: ownershipRows, integrity: integrity,
                            mismatchCount: mismatchCount, noChecksumCount: integrity.filter { $0["status"] == "no_checksum_record" }.count,
                            hardFailureCount: hardFailureCount, warningCount: warningCount,
                            notConfirmedCount: notConfirmedCount, conflictCount: conflictCount,
                            unownedPluginFiles: unownedPluginFiles)
    }

    private static func conffilePaths(fields: [String: String], infoDirectory: String) -> [String] {
        var paths: Set<String> = []
        if let field = fields["Conffiles"] {
            for line in field.components(separatedBy: .newlines) {
                let path = line.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
                if path.hasPrefix("/") { paths.insert(path) }
            }
        }
        if let packageID = fields["Package"] {
            let file = (infoDirectory as NSString).appendingPathComponent(packageID + ".conffiles")
            if let text = try? String(contentsOfFile: file, encoding: .utf8) {
                for line in text.components(separatedBy: .newlines) {
                    let path = line.trimmingCharacters(in: .whitespaces)
                    if path.hasPrefix("/") { paths.insert(path) }
                }
            }
        }
        return paths.sorted()
    }

    private static func canonicalDpkgPath(_ path: String, root: String?) -> String {
        var value = (path as NSString).standardizingPath
        if let root, value.hasPrefix(root) { value = String(value.dropFirst(root.count)) }
        if value.hasPrefix("/var/jb/") { value = String(value.dropFirst(7)) }
        if value == "/var/jb" { value = "/" }
        return value.hasPrefix("/") ? value : "/" + value
    }

    private static func physicalDpkgPath(_ path: String, root: String?) -> String {
        if path.hasPrefix("/var/jb/") || path == "/var/jb" { return path }
        guard let root, path.hasPrefix("/") else { return path }
        return (root as NSString).appendingPathComponent(String(path.dropFirst()))
    }

    /// dpkg Status field: `want flag current-state` decomposed conservatively.
    private static func dpkgState(_ status: String) -> (want: String, errorFlag: String, current: String, state: String) {
        let parts = status.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let want = parts.count > 0 ? parts[0] : "unknown"
        let errorFlag = parts.count > 1 ? parts[1] : "unknown"
        let current = parts.count > 2 ? parts[2] : "unknown"
        let state: String
        if parts.count != 3 {
            state = current
        } else if errorFlag == "reinstreq" {
            state = "reinstreq"
        } else if current == "installed" && want == "install" && errorFlag == "ok" {
            state = "installed"
        } else if current == "installed" {
            state = "installed_nonstandard_status"
        } else if let known = ["unpacked", "half-installed", "half-configured", "config-files",
                               "not-installed", "triggers-awaited", "triggers-pending"].first(where: { $0 == current }) {
            state = known
        } else {
            state = current
        }
        return (want, errorFlag, current, state)
    }

    private static func classifyFile(path: String, physicalPath: String)
    -> (fileType: String, format: String, detectionMethod: String, confidence: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        var format: String?
        var magicType: String?
        var bytes: [UInt8] = []
        if let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: physicalPath)) {
            // Legacy Foundation file handle APIs: `closeFile()` / `readData(ofLength:)`
            // predate the macOS 10.15 / 10.15.4 availability gates of `close()` and
            // `read(upToCount:)`, so they stay compilable on the current deployment target.
            defer { handle.closeFile() }
            let sample = handle.readData(ofLength: 16)
            bytes = [UInt8](sample)
            format = Self.magicFormat(bytes: bytes)
            magicType = Self.typeFromFormat(format)
        }
        if let magicType {
            return (magicType, format ?? "", "magic", "high")
        }
        if !physicalPath.isEmpty && Self.isLikelyTextFile(physicalPath) {
            let textType = Self.isConfigurationExtension(ext) ? "configuration" : "text"
            return (textType, "text", "content", "medium")
        }
        if Self.isConfigurationExtension(ext) {
            return ("configuration", ext, "extension", "medium")
        }
        if Self.isTextExtension(ext) {
            return ("text", ext, "extension", "medium")
        }
        if Self.isResourceExtension(ext) {
            return ("resource", ext, "extension", "medium")
        }
        return ("unknown", "", "unknown", "low")
    }

    private static func magicFormat(bytes: [UInt8]) -> String? {
        // Short-buffer signatures are matched by byte position before the
        // four-byte tuple switch, whose patterns must all be four-element.
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "jpeg"
        }
        if bytes.count >= 2, bytes[0] == 0x1F, bytes[1] == 0x8B {
            return "gzip"
        }
        guard bytes.count >= 4 else { return nil }
        let b0 = bytes[0], b1 = bytes[1], b2 = bytes[2], b3 = bytes[3]
        switch (b0, b1, b2, b3) {
        case (0xFE, 0xED, 0xFA, 0xCE), (0xFE, 0xED, 0xFA, 0xCF),
             (0xCE, 0xFA, 0xED, 0xFE), (0xCF, 0xFA, 0xED, 0xFE):
            return "mach_o"
        case (0xCA, 0xFE, 0xBA, 0xBE), (0xBE, 0xBA, 0xFE, 0xCA),
             (0xCA, 0xFE, 0xBA, 0xBF), (0xBF, 0xBA, 0xFE, 0xCA):
            return "fat_macho"
        case (0x7F, 0x45, 0x4C, 0x46): return "elf"
        case (0x89, 0x50, 0x4E, 0x47): return "png"
        case (0xFF, 0xD8, 0xFF, _): return "jpeg"
        case (0x50, 0x4B, 0x03, 0x04): return "zip"
        case (0x1F, 0x8B, _, _): return "gzip"
        case (0x25, 0x50, 0x44, 0x46): return "pdf"
        default: break
        }
        if bytes.count >= 8, bytes[0] == 0x62, bytes[1] == 0x70, bytes[2] == 0x6C, bytes[3] == 0x69,
           bytes[4] == 0x73, bytes[5] == 0x74, bytes[6] == 0x30, bytes[7] == 0x30 {
            return "bplist"
        }
        if bytes.count >= 6, bytes[0] == 0x53, bytes[1] == 0x51, bytes[2] == 0x4C,
           bytes[3] == 0x69, bytes[4] == 0x74, bytes[5] == 0x65 {
            return "sqlite"
        }
        return nil
    }

    private static func typeFromFormat(_ format: String?) -> String? {
        guard let format else { return nil }
        switch format {
        case "mach_o", "fat_macho", "elf": return "mach_o"
        case "png", "jpeg", "zip", "gzip", "sqlite", "pdf", "bplist": return "resource"
        default: return nil
        }
    }

    private static func isLikelyTextFile(_ physicalPath: String) -> Bool {
        guard let stream = InputStream(fileAtPath: physicalPath) else { return false }
        stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var total = 0, nonPrintable = 0
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return false }
            if count == 0 { break }
            for i in 0..<count {
                let c = buffer[i]
                total += 1
                let printable = (c >= 0x20 && c < 0x7F) || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C || c == 0x0B
                if !printable { nonPrintable += 1 }
            }
            if total >= 4096 { break }
        }
        guard total > 0 else { return false }
        return Double(nonPrintable) / Double(total) < 0.10
    }

    private static func isConfigurationExtension(_ ext: String) -> Bool {
        ["plist", "conf", "ini", "json", "xml", "yaml", "yml", "toml", "cfg"].contains(ext)
    }

    private static func isTextExtension(_ ext: String) -> Bool {
        ["txt", "md", "sh", "py", "rb", "js", "strings", "mo"].contains(ext)
    }

    private static func isResourceExtension(_ ext: String) -> Bool {
        ["png", "jpg", "jpeg", "webp", "gif", "zst", "zip", "car", "nib", "dat", "pdf", "ttf", "otf"].contains(ext)
    }

    private static func pathCategory(_ logical: String) -> String {
        if logical.hasPrefix("/usr/lib/") { return "/usr/lib" }
        if logical.hasPrefix("/usr/bin/") { return "/usr/bin" }
        if logical.hasPrefix("/usr/sbin/") { return "/usr/sbin" }
        if logical.hasPrefix("/Library/") { return "/Library" }
        if logical.hasPrefix("/Applications/") { return "/Applications" }
        if logical.hasPrefix("/System/") { return "/System" }
        if logical.hasPrefix("/var/") { return "/var" }
        return "other"
    }

    private static func extensionKey(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext.isEmpty ? "(无扩展名)" : ext
    }

    private static func fileType(at path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let type = attrs[.type] as? FileAttributeType else { return "unknown" }
        switch type {
        case .typeRegular: return "regular"
        case .typeSymbolicLink: return "symlink"
        case .typeDirectory: return "directory"
        default: return "other"
        }
    }

    private static func symlinkFlag(at path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let type = attrs[.type] as? FileAttributeType else { return "unknown" }
        return String(type == .typeSymbolicLink)
    }

    private static func md5File(atPath path: String) -> String? {
        #if canImport(CommonCrypto)
        guard let stream = InputStream(fileAtPath: path) else { return nil }
        stream.open(); defer { stream.close() }
        var context = CC_MD5_CTX(); CC_MD5_Init(&context)
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            buffer.withUnsafeBytes { rawBuffer in
                _ = CC_MD5_Update(&context, rawBuffer.baseAddress!, CC_LONG(count))
            }
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        digest.withUnsafeMutableBufferPointer { output in
            _ = CC_MD5_Final(output.baseAddress!, &context)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return nil
        #endif
    }

    // MARK: 14 — Helper preflight

    private func inspectHelpers(root: String?, ownership: [[String: String]])
    -> (candidates: [[String: String]], registrations: [[String: String]]) {
        var ownersByLogical: [String: [String]] = [:]
        for owner in ownership {
            if let path = owner["path"], let packages = owner["packages"] {
                ownersByLogical[path] = packages.split(separator: ",").map(String.init)
            }
        }

        func logicalPath(_ physical: String) -> String {
            var p = (physical as NSString).standardizingPath
            if let root, p.hasPrefix(root) { p = String(p.dropFirst(root.count)) }
            if !p.hasPrefix("/") { p = "/" + p }
            return (p as NSString).standardizingPath
        }

        func probe(_ path: String) -> [String: String] {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            let attrs = try? fileManager.attributesOfItem(atPath: path)
            let type: String
            if !exists { type = "unknown" }
            else if let attrType = attrs?[.type] as? FileAttributeType {
                switch attrType {
                case .typeRegular: type = "regular"
                case .typeSymbolicLink: type = "symlink"
                case .typeDirectory: type = "directory"
                default: type = "other"
                }
            } else { type = "unknown" }
            let executable = exists && type == "regular" && fileManager.isExecutableFile(atPath: path)
            let logical = logicalPath(path)
            return ["path": path, "exists": String(exists), "regular_file": String(type == "regular"),
                    "executable": String(executable), "file_type": type,
                    "size": String((attrs?[.size] as? NSNumber)?.intValue ?? 0),
                    "logical_path": logical,
                    "package_ids": ownersByLogical[logical]?.joined(separator: ",") ?? "",
                    "operation": "not_launched"]
        }

        var candidates: [[String: String]] = []
        var seen = Set<String>()
        let fixedRelative = ["usr/libexec/RootHelper", "usr/libexec/roothelper",
                             "usr/libexec/roothide/RootHelper", "usr/libexec/roothide/roothelper",
                             "usr/bin/RootHelper"]
        let fixedRoots = [root, "/var/jb", "/"].compactMap { $0 }
        for relative in fixedRelative {
            for base in fixedRoots {
                let candidate = (base as NSString).appendingPathComponent(relative)
                guard !seen.contains(candidate) else { continue }
                seen.insert(candidate)
                let record = probe(candidate)
                let rootPrefix = root ?? ""
                if record["exists"] == "true" || (!rootPrefix.isEmpty && candidate.hasPrefix(rootPrefix)) {
                    candidates.append(record)
                }
            }
        }

        var searchRoots = ["/usr/libexec", "/usr/bin", "/usr/sbin", "/Library/PrivilegedHelperTools"]
        if let root {
            searchRoots += ["usr/libexec", "usr/bin", "usr/sbin", "Library/PrivilegedHelperTools"].map {
                (root as NSString).appendingPathComponent($0)
            }
        }
        let keywords = ["helper", "root", "daemon", "agent", "service", "privileged", "ellekit", "substrate", "tweak"]
        for directory in Set(searchRoots) {
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for name in names where keywords.contains(where: { name.lowercased().contains($0) }) {
                let path = (directory as NSString).appendingPathComponent(name)
                guard !seen.contains(path) else { continue }
                seen.insert(path)
                let record = probe(path)
                if record["exists"] == "true" { candidates.append(record) }
            }
        }

        var registrations: [[String: String]] = []
        var launchDaemonDirectories = ["/Library/LaunchDaemons", "/System/Library/LaunchDaemons"]
        if let root {
            launchDaemonDirectories += [
                (root as NSString).appendingPathComponent("Library/LaunchDaemons"),
                (root as NSString).appendingPathComponent("var/jb/Library/LaunchDaemons")
            ]
        }
        for directory in launchDaemonDirectories {
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for name in names where name.hasSuffix(".plist") {
                let path = (directory as NSString).appendingPathComponent(name)
                let readableData = (try? Data(contentsOf: URL(fileURLWithPath: path)))
                let object = readableData.flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) }
                let plist = object as? [String: Any]
                let program = plist?["Program"] as? String
                let arguments = plist?["ProgramArguments"] as? [String]
                let target = program ?? arguments?.first
                var record: [String: String] = [
                    "plist": path, "readable": String(readableData != nil),
                    "valid_plist": String(plist != nil),
                    "label": plist?["Label"] as? String ?? "unknown",
                    "program": target ?? "",
                    "program_exists": String(target.map { fileManager.fileExists(atPath: $0) } ?? false),
                    "user_name": plist?["UserName"] as? String ?? "",
                    "group_name": plist?["GroupName"] as? String ?? ""
                ]
                if let target { record["program_exists"] = String(fileManager.fileExists(atPath: target)) }
                registrations.append(record)
            }
        }
        return (candidates, registrations)
    }

    // MARK: 15/16 — Installed Apps and metadata

    private func scanInstalledApplications() -> [[String: String]] {
        #if canImport(ObjectiveC)
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") else { return [] }
        let defaultSelector = NSSelectorFromString("defaultWorkspace")
        guard let method = class_getClassMethod(workspaceClass, defaultSelector) else { return [] }
        typealias ObjectReturnFunction = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let implementation = method_getImplementation(method)
        let invoke = unsafeBitCast(implementation, to: ObjectReturnFunction.self)
        guard let workspaceObject = invoke(workspaceClass, defaultSelector)?.takeUnretainedValue(),
              let workspace = workspaceObject as? NSObject else { return [] }
        let selector = NSSelectorFromString("allInstalledApplications")
        let fallback = NSSelectorFromString("allApplications")
        let proxies = (workspace.responds(to: selector) ? workspace.perform(selector)?.takeUnretainedValue() : nil)
            ?? (workspace.responds(to: fallback) ? workspace.perform(fallback)?.takeUnretainedValue() : nil)
        guard let array = proxies as? [NSObject] else { return [] }
        return array.compactMap { proxy in
            guard let bundleID = Self.invokeString(proxy, "applicationIdentifier"), !bundleID.isEmpty else { return nil }
            let name = Self.invokeString(proxy, "localizedName") ?? bundleID
            let bundleURL = proxy.perform(NSSelectorFromString("bundleURL"))?.takeUnretainedValue() as? URL
            let path = bundleURL?.path ?? ""
            let info = NSDictionary(contentsOfFile: (path as NSString).appendingPathComponent("Info.plist")) as? [String: Any] ?? [:]
            let shortVersion = info["CFBundleShortVersionString"] as? String
            let buildVersion = info["CFBundleVersion"] as? String
            let iconDictionary = info["CFBundleIcons"] as? [String: Any]
            let primaryIcon = iconDictionary?["CFBundlePrimaryIcon"] as? [String: Any]
            let iconFiles = primaryIcon?["CFBundleIconFiles"] as? [String] ?? (info["CFBundleIconFiles"] as? [String] ?? [])
            let iconName = iconFiles.last ?? ""
            let iconPath = iconName.isEmpty ? "" : (path as NSString).appendingPathComponent(iconName)
            #if canImport(UIKit)
            let iconDecoded = !iconPath.isEmpty && UIImage(contentsOfFile: iconPath) != nil
            let iconSource = iconDecoded ? "bundle_file" : (iconPath.isEmpty ? "unresolved" : "bundle_file_candidate")
            #else
            let iconDecoded = false
            let iconSource = iconPath.isEmpty ? "unresolved" : "bundle_file_candidate"
            #endif
            return ["bundle_id": bundleID, "name": name, "bundle_path": path,
                    "version": shortVersion ?? buildVersion ?? "unknown",
                    "version_source": shortVersion != nil ? "CFBundleShortVersionString" : (buildVersion != nil ? "CFBundleVersion" : "unknown"),
                    "build_version": buildVersion ?? "", "executable": info["CFBundleExecutable"] as? String ?? "",
                    "is_system": String(path.hasPrefix("/Applications/") || path.hasPrefix("/System/")),
                    "icon_source": iconSource,
                    "icon_path": iconPath, "icon_decoded": String(iconDecoded)]
        }
        #else
        return []
        #endif
    }

    #if canImport(ObjectiveC)
    private static func invokeString(_ object: NSObject, _ selectorName: String) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? String
    }
    #endif

    // MARK: 17 — Static plugin/App associations

    private struct AssociationSummary {
        let global: Int
        let unmatched: Int
        let missingDylib: Int
        let missingPlist: Int
    }

    private static func associationSummary(filters: [[String: String]], plugins: [[String: String]]) -> AssociationSummary {
        let global = filters.filter { $0["global"] == "true" }.count
        let unmatched = filters.filter {
            !($0["unmatched_bundle_ids"] ?? "").isEmpty || !($0["unmatched_executables"] ?? "").isEmpty
        }.count
        let pluginBases = Set(plugins.map { (($0["path"] ?? "") as NSString).deletingPathExtension.lowercased() })
        let plistBases = Set(filters.map { (($0["plist_path"] ?? "") as NSString).deletingPathExtension.lowercased() })
        let missingDylib = plistBases.subtracting(pluginBases).count
        let missingPlist = pluginBases.subtracting(plistBases).count
        return AssociationSummary(global: global, unmatched: unmatched, missingDylib: missingDylib, missingPlist: missingPlist)
    }

    private func buildAssociations(applications: [[String: String]], filters: [[String: String]]) -> [[String: String]] {
        var results: [[String: String]] = []
        for filter in filters {
            let bundleTargets = Set((filter["bundles"] ?? "").split(separator: ",").map(String.init))
            let executableTargets = Set((filter["executables"] ?? "").split(separator: ",").map(String.init))
            let isGlobal = filter["global"] == "true"
            let matches = applications.filter { app in
                let bundleID = app["bundle_id"] ?? ""
                let executable = app["executable"] ?? ""
                return bundleTargets.contains(bundleID) || executableTargets.contains(executable)
            }
            let unmatchedBundles = Set((filter["unmatched_bundle_ids"] ?? "").split(separator: ",").map(String.init))
            let unmatchedExecutables = Set((filter["unmatched_executables"] ?? "").split(separator: ",").map(String.init))
            let category: String
            if filter["parse_status"] == "not_parsed" || filter["parse_status"] == "read_failed" {
                category = "invalid_configuration"
            } else if isGlobal {
                category = "global"
            } else if !matches.isEmpty {
                category = "exact_match"
            } else if !unmatchedBundles.isEmpty || !unmatchedExecutables.isEmpty {
                category = "unmatched_target"
            } else {
                category = "unresolved_non_bundle_rule"
            }
            for app in matches {
                results.append(["plugin": filter["plugin"] ?? "unknown", "bundle_id": app["bundle_id"] ?? "unknown",
                                "match_type": bundleTargets.contains(app["bundle_id"] ?? "") ? "bundle" : "executable",
                                "category": category, "is_global": String(isGlobal),
                                "matched_app_count": String(matches.count),
                                "unmatched_target_count": String(unmatchedBundles.count + unmatchedExecutables.count),
                                "evidence": "static_filter_match_only", "loaded": "unknown"])
            }
            if matches.isEmpty {
                results.append(["plugin": filter["plugin"] ?? "unknown", "bundle_id": "",
                                "match_type": "none", "category": category, "is_global": String(isGlobal),
                                "matched_app_count": "0",
                                "unmatched_target_count": String(unmatchedBundles.count + unmatchedExecutables.count),
                                "evidence": "static_filter_match_only", "loaded": "unknown"])
            }
        }
        return results
    }

    // MARK: Filter dictionary parsing (item 5)

    private static func parseFilterDictionary(_ object: Any?,
                                              installedBundleIDs: Set<String>,
                                              installedExecutables: Set<String>) -> [String: String] {
        guard let filter = object as? [String: Any] else {
            return ["valid": "false", "entry_count": "0", "warnings": "filter_not_a_dictionary"]
        }
        let knownKeys = ["Bundles", "Executables", "Classes"]
        var warnings: [String] = []
        var otherKeys: [String] = []
        var global = false
        var matchedBundles: [String] = []
        var unmatchedBundles: [String] = []
        var matchedExecutables: [String] = []
        var unmatchedExecutables: [String] = []

        func stringItems(_ key: String) -> [String] {
            guard let value = filter[key] else { return [] }
            guard let array = value as? [Any] else {
                warnings.append("\(key) 不是数组（实际类型 \(String(describing: type(of: value)))）")
                return []
            }
            var items: [String] = []
            for item in array {
                guard let stringItem = item as? String else {
                    warnings.append("\(key) 含非字符串元素（\(String(describing: type(of: item)))）")
                    continue
                }
                let trimmed = stringItem.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    warnings.append("\(key) 含空字符串，已忽略")
                    continue
                }
                items.append(stringItem)
            }
            return items
        }

        let bundles = stringItems("Bundles")
        let executables = stringItems("Executables")
        let classes = stringItems("Classes")

        for bundle in bundles {
            if bundle == "*" {
                global = true
            } else if installedBundleIDs.contains(bundle) {
                matchedBundles.append(bundle)
            } else {
                unmatchedBundles.append(bundle)
            }
        }
        for executable in executables {
            let lower = executable.lowercased()
            if installedExecutables.contains(lower) {
                matchedExecutables.append(executable)
            } else {
                unmatchedExecutables.append(executable)
            }
        }
        for key in filter.keys {
            if !knownKeys.contains(key) { otherKeys.append(key) }
        }
        otherKeys.sort()
        if global {
            warnings.append("Bundles 含 *；按候选全局规则标记，通配语义尚未由 ElleKit loader 源码确认")
        }
        let entryCount = bundles.count + executables.count + classes.count
        return [
            "bundles": bundles.joined(separator: ","),
            "executables": executables.joined(separator: ","),
            "classes": classes.joined(separator: ","),
            "other_keys": otherKeys.joined(separator: ","),
            "global": String(global),
            "matched_bundle_ids": matchedBundles.joined(separator: ","),
            "unmatched_bundle_ids": unmatchedBundles.joined(separator: ","),
            "matched_executables": matchedExecutables.joined(separator: ","),
            "unmatched_executables": unmatchedExecutables.joined(separator: ","),
            "warnings": warnings.joined(separator: " | "),
            "valid": String(entryCount > 0),
            "entry_count": String(entryCount)
        ]
    }

    // MARK: Utilities

    private func add(_ id: String, _ title: String, _ state: String, _ detail: String) {
        findings.append(FKDiagnosticFinding(id: id, title: title, state: state, detail: detail))
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { $0 as? String }
    }

    private static var machineArchitecture: String {
        #if canImport(Darwin)
        var info = utsname(); uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        #else
        return "unknown"
        #endif
    }
}

private extension String {
    func droppingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
