import Foundation

/// The UI page that initiated a lifecycle action. This is a product boundary, not a
/// security boundary; Helper authorization remains mandatory for privileged mutations.
enum PluginLifecycleEntryPoint: String, Codable, Equatable {
    case home
    case apps
    case plugin
    case settings
}

enum PluginLifecycleAction: String, Codable, Equatable {
    case inject
    case enable
    case disable
    case addAssociation
    case removeAssociation
    case export
    case restore
    case uninstall
}

enum PluginLifecycleDenial: String, Codable, Equatable {
    case wrongEntryPoint
    case notFilterKitOwned
    case payloadNotVerified
    case manifestNotVerified
    case fixedOwnerImmutable
    case invalidAssociation
}

/// A read-only snapshot of lifecycle facts. App availability is deliberately separate from
/// the persisted binding topology and per-App desired activation states.
struct PluginLifecycleEvidence: Equatable {
    enum PayloadState: Equatable { case verifiedPair, missingDylib, missingPlist, missingBoth, unverified }

    let ownership: PluginOwnership
    let payloadState: PayloadState
    let manifestVerified: Bool
    let fixedOwnerBundleIdentifier: String?
    let additionalAssociationBundleIdentifiers: Set<String>
    let enabledBundleIdentifiers: Set<String>
    let installedBundleIdentifiers: Set<String>

    var allAssociatedBundleIdentifiers: Set<String> {
        var result = additionalAssociationBundleIdentifiers
        if let fixedOwnerBundleIdentifier { result.insert(fixedOwnerBundleIdentifier) }
        return result
    }

    /// Returns the persisted association identifiers whose Apps are currently installed.
    /// Matching is case-insensitive, while the returned values preserve Manifest spelling.
    var installedAssociatedBundleIdentifiers: Set<String> {
        let installedKeys = HelperBundleIdentifierKey.set(installedBundleIdentifiers)
        return Set(allAssociatedBundleIdentifiers.filter {
            installedKeys.contains(HelperBundleIdentifierKey.make($0))
        })
    }

    /// Uninstall/reinstall of an App changes only this derived set. It never mutates bindings.
    /// Matching is case-insensitive, while the returned values preserve Manifest spelling.
    var unavailableAssociatedBundleIdentifiers: Set<String> {
        let installedKeys = HelperBundleIdentifierKey.set(installedBundleIdentifiers)
        return Set(allAssociatedBundleIdentifiers.filter {
            !installedKeys.contains(HelperBundleIdentifierKey.make($0))
        })
    }

    /// Desired activation is independent per App and uses Bundle ID identity, not spelling.
    func isEnabled(bundleIdentifier: String) -> Bool {
        enabledBundleIdentifiers.contains {
            HelperBundleIdentifierKey.make($0) == HelperBundleIdentifierKey.make(bundleIdentifier)
        }
    }
}

/// Central page and lifecycle policy shared by UI preflight and tests. It does not execute I/O.
enum PluginLifecyclePolicy {
    static func denial(for action: PluginLifecycleAction,
                       entryPoint: PluginLifecycleEntryPoint,
                       evidence: PluginLifecycleEvidence,
                       associationBundleIdentifier: String? = nil) -> PluginLifecycleDenial? {
        let requiredEntryPoint: PluginLifecycleEntryPoint
        switch action {
        case .inject, .enable, .disable:
            requiredEntryPoint = .apps
        case .addAssociation, .removeAssociation, .export, .restore, .uninstall:
            requiredEntryPoint = .plugin
        }
        guard entryPoint == requiredEntryPoint else { return .wrongEntryPoint }

        switch action {
        case .inject:
            // First-time injection candidates may not yet have FilterKit ownership. The Helper
            // must prove the source is not package-managed and that destination files are absent.
            return nil
        case .enable, .disable:
            guard evidence.ownership == .filterKit else { return .notFilterKitOwned }
            guard evidence.payloadState == .verifiedPair else { return .payloadNotVerified }
            guard evidence.manifestVerified else { return .manifestNotVerified }
            return nil
        case .addAssociation:
            guard let bundleID = associationBundleIdentifier, isValidBundleIdentifier(bundleID),
                  HelperBundleIdentifierKey.make(bundleID)
                    != HelperBundleIdentifierKey.make(evidence.fixedOwnerBundleIdentifier ?? ""),
                  !evidence.additionalAssociationBundleIdentifiers.contains(where: {
                      HelperBundleIdentifierKey.make($0) == HelperBundleIdentifierKey.make(bundleID)
                  }) else {
                return .invalidAssociation
            }
            guard evidence.ownership == .filterKit else { return .notFilterKitOwned }
            guard evidence.manifestVerified else { return .manifestNotVerified }
            return nil
        case .removeAssociation:
            guard let bundleID = associationBundleIdentifier, isValidBundleIdentifier(bundleID) else {
                return .invalidAssociation
            }
            guard HelperBundleIdentifierKey.make(bundleID)
                != HelperBundleIdentifierKey.make(evidence.fixedOwnerBundleIdentifier ?? "") else {
                return .fixedOwnerImmutable
            }
            guard evidence.additionalAssociationBundleIdentifiers.contains(where: {
                HelperBundleIdentifierKey.make($0) == HelperBundleIdentifierKey.make(bundleID)
            }) else { return .invalidAssociation }
            // Helper atomically removes an enabled target from Filter.plist and Manifest.
            // The Plugin page never edits an App activation bit in place.
            guard evidence.ownership == .filterKit else { return .notFilterKitOwned }
            guard evidence.manifestVerified else { return .manifestNotVerified }
            return nil
        case .export, .restore:
            guard evidence.ownership == .filterKit else { return .notFilterKitOwned }
            guard evidence.payloadState == .verifiedPair else { return .payloadNotVerified }
            guard evidence.manifestVerified else { return .manifestNotVerified }
            return nil
        case .uninstall:
            guard evidence.ownership == .filterKit else { return .notFilterKitOwned }
            guard evidence.payloadState == .verifiedPair else { return .payloadNotVerified }
            guard evidence.manifestVerified else { return .manifestNotVerified }
            // Uninstall removes the dylib, Filter.plist and ownership Manifest as one
            // journaled transaction, so no associated App can load it on future launches.
            return nil
        }
    }

    static func isValidBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.first!.isLetter && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
