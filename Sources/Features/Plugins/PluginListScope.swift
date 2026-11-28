import Foundation

/// The alternate list contains FilterKit-managed plugins that participate in
/// the App-association layer. Enabled and disabled associations are both valid.
enum PluginListScope {
    static func includes(_ item: PluginScanItem, filterKitAssociatedOnly: Bool) -> Bool {
        guard filterKitAssociatedOnly else { return true }
        guard item.ownership == .filterKit else { return false }
        return PluginListStatus(item: item).hasAppAssociation
    }
}

struct PluginListStatus: Equatable {
    enum Injection: Equatable { case enabled, disabled, unknown }
    enum ManagementType: Equatable { case standalone, appAssociated }

    struct AppEntry: Equatable {
        let bundleIdentifier: String
        let isFixedOwner: Bool
        let injection: Injection
    }

    let apps: [AppEntry]
    let injectionSummary: Injection
    let enabledCount: Int
    let disabledCount: Int
    let unknownCount: Int

    var hasAppAssociation: Bool { !apps.isEmpty }
    var managementType: ManagementType { hasAppAssociation ? .appAssociated : .standalone }

    init(item: PluginScanItem) {
        let fixedOwner = item.hardBoundBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bundle identifiers are case-insensitive identifiers for display/deduplication.
        // Preserve the first original spelling for the visible label, but never show
        // the Fixed Owner twice if it also appears in the additional-association list.
        var softIDsByNormalizedID: [String: String] = [:]
        for rawID in item.softAssociatedBundleIdentifiers {
            let bundleID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty else { continue }
            let normalized = bundleID.lowercased()
            if let fixedOwner, !fixedOwner.isEmpty,
               normalized == fixedOwner.lowercased() { continue }
            if softIDsByNormalizedID[normalized] == nil {
                softIDsByNormalizedID[normalized] = bundleID
            }
        }

        let filter = item.filterConfiguration
        let filterUsable = filter?.parseState == .valid
            && filter?.bundles.contains("*") == false
            && filter?.classes.isEmpty == true
            && filter?.executables.isEmpty == true
            && !(filter?.warnings.contains(where: {
                $0 == "plugin_filter.duplicate_key_bundles"
                    || $0 == "plugin_filter.duplicate_key_executables"
            }) ?? false)
        let observedBundles = Set((filter?.bundles ?? []).map { $0.lowercased() })
        let states = Dictionary(grouping: item.softAssociationStates ?? [], by: { $0.bundleIdentifier.lowercased() })

        var entries: [AppEntry] = []
        if let fixedOwner, !fixedOwner.isEmpty {
            let enabled: Injection = filterUsable
                ? (observedBundles.contains(fixedOwner.lowercased()) ? .enabled : .disabled)
                : .unknown
            entries.append(AppEntry(bundleIdentifier: fixedOwner, isFixedOwner: true, injection: enabled))
        }
        let sortedSoftIDs = softIDsByNormalizedID.values.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        for bundleID in sortedSoftIDs {
            let key = bundleID.lowercased()
            let injection: Injection
            if !filterUsable {
                injection = .unknown
            } else if let matches = states[key], matches.count == 1, let state = matches.first {
                let filterEnabled = observedBundles.contains(key)
                injection = state.isEnabled == filterEnabled ? (state.isEnabled ? .enabled : .disabled) : .unknown
            } else {
                injection = .unknown
            }
            entries.append(AppEntry(bundleIdentifier: bundleID, isFixedOwner: false, injection: injection))
        }

        self.apps = entries
        self.enabledCount = entries.filter { $0.injection == .enabled }.count
        self.disabledCount = entries.filter { $0.injection == .disabled }.count
        self.unknownCount = entries.filter { $0.injection == .unknown }.count
        if !entries.isEmpty && entries.allSatisfy({ $0.injection == .enabled }) {
            self.injectionSummary = .enabled
        } else if !entries.isEmpty && entries.allSatisfy({ $0.injection == .disabled }) {
            self.injectionSummary = .disabled
        } else {
            self.injectionSummary = .unknown
        }
    }
}
