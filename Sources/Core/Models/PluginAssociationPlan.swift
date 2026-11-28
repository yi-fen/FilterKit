import Foundation

/// A user-selected soft association. The hard-bound source app is intentionally not represented here.
struct PluginSoftAssociation: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    var isEnabled: Bool
    var id: String { bundleIdentifier }
}

/// Desired association state is separate from installed-app availability and deployed plist contents.
struct PluginAssociationPlan: Codable, Equatable {
    let pluginID: UUID
    let hardBoundBundleIdentifier: String
    var softAssociations: [PluginSoftAssociation]

    init(pluginID: UUID, hardBoundBundleIdentifier: String,
         softAssociations: [PluginSoftAssociation] = []) {
        self.pluginID = pluginID
        self.hardBoundBundleIdentifier = hardBoundBundleIdentifier
        self.softAssociations = softAssociations.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }

    /// Existing manifest associations have no per-App enabled bit in schema 1/2;
    /// the current compatibility interpretation is that each recorded soft association is desired enabled.
    init?(snapshot: PluginAssociationSnapshot) {
        guard let hardBound = snapshot.hardBoundBundleIdentifier else { return nil }
        let ownerKey = HelperBundleIdentifierKey.make(hardBound)
        var seen = Set<String>()
        let softIDs = (snapshot.softAssociatedApps.map(\.bundleIdentifier) + snapshot.missingSoftBundleIdentifiers)
            .filter { let key = HelperBundleIdentifierKey.make($0); return key != ownerKey && seen.insert(key).inserted }
        self.init(pluginID: snapshot.pluginID, hardBoundBundleIdentifier: hardBound,
                  softAssociations: softIDs.map {
                      PluginSoftAssociation(bundleIdentifier: $0, isEnabled: true)
                  })
    }
}

enum PluginAssociationPlanIssue: String, Codable, Equatable, Hashable {
    case invalidHardBoundBundleIdentifier
    case duplicateSoftAssociation
    case invalidSoftBundleIdentifier
    case hardBoundCannotBeSoftAssociated
}

struct PluginAssociationResolution: Codable, Equatable {
    let pluginID: UUID
    let hardBoundBundleIdentifier: String
    let hardBoundIsInstalled: Bool
    let enabledSoftBundleIdentifiers: [String]
    let disabledSoftBundleIdentifiers: [String]
    let missingSoftBundleIdentifiers: [String]
    let effectiveBundleIdentifiers: [String]
    let issues: [PluginAssociationPlanIssue]

    var isValid: Bool { issues.isEmpty }
}

/// Pure resolver: no persistence, filesystem access, or plist mutation.
struct PluginAssociationPlanResolver {
    func resolve(_ plan: PluginAssociationPlan, installedBundleIdentifiers: Set<String>) -> PluginAssociationResolution {
        var issues: [PluginAssociationPlanIssue] = []
        if !Self.isValidBundleIdentifier(plan.hardBoundBundleIdentifier) {
            issues.append(.invalidHardBoundBundleIdentifier)
        }

        var seen = Set<String>()
        let ownerKey = HelperBundleIdentifierKey.make(plan.hardBoundBundleIdentifier)
        let installedKeys = HelperBundleIdentifierKey.set(installedBundleIdentifiers)
        for association in plan.softAssociations {
            let key = HelperBundleIdentifierKey.make(association.bundleIdentifier)
            if !Self.isValidBundleIdentifier(association.bundleIdentifier) {
                issues.append(.invalidSoftBundleIdentifier)
            }
            if key == ownerKey {
                issues.append(.hardBoundCannotBeSoftAssociated)
            }
            if !seen.insert(key).inserted {
                issues.append(.duplicateSoftAssociation)
            }
        }

        let hardIsValid = Self.isValidBundleIdentifier(plan.hardBoundBundleIdentifier)
        let hardInstalled = hardIsValid && installedKeys.contains(ownerKey)
        let enabled = plan.softAssociations
            .filter { $0.isEnabled && Self.isValidBundleIdentifier($0.bundleIdentifier)
                && installedKeys.contains(HelperBundleIdentifierKey.make($0.bundleIdentifier)) }
            .map(\.bundleIdentifier).sorted()
        let disabled = plan.softAssociations
            .filter { !$0.isEnabled && Self.isValidBundleIdentifier($0.bundleIdentifier) }.map(\.bundleIdentifier).sorted()
        let missing = plan.softAssociations
            .filter { Self.isValidBundleIdentifier($0.bundleIdentifier)
                && !installedKeys.contains(HelperBundleIdentifierKey.make($0.bundleIdentifier)) }
            .map(\.bundleIdentifier).sorted()
        var effective = Set(enabled)
        if hardInstalled { effective.insert(plan.hardBoundBundleIdentifier) }

        return PluginAssociationResolution(
            pluginID: plan.pluginID,
            hardBoundBundleIdentifier: plan.hardBoundBundleIdentifier,
            hardBoundIsInstalled: hardInstalled,
            enabledSoftBundleIdentifiers: enabled,
            disabledSoftBundleIdentifiers: disabled,
            missingSoftBundleIdentifiers: missing,
            effectiveBundleIdentifiers: effective.sorted(),
            issues: Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
        )
    }

