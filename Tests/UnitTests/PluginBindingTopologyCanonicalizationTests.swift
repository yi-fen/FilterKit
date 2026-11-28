import XCTest
@testable import FilterKit

final class PluginBindingTopologyCanonicalizationTests: XCTestCase {
    private let owner = "com.example.owner"
    private let alpha = "com.example.alpha"

    func testCaseVariantDuplicateAndOwnerCollisionAreRejected() {
        let topology = PluginBindingTopology(pluginID: UUID(),
            fixedOwnerBundleIdentifier: owner,
            additionalAssociations: [
                PluginBindingAssociation(bundleIdentifier: alpha, isEnabled: true),
                PluginBindingAssociation(bundleIdentifier: "COM.EXAMPLE.ALPHA", isEnabled: false),
                PluginBindingAssociation(bundleIdentifier: "COM.EXAMPLE.OWNER", isEnabled: true)
            ])
        let issues = PluginBindingTopologyValidator().validate(topology)
        XCTAssertTrue(issues.contains(.duplicateAssociation("COM.EXAMPLE.ALPHA")))
        XCTAssertTrue(issues.contains(.fixedOwnerRepeatedAsAssociation))
    }

    func testAddingCaseVariantOfExistingAssociationIsRejected() throws {
        let topology = PluginBindingTopology(pluginID: UUID(), fixedOwnerBundleIdentifier: owner,
            additionalAssociations: [PluginBindingAssociation(bundleIdentifier: alpha, isEnabled: false)])
        XCTAssertThrowsError(try PluginBindingTopologyEditor().addAdditionalAssociation("COM.EXAMPLE.ALPHA", to: topology))
    }

    func testRemovingAssociationUsesCanonicalIdentityAndPreservesOriginalOwner() throws {
        let topology = PluginBindingTopology(pluginID: UUID(), fixedOwnerBundleIdentifier: owner,
            additionalAssociations: [PluginBindingAssociation(bundleIdentifier: "Com.Example.Alpha", isEnabled: true)])
        let updated = try PluginBindingTopologyEditor().removeAdditionalAssociation("com.example.alpha", from: topology)
        XCTAssertEqual(updated.fixedOwnerBundleIdentifier, owner)
        XCTAssertTrue(updated.additionalAssociations.isEmpty)
    }
}
