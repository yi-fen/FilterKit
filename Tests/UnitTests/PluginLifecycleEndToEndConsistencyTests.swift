import XCTest
@testable import FilterKit

/// Cross-layer regression tests: Plugin-page association edits are projected through the
/// domain topology and the exact Helper Filter.plist planner before they are considered valid.
final class PluginLifecycleEndToEndConsistencyTests: XCTestCase {
    private let owner = "com.example.owner"
    private let alpha = "com.example.alpha"
    private let beta = "com.example.beta"
    private let gamma = "com.example.gamma"

    func testPluginPageRemovalStopsPreviouslyEnabledAppWithoutChangingOtherApps() throws {
        let pluginID = UUID()
        let initialTopology = PluginBindingTopology(pluginID: pluginID,
            fixedOwnerBundleIdentifier: owner, fixedOwnerIsEnabled: true,
            additionalAssociations: [
                PluginBindingAssociation(bundleIdentifier: alpha, isEnabled: true),
                PluginBindingAssociation(bundleIdentifier: beta, isEnabled: false),
                PluginBindingAssociation(bundleIdentifier: gamma, isEnabled: true)
            ])
        let editedTopology = try PluginBindingTopologyEditor().removeAdditionalAssociation(alpha, from: initialTopology)
        XCTAssertEqual(editedTopology.fixedOwnerBundleIdentifier, owner)
        XCTAssertTrue(editedTopology.fixedOwnerIsEnabled)
        XCTAssertEqual(editedTopology.additionalAssociations, [
            PluginBindingAssociation(bundleIdentifier: beta, isEnabled: false),
            PluginBindingAssociation(bundleIdentifier: gamma, isEnabled: true)
        ])

        let input = try makeFilter(bundles: [owner, alpha, gamma])
        let plan = try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner,
            fixedOwnerIsEnabled: editedTopology.fixedOwnerIsEnabled,
            original: initialTopology.additionalAssociations.map {
                HelperPluginSoftAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled)
            },
            desired: editedTopology.additionalAssociations.map {
                HelperPluginSoftAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled)
            })

        XCTAssertEqual(plan.beforeBundleIdentifiers, [owner, alpha, gamma])
        XCTAssertEqual(plan.afterBundleIdentifiers, [owner, gamma])
        XCTAssertEqual(try bundles(in: plan.replacementData), [owner, gamma])
        XCTAssertFalse(try bundles(in: plan.replacementData).contains(alpha),
            "A removed association must no longer match through the Bundle filter.")
    }

    func testPluginPageAdditionRemainsDisabledUntilAppPageEnablesIt() throws {
        let topology = PluginBindingTopology(pluginID: UUID(), fixedOwnerBundleIdentifier: owner,
            fixedOwnerIsEnabled: true,
            additionalAssociations: [PluginBindingAssociation(bundleIdentifier: alpha, isEnabled: true)])
        let edited = try PluginBindingTopologyEditor().addAdditionalAssociation(beta, to: topology)
        XCTAssertEqual(edited.additionalAssociations.first(where: { $0.bundleIdentifier == beta })?.isEnabled, false)

        let input = try makeFilter(bundles: [owner, alpha])
        let plan = try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner,
            original: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: true)],
            desired: edited.additionalAssociations.map {
                HelperPluginSoftAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled)
            })
        XCTAssertEqual(plan.afterBundleIdentifiers, [owner, alpha])
        XCTAssertEqual(try bundles(in: plan.replacementData), [owner, alpha])
        XCTAssertFalse(try bundles(in: plan.replacementData).contains(beta))
    }

    func testPluginPageCannotChangeRetainedAppActivationBit() throws {
        let topology = PluginBindingTopology(pluginID: UUID(), fixedOwnerBundleIdentifier: owner,
            additionalAssociations: [PluginBindingAssociation(bundleIdentifier: alpha, isEnabled: true)])
        XCTAssertThrowsError(try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: makeFilter(bundles: [owner, alpha]), fixedOwnerBundleIdentifier: owner,
            original: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: true)],
            desired: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: false)]))
        XCTAssertTrue(topology.additionalAssociations[0].isEnabled)
    }

    func testDisabledFixedOwnerAndOtherAppStatesSurviveAssociationRemoval() throws {
        let input = try makeFilter(bundles: [alpha, gamma])
        let plan = try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner, fixedOwnerIsEnabled: false,
            original: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: true),
                       HelperPluginSoftAssociation(bundleIdentifier: gamma, isEnabled: true)],
            desired: [HelperPluginSoftAssociation(bundleIdentifier: gamma, isEnabled: true)])
        XCTAssertEqual(plan.afterBundleIdentifiers, [gamma])
        XCTAssertEqual(try bundles(in: plan.replacementData), [gamma])
    }


    func testCaseVariantAssociationRemovalKeepsOwnerAndOtherAppTargets() throws {
        let input = try makeFilter(bundles: ["COM.EXAMPLE.OWNER", "COM.EXAMPLE.ALPHA", "com.example.gamma"])
        let plan = try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner,
            original: [HelperPluginSoftAssociation(bundleIdentifier: "Com.Example.Alpha", isEnabled: true),
                       HelperPluginSoftAssociation(bundleIdentifier: gamma, isEnabled: true)],
            desired: [HelperPluginSoftAssociation(bundleIdentifier: gamma, isEnabled: true)])
        XCTAssertEqual(HelperBundleIdentifierKey.set(try bundles(in: plan.replacementData)),
            HelperBundleIdentifierKey.set([owner, gamma]))
    }

    func testThreeAppLifecycleDoesNotAllowAPPPageToInventFourthAssociation() throws {
        let associations = [
            FilterKitManifestSoftAssociation(bundleIdentifier: alpha, isEnabled: true),
            FilterKitManifestSoftAssociation(bundleIdentifier: beta, isEnabled: false),
            FilterKitManifestSoftAssociation(bundleIdentifier: gamma, isEnabled: true)
        ]
        XCTAssertEqual(try HelperAppPluginActivationTargetPolicy.validate(
            targetBundleIdentifier: beta, fixedOwnerBundleIdentifier: owner,
            additionalAssociations: associations), .additionalAssociation)
        XCTAssertThrowsError(try HelperAppPluginActivationTargetPolicy.validate(
            targetBundleIdentifier: "com.example.delta", fixedOwnerBundleIdentifier: owner,
            additionalAssociations: associations))

        let filter = try makeFilter(bundles: [owner, alpha, gamma])
        let plan = try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: filter, fixedOwnerBundleIdentifier: owner,
            original: associations.map { HelperPluginSoftAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled) },
            desired: [
                HelperPluginSoftAssociation(bundleIdentifier: beta, isEnabled: false),
                HelperPluginSoftAssociation(bundleIdentifier: gamma, isEnabled: true)
            ])
        XCTAssertEqual(HelperBundleIdentifierKey.set(try bundles(in: plan.replacementData)),
                       HelperBundleIdentifierKey.set([owner, gamma]))
    }

    private func makeFilter(bundles: [String]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["Filter": [
            "Bundles": bundles, "Classes": [String](), "Executables": [String]()
        ]], format: .xml, options: 0)
    }

    private func bundles(in data: Data) throws -> [String] {
        let root = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        let filter = try XCTUnwrap(root["Filter"] as? [String: Any])
        return try XCTUnwrap(filter["Bundles"] as? [String])
    }
}
