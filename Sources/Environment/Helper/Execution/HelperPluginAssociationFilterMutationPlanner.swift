import Foundation

/// Builds the exact Filter.plist result for a Plugin-page association edit.
/// Membership changes are allowed here; activation bits of retained associations are not.
/// Removing an enabled association also removes its Bundle filter in the same proposed result.
struct HelperPluginAssociationFilterMutationPlanner {
    enum PlanningError: Error, Equatable {
        case invalidAssociationMetadata
        case currentFilterDoesNotMatchManifest
        case filterSemanticsCannotBeSafelyChanged
        case resultingFilterDoesNotMatchManifest
    }

    struct Plan: Equatable {
        let originalData: Data
        let replacementData: Data
        let removedActiveBundleIdentifiers: Set<String>
        let beforeBundleIdentifiers: Set<String>
        let afterBundleIdentifiers: Set<String>
    }

    private let filterStrategy = RootHideElleKitFilterStrategy()

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 255 else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 63 && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    func makePlan(originalData: Data,
                  fixedOwnerBundleIdentifier: String,
                  fixedOwnerIsEnabled: Bool = true,
                  original: [HelperPluginSoftAssociation],
                  desired: [HelperPluginSoftAssociation]) throws -> Plan {
        guard Self.isValidBundleIdentifier(fixedOwnerBundleIdentifier),
              original.count <= 512, desired.count <= 512 else {
            throw PlanningError.invalidAssociationMetadata
        }

        func index(_ values: [HelperPluginSoftAssociation]) throws -> [String: HelperPluginSoftAssociation] {
            var result: [String: HelperPluginSoftAssociation] = [:]
            let ownerKey = HelperBundleIdentifierKey.make(fixedOwnerBundleIdentifier)
            for item in values {
                let key = HelperBundleIdentifierKey.make(item.bundleIdentifier)
                guard Self.isValidBundleIdentifier(item.bundleIdentifier),
                      key != ownerKey, result[key] == nil else {
                    throw PlanningError.invalidAssociationMetadata
                }
                result[key] = item
            }
            return result
        }

        let old = try index(original)
        let new = try index(desired)
        for (bundleKey, item) in new {
            if let previous = old[bundleKey] {
                guard previous.isEnabled == item.isEnabled else { throw PlanningError.invalidAssociationMetadata }
            } else if item.isEnabled {
                // Plugin-page association creation never implicitly enables injection.
                throw PlanningError.invalidAssociationMetadata
            }
        }

        let oldEnabled = Set(old.filter { $0.value.isEnabled }.map(\.key))
        let newEnabled = Set(new.filter { $0.value.isEnabled }.map(\.key))
        let ownerKey = HelperBundleIdentifierKey.make(fixedOwnerBundleIdentifier)
        let before = (fixedOwnerIsEnabled ? Set([ownerKey]) : Set<String>()).union(oldEnabled)
        let initial = filterStrategy.makePlan(originalData: originalData,
            targetBundleIdentifier: fixedOwnerBundleIdentifier, action: .enableForApp)
        guard initial.isPreviewable, HelperBundleIdentifierKey.set(initial.beforeBundles) == before else {
            throw PlanningError.currentFilterDoesNotMatchManifest
        }

        var working = originalData
        let removedAssociations = Set(old.keys).subtracting(new.keys)
        for bundleKey in removedAssociations.sorted() {
            guard let bundleID = old[bundleKey]?.bundleIdentifier else { throw PlanningError.invalidAssociationMetadata }
            let step = filterStrategy.makePlan(originalData: working,
                targetBundleIdentifier: bundleID, action: .disableForApp)
            guard step.isPreviewable else {
                throw PlanningError.filterSemanticsCannotBeSafelyChanged
            }
            if oldEnabled.contains(bundleKey) {
                guard step.disposition == .previewReady || step.disposition == .alreadyNotAssociated,
                      HelperBundleIdentifierKey.set(step.beforeBundles).contains(bundleKey) else {
                    throw PlanningError.filterSemanticsCannotBeSafelyChanged
                }
                if let preview = step.previewPropertyList { working = preview }
            } else {
                // Even a currently disabled association must be proven not to match through
                // Classes/Executables dimensions before the relationship can be removed.
                guard step.disposition == .alreadyNotAssociated,
                      !HelperBundleIdentifierKey.set(step.beforeBundles).contains(bundleKey) else {
                    throw PlanningError.filterSemanticsCannotBeSafelyChanged
                }
            }
        }

        let final = filterStrategy.makePlan(originalData: working,
            targetBundleIdentifier: fixedOwnerBundleIdentifier, action: .enableForApp)
        let after = (fixedOwnerIsEnabled ? Set([ownerKey]) : Set<String>()).union(newEnabled)
        guard final.isPreviewable, HelperBundleIdentifierKey.set(final.beforeBundles) == after else {
            throw PlanningError.resultingFilterDoesNotMatchManifest
        }
        return Plan(originalData: originalData, replacementData: working,
            removedActiveBundleIdentifiers: Set(old.filter { $0.value.isEnabled && new[$0.key] == nil }.map { $0.value.bundleIdentifier }),
            beforeBundleIdentifiers: Set(initial.beforeBundles), afterBundleIdentifiers: Set(final.beforeBundles))
    }
}
