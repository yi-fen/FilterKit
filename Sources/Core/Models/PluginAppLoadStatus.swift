import Foundation

/// Describes the plugin's configured loading scope, not whether a process is
/// currently alive or whether dyld has confirmed the image in memory.
enum PluginAppLoadStatus: Equatable {
    case appTargets([String])
    case executableTargets([String])
    case globalTarget
    case independent
    case unknown

    static func resolve(plugin: PluginScanItem,
                        appNamesByBundleID: [String: String],
                        appNamesByExecutable: [String: String]) -> PluginAppLoadStatus {
        let filter = plugin.filterConfiguration
        // Only the observed ElleKit filter is evidence of a configured load target.
        // Manifest owner/association hints are intentionally excluded because the
        // scanner may have read them without verifying the Manifest identity.
        guard let filter, (filter.parseState == .valid || filter.parseState == .partial) else {
            return .unknown
        }
        // Case-variant duplicate target keys are ambiguous: never infer a partial
        // target list from whichever dictionary entry happened to be visited first.
        if filter.warnings.contains(where: {
            $0 == "plugin_filter.duplicate_key_bundles"
                || $0 == "plugin_filter.duplicate_key_executables"
        }) {
            return .unknown
        }

        if filter.bundles.contains(where: { $0 == "*" }) {
            return .globalTarget
        }

        let bundleTargets = Set(filter.bundles.filter {
            PluginAssociationPlanResolver.isValidBundleIdentifier($0)
        })
        if !filter.bundles.isEmpty && bundleTargets.isEmpty {
            return .unknown
        }

        let appNames = bundleTargets.map { identifier in
            appNamesByBundleID[identifier.lowercased()] ?? identifier
        }
        let uniqueAppNames = Array(Set(appNames)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        if !uniqueAppNames.isEmpty {
            return .appTargets(uniqueAppNames)
        }

        let executables = Set(filter.executables.compactMap { raw -> String? in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        })
        if !executables.isEmpty {
            let names = executables.map { value in
                appNamesByExecutable[value.lowercased()] ?? value
            }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return .executableTargets(names)
        }

        // Only a fully valid, empty target list can be called independent.
        // Partial parsing may have hidden a target in a malformed field.
        return filter.parseState == .valid ? .independent : .unknown
    }
}
