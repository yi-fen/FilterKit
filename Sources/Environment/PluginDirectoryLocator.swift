import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Read-only locator for third-party tweak directories. ElleKit's own component
/// directory is observed separately and is never selected as a plugin directory.
final class PluginDirectoryLocator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func inspect(jbroot: String, environment: JailbreakEnvironmentKind) -> PluginDirectoryAssessment {
        guard environment == .rootHide || environment == .rootless else {
            return .unresolved("environment.plugin_directory.unsupported_environment")
        }

        let definitions: [(String, PluginDirectoryKind, PluginDirectoryRole)] = [
            ("Library/ElleKit/DynamicLibraries", .elleKitDynamicLibraries, .thirdPartyPluginDirectory),
            ("Library/MobileSubstrate/DynamicLibraries", .mobileSubstrateDynamicLibraries, .thirdPartyPluginDirectory),
            ("library/MobileSubstrate/DynamicLibraries", .mobileSubstrateDynamicLibraries, .thirdPartyPluginDirectory),
            ("usr/lib/TweakInject", .tweakInject, .thirdPartyPluginDirectory),
            // ElleKit's own component directory is not automatically a third-party plugin directory.
            ("Library/TweakInject", .elleKitComponentDirectory, .elleKitComponentDirectory)
        ]

        var candidates = definitions.map { relative, kind, role in
            inspectCandidate(path: URL(fileURLWithPath: jbroot, isDirectory: true)
                .appendingPathComponent(relative, isDirectory: true).path,
                kind: kind, role: role)
        }
        candidates = mergeCanonicalAliases(candidates)

        let usable = candidates.filter(\.isUsable)
        let inaccessible = candidates.contains { $0.role == .thirdPartyPluginDirectory && $0.exists && (!$0.isReadable || !$0.isEnumerable) }
        // Empty compatibility directories are common in rootless/rootHide layouts. They
        // must not compete with a directory that actually contains plugin inventory.
        let populated = usable.filter { $0.dylibCount > 0 || $0.plistCount > 0 }
        let distinctPopulated = Dictionary(grouping: populated, by: { $0.canonicalPath ?? $0.path }).keys
        let preferredOrder: [PluginDirectoryKind] = [.elleKitDynamicLibraries, .mobileSubstrateDynamicLibraries, .tweakInject]
        let preferred: (PluginDirectoryCandidate) -> Int = { candidate in
            preferredOrder.firstIndex(of: candidate.kind) ?? preferredOrder.count
        }

        let state: PluginDirectoryResolutionState
        let selected: String?
        var warnings: [String] = []
        if inaccessible {
            state = .inaccessible
            selected = nil
            warnings.append("environment.plugin_directory.inaccessible")
        } else if distinctPopulated.count > 1 {
            state = .ambiguous
            selected = nil
            warnings.append("environment.plugin_directory.ambiguous")
        } else if let only = populated.sorted(by: { preferred($0) < preferred($1) }).first,
                  let canonical = only.canonicalPath {
            state = .resolved
            selected = canonical
            if only.kind == .mobileSubstrateDynamicLibraries { warnings.append("environment.plugin_directory.legacy_layout_selected") }
        } else if let empty = usable.sorted(by: { preferred($0) < preferred($1) }).first,
                  let canonical = empty.canonicalPath {
            // No plugin evidence anywhere: resolve deterministically to the preferred
            // existing directory and return an empty inventory rather than false ambiguity.
            state = .resolved
            selected = canonical
        } else {
            state = .unavailable
            selected = nil
            warnings.append("environment.plugin_directory.not_found")
        }
        if candidates.contains(where: { $0.role == .elleKitComponentDirectory && $0.exists }) {
            warnings.append("environment.plugin_directory.ellekit_component_separate")
        }
        warnings.append("environment.probe.read_only")
        return PluginDirectoryAssessment(state: state, selectedPath: selected,
                                          candidates: candidates, warnings: warnings,
                                          isReadOnly: true)
    }

    private func inspectCandidate(path: String, kind: PluginDirectoryKind,
                                  role: PluginDirectoryRole) -> PluginDirectoryCandidate {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists else {
            return PluginDirectoryCandidate(path: path, canonicalPath: nil, kind: kind, role: role,
                exists: false, isDirectory: false, isReadable: false, isEnumerable: false,
                isWritable: false, isSymbolicLink: false, dylibCount: 0, plistCount: 0,
                detailCode: "plugin_directory.not_found")
        }
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let isLink = (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
        let readable = isDirectory.boolValue && fileManager.isReadableFile(atPath: path)
        let writable = isDirectory.boolValue && fileManager.isWritableFile(atPath: path)
        let entries: [String]?
        if readable && role == .thirdPartyPluginDirectory {
            PluginInventoryPerformanceDiagnostics.recordEnvironmentProbeEnumeration()
            entries = try? fileManager.contentsOfDirectory(atPath: path)
        } else {
            // ElleKit's own component directory is diagnostic-only and is never
            // part of the third-party plugin inventory, so do not enumerate it.
            entries = nil
        }
        let enumerable = entries != nil
        let names = entries ?? []
        let dylibCount = names.filter { $0.lowercased().hasSuffix(".dylib") }.count
        let plistCount = names.filter { $0.lowercased().hasSuffix(".plist") }.count
        let canonical = URL(fileURLWithPath: path, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let detail: String
        if !isDirectory.boolValue { detail = "plugin_directory.not_directory" }
        else if !readable { detail = "plugin_directory.not_readable" }
        else if role == .elleKitComponentDirectory { detail = "plugin_directory.component_not_enumerated" }
        else if !enumerable { detail = "plugin_directory.not_enumerable" }
        else { detail = "plugin_directory.enumerable" }
        return PluginDirectoryCandidate(path: path, canonicalPath: canonical, kind: kind, role: role,
            exists: true, isDirectory: isDirectory.boolValue, isReadable: readable,
            isEnumerable: enumerable, isWritable: writable, isSymbolicLink: isLink,
            dylibCount: dylibCount, plistCount: plistCount,
            entryNames: entries, detailCode: detail)
    }

    /// Canonical paths collapse symlink aliases without hiding genuinely distinct
    /// plugin directories. Keep a representative plus aggregated file counts.
    private func mergeCanonicalAliases(_ input: [PluginDirectoryCandidate]) -> [PluginDirectoryCandidate] {
        let groups = Dictionary(grouping: input) { $0.canonicalPath ?? $0.path }
        return groups.values.map { group in
            guard group.count > 1 else { return group[0] }
            let preferred = group.first(where: { $0.role == .thirdPartyPluginDirectory }) ?? group[0]
            return PluginDirectoryCandidate(path: preferred.path, canonicalPath: preferred.canonicalPath,
                kind: preferred.kind, role: preferred.role,
                exists: group.contains(where: \.exists),
                isDirectory: group.contains(where: \.isDirectory),
                isReadable: group.contains(where: \.isReadable),
                isEnumerable: group.contains(where: \.isEnumerable),
                isWritable: group.contains(where: \.isWritable),
                isSymbolicLink: group.contains(where: \.isSymbolicLink),
                dylibCount: group.map(\.dylibCount).max() ?? 0,
                plistCount: group.map(\.plistCount).max() ?? 0,
                entryNames: preferred.entryNames,
                detailCode: "plugin_directory.canonical_aliases_merged")
        }.sorted { $0.path < $1.path }
    }
}
