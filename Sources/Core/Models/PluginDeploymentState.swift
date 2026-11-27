import Foundation

/// User intent is deliberately separate from on-disk configuration and runtime evidence.
enum PluginDesiredState: String, Codable, Equatable {
    case enabled
    case disabled
    case notSet
}

enum PluginDeployedState: String, Codable, Equatable {
    case enabledInConfiguration
    case disabledInConfiguration
    case partiallyConfigured
    case absent
    case unknown
}

enum PluginRuntimeState: String, Codable, Equatable {
    case observedLoaded
    case observedNotLoaded
    case notObserved
    case inaccessible
}

struct PluginDeploymentStateSnapshot: Codable, Equatable {
    let desiredState: PluginDesiredState
    let deployedState: PluginDeployedState
    let runtimeState: PluginRuntimeState
    let evidenceKeys: [String]

    /// A disk/configuration observation must never be promoted to runtime success.
    var reportsInjectionSuccess: Bool { runtimeState == .observedLoaded }
}

enum PluginToggleDenial: String, Codable, Equatable {
    case hardBoundAssociation
    case notFilterKitOwned
    case managementPermissionDenied
    case strategyUnverified
    case appUnavailable
}

struct PluginToggleAuthorization {
    static func denial(ownership: PluginOwnership,
                       permission: PluginManagementPermission,
                       isHardBoundApp: Bool,
                       appIsAvailable: Bool,
                       strategy: EnableDisableStrategy) -> PluginToggleDenial? {
        // A hard binding is immutable as an association, not as an activation state.
        // App Detail may disable/enable its own hard-bound plugin; it may never unbind it.
        if ownership != .filterKit { return .notFilterKitOwned }
        if !permission.canModify { return .managementPermissionDenied }
        if !appIsAvailable { return .appUnavailable }
        if strategy == .unverified { return .strategyUnverified }
        return nil
    }
}