    static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 255 else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.count <= 63 &&
            (part.first?.isLetter == true || part.first?.isNumber == true) &&
            part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}

/// Plugin-page edit surface is intentionally limited to association membership.
/// Per-App injection enable/disable is owned exclusively by the Apps feature.
enum PluginAssociationEdit: Equatable {
    case addSoft(bundleIdentifier: String)
    /// Re-adds a relationship removed earlier in the same draft while preserving its prior activation bit.
    case restoreSoft(association: PluginSoftAssociation)
    case removeSoft(bundleIdentifier: String)
}

enum PluginAssociationEditDenial: String, Codable, Equatable, Error {
    case hardBoundIsImmutable
    case invalidBundleIdentifier
    case appNotInstalled
    case duplicateAssociation
    case associationNotFound
    case pluginNotManageable
}

/// Validates edits to the in-memory association plan. Callers must separately persist through a future verified Helper workflow.
struct PluginAssociationPlanEditor {
    func applying(_ edit: PluginAssociationEdit, to plan: PluginAssociationPlan,
                  installedBundleIdentifiers: Set<String>, pluginIsManageable: Bool)
        -> Result<PluginAssociationPlan, PluginAssociationEditDenial> {
        guard pluginIsManageable else { return .failure(.pluginNotManageable) }
        var updated = plan
        switch edit {
        case .addSoft(let bundleID):
            guard PluginAssociationPlanResolver.isValidBundleIdentifier(bundleID) else { return .failure(.invalidBundleIdentifier) }
            let bundleKey = HelperBundleIdentifierKey.make(bundleID)
            guard bundleKey != HelperBundleIdentifierKey.make(plan.hardBoundBundleIdentifier) else { return .failure(.hardBoundIsImmutable) }
            guard HelperBundleIdentifierKey.set(installedBundleIdentifiers).contains(bundleKey) else { return .failure(.appNotInstalled) }
            guard !plan.softAssociations.contains(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == bundleKey }) else { return .failure(.duplicateAssociation) }
            // Creating a relationship must never implicitly activate injection.
            // The per-App activation state is controlled only from the App detail page.
            updated.softAssociations.append(PluginSoftAssociation(bundleIdentifier: bundleID, isEnabled: false))
        case .restoreSoft(let association):
            let bundleID = association.bundleIdentifier
            guard PluginAssociationPlanResolver.isValidBundleIdentifier(bundleID) else { return .failure(.invalidBundleIdentifier) }
            let bundleKey = HelperBundleIdentifierKey.make(bundleID)
            guard bundleKey != HelperBundleIdentifierKey.make(plan.hardBoundBundleIdentifier) else { return .failure(.hardBoundIsImmutable) }
            guard HelperBundleIdentifierKey.set(installedBundleIdentifiers).contains(bundleKey) else { return .failure(.appNotInstalled) }
            guard !plan.softAssociations.contains(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == bundleKey }) else { return .failure(.duplicateAssociation) }
            updated.softAssociations.append(association)
        case .removeSoft(let bundleID):
            let bundleKey = HelperBundleIdentifierKey.make(bundleID)
            guard bundleKey != HelperBundleIdentifierKey.make(plan.hardBoundBundleIdentifier) else { return .failure(.hardBoundIsImmutable) }
            guard updated.softAssociations.contains(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == bundleKey }) else { return .failure(.associationNotFound) }
            updated.softAssociations.removeAll { HelperBundleIdentifierKey.make($0.bundleIdentifier) == bundleKey }
        }
        updated.softAssociations.sort { $0.bundleIdentifier < $1.bundleIdentifier }
        return .success(updated)
    }
}
