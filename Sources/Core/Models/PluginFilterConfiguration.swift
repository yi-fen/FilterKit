import Foundation

enum PluginFilterParseState: String, Codable, Equatable {
    case valid
    case partial
    case invalid
    case unavailable
}

/// Read-only projection of the ElleKit filter dictionary. Original plist bytes remain untouched.
struct PluginFilterConfiguration: Codable, Equatable {
    let parseState: PluginFilterParseState
    let containerKey: String
    let bundles: [String]
    let executables: [String]
    let classes: [String]
    /// Preserves the plist value as a display string; semantics are not inferred here.
    let modeDescription: String?
    let unknownKeys: [String]
    let warnings: [String]

    static func parse(_ data: Data) -> PluginFilterConfiguration {
        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let root = object as? [String: Any] else {
                return invalid("plugin_filter.root_not_dictionary")
            }
            let filter: [String: Any]
            let containerKey: String
            if let rawFilter = root["Filter"] {
                guard let dictionary = rawFilter as? [String: Any] else {
                    return invalid("plugin_filter.filter_not_dictionary")
                }
                filter = dictionary
                containerKey = "Filter"
            } else {
                filter = root
                containerKey = "root"
            }

            var warnings: [String] = []
            func stringArray(_ key: String) -> [String] {
                guard let raw = filter[key] else { return [] }
                guard let values = raw as? [Any] else {
                    warnings.append("plugin_filter.\(key.lowercased())_not_array")
                    return []
                }
                let strings = values.compactMap { $0 as? String }
                if strings.count != values.count {
                    warnings.append("plugin_filter.\(key.lowercased())_contains_non_string")
                }
                return strings
            }
            let bundles = stringArray("Bundles")
            let executables = stringArray("Executables")
            let classes = stringArray("Classes")
            let mode: String?
            if let rawMode = filter["Mode"] {
                if let value = rawMode as? String { mode = value }
                else if let value = rawMode as? NSNumber { mode = value.stringValue }
                else { mode = String(describing: type(of: rawMode)); warnings.append("plugin_filter.mode_unrecognized_type") }
            } else { mode = nil }
            let known: Set<String> = ["Bundles", "Executables", "Classes", "Mode"]
            let unknown = filter.keys.filter { !known.contains($0) }.sorted()
            return PluginFilterConfiguration(parseState: warnings.isEmpty ? .valid : .partial,
                containerKey: containerKey, bundles: bundles, executables: executables,
                classes: classes, modeDescription: mode, unknownKeys: unknown, warnings: warnings)
        } catch {
            return invalid("plugin_filter.plist_parse_failed")
        }
    }

    private static func invalid(_ warning: String) -> PluginFilterConfiguration {
        PluginFilterConfiguration(parseState: .invalid, containerKey: "unknown", bundles: [],
            executables: [], classes: [], modeDescription: nil, unknownKeys: [], warnings: [warning])
    }
}

enum PluginManagementAccess: String, Codable, Equatable {
    case manageable
    case readOnlyPackageManager
    case readOnlyUnknownSource
    case readOnlyInvalidPair
    case readOnlyUnverifiedIdentity
    case readOnlyIdentityConflict
    case readOnlyOwnershipConflict
}

/// Centralized authorization decision. UI visibility never grants management permission.
struct PluginManagementPermission: Codable, Equatable {
    let access: PluginManagementAccess
    let reasonKey: String

    var canModify: Bool { access == .manageable }

    static func evaluate(ownership: PluginOwnership, pairing: PluginPairingState,
                         binaryKind: PluginBinaryKind?, verifiedPluginID: String?,
                         filterConfiguration: PluginFilterConfiguration?) -> PluginManagementPermission {
        guard ownership == .filterKit else {
            return PluginManagementPermission(access: ownership == .packageManager ? .readOnlyPackageManager : .readOnlyUnknownSource,
                reasonKey: ownership == .packageManager ? "plugins.permission.package_manager" : "plugins.permission.unknown_source")
        }
        guard pairing == .paired, binaryKind == .machO,
              filterConfiguration?.parseState == .valid else {
            return PluginManagementPermission(access: .readOnlyInvalidPair, reasonKey: "plugins.permission.invalid_pair")
        }
        guard let id = verifiedPluginID, UUID(uuidString: id) != nil else {
            return PluginManagementPermission(access: .readOnlyUnverifiedIdentity, reasonKey: "plugins.permission.unverified_identity")
        }
        return PluginManagementPermission(access: .manageable, reasonKey: "plugins.permission.filterkit_managed")
    }

    static func restricting(_ permission: PluginManagementPermission,
                            identityStatus: PluginIdentityStatus,
                            ownershipConflict: PluginOwnershipConflict) -> PluginManagementPermission {
        if ownershipConflict != .none {
            return PluginManagementPermission(access: .readOnlyOwnershipConflict,
                reasonKey: "plugins.permission.ownership_conflict")
        }
        switch identityStatus {
        case .duplicateIdentity, .installNameCollision, .uuidCDHashMismatch, .unresolvedBasenameCollision:
            return PluginManagementPermission(access: .readOnlyIdentityConflict,
                reasonKey: "plugins.permission.identity_conflict")
        case .unique, .insufficientFingerprint:
            return permission
        }
    }
}
