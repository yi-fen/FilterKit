import XCTest
@testable import FilterKit

final class HelperPluginAssociationMutationPolicyTests: XCTestCase {
    private let hardBound = "com.example.source"
    private let a = "com.example.alpha"
    private let b = "com.example.beta"

    func testNewAssociationMustStartDisabled() throws {
        let result = try HelperPluginAssociationMutationPolicy.validate(original: [],
            desired: [PluginSoftAssociation(bundleIdentifier: a, isEnabled: false)],
            hardBoundBundleIdentifier: hardBound)
        XCTAssertEqual(result, [PluginSoftAssociation(bundleIdentifier: a, isEnabled: false)])
    }

    func testNewEnabledAssociationIsRejected() {
        XCTAssertThrowsError(try HelperPluginAssociationMutationPolicy.validate(original: [],
            desired: [PluginSoftAssociation(bundleIdentifier: a, isEnabled: true)],
            hardBoundBundleIdentifier: hardBound))
    }

    func testExistingActivationBitMustBePreserved() {
        let original = [PluginSoftAssociation(bundleIdentifier: a, isEnabled: true)]
        let desired = [PluginSoftAssociation(bundleIdentifier: a, isEnabled: false)]
        XCTAssertThrowsError(try HelperPluginAssociationMutationPolicy.validate(original: original,
            desired: desired, hardBoundBundleIdentifier: hardBound))
    }

    func testEnabledAssociationCanBeRemovedByPluginPageTransaction() throws {
        let original = [PluginSoftAssociation(bundleIdentifier: a, isEnabled: true)]
        XCTAssertTrue(try HelperPluginAssociationMutationPolicy.validate(original: original,
            desired: [], hardBoundBundleIdentifier: hardBound).isEmpty)
        // The Helper transaction is responsible for removing the active Bundle filter
        // together with the Manifest relationship; this policy does not toggle activation.
    }

    func testDisabledAssociationCanBeRemoved() throws {
        let original = [PluginSoftAssociation(bundleIdentifier: a, isEnabled: false)]
        XCTAssertTrue(try HelperPluginAssociationMutationPolicy.validate(original: original,
            desired: [], hardBoundBundleIdentifier: hardBound).isEmpty)
    }

    func testHardBoundAndDuplicatesAreRejected() {
        XCTAssertThrowsError(try HelperPluginAssociationMutationPolicy.validate(original: [],
            desired: [PluginSoftAssociation(bundleIdentifier: hardBound, isEnabled: false)],
            hardBoundBundleIdentifier: hardBound))
        XCTAssertThrowsError(try HelperPluginAssociationMutationPolicy.validate(original: [],
            desired: [PluginSoftAssociation(bundleIdentifier: a, isEnabled: false),
                      PluginSoftAssociation(bundleIdentifier: a, isEnabled: false)],
            hardBoundBundleIdentifier: hardBound))
    }

    func testOutputIsSorted() throws {
        let result = try HelperPluginAssociationMutationPolicy.validate(original: [],
            desired: [PluginSoftAssociation(bundleIdentifier: b, isEnabled: false),
                      PluginSoftAssociation(bundleIdentifier: a, isEnabled: false)],
            hardBoundBundleIdentifier: hardBound)
        XCTAssertEqual(result.map(\.bundleIdentifier), [a, b])
    }
}
