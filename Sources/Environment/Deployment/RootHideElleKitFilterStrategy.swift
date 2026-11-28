import Foundation
import CoreFoundation

/// RootHide ElleKit 1.2-3 filter semantics, based on roothide/ellekit
/// commit 16e3e7ed223c24c86ca2aaab6e78ad7d8d5c1d2e (injector/injector.c).
/// This type only creates an in-memory preview. It never reads or writes a device path.
enum RootHideFilterAction: String, Codable, Equatable {
    case enableForApp
    case disableForApp
}

enum RootHideFilterPlanDisposition: String, Codable, Equatable {
    case previewReady
    case alreadyAssociated
    case alreadyNotAssociated
    case blocked
}

enum RootHideFilterPlanBlocker: String, Codable, Equatable {
    case rootIsNotDictionary
    case filterDictionaryMissing
    case invalidBundlesType
    case duplicateBundleIdentifiers
    case invalidClassesType
    case invalidExecutablesType
    case invalidCoreFoundationVersionType
    case invalidManagerFlagType
    case invalidTargetBundleIdentifier
    case alternateMatchDimensionsPreventSafeDisable
    case propertyListSerializationFailed
}

struct RootHideFilterPlan: Equatable {
    let action: RootHideFilterAction
    let targetBundleIdentifier: String
    let disposition: RootHideFilterPlanDisposition
    let blockers: [RootHideFilterPlanBlocker]
    let beforeBundles: [String]
    let afterBundles: [String]
    let preservedRootKeys: [String]
    let preservedFilterKeys: [String]
    /// Serialized preview only. It is not passed to a writer or Helper in P2-02.
    let previewPropertyList: Data?

    var isPreviewable: Bool { disposition == .previewReady || disposition == .alreadyAssociated || disposition == .alreadyNotAssociated }
}

struct RootHideElleKitFilterStrategy {
    private let knownFilterKeys: Set<String> = ["Bundles", "Classes", "Executables", "CoreFoundationVersion"]

