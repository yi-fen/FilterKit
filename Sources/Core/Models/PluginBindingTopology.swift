import Foundation

/// Canonical per-plugin binding model for the fixed-owner / additional-association terminology.
/// This is a domain model only; Helper wire-format integration is intentionally a later phase.
struct PluginBindingTopology: Codable, Equatable {
    let schemaVersion: Int
    let pluginID: UUID
    let fixedOwnerBundleIdentifier: String?
    var fixedOwnerIsEnabled: Bool
    var additionalAssociations: [PluginBindingAssociation]

    init(pluginID: UUID,
         fixedOwnerBundleIdentifier: String?,
         fixedOwnerIsEnabled: Bool = true,
         additionalAssociations: [PluginBindingAssociation] = []) {
        self.schemaVersion = 1
        self.pluginID = pluginID
        self.fixedOwnerBundleIdentifier = fixedOwnerBundleIdentifier
        self.fixedOwnerIsEnabled = fixedOwnerIsEnabled
        self.additionalAssociations = additionalAssociations.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }

    var bindingKind: PluginBindingKind {
        fixedOwnerBundleIdentifier == nil ? .additionalAssociationsOnly : .fixedOwner
    }

    /// App targets whose injection is currently intended to be active.
    var enabledBundleIdentifiers: Set<String> {
        var result = Set(additionalAssociations.filter(\.isEnabled).map(\.bundleIdentifier))
        if fixedOwnerIsEnabled, let fixedOwnerBundleIdentifier {
            result.insert(fixedOwnerBundleIdentifier)
        }
        return result
    }

    static func forImport(pluginID: UUID, decision: PluginImportBatchDecision) -> PluginBindingTopology {
        switch decision.bindingMode {
        case .fixedOwner:
            return PluginBindingTopology(pluginID: pluginID,
                fixedOwnerBundleIdentifier: decision.fixedOwnerBundleIdentifier,
                fixedOwnerIsEnabled: decision.defaultsEnabled)
        case .additionalAssociation:
            return PluginBindingTopology(pluginID: pluginID,
                fixedOwnerBundleIdentifier: nil,
                additionalAssociations: decision.initialSoftAssociations.map {
                    PluginBindingAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled)
                })
        }
    }
}

enum PluginBindingKind: String, Codable, Equatable {
    case fixedOwner
    case additionalAssociationsOnly
}

struct PluginBindingAssociation: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    var isEnabled: Bool
    var id: String { bundleIdentifier }
}

enum PluginBindingTopologyIssue: Equatable {
    case unsupportedSchema
    case invalidFixedOwner
    case invalidAssociation(String)
    case duplicateAssociation(String)
    case fixedOwnerRepeatedAsAssociation
}

enum PluginBindingTopologyError: Error, Equatable {
    case invalidBundleIdentifier
    case fixedOwnerCannotBeRemoved
    case duplicateAssociation
    case associationNotFound
    case invalidTopology
}

struct PluginBindingTopologyValidator {
    func validate(_ topology: PluginBindingTopology) -> [PluginBindingTopologyIssue] {
        var issues: [PluginBindingTopologyIssue] = []
        if topology.schemaVersion != 1 { issues.append(.unsupportedSchema) }
        if let owner = topology.fixedOwnerBundleIdentifier,
           !PluginAssociationPlanResolver.isValidBundleIdentifier(owner) {
            issues.append(.invalidFixedOwner)
        }
        var seen = Set<String>()
        for association in topology.additionalAssociations {
            let bundleID = association.bundleIdentifier
            let key = HelperBundleIdentifierKey.make(bundleID)
            if !PluginAssociationPlanResolver.isValidBundleIdentifier(bundleID) {
                issues.append(.invalidAssociation(bundleID))
            }
            if let owner = topology.fixedOwnerBundleIdentifier,
               key == HelperBundleIdentifierKey.make(owner) {
                issues.append(.fixedOwnerRepeatedAsAssociation)
            }
            if !seen.insert(key).inserted {
                issues.append(.duplicateAssociation(bundleID))
            }
        }
        return issues
    }
}

/// Edits preserve the product rule: fixed owner is immutable, but its activation can be toggled;
/// additional associations may be removed directly; Helper removes any active filter target atomically.
struct PluginBindingTopologyEditor {
    func setFixedOwnerEnabled(_ enabled: Bool, in topology: PluginBindingTopology) throws -> PluginBindingTopology {
        guard topology.fixedOwnerBundleIdentifier != nil else { throw PluginBindingTopologyError.fixedOwnerCannotBeRemoved }
        try requireValid(topology)
        var updated = topology
        updated.fixedOwnerIsEnabled = enabled
        return updated
    }

    /// Plugin-page association creation defaults to disabled. Import-time association defaults
    /// are handled separately by `forImport`, where the batch policy explicitly supplies `true`.
    func addAdditionalAssociation(_ bundleIdentifier: String,
                                  to topology: PluginBindingTopology) throws -> PluginBindingTopology {
        try requireValid(topology)
        guard PluginAssociationPlanResolver.isValidBundleIdentifier(bundleIdentifier) else {
            throw PluginBindingTopologyError.invalidBundleIdentifier
        }
        guard HelperBundleIdentifierKey.make(bundleIdentifier) != HelperBundleIdentifierKey.make(topology.fixedOwnerBundleIdentifier ?? "") else {
            throw PluginBindingTopologyError.fixedOwnerCannotBeRemoved
        }
        guard !topology.additionalAssociations.contains(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(bundleIdentifier) }) else {
            throw PluginBindingTopologyError.duplicateAssociation
        }
        var updated = topology
        updated.additionalAssociations.append(PluginBindingAssociation(bundleIdentifier: bundleIdentifier, isEnabled: false))
        updated.additionalAssociations.sort { $0.bundleIdentifier < $1.bundleIdentifier }
        return updated
    }

    func setAdditionalAssociationEnabled(_ bundleIdentifier: String, enabled: Bool,
                                         in topology: PluginBindingTopology) throws -> PluginBindingTopology {
        try requireValid(topology)
        guard let index = topology.additionalAssociations.firstIndex(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(bundleIdentifier) }) else {
            throw PluginBindingTopologyError.associationNotFound
        }
        var updated = topology
        updated.additionalAssociations[index].isEnabled = enabled
        return updated
    }

    func removeAdditionalAssociation(_ bundleIdentifier: String,
                                    from topology: PluginBindingTopology) throws -> PluginBindingTopology {
        try requireValid(topology)
        guard topology.additionalAssociations.contains(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(bundleIdentifier) }) else {
            throw PluginBindingTopologyError.associationNotFound
        }
        // Removing an active association is allowed at the domain/UI layer. The Helper
        // must remove its Bundle filter and Manifest relationship atomically before commit.
        var updated = topology
        updated.additionalAssociations.removeAll { HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(bundleIdentifier) }
        return updated
    }

    private func requireValid(_ topology: PluginBindingTopology) throws {
        guard PluginBindingTopologyValidator().validate(topology).isEmpty else {
            throw PluginBindingTopologyError.invalidTopology
        }
    }
}
