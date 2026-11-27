import Foundation

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