    func makePlan(originalData: Data,
                  targetBundleIdentifier: String,
                  action: RootHideFilterAction) -> RootHideFilterPlan {
        guard Self.isValidBundleIdentifier(targetBundleIdentifier) else {
            return blocked(action, targetBundleIdentifier, .invalidTargetBundleIdentifier)
        }

        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: originalData, options: [], format: nil)
        } catch {
            return blocked(action, targetBundleIdentifier, .propertyListSerializationFailed)
        }
        guard var root = object as? [String: Any] else {
            return blocked(action, targetBundleIdentifier, .rootIsNotDictionary)
        }
        guard var filter = root["Filter"] as? [String: Any] else {
            return blocked(action, targetBundleIdentifier, .filterDictionaryMissing)
        }

        if let manager = root["IsTweakManager"], !Self.isBoolean(manager) {
            return blocked(action, targetBundleIdentifier, .invalidManagerFlagType)
        }

        let bundles: [String]
        if let raw = filter["Bundles"] {
            guard let values = raw as? [Any], values.allSatisfy({ $0 is String }) else {
                return blocked(action, targetBundleIdentifier, .invalidBundlesType)
            }
            bundles = values.compactMap { $0 as? String }
            let bundleKeys = bundles.map(HelperBundleIdentifierKey.make)
            guard Set(bundleKeys).count == bundleKeys.count else {
                return blocked(action, targetBundleIdentifier, .duplicateBundleIdentifiers, before: bundles)
            }
        } else { bundles = [] }

        let classes: [String]
        if let raw = filter["Classes"] {
            guard let values = raw as? [Any], values.allSatisfy({ $0 is String }) else {
                return blocked(action, targetBundleIdentifier, .invalidClassesType)
            }
            classes = values.compactMap { $0 as? String }
        } else { classes = [] }

        let executables: [String]
        if let raw = filter["Executables"] {
            guard let values = raw as? [Any], values.allSatisfy({ $0 is String }) else {
                return blocked(action, targetBundleIdentifier, .invalidExecutablesType)
            }
            executables = values.compactMap { $0 as? String }
        } else { executables = [] }

        if let raw = filter["CoreFoundationVersion"] {
            guard let values = raw as? [Any], (values.count == 1 || values.count == 2),
                  values.allSatisfy({ $0 is NSNumber && !Self.isBoolean($0) }) else {
                return blocked(action, targetBundleIdentifier, .invalidCoreFoundationVersionType)
            }
        }

        let preservedRootKeys = root.keys.filter { $0 != "Filter" && $0 != "IsTweakManager" }.sorted()
        let preservedFilterKeys = filter.keys.filter { !knownFilterKeys.contains($0) }.sorted()
        let targetKey = HelperBundleIdentifierKey.make(targetBundleIdentifier)
        let existing = bundles.contains { HelperBundleIdentifierKey.make($0) == targetKey }

        switch action {
        case .enableForApp:
            guard !existing else {
                return plan(action, targetBundleIdentifier, .alreadyAssociated, [], bundles, bundles,
                            preservedRootKeys, preservedFilterKeys, nil)
            }
            var updated = bundles
            updated.append(targetBundleIdentifier)
            filter["Bundles"] = updated
            root["Filter"] = filter
            return serializedPlan(action, targetBundleIdentifier, .previewReady, [], bundles, updated,
                                  preservedRootKeys, preservedFilterKeys, root)

        case .disableForApp:
            guard existing else {
                // A missing Bundle entry does not prove that Classes or Executables cannot match.
                if !classes.isEmpty || !executables.isEmpty {
                    return blocked(action, targetBundleIdentifier, .alternateMatchDimensionsPreventSafeDisable,
                                   before: bundles, rootKeys: preservedRootKeys, filterKeys: preservedFilterKeys)
                }
                return plan(action, targetBundleIdentifier, .alreadyNotAssociated, [], bundles, bundles,
                            preservedRootKeys, preservedFilterKeys, nil)
            }
            // ElleKit 1.2-3 combines Bundles, Classes and Executables with OR semantics.
            // Removing a Bundle ID cannot disable the target if either alternate dimension remains.
            guard classes.isEmpty && executables.isEmpty else {
                return blocked(action, targetBundleIdentifier, .alternateMatchDimensionsPreventSafeDisable,
                               before: bundles, rootKeys: preservedRootKeys, filterKeys: preservedFilterKeys)
            }
            let updated = bundles.filter { HelperBundleIdentifierKey.make($0) != targetKey }
            filter["Bundles"] = updated
            root["Filter"] = filter
            return serializedPlan(action, targetBundleIdentifier, .previewReady, [], bundles, updated,
                                  preservedRootKeys, preservedFilterKeys, root)
        }
    }

    private func serializedPlan(_ action: RootHideFilterAction, _ target: String,
                                _ disposition: RootHideFilterPlanDisposition,
                                _ blockers: [RootHideFilterPlanBlocker], _ before: [String], _ after: [String],
                                _ rootKeys: [String], _ filterKeys: [String], _ root: [String: Any]) -> RootHideFilterPlan {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
            return plan(action, target, disposition, blockers, before, after, rootKeys, filterKeys, data)
        } catch {
            return blocked(action, target, .propertyListSerializationFailed, before: before,
                           rootKeys: rootKeys, filterKeys: filterKeys)
        }
    }

    private func plan(_ action: RootHideFilterAction, _ target: String,
                      _ disposition: RootHideFilterPlanDisposition,
                      _ blockers: [RootHideFilterPlanBlocker], _ before: [String], _ after: [String],
                      _ rootKeys: [String], _ filterKeys: [String], _ data: Data?) -> RootHideFilterPlan {
        RootHideFilterPlan(action: action, targetBundleIdentifier: target, disposition: disposition,
                           blockers: blockers, beforeBundles: before, afterBundles: after,
                           preservedRootKeys: rootKeys, preservedFilterKeys: filterKeys,
                           previewPropertyList: data)
    }

    private func blocked(_ action: RootHideFilterAction, _ target: String,
                         _ blocker: RootHideFilterPlanBlocker, before: [String] = [],
                         rootKeys: [String] = [], filterKeys: [String] = []) -> RootHideFilterPlan {
        plan(action, target, .blocked, [blocker], before, before, rootKeys, filterKeys, nil)
    }

    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 255 else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 63 &&
            part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
