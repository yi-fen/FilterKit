import XCTest
@testable import FilterKit

final class HelperPluginAssociationFilterMutationPlannerTests: XCTestCase {
    private let owner = "com.example.owner"
    private let alpha = "com.example.alpha"
    private let beta = "com.example.beta"

    func testRemovingEnabledAssociationRemovesItsFilterTargetAtomically() throws {
        let input = try makePlist(bundles: [owner, alpha], classes: [], executables: [])
        let plan = try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner,
            original: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: true)],
            desired: [])

        XCTAssertEqual(plan.removedActiveBundleIdentifiers, [alpha])
        XCTAssertEqual(plan.beforeBundleIdentifiers, [owner, alpha])
        XCTAssertEqual(plan.afterBundleIdentifiers, [owner])
        XCTAssertEqual(try bundles(in: plan.replacementData), [owner])
    }

    func testAddingAssociationDoesNotEnableItInFilter() throws {
        let input = try makePlist(bundles: [owner], classes: [], executables: [])
        let plan = try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner,
            original: [], desired: [HelperPluginSoftAssociation(bundleIdentifier: beta, isEnabled: false)])
        XCTAssertEqual(plan.afterBundleIdentifiers, [owner])
        XCTAssertEqual(try bundles(in: plan.replacementData), [owner])
    }

    func testPluginPageCannotChangeActivationOfRetainedAssociation() throws {
        let input = try makePlist(bundles: [owner, alpha], classes: [], executables: [])
        XCTAssertThrowsError(try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner,
            original: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: true)],
            desired: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: false)]))
    }

    func testRemovalBlockedWhenAlternateFilterDimensionsCouldStillMatchApp() throws {
        let input = try makePlist(bundles: [owner, alpha], classes: ["SomeClass"], executables: [])
        XCTAssertThrowsError(try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner,
            original: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: true)],
            desired: []))
    }

    func testRemovingDisabledAssociationAlsoRequiresNoAlternateMatchDimensions() throws {
        let input = try makePlist(bundles: [owner], classes: ["SomeClass"], executables: [])
        XCTAssertThrowsError(try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner,
            original: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: false)],
            desired: []))
    }

    func testRemovingAssociationPreservesOtherAppsActivationBits() throws {
        let gamma = "com.example.gamma"
        let input = try makePlist(bundles: [owner, alpha, gamma], classes: [], executables: [])
        let plan = try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner,
            original: [
                HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: true),
                HelperPluginSoftAssociation(bundleIdentifier: beta, isEnabled: false),
                HelperPluginSoftAssociation(bundleIdentifier: gamma, isEnabled: true)
            ],
            desired: [
                HelperPluginSoftAssociation(bundleIdentifier: beta, isEnabled: false),
                HelperPluginSoftAssociation(bundleIdentifier: gamma, isEnabled: true)
            ])
        XCTAssertEqual(plan.removedActiveBundleIdentifiers, [alpha])
        XCTAssertEqual(plan.afterBundleIdentifiers, [owner, gamma])
        XCTAssertEqual(try bundles(in: plan.replacementData), [owner, gamma])
    }

    func testDisabledFixedOwnerRemainsDisabledWhenRemovingAdditionalAssociation() throws {
        let input = try makePlist(bundles: [alpha], classes: [], executables: [])
        let plan = try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner, fixedOwnerIsEnabled: false,
            original: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: true)],
            desired: [])
        XCTAssertEqual(plan.beforeBundleIdentifiers, [alpha])
        XCTAssertTrue(plan.afterBundleIdentifiers.isEmpty)
        XCTAssertTrue(try bundles(in: plan.replacementData).isEmpty)
    }

    func testOwnerIsNotReintroducedWhenAlreadyDisabledAndAllSoftAssociationsAreRemoved() throws {
        let input = try makePlist(bundles: [], classes: [], executables: [])
        let plan = try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner, fixedOwnerIsEnabled: false,
            original: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: false)],
            desired: [])
        XCTAssertTrue(plan.afterBundleIdentifiers.isEmpty)
        XCTAssertTrue(try bundles(in: plan.replacementData).isEmpty)
    }


    func testCaseVariantBundleFilterIsRecognizedAndRemovedCompletely() throws {
        let input = try makePlist(bundles: ["COM.EXAMPLE.OWNER", "Com.Example.Alpha"],
            classes: [], executables: [])
        let plan = try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner,
            original: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: true)],
            desired: [])
        XCTAssertEqual(HelperBundleIdentifierKey.set(plan.beforeBundleIdentifiers),
            HelperBundleIdentifierKey.set([owner, alpha]))
        XCTAssertEqual(HelperBundleIdentifierKey.set(plan.afterBundleIdentifiers),
            HelperBundleIdentifierKey.set([owner]))
        XCTAssertEqual(HelperBundleIdentifierKey.set(try bundles(in: plan.replacementData)),
            HelperBundleIdentifierKey.set([owner]))
    }

    func testCaseVariantDuplicateAssociationMetadataIsRejected() throws {
        let input = try makePlist(bundles: [owner, alpha], classes: [], executables: [])
        XCTAssertThrowsError(try HelperPluginAssociationFilterMutationPlanner().makePlan(
            originalData: input, fixedOwnerBundleIdentifier: owner,
            original: [HelperPluginSoftAssociation(bundleIdentifier: alpha, isEnabled: true)],
            desired: [HelperPluginSoftAssociation(bundleIdentifier: "COM.EXAMPLE.ALPHA", isEnabled: true)]))
    }

    private func makePlist(bundles: [String], classes: [String], executables: [String]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["Filter": [
            "Bundles": bundles, "Classes": classes, "Executables": executables
        ]], format: .xml, options: 0)
    }

    private func bundles(in data: Data) throws -> [String] {
        let root = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        let filter = try XCTUnwrap(root["Filter"] as? [String: Any])
        return try XCTUnwrap(filter["Bundles"] as? [String])
    }
}
