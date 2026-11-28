import Foundation

enum PluginManagedOperation: String {
    case inject
    case export
    case uninstall
    case restore
}

enum PluginSourceOperationDecision: Equatable {
    case allow
    case skipExternalDuplicate
    case denyReadOnlySource
}

/// Shared source/ownership boundary. Hash equality can only produce a duplicate
/// skip for a package-manager-owned file; it can never grant FilterKit ownership.
enum PluginSourceOperationPolicy {
    static func decision(for ownership: PluginOwnership,
                         operation: PluginManagedOperation,
                         exactPackageManagedSHA256Match: Bool = false) -> PluginSourceOperationDecision {
        if ownership == .filterKit { return .allow }
        if ownership == .packageManager,
           (operation == .restore || operation == .inject),
           exactPackageManagedSHA256Match {
            return .skipExternalDuplicate
        }
        return .denyReadOnlySource
    }
}
